import 'dart:async';

import 'package:flutter/services.dart';

/// Native Android köprüsünün Dart yüzü. Donanım/izin yoksa açıkça false/denied döner.
abstract class HardwareBridge {
  String? get lastError => null;
  Future<Map<String, dynamic>> capabilities();
  Future<Map<String, String>> permissionStatus();
  Future<Map<String, String>> requestPermissions(List<String> keys);
  Future<Map<String, dynamic>> startSensors();
  Future<void> stopSensors();
  Future<bool> startNfc();
  Future<void> stopNfc();
  Future<bool> showNotification(String title, String body);
  Stream<Map<String, dynamic>> get events;
}

class AndroidHardwareBridge implements HardwareBridge {
  static const MethodChannel _m = MethodChannel('com.yesiladim.ecoclan/hardware');
  static const EventChannel _e = EventChannel('com.yesiladim.ecoclan/events');

  String? _lastError;
  @override
  String? get lastError => _lastError;

  Map<String, dynamic> _map(Object? o) => o is Map ? o.map((k, v) => MapEntry(k.toString(), v)) : {};
  Map<String, String> _smap(Object? o) => _map(o).map((k, v) => MapEntry(k, v.toString()));

  @override
  Future<Map<String, dynamic>> capabilities() async {
    try {
      final res = _map(await _m.invokeMethod('capabilities'));
      _lastError = null;
      return res;
    } on MissingPluginException {
      _lastError = 'Android donanım kanalı bağlı değil';
      return {};
    } on PlatformException catch (e) {
      _lastError = 'Donanım sorgu hatası (${e.code})';
      return {};
    }
  }

  @override
  Future<Map<String, String>> permissionStatus() async {
    try {
      return _smap(await _m.invokeMethod('permissionStatus'));
    } on MissingPluginException {
      return {};
    } on PlatformException {
      return {};
    }
  }

  @override
  Future<Map<String, String>> requestPermissions(List<String> keys) async {
    try {
      return _smap(await _m.invokeMethod('requestPermissions', {'permissions': keys}));
    } on MissingPluginException {
      return {};
    } on PlatformException {
      return {};
    }
  }

  @override
  Future<Map<String, dynamic>> startSensors() async {
    try {
      return _map(await _m.invokeMethod('startSensors'));
    } on MissingPluginException {
      return {};
    } on PlatformException {
      return {};
    }
  }

  @override
  Future<void> stopSensors() async {
    try {
      await _m.invokeMethod('stopSensors');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  @override
  Future<bool> startNfc() async {
    try {
      return (await _m.invokeMethod<bool>('startNfc')) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> stopNfc() async {
    try {
      await _m.invokeMethod('stopNfc');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  @override
  Future<bool> showNotification(String title, String body) async {
    try {
      return (await _m.invokeMethod<bool>('showNotification', {'title': title, 'body': body})) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Stream<Map<String, dynamic>> get events =>
      _e.receiveBroadcastStream().map((o) => _map(o)).handleError((Object _) {});
}

/// Testler/platform dışı için: hiçbir donanım yok.
class NoHardwareBridge implements HardwareBridge {
  final StreamController<Map<String, dynamic>> controller = StreamController.broadcast();
  @override
  String? get lastError => null;
  @override
  Future<Map<String, dynamic>> capabilities() async => {};
  @override
  Future<Map<String, String>> permissionStatus() async => {};
  @override
  Future<Map<String, String>> requestPermissions(List<String> keys) async => {};
  @override
  Future<Map<String, dynamic>> startSensors() async => {};
  @override
  Future<void> stopSensors() async {}
  @override
  Future<bool> startNfc() async => false;
  @override
  Future<void> stopNfc() async {}
  @override
  Future<bool> showNotification(String title, String body) async => false;
  @override
  Stream<Map<String, dynamic>> get events => controller.stream;
}
