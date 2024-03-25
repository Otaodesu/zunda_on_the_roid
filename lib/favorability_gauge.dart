import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart'; // 🤩🤩🤩🤩🤩.
import 'package:shared_preferences/shared_preferences.dart';

// 謎機能「好感度ゲージ」。手動のお気に入り登録ではなく、もっと実態を見るべきだ！とか思ったんです.
// マップ形式なので一度も使ったことのない話者IDはnull。事後報告でキーが増えていく仕様.

// 話者の使用回数を1増やして記録する関数.
void incrementSpeakerUseCount({required int speakerId}) async {
  final speakerIdUseCountMap = await _loadSpeakerIdUseCountMap();
  final speakerIdUseCount = speakerIdUseCountMap[speakerId] ?? 0;
  speakerIdUseCountMap[speakerId] = speakerIdUseCount + 1;
  _saveSpeakerIdUseCountMap(speakerIdUseCountMap);
}

// 好感度ゲージを作ってテイクアウトする関数。あとで左右反転すること🙃.
Future<RatingBar> takeoutSpeakerFavorabilityGauge(int speakerId) async {
  final speakerIdUseCountMap = await _loadSpeakerIdUseCountMap();
  final speakerIdUseCount = speakerIdUseCountMap[speakerId] ?? 0;
  final speakerFavorabilityRateMax5 = 5 * speakerIdUseCount / (4 + speakerIdUseCount); // ☆の数を算出。1回使用で☆1にしたい.

  return RatingBar(
    ignoreGestures: true,
    allowHalfRating: true,
    initialRating: speakerFavorabilityRateMax5,
    itemCount: 5, // Rating > itemCountになるとバーが消える🤔.
    itemSize: 20,
    ratingWidget: RatingWidget(
      full: Icon(Icons.star_rounded, color: Colors.lightGreen.shade200), //
      half: Icon(Icons.star_half_rounded, color: Colors.lightGreen.shade200), // 色決めるのムズ！異物感がなく文字より目立たずアイコンにマッチするもの…🤯.
      empty: const Icon(null),
    ),
    onRatingUpdate: (rating) {
      print(rating);
    },
  );
}

// 話者ID-使用回数マップをロードする関数.
Future<Map<int, int>> _loadSpeakerIdUseCountMap() async {
  final prefsInstance = await SharedPreferences.getInstance();
  final asJsonableMapAsText = prefsInstance.getString('speakerIdUseCountMap'); // キー名の変更時は要注意☢.
  print('${DateTime.now()}😎$asJsonableMapAsTextを取り出しました');

  if (asJsonableMapAsText != null) {
    final speakerIdUseCountMap = <int, int>{};
    final Map<String, dynamic> asJsonableMap = json.decode(asJsonableMapAsText);

    asJsonableMap.forEach((stringKey, intValue) {
      speakerIdUseCountMap[int.parse(stringKey)] = intValue;
    });
    return speakerIdUseCountMap;
  } else {
    return {}; // 🤔.
  }
}

// 話者ID-使用回数マップを保存する関数.
void _saveSpeakerIdUseCountMap(Map<int, int> updatedSpeakerIdUseCountMap) async {
  final asJsonableMap = <String, int>{}; // JSONのキーはStringのみ対応のため変換していく😫.

  updatedSpeakerIdUseCountMap.forEach((intKey, intValue) {
    asJsonableMap[intKey.toString()] = intValue;
  });
  final asJsonableMapAsText = json.encode(asJsonableMap);
  final prefsInstance = await SharedPreferences.getInstance();
  await prefsInstance.setString('speakerIdUseCountMap', asJsonableMapAsText); // キー名の変更時は要注意☘.
  print('${DateTime.now()}😆$asJsonableMapAsTextとして保存したでな');
}
