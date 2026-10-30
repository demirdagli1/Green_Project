import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_store.dart';
import 'hardware_bridge.dart';

/// Donanım olaylarını AppStore'a iletir; yetenek/izin durumunu UI'ya açar.
/// Arka planda/uygulama kapalıyken izleme YOKTUR (native taraf onPause'da sensörleri durdurur).
class SensorController extends ChangeNotifier {
  final HardwareBridge bridge;
  final AppStore store;
  StreamSubscription<Map<String, dynamic>>? _sub;

  Map<String, dynamic> caps = {};
  Map<String, String> perms = {};
  Map<String, dynamic> started = {};
  bool nfcListening = false;
  String? lastNfcUid;
  String? lastEventNote;
  bool sensorsRunning = false;

  SensorController({required this.bridge, required this.store});

  bool get stepCounterAvailable => caps['stepCounter'] == true;
  bool get gpsAvailable => caps['gps'] == true;
  bool get locationEnabled => caps['locationEnabled'] == true;
  bool get nfcAvailable => caps['nfc'] == true;
  bool get nfcEnabled => caps['nfcEnabled'] == true;
  bool get capsKnown => caps.isNotEmpty;
  String? get bridgeError => bridge.lastError;

  Future<void> refresh() async {
    caps = await bridge.capabilities();
    perms = await bridge.permissionStatus();
    notifyListeners();
  }

  Future<void> requestAll() async {
    perms = await bridge.requestPermissions(['activity', 'location', 'notifications']);
    await refresh();
  }

  Future<String?> pickProfileImage() => bridge.pickProfileImage();

  Future<void> start() async {
    if (caps.isEmpty) {
      await refresh();
    }
    _sub ??= bridge.events.listen(_onEvent);
    started = await bridge.startSensors();
    sensorsRunning = started.values.any((v) => v == true);
    notifyListeners();
  }

  Future<void> stop() async {
    await bridge.stopSensors();
    await bridge.stopNfc();
    sensorsRunning = false;
    nfcListening = false;
    notifyListeners();
  }

  Future<bool> startNfc() async {
    _sub ??= bridge.events.listen(_onEvent);
    nfcListening = await bridge.startNfc();
    notifyListeners();
    return nfcListening;
  }

  Future<void> stopNfc() async {
    await bridge.stopNfc();
    nfcListening = false;
    notifyListeners();
  }

  void _onEvent(Map<String, dynamic> e) {
    switch (e['type']) {
      case 'sensor_started':
        final gpsOn = e['gps'] == true;
        final mode = e['gpsMode'] as String? ?? 'bilinmiyor';
        store.telemetry.gpsStatus = gpsOn ? 'Dinleniyor ($mode)' : 'Konum kapalı/yetkisiz';
        notifyListeners();
      case 'steps':
        final total = (e['total'] as num?)?.toInt();
        if (total != null) store.onSensorSteps(total);
        notifyListeners();
      case 'accel':
        final freq = (e['freqHz'] as num?)?.toDouble() ?? double.nan;
        final variance = (e['variance'] as num?)?.toDouble() ?? double.nan;
        final count = (e['sampleCount'] as num?)?.toInt() ?? 1;
        store.onAccel(
          freqHz: freq,
          variance: variance,
          sampleCount: count,
        );
        notifyListeners();
      case 'location':
        store.onLocation(
          lat: (e['lat'] as num?)?.toDouble() ?? double.nan,
          lon: (e['lon'] as num?)?.toDouble() ?? double.nan,
          speedMps: (e['speedMps'] as num?)?.toDouble(),
          accuracy: (e['accuracy'] as num?)?.toDouble(),
          tsMs: (e['ts'] as num?)?.toInt(),
          provider: e['provider'] as String?,
        );
        notifyListeners();
      case 'gpsDisabled':
        store.telemetry.gpsStatus = 'Konum sağlayıcı devre dışı';
        lastEventNote = 'Konum kapatıldı.';
        notifyListeners();
      case 'gpsEnabled':
        store.telemetry.gpsStatus = 'Konum sağlayıcı devrede (${e['provider'] ?? ''})';
        lastEventNote = 'Konum açıldı.';
        notifyListeners();
      case 'nfc':
        lastNfcUid = e['uid'] as String?;
        final text = e['text'] as String?;
        // Etiket metni YESILADIM://TRANSIT/<KOD> değilse UID tek başına bilinmeyen durak sayılır.
        final r = store.scanTransit(text ?? lastNfcUid, source: 'NFC');
        lastEventNote = r.message;
        notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
