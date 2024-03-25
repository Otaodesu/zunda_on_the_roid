import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ui_dialog_classes.dart';

// 読み方辞書=TextDictionary。実態はbeforeをafterに置換するだk…素晴らしいシステム.
// すっごい文脈依存なtextDictionaryなる表現が繰り返されている！明日にはきっと理解できない🤯.

// 辞書編集画面を呼び出す関数.
void showDictionaryEditPage(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => const _TextDictionaryEditPage(),
    ),
  );
}

class _TextDictionaryEditPage extends StatefulWidget {
  const _TextDictionaryEditPage();
  @override
  State<_TextDictionaryEditPage> createState() => _TextDictionaryEditPageState();
}

// 読み方辞書編集画面.
class _TextDictionaryEditPageState extends State<_TextDictionaryEditPage> {
  List<TextEditingController> beforeControllers = [];
  List<TextEditingController> afterControllers = []; // 文字入力欄コントローラーを格納するリスト。左右独立管理🙈.

  @override // ↓asyncにするとおそろしい画面出る.
  void initState() {
    super.initState();
    _orderLoadTextDictionary();
  }

  void _orderLoadTextDictionary() async {
    // ↓ローカルにできるやん🤬😡😌入力欄の表示に必須な2つのTextEditingControllerリストだけ考えればOK.
    final loadedTextDictionary = await _loadTextDictionary();
    for (var pickedItem in loadedTextDictionary) {
      setState(() {
        beforeControllers.add(TextEditingController(text: pickedItem.before));
        afterControllers.add(TextEditingController(text: pickedItem.after));
      });
      // ここに1sec待機入れると順番に表示されていくのが見える。つまりinitState完了後に画面遷移ではないっぽい。asyncやしね.
      // ループ後にsetStateでは極端に項目数が多いとなかなか表示されなくなりそう.
    }
  }

  void _handleHamburgerPressed() {
    showDialog<String>(
      context: context,
      builder: (_) => HamburgerMenuForTextDictionary(
        onExportDictionaryPressed: _showDictionaryExportView,
        onImportDictionaryPressed: _letsImportDictionary,
        onDeduplicatePressed: _deduplicateItems,
      ),
    );
  }

  void _showDictionaryExportView() {
    final exportingDictionary = <TextDictionaryItem>[];
    for (var i = 0; i <= beforeControllers.length - 1; i++) {
      exportingDictionary.add(TextDictionaryItem(before: beforeControllers[i].text, after: afterControllers[i].text));
    }
    final exportingText = jsonEncode(exportingDictionary);
    showAlterateOfKakidashi(context, exportingText);
  }

  // 辞書インポート機能。どんなJSONが入ってくるかまるでチェックしてないけどヨシ！😸.
  void _letsImportDictionary() async {
    final whatYouInputed = await showEditingDialog(context, 'ずんだ');
    // ↕時間経過あり。今回はそんな関係ないけど.
    if (whatYouInputed == null) {
      await Fluttertoast.showToast(msg: 'ぬるぽ');
      return;
    }
    try {
      final additionalDictionaryAsDynamic = await json.decode(whatYouInputed); // JSONでない場合ここで例外.
      for (var pickedItem in additionalDictionaryAsDynamic.reversed) {
        setState(() {
          beforeControllers.insert(0, TextEditingController(text: pickedItem['before']));
          afterControllers.insert(0, TextEditingController(text: pickedItem['after']));
        });
      } // JSONだけどもリストじゃない場合ここで例外？ text:はnullableなのでキーがなくても許される.
    } catch (e) {
      await Fluttertoast.showToast(msg: '😾これは読み方辞書ではありません！\n$e');
      return;
    }
    await Fluttertoast.showToast(msg: '😹インポートに成功しました！！！');
  }

  // 重複削除機能。処理中に編集されると非常にマズいけど超高速なので問題ナシ！.
  void _deduplicateItems() {
    final beforeLengthBackup = beforeControllers.length;

    // リスト内包表記。4行を1行にするすばらしいギミック。明日の自分に理解できるかは疑問符.
    final beforeCopies = [for (var pickedItem in beforeControllers) pickedItem.text];
    for (var i = beforeCopies.length - 1; i >= 0; i--) {
      if (beforeCopies[i] == '') {
        continue; // Beforeを空欄にしてAfterにメモを書く使い方をしているので削除しない😶‍🌫️.
      }
      if (beforeCopies.indexWhere((element) => element == beforeCopies[i]) != i) {
        print('${DateTime.now()}🤯${beforeCopies[i]}は重複しているので排除します');
        _deleteItem(i);
        beforeCopies.removeAt(i);
      }
    }
    Fluttertoast.showToast(msg: '😇${beforeLengthBackup - beforeControllers.length}個の項目を削除しました！');
  }

  void _deleteItem(int index) {
    setState(() {
      beforeControllers.removeAt(index);
      afterControllers.removeAt(index);
    });
  }

  void _addNewItem() {
    setState(() {
      beforeControllers.insert(0, TextEditingController(text: ''));
      afterControllers.insert(0, TextEditingController(text: ''));
    });
  }

  @override
  void dispose() {
    // 入力欄を読み取って辞書にしていく.
    final savingTextDictionary = <TextDictionaryItem>[];
    for (var i = 0; i <= beforeControllers.length - 1; i++) {
      savingTextDictionary.add(TextDictionaryItem(before: beforeControllers[i].text, after: afterControllers[i].text));
    }
    _saveTextDictionary(savingTextDictionary);

    for (var i = 0; i <= beforeControllers.length - 1; i++) {
      beforeControllers[i].dispose();
      afterControllers[i].dispose();
    }
    super.dispose();
  } // 果たしてこの青線推奨の順番が見やすいんでしょうか🤔.

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: ThemeData(
          fontFamily: 'Noto Sans JP',
          colorScheme: const ColorScheme.light(), // なんでAppBar紫やねん！.
        ),
        home: Scaffold(
          appBar: AppBarForTextDictionary(
            onAddTap: _addNewItem,
            onHamburgerPress: _handleHamburgerPressed,
          ),
          body: Scrollbar(
            radius: const Radius.circular(10),
            child: ListView.builder(
              itemCount: beforeControllers.length,
              itemBuilder: (context, index) => Row(
                children: [
                  const SizedBox(width: 15), // 画面左端の余白はここ.
                  Expanded(
                    child: TextFormField(
                      controller: beforeControllers[index],
                    ),
                  ),
                  const Icon((Icons.navigate_next_rounded)),
                  Expanded(
                    child: TextFormField(
                      controller: afterControllers[index],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _deleteItem(index),
                    icon: const Icon(Icons.delete_rounded),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

// あ～あ～関数まで入れちゃって😩.

void _saveTextDictionary(List<TextDictionaryItem> savingTextDictionary) async {
  final textDictionaryAsText = jsonEncode(savingTextDictionary);
  final prefsInstance = await SharedPreferences.getInstance();
  await prefsInstance.setString('textDictionary', textDictionaryAsText); // キー名の変更時は要注意☢.
  print('${DateTime.now()}😆$textDictionaryAsTextとして保存したでな');
}

Future<List<TextDictionaryItem>> _loadTextDictionary() async {
  final prefsInstance = await SharedPreferences.getInstance();
  final textDictionaryAsText = prefsInstance.getString('textDictionary'); // キー名の変更時は要注意☘.
  print('${DateTime.now()}😎$textDictionaryAsTextを取り出しました');
  if (textDictionaryAsText != null) {
    final textDictionaryAsDynamic = await json.decode(textDictionaryAsText);
    final textDictionary = <TextDictionaryItem>[];
    for (var pickedItem in textDictionaryAsDynamic) {
      textDictionary.add(TextDictionaryItem(before: pickedItem['before'], after: pickedItem['after']));
    } // こんなのウソでしょ…なぜなんです…😨.
    return textDictionary;
  } else {
    const defaultTextDictionary = <TextDictionaryItem>[
      TextDictionaryItem(before: '行っていく', after: 'おこなっていく'),
      TextDictionaryItem(before: 'AM5(?=[^時])', after: 'AMファイブ'),
    ];
    return defaultTextDictionary;
  }
} // 予想外に高速や.

// 辞書を適用して文字列置換する関数。ここが本命であとは脇役なんだけどなぁ.
Future<String> convertTextToSerif(String text) async {
  print('${DateTime.now()}🥱辞書をロードします');
  final textDictionary = await _loadTextDictionary();
  for (var pickedItem in textDictionary) {
    if (pickedItem.before == '') {
      continue;
    }
    try {
      text = text.replaceAll(RegExp(pickedItem.before), pickedItem.after); // 単語優先度？😌最高だ.
    } catch (e) {
      await Fluttertoast.showToast(msg: '${pickedItem.before}\nは不正な正規表現です😫');
      print('キャッチ🤗 $e');
    }
  }
  print('${DateTime.now()}置換しました😊$text');
  return text;
}

/// 型を定義してまとめてみる。なるほどクラスが型の正体なのか🤔型付きの値はインスタンスなのね.
class TextDictionaryItem {
  const TextDictionaryItem({required this.before, required this.after}); // コンストコンストラクタでコンストのインスタンスも作れるようになる🦊.

  final String before;
  final String after;

  // "toJson" は決め打ち！jsonEncode関数がこの名前を探して変換に使うため😧.
  Map<String, String> toJson() => {
        'before': before,
        'after': after,
      };
}

class AppBarForTextDictionary extends StatelessWidget implements PreferredSizeWidget {
  const AppBarForTextDictionary({
    super.key,
    this.onAddTap,
    this.onHamburgerPress, // 🍔はプレスするものだからPress.
  });

  final VoidCallback? onAddTap;
  final VoidCallback? onHamburgerPress;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) => AppBar(
        title: const Text('読み方辞書', style: TextStyle(color: Colors.black54)),
        backgroundColor: Colors.white.withAlpha(230),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
        ),
        actions: [
          Tooltip(
            message: '項目を追加する',
            child: IconButton(
              // ←←エディターにアイコンのプレビュー出るのヤバくね！？.
              icon: const Icon(Icons.add_rounded),
              onPressed: onAddTap,
            ),
          ),
          Tooltip(
            message: '読み方辞書のオプションを表示する',
            child: IconButton(
              icon: const Icon(Icons.more_vert_rounded),
              onPressed: onHamburgerPress,
            ),
          ),
        ],
      );
  // SliverAppBar…うーん必要性…まぁええわ😐.
}

// ハンバーガーメニュー.
class HamburgerMenuForTextDictionary extends StatelessWidget {
  const HamburgerMenuForTextDictionary({
    super.key,
    this.onExportDictionaryPressed,
    this.onImportDictionaryPressed,
    this.onDeduplicatePressed,
  });

  final VoidCallback? onExportDictionaryPressed;
  final VoidCallback? onImportDictionaryPressed;
  final VoidCallback? onDeduplicatePressed;

  @override
  Widget build(BuildContext context) => SimpleDialog(
        title: const Text('アクション選択'),
        surfaceTintColor: Colors.green,
        children: [
          SimpleDialogOption(
            onPressed: onExportDictionaryPressed,
            child: const ListTile(
              leading: Icon(Icons.output_rounded),
              title: Text('辞書を書き出す（.json）'),
            ),
          ),
          SimpleDialogOption(
            onPressed: onImportDictionaryPressed,
            child: const ListTile(
              leading: Icon(Icons.exit_to_app_rounded),
              title: Text('辞書を読み込む（.json）'),
            ),
          ),
          SimpleDialogOption(
            onPressed: onDeduplicatePressed,
            child: const ListTile(
              leading: Icon(Icons.layers_clear_rounded),
              title: Text('重複を削除する'),
            ),
          ),
        ],
      );
}
