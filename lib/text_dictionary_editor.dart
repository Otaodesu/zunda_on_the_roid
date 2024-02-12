import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 読み方辞書=TextDictionary。実態はまぁ…beforeとafterのリストですわい.
// すっごい文脈依存なtextDictionaryなる表現が繰り返されている！明日にはきっと理解できない🤯.

// 辞書編集画面を呼び出す関数.
void showDictionaryEditWindow(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => const TextDictionaryEditWindow(),
    ),
  );
}

class TextDictionaryEditWindow extends StatefulWidget {
  const TextDictionaryEditWindow({super.key});
  @override
  State<TextDictionaryEditWindow> createState() => _TextDictionaryEditWindowState();
}

// 読み方辞書編集画面.
class _TextDictionaryEditWindowState extends State<TextDictionaryEditWindow> {
  List<TextEditingController> beforeControllers = [];
  List<TextEditingController> afterControllers = []; // 文字入力欄コントローラーを格納するリスト。左右独立管理🙈.

  List<Map<String, String>> _textDictionary = [];

  @override
  void initState() {
    super.initState();
    _orderLoadTextDictionary();
  } // ここasyncにするとおそろしい画面出る.

  void _orderLoadTextDictionary() async {
    final textDictionary = await loadTextDictionary();
    _textDictionary = textDictionary;

    // 😡😡😡こことdispose以外では_textDictionaryに触らない！両方整合性取るなんてできるはずがない🤬🤬🤬.
    for (var i = 0; i < _textDictionary.length; i++) {
      beforeControllers.add(TextEditingController(text: _textDictionary[i]['before']));
      afterControllers.add(TextEditingController(text: _textDictionary[i]['after']));
    }

    setState(() {
      beforeControllers;
    });
  }

  @override
  void dispose() {
    final savingTextDictionary = <Map<String, String>>[];
    for (var i = 0; i <= beforeControllers.length - 1; i++) {
      savingTextDictionary.add({'before': beforeControllers[i].text, 'after': afterControllers[i].text});
    }
    saveTextDictionary(savingTextDictionary);

    for (int i = 0; i < beforeControllers.length; i++) {
      beforeControllers[i].dispose();
      afterControllers[i].dispose();
    }
    print('disposeするで😆新textDictionaryは$_textDictionaryや');
    super.dispose();
  }

  void deleteItem(int index) {
    beforeControllers.removeAt(index);
    afterControllers.removeAt(index);
    setState(() {
      beforeControllers;
    });
  }

  void addNewItem() {
    beforeControllers.insert(0, TextEditingController(text: ''));
    afterControllers.insert(0, TextEditingController(text: ''));
    setState(() {
      beforeControllers;
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: ThemeData(
          fontFamily: 'Noto Sans JP',
          colorScheme: const ColorScheme.light(), // なんでAppBar紫やねん！.
        ),
        home: Scaffold(
          appBar: AppBarForTextDictionary(
            onAddTap: addNewItem,
          ),
          body: ListView.builder(
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
                  onPressed: () => deleteItem(index),
                  icon: const Icon(Icons.delete_rounded),
                ),
              ],
            ),
          ),
        ),
      );
}

// あ～あ～関数まで入れちゃって😩.

void saveTextDictionary(List<Map<String, String>> savingTextDictionary) async {
  final prefs = await SharedPreferences.getInstance();
  final textDictionaryAsText = json.encode(savingTextDictionary);
  await prefs.setString('textDictionary', textDictionaryAsText); // キー名の変更時は要注意☢.
  print('$textDictionaryAsTextとして保存したでな');
}

Future<List<Map<String, String>>> loadTextDictionary() async {
  final prefs = await SharedPreferences.getInstance();
  final textDictionaryAsText = prefs.getString('textDictionary'); // キー名の変更時は要注意☘.
  print('${DateTime.now()}😎$textDictionaryAsTextを取り出しました');
  if (textDictionaryAsText != null) {
    final List<dynamic> textDictionaryAsDynamic = json.decode(textDictionaryAsText);
    final textDictionary = <Map<String, String>>[];

    for (var pickedDynamic in textDictionaryAsDynamic) {
      textDictionary.add({'before': pickedDynamic['before'], 'after': pickedDynamic['after']});
      print(pickedDynamic['before']);
    } // こんなのウソでしょ…なぜなんです…😨.
    return textDictionary;
  } else {
    const List<Map<String, String>> defaultTextDictionary = [
      {'before': '行っていく', 'after': 'おこなっていく'},
      {'before': 'AM5(?=[^時])', 'after': 'AMファイブ'},
    ];
    return defaultTextDictionary;
  }
} // 予想外に高速や.

// 辞書を適用して文字列置換する関数.
Future<String> convertTextToSerif(String text) async {
  print('${DateTime.now()}🥱辞書をロードします');
  final textDictionary = await loadTextDictionary();
  for (var pickedItem in textDictionary) {
    final before = pickedItem['before'];
    if (before == null) {
      continue;
    }
    final after = pickedItem['after'] ?? '';
    text = text.replaceAll(RegExp(before), after); // 単語優先度？😌最高だ.
    print('${DateTime.now()} "$before" を置換しました😊$text');
  }
  return text;
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
            message: 'まだ機能がないです',
            child: IconButton(
              icon: const Icon(Icons.more_vert_rounded),
              onPressed: onHamburgerPress,
            ),
          ),
        ],
      );
  // SliverAppBar…うーん必要性…まぁええわ😐.
}
