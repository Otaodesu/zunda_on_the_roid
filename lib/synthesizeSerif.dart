import 'dart:convert';
import 'dart:io';

import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:just_audio/just_audio.dart';

// ビルドしてapkにするとしゃべらない時は 『Android でインターネットに接続するためのパーミッションを設定する』かも.

// 音声合成にはsu-shiki.comさんの『WEB版VOICEVOX API（低速）』を利用させていただきます。便利なサービスを提供してくださり本当にありがたい限りです！😘.
Future<Map<String, dynamic>> synthesizeSerif({required String serif, int? speakerId}) async {
  // 1250文字あたりでtextTooLongとお叱りを受けるので思い切ってカットしてしまう.
  if (serif.length > 1010) {
    serif = serif.substring(0, 1000);
    await Fluttertoast.showToast(msg: '👺長すぎます！');
  } // 文字列が存在する必要があるのでチェック。厳格や.

  final requestUrl =
      'https://api.tts.quest/v3/voicevox/synthesis?speaker=$speakerId&text=${Uri.encodeComponent(serif)}';
  print('音声合成をオーダーするURLは$requestUrl');

  var responceBodyMapped = <String, dynamic>{'デフォルト': '中身'};
  const erroredMap = {
    'success': 'false',
    'errorMessage': '何かしらのエラーです！😰',
  }; // エラー発生時はとりまこれ返してみる.

  // 音声合成オーダーを出す。連続でオーダーを出すとretryAfter秒待てと言われるのでリトライする.
  for (var i = 0; i < 5; i++) {
    try {
      // 『DartでHTTPリクエストを送信する』より。おぶじぇくとを作る.
      final requestObject = await HttpClient().getUrl(Uri.parse(requestUrl));
      final responce = await requestObject.close();
      final responceBodyText = await utf8.decodeStream(responce);
      print('レスポンスJSONは$responceBodyText');
      // PADでいうところのカスタムオブジェクトに変換。『【Flutter】JSONをデコードする』より.
      responceBodyMapped = json.decode(responceBodyText);
    } catch (e) {
      return erroredMap; // ネット未接続だと例外発生.
    }

    if (responceBodyMapped['retryAfter'] is num) {
      // 変数のスコープってなんだ。intって127までしか入らなくないか？.
      int waitBeforeRetrySecond = responceBodyMapped['retryAfter'];
      waitBeforeRetrySecond = waitBeforeRetrySecond + 5;
      print('retryAfterのため$waitBeforeRetrySecond秒待ちます');
      await Future.delayed(Duration(seconds: waitBeforeRetrySecond));
    } else {
      print('MP3ダウンロードURLは ${responceBodyMapped['mp3DownloadUrl']}');
      break;
    }
  }

  // リトライ回数内にオーダーが受理されなかった場合はここで抜ける.
  if (responceBodyMapped['mp3DownloadUrl'] == null) {
    return erroredMap;
  }

  // ここから合成待ちフェーズ。audioCountを利用して全体の合成が完了する前に追っかけ再生する😤.

  // AudioCountを取得する。すぐアクセスすると0と返ってくるのでリトライする.
  var audioStatusMapped = {};
  for (var i = 0; i < 100; i++) {
    try {
      final requestObject = await HttpClient().getUrl(Uri.parse(responceBodyMapped['audioStatusUrl']));
      final responce = await requestObject.close();
      final responceBodyText = await utf8.decodeStream(responce);
      print('レスポンスJSONは$responceBodyText');
      audioStatusMapped = json.decode(responceBodyText);
    } catch (e) {
      return erroredMap; // ネット未接続だと例外発生.
    }

    if (audioStatusMapped['audioCount'] > 0) {
      break;
    } else {
      print('🤗まだaudioCount=0なので待ちます');
      await Future.delayed(const Duration(seconds: 2));
    }
  }
  print('😋${DateTime.now()}audioCountは${audioStatusMapped['audioCount']}です！');
  if (audioStatusMapped['audioCount'] == null) {
    return erroredMap;
  }
  final audioCount = audioStatusMapped['audioCount']; // 後からfinalに変えられるならそうしたい.

  // "数字.mp3" を後付けできるURLを作る.
  final mp3AudioCountableUrl = responceBodyMapped['mp3DownloadUrl'].toString().replaceFirst('audio.mp3', '');
  print('カウントしやすくしたURLは$mp3AudioCountableUrlです');

  // 関数内の関数.
  Future<bool> checkAudioUrlPlayable(String url) async {
    try {
      final requestObject = await HttpClient().getUrl(Uri.parse(url));
      final response = await requestObject.close(); // れすぽんせ.
      if (response.statusCode == 200) {
        print('🤖$url は再生できマス');
        return true;
      } else {
        print('👻まだ$url は再生できません！ステースタスコード${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('🤗キャッチ！ネットワークエラーかも$e');
      return false;
    }
  }

  // 一定の割合が合成完了するまで待つ。追いつくことがあるので🐁.
  const synthesizeWaitRatio = 0.4; // 割合はここ。再生が不安定なら増やしてみて.
  for (var i = 0; i < 100; i++) {
    final halfAudioCount = ((audioCount - 1) * synthesizeWaitRatio).round(); // カウント=1の時は0.mp3まで。リストと同様.
    final isHalfPlayable = await checkAudioUrlPlayable('$mp3AudioCountableUrl$halfAudioCount.mp3');
    if (isHalfPlayable) {
      print('😋${DateTime.now()}比率$synthesizeWaitRatioまで合成完了しました');
      break;
    } else {
      print('🤗まだaudioCount x$synthesizeWaitRatio =$halfAudioCountは再生できないので待ちます');
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  // ここから再生フェーズ。ジェットコースターでいうとファーストドロップ.

  // 公式pub.devのReadme #Working with gapless playlists.
  final playlist = ConcatenatingAudioSource(
    useLazyPreparation: true,
    children: [],
  );
  for (var i = 0; i <= audioCount - 1; i++) {
    await playlist.add(AudioSource.uri(Uri.parse('$mp3AudioCountableUrl$i.mp3')));
  }

  final playlistPlayer = AudioPlayer();
  await playlistPlayer.setAudioSource(
    playlist,
    preload: false,
  );

  // プレーヤーをみはr…見守るStreamSubscriptionを仕掛ける.
  playlistPlayer.currentIndexStream.listen((playingIndex) async {
    print('😸${DateTime.now()}再生インデックスは$playingIndex'); // 最初はnullになる.
    if (playingIndex != null) {
      // 未来のAudioCountが再生可能かチェックする。バッファが切れてからだとポーズできないっぽいため.
      const sakiyomiDistance = 2; // 単語がスキップされる場合は増やしてみて。毎回constしてるがええんか？.
      if (playingIndex + sakiyomiDistance <= audioCount - 1) {
        final sakiyomiAudioUrl = '$mp3AudioCountableUrl${playingIndex + sakiyomiDistance}.mp3';
        // 🙄プレイリストのindexとi.mp3の同期が前提.
        final isSakiyomiPlayable = await checkAudioUrlPlayable(sakiyomiAudioUrl);
        if (!isSakiyomiPlayable) {
          print('🙊${DateTime.now()}じゃあポーズしますよ');
          await playlistPlayer.pause();

          for (var i = 0; i < 25; i++) {
            await Future.delayed(const Duration(seconds: 3)); // 再開後即止まるなら増やしてみて.
            if (await checkAudioUrlPlayable(sakiyomiAudioUrl)) {
              break;
            }
          }

          print('😹${DateTime.now()}再開しますよ～');
          await playlistPlayer.play();
        }
      } // ↑halfAudioCountまでは重複チェックしてるけどまいっか.
    }
    // チューニングに使いやがれ print('ちなみに最終ACは${await checkAudioUrlPlayable('$mp3AudioCountableUrl${audioCount - 1}.mp3')}'); .
  });

  // こっちは再生完了を見張る。画期的やけど不思議な動き方や😣.
  var isPlaylistPlayerFinished = false;
  playlistPlayer.processingStateStream.listen((state) {
    if (state == ProcessingState.completed) {
      print('🐶再生完了だってよ');
      isPlaylistPlayerFinished = true;
    }
  });

  await playlistPlayer.play();

  // ポーズやストップするとawaitを突破するのでここで待つ。長文が途中で完了する場合は伸ばしてみて.
  for (var i = 0; i <= 500; i++) {
    await Future.delayed(const Duration(seconds: 1));
    if (isPlaylistPlayerFinished) {
      break;
    }
  }

  print('たぶん合成成功! synthesizeSerif関数を終了するよ');
  return responceBodyMapped;
}
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

// メッセージ再再生関連を一挙に制御するクラス作ったった！.
class AudioPlayManager {
  List<AudioPlayer> _playerObjects = []; // 連打に対応するため複数のプレーヤーを作り出すようにした.

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
