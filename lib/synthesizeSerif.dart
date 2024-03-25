import 'dart:convert';
import 'dart:io';

import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:just_audio/just_audio.dart';

import 'text_dictionary_editor.dart';

// 実機では喋らなくなるなら『Android でインターネットに接続するためのパーミッションを設定する』かも.

class NewSuperSynthesizer {
  // これもコンストラクタ。インスタンス生成時に実行される.
  NewSuperSynthesizer() {
    _initialize();
  }

  final _playlistPlayer = AudioPlayer();
  final _playlist = ConcatenatingAudioSource(children: []);

  // チャット画面の送信順=orderWaitingList=playlistAddWaitingListになるように制御すること😦.
  var _orderWaitingList = <String>[];
  final _playlistAddWaitingList = <DateTime>[];

  // 🤔順番待ちリストを整理し、順番入れ替えや合成キャンセルが行えるメソッド。引数は優先度高い順。好きなタイミングで発動していいし、発動しなくてもいい.
  void organizeWaitingOrders(List<String> messageIDs) {
    final updatedList = <String>[];
    for (final pickedItem in messageIDs) {
      if (_orderWaitingList.contains(pickedItem)) {
        updatedList.add(pickedItem);
      }
    }

    print('😂${DateTime.now()} 順番待ち列を整理しました！${updatedList.length - _orderWaitingList.length}個');
    _orderWaitingList = updatedList; // 引数に含まれないIDはなくなる.
  }

  // 🤐すでに順番待ち列に並んでいるか確認できるメソッド。重複オーダー防止にご活用ください.
  bool isMeAlreadyThere(String messageId) {
    if (_orderWaitingList.contains(messageId)) {
      return true;
    }
    return false;
  }

  // 😆主役のメソッド。実態は順番待ちコントローラー。順番待ちに関係ない部分は徹底的に分けた.
  Future<Map<String, dynamic>> synthesizeText({required String text, int? speakerId, required String messageId}) async {
    // 順番待ちシステム。合成できなくなったらまず疑うこと😹.
    _orderWaitingList.add(messageId); // オーダーが通ったら必ず自分のIDを消しましょう！！😹😹😹.
    while (_orderWaitingList[0] != messageId) {
      await Future.delayed(const Duration(seconds: 1));

      // 整理システム搭載により、いつのまにかリストから消える可能性が出てきた。無限待機になる前にmainに帰る.
      if (!_orderWaitingList.contains(messageId)) {
        return {'success': false, 'errorMessage': '順番待ちから消えてます！🤯'};
      }
    }

    final serif = await convertTextToSerif(text); // 読み方辞書を適用して置換する.

    final responceBodyMapped = await _phase1Request(serif: serif, speakerId: speakerId);

    _orderWaitingList.remove(messageId); // オーダーを出したので順番を進める😸 整理システムにより順番が変わるのでremoveAtから変更した.

    // オーダーが受理されなかった場合はここでmainに帰る.
    if (responceBodyMapped['mp3DownloadUrl'] == null || responceBodyMapped['audioStatusUrl'] == null) {
      return responceBodyMapped;
    }

    // 今度はプレイリスト追加フェーズを順番待ちする.
    final registrationTime = DateTime.now();

    _playlistAddWaitingList.add(registrationTime); // あとで必ず解除すること！！😹😹😹.
    while (_playlistAddWaitingList[0] != registrationTime) {
      await Future.delayed(const Duration(seconds: 1));
    }

    await _phase2WaitAndPlay(
      mp3DownloadUrl: responceBodyMapped['mp3DownloadUrl'],
      audioStatusUrl: responceBodyMapped['audioStatusUrl'],
    );

    _playlistAddWaitingList.removeAt(0); // プレイリストへの追加が完了したので順番を進める😸😸😸.

    print('😊${DateTime.now()} メッセージID「$messageId」の合成完了！synthesizeSerifメソッドを終了するよ');
    return responceBodyMapped;
  }

  // 😝音声合成をオーダーするフェーズ。phase1Orderでは10に見えてしまうのでこの名前に.
  static Future<Map<String, dynamic>> _phase1Request({required String serif, int? speakerId}) async {
    // 音声合成にはsu-shiki.comさんの『WEB版VOICEVOX API（低速）』を利用させていただきます。便利なサービスを提供してくださり本当にありがたい限りです！😘.
    final requestUrl =
        'https://api.tts.quest/v3/voicevox/synthesis?speaker=$speakerId&text=${Uri.encodeComponent(serif)}';
    print('😘音声合成をオーダーするURLは$requestUrl');

    var responceBodyMapped = <String, dynamic>{'デフォルト': true};

    // 音声合成オーダーを出す。連続でオーダーを出すとretryAfter秒待てと言われるのでリトライする.
    for (var retry = 1; retry < 6; retry++) {
      responceBodyMapped = await _accessAPI(requestUrl); // これだけでオーダー出せるようにした😎.

      if (responceBodyMapped['mp3DownloadUrl'] != null) {
        print('😋MP3ダウンロードURLが判明！ ${responceBodyMapped['mp3DownloadUrl']}です');
        break;
      } else if (responceBodyMapped['retryAfter'] is int) {
        print('😴retryAfterのため${responceBodyMapped['retryAfter'] + retry}秒待ちます');
        await Future.delayed(Duration(seconds: responceBodyMapped['retryAfter'] + retry));
        continue;
      }
      await Future.delayed(const Duration(seconds: 2));
    }

    return responceBodyMapped;
  }

  // 😋合成待ちフェーズと再生フェーズ.
  Future<void> _phase2WaitAndPlay({required String mp3DownloadUrl, required String audioStatusUrl}) async {
    // AudioCountを取得する。すぐアクセスすると0が返ってくるのでリトライする.
    var audioStatusMapped = <String, dynamic>{'デフォルト': true};
    for (var retry = 1; retry < 100; retry++) {
      audioStatusMapped = await _accessAPI(audioStatusUrl);

      if (audioStatusMapped['audioCount'] > 0) {
        print('😋audioCountが判明！${audioStatusMapped['audioCount']}です');
        break;
      } else if (audioStatusMapped['isAudioError'] == true) {
        return; // 絵文字だけのオーダーは合成エラー。ここで.syntheに帰る.
      }
      print('😴まだaudioCount=0なので$retry秒待ちます');
      await Future.delayed(Duration(seconds: retry));
    }

    // それでもaudioCountが取得できなかった場合はここで.syntheに帰る.
    if (audioStatusMapped['audioCount'] is! int) {
      return;
    }

    final int audioCount = audioStatusMapped['audioCount'];
    final mp3AudioCountableUrl = mp3DownloadUrl.replaceFirst('audio.mp3', ''); // "数字.mp3" を後付けできるURLを作る.

    // 一定の割合が合成完了するまで待つ。追いつくことがあるので🐇.
    const synthesizeWaitRatio = 0.4; // 割合はここ。再生が不安定なら増やしてみて.
    for (var retry = 1; retry < 20; retry++) {
      final halfAudioCount = ((audioCount - 1) * synthesizeWaitRatio).round(); // カウント=1の時は0.mp3まで。リストと同様.
      if (await _checkAudioUrlPlayable('$mp3AudioCountableUrl$halfAudioCount.mp3')) {
        print('😋${synthesizeWaitRatio * 100}％合成完了しました！プレイリスト追加へ進みます');
        break;
      } else {
        print('😴まだ${synthesizeWaitRatio * 100}％地点は再生できないので$retry秒待ちます');
        await Future.delayed(Duration(seconds: retry));
      }
    }

    await _playlistPlayer.play();

    // 確認次第じゃんじゃんプレイリストに追加していく.
    for (var i = 0; i <= audioCount - 1; i++) {
      for (var retry = 1; retry < 10; retry++) {
        if (await _checkAudioUrlPlayable('$mp3AudioCountableUrl$i.mp3')) {
          await _playlist.add(AudioSource.uri(Uri.parse('$mp3AudioCountableUrl$i.mp3')));
          print('😆playlistに追加しました。lastIndexは[${_playlist.length - 1}]、[${_playlistPlayer.currentIndex}]を再生中');
          break;
        } else {
          print('😴まだ再生できないので$retry秒待ちます');
          await Future.delayed(Duration(seconds: retry));
        }
      }
    }

    print('🥰全ACのプレイリストへの追加が完了しました');
  }

  // 😎HTTPリクエスト(GET)を出す。エラーならerroredMapを返す.
  static Future<Map<String, dynamic>> _accessAPI(String url) async {
    try {
      // おぶじぇくとを作る。『DartでHTTPリクエストを送信する』より.
      final requestObject = await HttpClient().getUrl(Uri.parse(url));
      final responce = await requestObject.close();
      final responceBodyText = await utf8.decodeStream(responce);
      print('🎃${DateTime.now()} レスポンスJSONは$responceBodyText');
      // PADでいうところのカスタムオブジェクトに変換。『【Flutter】JSONをデコードする』より.
      final responceBodyMapped = json.decode(responceBodyText);
      return responceBodyMapped;
    } catch (e) {
      // ネット未接続だと例外発生.
      return {'success': false, 'errorMessage': '何かしらのエラーです！😰$e'}; // 一応APIエラー時のパロディ仕様.
    }
  }

  // 🧐再生できるかチェックする。関数内の関数がクラス内のプライベートメソッドに昇格。中身同じでもゴージャスに聞こえる.
  static Future<bool> _checkAudioUrlPlayable(String mp3Url) async {
    try {
      final requestObject = await HttpClient().getUrl(Uri.parse(mp3Url));
      final response = await requestObject.close(); // れすぽんせ.
      if (response.statusCode == 200) {
        print('🤖${DateTime.now()} $mp3Url は再生できマス');
        return true;
      } else {
        print('👻${DateTime.now()} まだ$mp3Url は再生できません！ステースタスコード${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('🤗キャッチ！ネットワークエラーかも$e');
      return false;
    }
  }

  // 😚このクラスのインスタンスが作成されたとき動かす初期化処理.
  void _initialize() async {
    await _playlistPlayer.setAudioSource(_playlist); // .setAudioSourceするたびリスト先頭に戻るため1回だけ行う.
  }
}
// （下ほど新しいコメント）.
// ↑mp3StreamingUrlを使うと英単語の多い文において（たぶん合成が追いつかず）先頭から再生をやり直すことがある.
// このとき例外は発生していないので、.play()メソッド内でリトライが起きているのだと思う.
// セリフ中のアルファベットの数に応じてウェイトを設けることで対策するとか？🤨.
// タスクマネージャー見ると再生開始の瞬間だけネットワーク使ってる。そもそもストリーミングしてなくね？→後に誤りと判明.
// 単純な.playでは、mp3StreamingUrlに対応できなかった…！.
// 1コ1コオブジェクトを作って再生するのでは間隔が長くなる。gapless playlistを使ってみよう.
// 合成にかかる時間 - mp3の再生時間 だけ待ったタイミングでストリーミング開始が理想。合成完了に追いつく.
// とりあえず50%合成完了を検出するまで待機してみる.
// 0.mp3からAudioCount-1.mp3までが生成される。リストと同じ.
// AudioCount = 1のときは待たなくても再生できる…は誤り。句読点のない長文のAudioCountは1なのだから.
// 「途中から句読点がなくなる長文」の場合、AudioCountであれやこれやはむりぽでは？罠？.
// Wikipediaのような、適度に区切られた高品質なテキストではうまくいく.
// 合成完了時刻を推測するのは無理がある。「あるAudioCountの合成に必要な時間」はテキスト次第でいくらでも伸ばせるからね.
// .setUrlのPreloadをfalseにすればその時点でURLが再生可能でなくても例外にならず、setUrlにかかる時間が130ms→6msへ短縮。.loadにそのぶん時間がかかる.
// 前半ひらがなばかりの文、後半英文のようにされると非常に困る.
// 長いAudioCountのための待ち時間が、そのAudioCountの再生開始 "前" に発生する。前提からしておかしいぜ.
// リストに内蔵したaudioPlayerオブジェクトを非同期で再生しつつその隙に次のsetUrlをするシステム…再生が完了せずFutureが解除しない状態が発生.
// 残りバッファを表示するにはprint('再生位置は${player.position}😐バッファ時間は${player.bufferedPosition}');.
// ストリーミングURLの場合はpreload:trueのほうがよさげ.
// プレイリスト再生で合成中に追いついた場合スキップされる。.currentIndexStream.listenの番号が飛ぶということはなかった.
// プレイリスト再生でスキップされると、プレイリスト(ConcatenatingAudioSource型).sequence[スキップされたインデックス].durationがnullになる.
// →じゃあ検出したら巻き戻してスキップされたaudioCountが合成できるまで待って再生すりゃええ思うやろ？.pauseやら.seekやらが思ったとおりに動かないんじゃい！！.
// 再生可能チェックはAudioPlayerを使うと>3100msかかったので古風なやり方に。HttpClientなら<150msで判断可能.
// DateTime.now()の方が書きやすいし見やすい～（ハチワレ）.
// かくしてgapless playlists + 先読み再生可能チェック + 再生中ポーズにたどり着いたのである（「のだ」はミーム汚染のため回避）.
// ポーズ前とポーズ中で先読みdistanceを変えるとよりインテリジェントやね.
// 読み方辞書機能によって安定性低下の要因である英単語のスペル読みが解消（できるようになった）。じゃんじゃん登録しよう！！.
// クラス化すればプレイリストが空になってもplayerオブジェクトはクラス変数として保持されているので好きなタイミングでプレイリストに追加すれば再生される！Streamなんていらんかったんや！.
// .setAudioSourceするとその都度[0]から再生になる（?付き引数になっている）.
// プレイリストが空のとき.playするとプレイリストに追加されるまで待つモードになる。アプリの外からは再生中として扱われるので待ちかねてYouTube見始めると追加しても鳴り始めない.
// 順番待ちシステムができた！長文分割投稿システムとのシナジー効果大爆発（WaitingListの制御から目をそらしながら）.
// ユーザーが入力したものは「テキスト」、音声合成に最適化したものは「セリフ」。辞書機能の追加時とか[いつ？]区別しやすくなる。…と当初は思ってました.
// なぜか急に重くなる問題（は？）、compute関数でマルチスレッド化しても変化なし。まさか辞書UIがあかんのか？.
// 順番待ちギミック部分を.syntheにまとめたい。"途中でreturn設けるときは注意👺" とか書かなければならないほど複雑.
// 読み方辞書を用いたテキスト→セリフ変換をこっちに持ってきた。辞書の変更がリアルタイムに反映されるようになるが流用性は薄れる.
// オーダーをmessageIDで待つことにしたので、同じmessageIDが「佐藤さ～ん」「「はい」」のように動き出す可能性がある.
// 2重オーダー防止のため、すでに列に並んでいるか確認可能にした。_orderWaitingListのプライベートを解除すればよかったのでは…？.
// _orderWaitingListがいつどんな状態に変化しようと動き続ける仕組みが必要になってしまった。でもこれによってメッセージ削除と並び替えに連動できるようになる！たぶん！！.
// 2重オーダー防止チェック、こんなことしてると「リストに載っているが人はいない」状態になったら詰んでしまわへんか？.
// 一連の再改造で、意図した順番通りに合成される確率を上げることができた（と思う）。かわりに複雑さが爆発した（断定）.

// メッセージ再再生関連を一挙に制御するクラス作ったった！.
class AudioPlayManager {
  List<AudioPlayer> _playerObjects = []; // 連打に対応するため複数のプレーヤーインスタンスを格納する.

  // メッセージ単発を再生するメソッド。連打できることは何より大事🫨.
  Future<bool> playFromMessage(types.Message message) async {
    final player = AudioPlayer(); // 『[flutter]just_audioで音を再生する』.
    _playerObjects.add(player);
    final index = _playerObjects.length - 1; // 連打すると位置がずれるので.last.playとかにしない.

    final mp3DownloadUrl = message.metadata?['mappedAudioURLs']['mp3DownloadUrl'];
    try {
      await _playerObjects[index].setUrl(mp3DownloadUrl);
      await _playerObjects[index].play();
      return true;
    } catch (e) {
      print('キャッチ！🤗${message.id}の$mp3DownloadUrlは$eのためアクセスできませんでした。現場からは以上です。');
      return false; // 再生できないURLなら例外になる。やっぱ例外だすんやね😮‍💨.
    }
  }

  // 連続再生するメソッド.
  void playFromMessages(List<types.Message> messages) {
    // 公式pub.devのReadme #Working with gapless playlists.
    final playlist = ConcatenatingAudioSource(
      useLazyPreparation: false,
      children: [],
    );
    for (var pickedMessage in messages) {
      final mp3DownloadUrl = pickedMessage.metadata?['mappedAudioURLs']['mp3DownloadUrl'];
      if (mp3DownloadUrl != null) {
        playlist.add(AudioSource.uri(Uri.parse(mp3DownloadUrl)));
      }
    }

    final playlistPlayer = AudioPlayer();
    _playerObjects.add(playlistPlayer); // 2つの "リスト" があるので注意🙈.
    final index = _playerObjects.length - 1;

    _playerObjects[index].setAudioSource(
      playlist,
      preload: true,
    );
    _playerObjects[index].play(); // アクセスできんURLがあっても例外出さないっぽい.
    // ぬるぽ出すタイミングがなくなった。コイツだけ再生されへんなーってのは自力で発見すべし.
  }

  // すべてストップするメソッド.
  void stop() {
    // Pickした場合コピーに対する操作になるのでstopが効かない。直接指定するとヨシ😹.
    for (var i = 0; i < _playerObjects.length; i++) {
      _playerObjects[i].dispose();
    }
    _playerObjects = [];
  }
} // オブジェクト指向、完全に理解した.
