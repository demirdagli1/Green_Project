import 'package:characters/characters.dart';

class NameMasker {
  NameMasker._();

  /// Utanç Tablosu: grafem kümelerini bölmeden ilk 3 karakter + '***'. Boş ad: '***'.
  static String maskShameName(String name) {
    final t = name.trim();
    if (t.isEmpty) return '***';
    return '${t.characters.take(3)}***';
  }
}
