import 'dart:convert';
import 'dart:io';

import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:just_audio/just_audio.dart';

// .apkにビルドすると喋らなくなるなら『Android でインターネットに接続するためのパーミッションを設定する』かも.

class NewSuperSynthesizer {
  // これもコンストラクタ。インスタンス生成時に実行される.
  NewSuperSynthesizer() {
    _initialize();
  }

  final _playlistPlayer = AudioPlayer();
  final _playlist = ConcatenatingAudioSource(children: []);

  // チャット画面の送信順=orderWaitingList=playlistAddWaitingListになるように制御する😦.
  final _orderWaitingList = <DateTime>[];
  final _playlistAddWaitingList = <DateTime>[];

  // 😆mainから見える唯一のメソッド.
  Future<Map<String, dynamic>> synthesizeSerif({required String serif, int? speakerId}) async {
    // 順番待ちシステム。改造後に合成できなくなったらまず疑うこと😹.
    final registrationTime = DateTime.now(); // オーダーが通ったら必ず自分のIDを消しましょう！！😹😹😹.
    _orderWaitingList.add(registrationTime);
    while (_orderWaitingList[0] != registrationTime) {
      await Future.delayed(const Duration(seconds: 1));
    }

    // 音声合成にはsu-shiki.comさんの『WEB版VOICEVOX API（低速）』を利用させていただきます。便利なサービスを提供してくださり本当にありがたい限りです！😘.
    final requestUrl =
        'https://api.tts.quest/v3/voicevox/synthesis?speaker=$speakerId&text=${Uri.encodeComponent(serif)}';
    print('😘音声合成をオーダーするURLは$requestUrl');

    var responceBodyMapped = <String, dynamic>{'デフォルト': true}; // メイン側のmappedAudioURLs.

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
    _orderWaitingList.removeAt(0); // オーダーを出したので順番を進める😸😸😸

    // それでもオーダーが受理されなかった場合はここでmainに帰る.
    if (responceBodyMapped['mp3DownloadUrl'] == null) {
      return responceBodyMapped;
    }

    // AudioCountを取得する。すぐアクセスすると0と返ってくるのでリトライする.
    var audioStatusMapped = <String, dynamic>{'デフォルト': true};
    for (var retry = 1; retry < 100; retry++) {
      audioStatusMapped = await _accessAPI(responceBodyMapped['audioStatusUrl']);

      if (audioStatusMapped['audioCount'] > 0) {
        print('😋audioCountが判明！${audioStatusMapped['audioCount']}です');
        break;
      } else if (audioStatusMapped['isAudioError'] == true) {
        return audioStatusMapped; // 絵文字だけのオーダーは合成エラー。ここでmainに帰る.
      }
      print('😴まだaudioCount=0なので$retry秒待ちます');
      await Future.delayed(Duration(seconds: retry));
    }

    // それでもaudioCountが取得できなかった場合はここでmainに帰る.
    if (audioStatusMapped['audioCount'] == null) {
      return audioStatusMapped;
    }

    await _atohaMakasero(
      mp3DownloadUrl: responceBodyMapped['mp3DownloadUrl'],
      audioCount: audioStatusMapped['audioCount'],
      registrationTime: registrationTime,
    );

    print('😊${DateTime.now()} 順番待ちId「$registrationTime」の合成完了！synthesizeSerifメソッドを終了するよ');
    return responceBodyMapped;
  }

  // 😋合成待ちフェーズと再生フェーズ。mainへのフィードバックに不要な部分なので分けてみた。分けんくてよかった？.
  Future<void> _atohaMakasero({
    required String mp3DownloadUrl,
    required int audioCount,
    required DateTime registrationTime,
  }) async {
    // プレイリスト追加を順番待ちする。このタイミングで待ち始めるということはaudioCountが準備できた順番とorderWaitingListが（偶然）一致していることが前提になる🙀.
    _playlistAddWaitingList.add(registrationTime); // あとで必ず解除すること！！😹😹😹途中でreturn設けるときは注意👺.
    while (_playlistAddWaitingList[0] != registrationTime) {
      await Future.delayed(const Duration(seconds: 1));
    }

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

    await _playlistPlayer.play(); // すでにplay中でも、リストが空でも.play可能.

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
    _playlistAddWaitingList.removeAt(0); // 追加が完了したので順番を進める😸😸😸.
  }

  // 😎HTTPリクエスト(GET)を出す。エラーならerroredMapを返す.
  Future<Map<String, dynamic>> _accessAPI(String url) async {
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
  Future<bool> _checkAudioUrlPlayable(String mp3Url) async {
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
    // .setAudioSourceするたびリスト先頭に戻るため1回だけ行う.
    await _playlistPlayer.setAudioSource(
      _playlist,
    );
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
      // 再生できないURLなら例外になる。やっぱ例外だすんやね😮‍💨.
      await Fluttertoast.showToast(msg: 'まだ合成中です🤔');
      print('キャッチ！🤗${message.id}の$mp3DownloadUrlは$eのためアクセスできませんでした。現場からは以上です。');
      return false;
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
