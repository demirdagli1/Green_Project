import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:green_project/main.dart';
import 'package:green_project/services/app_store.dart';
import 'package:green_project/services/hardware_bridge.dart';
import 'package:green_project/services/hub.dart';
import 'package:green_project/services/sensor_controller.dart';
import 'package:green_project/services/storage.dart';

class _DelayedHardwareBridge implements HardwareBridge {
  final StreamController<Map<String, dynamic>> controller = StreamController.broadcast();
  Map<String, dynamic> nextCaps = {};
  Map<String, String> nextPerms = {};
  Map<String, dynamic> nextStarted = {};
  @override
  String? get lastError => null;
  @override
  Future<Map<String, dynamic>> capabilities() async => nextCaps;
  @override
  Future<Map<String, String>> permissionStatus() async => nextPerms;
  @override
  Future<Map<String, String>> requestPermissions(List<String> keys) async => nextPerms;
  @override
  Future<Map<String, dynamic>> startSensors() async => nextStarted;
  @override
  Future<void> stopSensors() async {}
  @override
  Future<bool> startNfc() async => true;
  @override
  Future<void> stopNfc() async {}
  @override
  Future<bool> showNotification(String title, String body) async => true;
  @override
  Stream<Map<String, dynamic>> get events => controller.stream;
}

Future<AppStore> boot(WidgetTester t, {Size size = const Size(360, 640), double textScale = 1.0}) async {
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize = size * 3;
  t.view.devicePixelRatio = 3;
  t.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearAllTestValues);
  final store = AppStore(backend: MemoryStore(), clock: () => DateTime.utc(2026, 10, 26, 9));
  await store.load();
  AppStore.instance = store;
  Hub.sensors = SensorController(bridge: NoHardwareBridge(), store: store);
  await t.pumpWidget(const GreenProjectApp());
  await t.pumpAndSettle();
  return store;
}

Future<void> onboard(WidgetTester t, AppStore store, {String name = 'Ayşe'}) async {
  await t.enterText(find.byType(TextField), name);
  await t.tap(find.byType(DropdownButtonFormField<String>));
  await t.pumpAndSettle();
  await t.tap(find.text('KTÜ Dağcılık Kulübü').last);
  await t.pumpAndSettle();
  await t.tap(find.text('Klanıma Katıl ve Başla'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('onboarding zorunlu: boş giriş kabul edilmez, sonra ana sayfa gerçek (sıfır) verilerle açılır', (t) async {
    final store = await boot(t);
    expect(find.text('Hoş Geldin!\nİsmin ne?'), findsOneWidget);
    await t.tap(find.text('Klanıma Katıl ve Başla'));
    await t.pumpAndSettle();
    expect(find.text('İsmini yaz ve bir klan seç.'), findsOneWidget);
    expect(store.hasProfile, false);
    await onboard(t, store);
    expect(store.hasProfile, true);
    expect(find.text('Daha yeşil bir gelecek için adım at!'), findsOneWidget);
    expect(find.text('0 adım'), findsOneWidget);
    expect(find.textContaining('Sonraki +5 puana sadece 1000 adım kaldı!'), findsOneWidget);
    expect(find.textContaining('Efe'), findsNothing);
  });

  testWidgets('gezinme: sıralama, utanç tablosu maskeli, mağaza, admin, geri tuşu', (t) async {
    final store = await boot(t);
    await onboard(t, store);
    await t.tap(find.byTooltip('Sıralama'));
    await t.pumpAndSettle();
    expect(find.text('🏆 Gurur Tablosu'), findsOneWidget);
    await t.tap(find.text('🚨 Utanç'));
    await t.pumpAndSettle();
    expect(find.text('Pel***'), findsOneWidget);
    expect(find.text('Pelin Aydın'), findsNothing);
    expect(find.text('Oğu***'), findsOneWidget);
    await t.tap(find.text('Klan'));
    await t.pumpAndSettle();
    await t.tap(find.text('🏆 Gurur'));
    await t.pumpAndSettle();
    final outFinder = find.textContaining('Yetersiz üye');
    await t.scrollUntilVisible(outFinder, 200, scrollable: find.byType(Scrollable).last);
    expect(outFinder, findsOneWidget);
    await t.tap(find.byTooltip('Mağaza ve profil'));
    await t.pumpAndSettle();
    expect(find.text('Profil ve Mağaza'), findsOneWidget);
    expect(find.textContaining('yetersiz'), findsWidgets);
    await t.tap(find.text('Jüri/Admin'));
    await t.pumpAndSettle();
    expect(find.textContaining('DEMO'), findsWidgets);
    await t.tap(find.text('[DEMO] +334 adım ekle'));
    await t.pumpAndSettle();
    expect(store.me!.todaySteps, 334);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Profil ve Mağaza'), findsOneWidget);
    // sistem geri tuşu: ana sayfaya döner
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('Daha yeşil bir gelecek için adım at!'), findsOneWidget);
  });

  testWidgets('mağaza çift dokunma bakiyeyi iki kez düşmez', (t) async {
    final store = await boot(t);
    await onboard(t, store);
    store.demoGrantGold(500);
    await t.tap(find.byTooltip('Mağaza ve profil'));
    await t.pumpAndSettle();
    final btn = find.text('500 🪙');
    await t.ensureVisible(btn);
    await t.tap(btn);
    await t.tap(btn, warnIfMissed: false);
    await t.pumpAndSettle();
    expect(store.me!.goldCoins, 0);
    expect(store.owned.contains('leaf_warrior'), true);
  });

  testWidgets('QR/NFC sayfası: kamera yok uyarısı, manuel kod, cooldown mesajı, klavye', (t) async {
    final store = await boot(t);
    await onboard(t, store);
    await t.tap(find.text('QR / NFC'));
    await t.pumpAndSettle();
    expect(find.textContaining('Kamera ile QR tarama bu sürümde YOK'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'YESILADIM://TRANSIT/TRB-KTU-01');
    await t.tap(find.text('Doğrula'));
    await t.pumpAndSettle();
    expect(store.me!.weeklyPoints, 3);
    await t.tap(find.text('Doğrula'));
    await t.pumpAndSettle();
    final msgFinder = find.textContaining('Aynı otobüsü iki kere mi');
    await t.scrollUntilVisible(msgFinder, 100, scrollable: find.byType(Scrollable).last);
    expect(msgFinder, findsOneWidget);
    expect(store.me!.weeklyPoints, 3);
    expect(find.text('Bu cihazda NFC donanımı yok.'), findsOneWidget);
  });

  testWidgets('küçük ekran + büyük yazı + uzun klan adı taşma üretmez', (t) async {
    final store = await boot(t, size: const Size(320, 568), textScale: 1.6);
    await t.enterText(find.byType(TextField), 'Ayşe');
    final dropFinder = find.byType(DropdownButtonFormField<String>);
    await t.ensureVisible(dropFinder);
    await t.tap(dropFinder);
    await t.pumpAndSettle();
    await t.tap(find.text('Sincanlılar Derneği').last);
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Klanıma Katıl ve Başla'));
    await t.tap(find.text('Klanıma Katıl ve Başla'));
    await t.pumpAndSettle();
    expect(store.hasProfile, true);
    expect(t.takeException(), isNull);
    await t.tap(find.byTooltip('Sıralama'));
    await t.pumpAndSettle();
    await t.tap(find.text('Klan'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.tap(find.byTooltip('Mağaza ve profil'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('regresyon: asenkron donanım köprüsü yanıtı sonrası HomeScreen sensör kartı güncellenir', (t) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore(backend: MemoryStore(), clock: () => DateTime.utc(2026, 10, 26, 9));
    await store.load();
    store.register(deviceId: 'dev_hw', name: 'Ali', clanName: 'KTÜ Kanuni');
    AppStore.instance = store;
    final bridge = _DelayedHardwareBridge();
    Hub.sensors = SensorController(bridge: bridge, store: store);

    // İlk karede henüz donanım yanıtı yokken kapalı/bilinmiyor görünür
    await t.pumpWidget(const GreenProjectApp());
    await t.pump();
    expect(find.text('📡 Sensörler kapalı'), findsOneWidget);
    expect(find.textContaining('Donanım bilgisi alınamadı'), findsOneWidget);

    // Native köprü gerçek cihaz yeteneklerini ve izinlerini döndürdüğünde kart yeniden çizilmelidir
    bridge.nextCaps = {
      'stepCounter': true,
      'accelerometer': true,
      'gps': true,
      'locationEnabled': true,
      'nfc': true,
      'nfcEnabled': true,
      'sdk': 36,
    };
    bridge.nextPerms = {
      'activity': 'granted',
      'location': 'granted',
      'notifications': 'granted',
    };
    bridge.nextStarted = {
      'stepCounter': true,
      'accelerometer': true,
      'gps': true,
    };
    await Hub.sensors.refresh();
    await Hub.sensors.start();
    await t.pumpAndSettle();

    expect(find.text('📡 Sensörler açık (yalnız uygulama ön plandayken)'), findsOneWidget);
    expect(find.textContaining('Donanım bilgisi alınamadı'), findsNothing);
    expect(find.textContaining('Donanım: Adımsayar var • GPS açık • NFC açık (API 36)'), findsOneWidget);
    expect(find.textContaining('İzinler: Aktivite verildi • Konum verildi • Bildirim verildi'), findsOneWidget);

    // İzinler zaten verilmişken butona basıldığında kullanıcıya bilgi mesajı gösterilir
    final refreshBtn = find.text('Durumu yenile (İzinler verildi)');
    await t.ensureVisible(refreshBtn);
    await t.tap(refreshBtn);
    await t.pumpAndSettle();
    expect(find.textContaining('İzinler zaten verilmiş'), findsOneWidget);
  });
}
