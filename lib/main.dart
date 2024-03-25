import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mime/mime.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'favorability_gauge.dart';
import 'launch_chrome.dart';
import 'synthesizeSerif.dart'; // これで自作のファイルを行き来できるみたい.
import 'text_dictionary_editor.dart';
import 'ui_dialog_classes.dart';

// 真っ赤ならターミナルでflutter pub get.
// ビルド時65536を超えるなら『[Flutter/Android]Android 64k問題を回避するための設定方法』.

void main() {
  // 日本時間を適用して、それからMyAppウィジェットを起動しに行く.
  initializeDateFormatting().then((_) => runApp(const MyApp()));
}

// 静的なウィジェットを継承したクラスを作る.
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: ThemeData(
          fontFamily: 'Noto Sans JP', // このへん『Flutterの中華フォントを直す』に合わせた.
        ),
        home: const ChatPage(), // ここはconstの方がPerformanceがいいんだとよ.
      );
}

// ここはステートを持つ動的ウィジェット.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

// ↑↓何が起こってるんだ…！何も起こってないのか…？.
class _ChatPageState extends State<ChatPage> {
  List<types.Message> _messages = [];

  List<Widget> _characterSelectButtons = []; // 話者選択ボタンを格納する.
  // _charaDicをここに保持しない仕様にしたが、おそらくまた必要になるしわかりにくくなった説もある😐.

  // 誰が投稿するのかはこのフォーマットで決める。起動直後の話者はここ.
  var _user = const types.User(
    id: '388f246b-8c41-4ac1-8e2d-5d79f3ff56d9',
    firstName: 'デフォルトスピーカー', // 追加した.
    lastName: 'デフォルトスタイル',
    updatedAt: 3, // これがspeakerId😫 スタイル違いも右に表示するにはこれしかなかったんだ…！.
  ); // 後から変更したいプロパティは必須プロパティでなくても初期化が必要だとわかった.

  final playerKun = AudioPlayManager(); // プレーヤーくん爆誕。以後は彼に頼んでください.
  final synthesizerChan = NewSuperSynthesizer(); // シンセサイザーちゃんも爆誕。特に対応関係とかはないです.

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _loadSpeakerSelectButtons(); // 話者選択ボタンを準備する.
  }

  void _addMessage(types.Message message, [int position = 0]) {
    // 安全装置: 《セリフを追加する》で長文を分割追加中に《すべて削除する》するとRangeErrorになるため.
    if (position < 0 || _messages.length < position) {
      position = 0;
    }
    setState(() {
      _messages.insert(position, message);
    });
  }

  // 画面左下の添付ボタンで動き出す関数.
  void _handleAttachmentPressed() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true, // これ追加するだけでスクロールし始めた。見直したぜFlutter(カッコがやばい).
      builder: (BuildContext context) => SafeArea(
        child: SizedBox(
          // SizedBoxで領域を指定してその中全面にSingleChildScrollViewを表示する。よくできてる！(カッコがやばい).
          height: MediaQuery.of(context).size.height * 0.8,
          child: Scrollbar(
            radius: const Radius.circular(10),
            child: SingleChildScrollView(
              // 最上段に突き当たると自動で閉じてほしい欲が出てくる。RefreshIndicatorでpopを発動すればできそう.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _characterSelectButtons, // 最終的に表示する中身がこれ。先に準備できている必要がある.
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleFileSelection() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);

    if (result != null && result.files.single.path != null) {
      final message = types.FileMessage(
        author: _user,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        id: const Uuid().v4(),
        mimeType: lookupMimeType(result.files.single.path!),
        name: result.files.single.name,
        size: result.files.single.size,
        uri: result.files.single.path!,
      );

      _addMessage(message);
    }
  }

  void _handleImageSelection() async {
    final result = await ImagePicker().pickImage(
      imageQuality: 70,
      maxWidth: 1440,
      source: ImageSource.gallery,
    );

    if (result != null) {
      final bytes = await result.readAsBytes();
      final image = await decodeImageFromList(bytes);

      final message = types.ImageMessage(
        author: _user,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        height: image.height.toDouble(),
        id: const Uuid().v4(),
        name: result.name,
        size: bytes.length,
        uri: result.path,
        width: image.width.toDouble(),
      );

      _addMessage(message);
    }
  }

  // キャラ選択から選んだとき呼び出す関数.
  void _handleCharactorSelection({required types.User whoAmI}) async {
    setState(() {
      _user = whoAmI;
    });
    print('ユーザーID${_user.id}、話者ID${_user.updatedAt}の姓${_user.firstName}名${_user.lastName}さんになりました');

    incrementSpeakerUseCount(speakerId: whoAmI.updatedAt ?? -1); // 禍根: ID-1の使用履歴が増えるかも.
    _loadSpeakerSelectButtons(); // 好感度ゲージを更新するためにリロードする.
  }

  void _handleMessageTap(BuildContext _, types.Message message) async {
    if (message is types.FileMessage) {
      var localPath = message.uri;

      if (message.uri.startsWith('http')) {
        try {
          final index = _messages.indexWhere((element) => element.id == message.id); // Idからメッセージの位置を逆引きしてる.
          final updatedMessage =
              (_messages[index] as types.FileMessage).copyWith(isLoading: true); // 特定のプロパティだけ上書きしつつコピーしてる.

          setState(() {
            _messages[index] = updatedMessage;
          }); // これできるのかよ！🤯コロンブスの卵というかなんというか.

          final client = http.Client();
          final request = await client.get(Uri.parse(message.uri));
          final bytes = request.bodyBytes;
          final documentsDir = (await getApplicationDocumentsDirectory()).path;
          localPath = '$documentsDir/${message.name}';

          if (!File(localPath).existsSync()) {
            final file = File(localPath);
            await file.writeAsBytes(bytes);
          }
        } finally {
          final index = _messages.indexWhere((element) => element.id == message.id);
          final updatedMessage = (_messages[index] as types.FileMessage).copyWith(isLoading: null);

          setState(() {
            _messages[index] = updatedMessage;
          });
        }
      }
      await OpenFilex.open(localPath);
    } else if (message is types.TextMessage) {
      print('ふきだしタップを検出。メッセージIDは${message.id}。再再生してみます！');
      final isURLStillPlayable = await playerKun.playFromMessage(message); // 再生してみて成否を取得.
      if (!isURLStillPlayable) {
        _synthesizeFromMessage(message); // 再合成する。連打しないでね🫡.
      }
    }
  }

  // ふきだしを長押ししたときここが発動.
  void _handleMessageLongPress(BuildContext _, types.Message message) {
    print('メッセージ${message.id}が長押しされたのを検出しました😎型は${message.runtimeType}です');

    if (message is! types.TextMessage) {
      print('TextMessage型じゃないので何もしません');
      return; // あらかじめフィルターする.
    }

    showDialog<String>(
      context: context,
      builder: (_) => FukidashiLongPressDialog(
        // ↕操作するまで時間経過あり。この隙にmessageが書き換わってる可能性（合成完了時など）があるのでUUIDを渡す.
        onAddMessageBelowPressed: () => _addMessageBelow(message.id),
        onChangeSpeakerPressed: () => _changeSpeaker(message.id, _user),
        onDeleteMessagePressed: () => _deleteMessage(message.id),
        onDownloadMp3Pressed: () => _goToDownloadPageMp3(message.id),
        onDownloadWavPressed: () => _goToDownloadPage(message.id),
        onMoveMessageUpPressed: () => _moveMessageUp(message.id),
        onMoveMessageDownPressed: () => _moveMessageDown(message.id),
      ),
    );
  }

  void _deleteMessage(String messageId) {
    final index = _messages.indexWhere((element) => element.id == messageId);
    setState(() {
      _messages.removeAt(index);
    });
    print('$messageIdを削除しました👻');
  }

  void _moveMessageUp(String messageId) {
    final index = _messages.indexWhere((element) => element.id == messageId);
    if (index + 1 == _messages.length) {
      Fluttertoast.showToast(msg: 'いじわるはやめろなのだ😫');
      return;
    }
    final temp = _messages[index];
    final updatedMessages = _messages;
    updatedMessages[index] = updatedMessages[index + 1];
    updatedMessages[index + 1] = temp;
    setState(() {
      _messages = updatedMessages;
    }); // 結構ボリュームフルになったぞ.
  }

  void _moveMessageDown(String messageId) {
    final index = _messages.indexWhere((element) => element.id == messageId);
    if (index == 0) {
      Fluttertoast.showToast(msg: 'いじわるはやめろなのだ😫');
      return;
    }
    final temp = _messages[index];
    final updatedMessages = _messages;
    updatedMessages[index] = updatedMessages[index - 1];
    updatedMessages[index - 1] = temp;
    setState(() {
      _messages = updatedMessages;
    }); // リスト上を指でスワイプして並べ替えできるUIがほしいよね？それめっちゃわかる😫.
  }

  void _goToDownloadPage(String messageId) {
    final index = _messages.indexWhere((element) => element.id == messageId);
    if (_messages[index].metadata?['mappedAudioURLs']['wavDownloadUrl'] is String) {
      Fluttertoast.showToast(msg: 'ブラウザを起動します😆');
      launchChrome(_messages[index].metadata?['mappedAudioURLs']['wavDownloadUrl']);
    } else {
      Fluttertoast.showToast(msg: 'まだ合成していません🤔'); // これだけでトースト表示😘.
      return;
    }
  }

  void _goToDownloadPageMp3(String messageId) {
    final index = _messages.indexWhere((element) => element.id == messageId);
    if (_messages[index].metadata?['mappedAudioURLs']['mp3DownloadUrl'] is String) {
      Fluttertoast.showToast(msg: 'ブラウザを起動します😆');
      launchChrome(_messages[index].metadata?['mappedAudioURLs']['mp3DownloadUrl']);
    } else {
      Fluttertoast.showToast(msg: 'まだ合成していません🤔'); // これだけでトースト表示😘.
      return;
    }
  }

  void _addMessageBelow(String messageId) async {
    final index = _messages.indexWhere((element) => element.id == messageId);
    final inputtedText = await showEditingDialog(context, '${_user.firstName}（${_user.lastName}）');
    // ↕時間経過あり.
    if (inputtedText == null) {
      await Fluttertoast.showToast(msg: 'ぬるぽ');
      return;
    }
    final partialText = types.PartialText(text: inputtedText);
    _handleSendPressed(partialText, index); // これによって長文分割に対応.
    // 長文を分割追加中に《すべて削除する》すると順番がおかしくなるのは_addMessageの安全装置によるもの😫.
  }

  void _changeSpeaker(String messageId, types.User afterActor) {
    final index = _messages.indexWhere((element) => element.id == messageId);
    final updatedMessage = (_messages[index] as types.TextMessage).copyWith(
      id: const Uuid().v4(), // WavとメッセージIDを1対1関係にしたいので新造.
      author: afterActor,
    );
    setState(() {
      _messages[index] = updatedMessage;
    });

    if (updatedMessage is! types.TextMessage) {
      return;
    } // ↓のために型を確認してあげる。文脈上TextMessageやと思うけどなぁ.
    _synthesizeFromMessage(updatedMessage);
    print('👫$messageIdの話者を変更して${updatedMessage.id}に置換しました');
  }

  void _handlePreviewDataFetched(types.TextMessage message, types.PreviewData previewData) {
    final index = _messages.indexWhere((element) => element.id == message.id);
    final updatedMessage = (_messages[index] as types.TextMessage).copyWith(previewData: previewData);

    setState(() {
      _messages[index] = updatedMessage;
    });
  }

  // 送信ボタン押すときここが動く。《セリフを追加》のときも.
  void _handleSendPressed(types.PartialText message, [int position = 0]) async {
    final splittedTexts = splitTextIfLong(message.text); // もともとPartialText.text以外投稿に反映されてないからいいよね😚.
    for (var pickedText in splittedTexts) {
      final textMessage = types.TextMessage(
        author: _user,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        id: const Uuid().v4(),
        text: pickedText,
      );
      _addMessage(textMessage, position); // 最新メッセージは[0]なのでこれでヨシ.
      _synthesizeFromMessage(textMessage); // これだけで合成できちゃうぞ～.
      await Future.delayed(const Duration(milliseconds: 500)); // 演出.
    }
  }

  // 音声合成する。TextMessage型を渡せば合成の準備から完了後の表示変更まですべてサポート！.
  void _synthesizeFromMessage(types.TextMessage message) async {
    final targetMessageId = message.id; // 合成中にメッセージの位置は変わりうるのでメッセージを更新する際はUUIDで逆引きする.

    // 重複して合成しないようにチェックする。意図しないタイミングでこれが出たら待ちリスト制御の見直しが必要.
    if (synthesizerChan.isMeAlreadyThere(targetMessageId)) {
      await Fluttertoast.showToast(msg: 'まだ合成中です🤔');
      return;
    }

    // 合成中とわかる表示に更新する.
    final indexBS = _messages.indexWhere((element) => element.id == targetMessageId);
    final updatedMessageBS = (_messages[indexBS] as types.TextMessage).copyWith(status: types.Status.sending);
    setState(() {
      _messages[indexBS] = updatedMessageBS; // BeforeSynthesize。合成完了後も更新するので取り違えないための名前😢.
    });

    final synthesizeResponce = await synthesizerChan.synthesizeText(
      text: message.text,
      speakerId: message.author.updatedAt,
      messageId: message.id,
    );
    // ↕音声合成完了までの時間経過あり.

    // 最新のメッセージIDの状況をsynthesizerChanに教える。このタイミングは↓のreturnより前、かつ長文分割合成時に適度な間隔で動かせる.
    final messageIDs = [for (var pickedMessage in _messages) pickedMessage.id];
    final sortedByPriority = messageIDs.reversed.toList(); // 上にあるメッセージから合成されてほしいため.
    synthesizerChan.organizeWaitingOrders(sortedByPriority); // ←引数は優先度順.

    // メッセージにURLマップを格納し、合成完了/合成エラーと分かる表示に更新していく.
    final indexAS = _messages.indexWhere((element) => element.id == targetMessageId); // AfterSynthesize.
    if (indexAS == -1) {
      print('🤯$synthesizeResponceに更新しようと思ったら…メッセージが消えてる！');
      return;
    } // Try-Catch使うまでもなくね？と思ったのでシンプル化した。例外出るようになったら戻すこと🤗.

    final updatedMetadataAS = _messages[indexAS].metadata ?? {}; // もとのmetadataを保持👻 空ならnull合体演算子で空Mapを作成😶.
    updatedMetadataAS['mappedAudioURLs'] = synthesizeResponce; // キーの変更時は要注意☢.

    types.Message updatedMessageAS; // スコープのためここで定義.
    if (synthesizeResponce['mp3DownloadUrl'] == null) {
      updatedMessageAS = (_messages[indexAS]).copyWith(
        status: types.Status.error,
        metadata: updatedMetadataAS,
      );
    } else {
      updatedMessageAS = (_messages[indexAS]).copyWith(
        status: types.Status.sent,
        metadata: updatedMetadataAS,
      );
    }
    setState(() {
      _messages[indexAS] = updatedMessageAS;
    });

    print('😆$targetMessageIdの音声合成が正常に完了しました!');
  }

  // User型しかやってこない。さあどうしよう.
  void _handleAvatarTap(types.User tappedUser) {
    print('$tappedUserのアイコンがタップされました');
    setState(() {
      _user = tappedUser;
    });
    // 期待するのは本家VOICEVOXと同じ動作。そんなんわかっとるわい🤧！.
    // でも直近に使ったスタイルをすぐ取り出せるから便利では？ほらほら.
  }

  // デフォチャットをアセット内からロードしてる。ここをまねてキャラクター一覧のJSONを取り込みたい.
  void _loadMessages() async {
    final response = await rootBundle.loadString('assets/messages.json');
    final messages =
        (jsonDecode(response) as List).map((e) => types.Message.fromJson(e as Map<String, dynamic>)).toList();
    setState(() {
      _messages = messages;
    });
  }

  // 選択ボタンウィジェットを準備する。好感度ゲージを更新したい場合はここを動かすこと.
  void _loadSpeakerSelectButtons() async {
    final textButtons = <TextButton>[];
    final charactersDictionary = await loadCharactersDictionary();

    // 二重ループでリストにボタンを追加しまくる。これはヤバいでPADの速度じゃありえん.
    // 起動時にリストを作って準備しておく…ことになった。毎回テイクアウトではコストがかさむため。←今は何言ってるか分かるけども….
    for (final pickedCharacter in charactersDictionary) {
      for (final pickedUser in pickedCharacter) {
        textButtons.add(
          TextButton(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${pickedUser.firstName}（${pickedUser.lastName}）'),
                Transform.flip(
                  flipX: true,
                  child: await takeoutSpeakerFavorabilityGauge(pickedUser.updatedAt ?? -1),
                ),
              ],
            ),
            onPressed: () {
              Navigator.pop(context);
              _handleCharactorSelection(whoAmI: pickedUser); // キャラ選択時にはこの関数が動く.
            },
          ),
        );
      }
    }

    // もとからあったフォト、ファイル、キャンセルのボタンも追加する.
    textButtons.add(
      TextButton(
        onPressed: () {
          Navigator.pop(context);
          _handleImageSelection();
        },
        child: const Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text('Photo'),
        ),
      ),
    );
    textButtons.add(
      TextButton(
        onPressed: () {
          Navigator.pop(context);
          _handleFileSelection();
        },
        child: const Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text('File'),
        ),
      ),
    );
    textButtons.add(
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text('Cancel'),
        ),
      ),
    );

    _characterSelectButtons = textButtons;
  }

  // メッセージを空にする.
  void _deleteAllMessages() {
    setState(() {
      _messages = [];
    });
  }

  // プロジェクトのエクスポート.
  void _showProjectExportView() {
    // ファイルを作って～、ユーザーがフォルダを選択して～、ってのが当初の予定だったんです。はい.
    // 手元のデバイスにデータを保存するのは、どこにあるかもわからないサーバーに保存するより遥かに難しい.
    final exportingText = jsonEncode(_messages);
    showAlterateOfKakidashi(
      context,
      exportingText,
    );
  }

  // テキストとしてエクスポート.
  void _showTextExportView() {
    final exportingText = makeText(_messages);
    // ↓async関数にする場合if(mounted)が必要になるかも.
    showAlterateOfKakidashi(
      context,
      exportingText,
    );
  }

  // プロジェクトのインポート。ノリで作ってしまったが絶対あぶない動き方。ヤバイ火遊び🎩🧢.
  void _letsImportProject() async {
    final whatYouInputted = await showEditingDialog(context, 'ずんだ');
    // ↕時間経過あり.
    final updatedMessages = combineMessagesFromJson(whatYouInputted, _messages);
    if (updatedMessages == _messages) {
      await Fluttertoast.showToast(msg: '😾これは.zrprojではありません！\n: $whatYouInputted');
      return;
    }
    setState(() {
      _messages = updatedMessages;
    });
    await Fluttertoast.showToast(msg: '😹インポートに成功しました！！！');
  }

  void _handleHamburgerPressed() {
    showDialog<String>(
      context: context,
      builder: (_) => HamburgerMenuForChat(
        onDeleteAllMessagesPressed: _deleteAllMessages,
        onExportProjectPressed: _showProjectExportView,
        onExportAsTextPressed: _showTextExportView,
        onImportProjectPressed: _letsImportProject,
        onEditTextDictionaryPressed: () => showDictionaryEditPage(context),
      ),
    );
  }

  // 先頭から順番に再生する関数。状態管理？😌そんなものはない.
  void _startPlayAll() async {
    final thisIsIterable = _messages.reversed; // 再生中にリストに変更が加わると例外になるためコピーする.
    final targetMessages = thisIsIterable.toList(); // なおもIterableのため固定する.
    // 些細な問題🙃: 再生中の変更が適用されない。合成完了とか.

    playerKun.playFromMessages(targetMessages);
    // なぜ人類はメソッド呼び出しをピリオドにしたのか？ "playerKun,pleasePlayFromMessage" 🫠.
  }

  void _stopPlayAll() {
    playerKun.stop(); // すぐさま止まります！.
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBarForChat(
          onPlayTap: _startPlayAll,
          onStopTap: _stopPlayAll,
          onHamburgerPress: _handleHamburgerPressed,
        ),
        body: Chat(
          messages: _messages,
          onAttachmentPressed: _handleAttachmentPressed,
          onMessageTap: _handleMessageTap,
          onMessageLongPress: _handleMessageLongPress,
          onAvatarTap: _handleAvatarTap,
          onPreviewDataFetched: _handlePreviewDataFetched,
          onSendPressed: _handleSendPressed,
          showUserAvatars: true,
          showUserNames: true,
          user: _user,
          theme: const DefaultChatTheme(
            seenIcon: Text(
              'read',
              style: TextStyle(
                fontSize: 10.0,
              ),
            ),
          ),
          l10n: ChatL10nEn(
            inputPlaceholder: '${_user.firstName}（${_user.lastName}）',
          ),
        ),
      );
}
