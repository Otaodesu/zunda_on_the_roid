import 'dart:convert';

import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

// 分ける意味ある？🐺
// →こういう系の処理を固める「その他」な場所にする予定.
// →こういう系の処理増えてきた.

// URLを入れたらChromeが起動するよ！っていう関数.
void launchChrome(String targetUrl) async {
  final url = Uri.parse(targetUrl);
  if (!await launchUrl(
    url,
    mode: LaunchMode.externalApplication,
  )) {
    throw Exception('Could not launch $url');
  }
}

// テキスト形式でエクスポートするときの内容を作るよ！っていう関数。名前適当すぎやろ.
String makeText(List<types.Message> messages) {
  final thisIsIterable = messages.reversed; // 再生中にリストに変更が加わると例外になるためコピーする.
  final targetMessages = thisIsIterable.toList(); // なおもIterableのため固定する.

  // 本家VOICEVOXの「テキスト読み込み」機能と互換性のあるテキストを作っていく😎.
  final outputList = <String>[];
  for (var pickedMessage in targetMessages) {
    if (pickedMessage is types.TextMessage) {
      final textList = pickedMessage.text.split('\n'); // 本家さまで読めるように複数行のテキストを分割する.
      for (var pickedText in textList) {
        final compatibleText = '${pickedMessage.author.firstName}(${pickedMessage.author.lastName}),$pickedText';
        print('${DateTime.now()}🤔$compatibleText');
        outputList.add(compatibleText);
      }
    }
  }

  final outputText = outputList.join('\n');
  return outputText;
}

// インポートしようとしてるJSONテキストともとのメッセージsから新しいメッセージsを作る。エラーならもとのメッセージsを返す.
List<types.Message> combineMessagesFromJson(String? jsonText, List<types.Message> beforeMessages) {
  if (jsonText == null) {
    return beforeMessages;
  }

  var additionalMessages = <types.Message>[];

  try {
    additionalMessages =
        (jsonDecode(jsonText) as List).map((e) => types.Message.fromJson(e as Map<String, dynamic>)).toList();
  } catch (e) {
    print('キャッチ！🤗$eとのことです。なんか見たことあるなこれ。');
    return beforeMessages;
  }

  final updatedMessages = <types.Message>[];

  // 新しいUUIDを振りなおす。なぜ気づかなかったんだ…😵！PADの時すら理解していたというのに…！.
  for (var pickedMessage in additionalMessages) {
    // ↓ここに入ってくるのはテキストメッセージだけじゃない.
    final updatedMessage = (pickedMessage).copyWith(
      id: const Uuid().v4(), // この際だから時刻も振り直します？.
    );
    updatedMessages.add(updatedMessage);
  }

  updatedMessages.addAll(beforeMessages);

  return updatedMessages;
}// こんなんで動くんでしょうか？私はそうは思わにあ😹←←まったくもってそうですね.
