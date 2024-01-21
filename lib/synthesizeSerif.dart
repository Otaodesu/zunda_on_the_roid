import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:just_audio/just_audio.dart';

// ビルドしてapkにするとしゃべらない時は 『Android でインターネットに接続するためのパーミッションを設定する』かも.

// 音声合成にはsu-shiki.comさんの『WEB版VOICEVOX API（低速）』を利用させていただきます。便利なサービスを提供してくださり本当にありがたい限りです！😘.
Future<Map<String, dynamic>> synthesizeSerif(
    String serif, int? speakerId, String savingUUID) async {
  // 😩メインではspeakerIdが_user.updatedAtに格納されています！
  // ToDo: #が入っていると途切れて話者が0になる.
  // ユーザーが入力したものは「テキスト」、音声合成に最適化したものは「セリフ」。辞書機能の追加時とか[いつ？]区別しやすくなる。.

  // 1250文字あたりでtextTooLongとお叱りを受けるので思い切ってカットしてしまう.
  if (serif.length > 1010) {
    serif = serif.substring(0, 1000);
    await Fluttertoast.showToast(msg: '👺長すぎます！');
  } // 文字列が存在する必要があるのでチェック。厳格や.

  var requestUrl =
      'https://api.tts.quest/v3/voicevox/synthesis?text=$serif&speaker=$speakerId';
  print('音声合成をオーダーするURLは$requestUrl');

  var WAVDownloadURL = 'スコープを関数全体に広げるためにここに書いた。';
  var MP3DownloadURL = 'チェックをすり抜けるとこのテキストが入る😨';
  Map<String, dynamic> responceBodyMapped = {'デフォルト': '中身'};

  // 音声合成オーダーを出す。
  // 連続でオーダーを出すとretryAfter秒待てと言われるのでリトライする.
  for (int i = 0; i < 5; i++) {
    // 『DartでHTTPリクエストを送信する』より。おぶじぇくとを作る.
    var requestObject = await HttpClient().getUrl(Uri.parse(requestUrl));
    var responce = await requestObject.close();
    var responceBodyText = await utf8.decodeStream(responce);
    // これでresponceBodyTextの中身はレスポンスJSONになった.
    print('responceBodyTextの中身は$responceBodyText');

    // PADでいうところのカスタムオブジェクトに変換。『【Flutter】JSONをデコードする』より.
    responceBodyMapped = json.decode(responceBodyText);

    if (responceBodyMapped['retryAfter'] is num) {
      // 変数のスコープってなんだ。intって127までしか入らなくないか？.
      int waitBeforeRetrySecond = responceBodyMapped['retryAfter'];
      waitBeforeRetrySecond = waitBeforeRetrySecond + 5;
      print('retryAfterのため$waitBeforeRetrySecond秒待ちます');
      await Future.delayed(Duration(seconds: waitBeforeRetrySecond));
    } else {
      WAVDownloadURL = responceBodyMapped['wavDownloadUrl'];
      MP3DownloadURL = responceBodyMapped['mp3DownloadUrl'];
      print('WAVダウンロードURLは$WAVDownloadURL');
      break;
    }
  }

  // 合成が完了してWAVがダウンロード可能になるまでリトライする.
  int retryTimeOutSecond = 200;
  int retryIntervalSecond = 4;

  while (retryTimeOutSecond > 0) {
    retryTimeOutSecond = retryTimeOutSecond - retryIntervalSecond;
    await Future.delayed(Duration(seconds: retryIntervalSecond));
    retryIntervalSecond = retryIntervalSecond + 2; // 徐々に伸ばす.

    var requestObjectForGetWAV =
        await HttpClient().getUrl(Uri.parse(WAVDownloadURL));
    // 処理が右から左に進むなんて激烈な違和感なんだが！！？.

    var responceOfGetWAV = await requestObjectForGetWAV.close();

    print(
      'WAVダウンロードのHTTPステータスコードは${responceOfGetWAV.statusCode}、'
      'タイムアウトまで$retryTimeOutSecond秒',
    );

    if (responceOfGetWAV.statusCode == 200) {
      print('HTTPステータスコード200が返ってきたことを式で判別できたよ');
      // 合成した音声を再生する。保存の仕方がわからなかったのでストリーミングすることにした.
      final player = AudioPlayer(); // オブジェクト？にしやんと動かんのか～い😫.
      await player.setUrl(MP3DownloadURL); // 『[flutter]just_audioで音を再生する』.
      await player.play();
      break;
    }
  }
  print('synthesizeSerif関数を終了するよ');
  return responceBodyMapped;
}

// 直下にmp3DowoloadUrlが入ったマップを入れれば再生する関数。時間経過で404ならFalse返すんでなんとかしてください.
// 廃止予定。playSerifFromMessageに統一したい.
Future<bool> playSerifByMappedURL(Map<String, dynamic> mappedURL) async {
  // 上のsynthesizeSerifと同様にダウンロード可能かチェックする.
  // ToDo audioStatusUrlから合成完了か聞きに行くほうが行儀がいいとは思いますが…！.
  // ToDo 例外は出なく…出にくくなったが重め。楽器のようにサクサク鳴らしたい.
  final String mp3DownloadUrl = mappedURL['mp3DownloadUrl'];

  var requestObjectForGetWAV =
      await HttpClient().getUrl(Uri.parse(mp3DownloadUrl));
  var responceOfGetWAV = await requestObjectForGetWAV.close();

  print(
    '$mp3DownloadUrlのHTTPステータスコードは${responceOfGetWAV.statusCode}',
  );

  if (responceOfGetWAV.statusCode == 200) {
    print('再ストリーミング再生します😆');
    final player = AudioPlayer();
    await player.setUrl(mp3DownloadUrl); // 『[flutter]just_audioで音を再生する』.
    await player.play();
    return true;
  } else {
    print('再生できません😱 時間が経ってサーバー上のキャッシュが削除されたと思われます。再合成してください');
    return false;
  }
} // 一体だれがアロー演算子なんか支持してるのかと思ったら青波線、おまえか！.

// メッセージ型を入れれば再生して成否を返す関数。再合成まではしない。↑ByとFromが混在。Byの後は仕組みの名前が自然だろう.
Future<bool> playSerifFromMessage(types.TextMessage message) async {
  // 呼び出す側が型チェックを行うことになるので手間感あるがとりま引数を制限する形にしてる.

  final mp3DownloadUrl = message.metadata?['mappedAudioURLs']['mp3DownloadUrl'];

  if (mp3DownloadUrl == null) {
    await Fluttertoast.showToast(
      msg: 'ぬるぽ', // どのセリフがぬるぽか書いてもいいけど余計かな🙊.
    );
    return false;
  }

  // 再生可能かチェックする。just_audio側でチェックできそうなもんだけど例外とか出さないんだよなぁ.
  final requestObjectForGetMP3 =
      await HttpClient().getUrl(Uri.parse(mp3DownloadUrl));
  final responceOfGetMP3 = await requestObjectForGetMP3.close();

  if (responceOfGetMP3.statusCode == 200) {
    print('😋${message.id}のMP3はアクセス可能！再生します');
    final player = AudioPlayer(); // 『[flutter]just_audioで音を再生する』.
    await player.setUrl(mp3DownloadUrl);
    await player.play();
    return true;
  } else {
    print('😓${message.id}のMP3はアクセスできませんでした。現場からは以上です。');
    return false;
  }
}
