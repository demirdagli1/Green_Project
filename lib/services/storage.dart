import 'package:shared_preferences/shared_preferences.dart';

abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class MemoryStore implements KeyValueStore {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

class PrefsStore implements KeyValueStore {
  @override
  Future<String?> read(String key) async => (await SharedPreferences.getInstance()).getString(key);
  @override
  Future<void> write(String key, String value) async {
    await (await SharedPreferences.getInstance()).setString(key, value);
  }
}
