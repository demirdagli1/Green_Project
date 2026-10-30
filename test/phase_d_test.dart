import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:green_project/screens/home/home_screen.dart';
import 'package:green_project/services/app_store.dart';
import 'package:green_project/services/auto_motion_engine.dart';
import 'package:green_project/services/command_dispatcher.dart';
import 'package:green_project/services/storage.dart';

void main() {
  group('Aşama D — Otomatik Hareket Motoru Birim Testleri', () {
    late MemoryStore backend;
    late AppStore store;
    late DateTime currentTime;

    setUp(() async {
      backend = MemoryStore();
      currentTime = DateTime.utc(2026, 10, 30, 10, 0, 0);
      store = AppStore(backend: backend, clock: () => currentTime);
      await store.load();
      store.register(deviceId: 'dev_phase_d', name: 'Zeynep', clanName: 'KTÜ Kanuni');
    });

    test('1. Başlangıç durumu Durgun (idle); adım artışı ile Yürüyüş (walking) moduna geçiş', () {
      final auto = store.autoMotion;
      expect(auto.mode, AutoMotionMode.idle);
      expect(auto.isAutoSessionActive, false);

      // İlk örnek taban çizgisini kurar, ikinci örnek artışı üretir
      store.onSensorSteps(1000);
      store.onSensorSteps(1015);
      expect(auto.mode, AutoMotionMode.walking);
      expect(auto.statusExplanation, contains('Yürüyüş'));
    });

    test('2. Başlama Histerezisi: Tekil GPS hızı doğrudan bisiklet başlatmaz; 10 sn + 3 fix gerektirir', () {
      final auto = store.autoMotion;

      // 1. Fix: 18 km/sa (5 m/s)
      store.onLocation(lat: 41.0, lon: 29.0, speedMps: 5.0, accuracy: 10.0, tsMs: currentTime.millisecondsSinceEpoch);
      expect(auto.mode, AutoMotionMode.potentialBike);
      expect(auto.isAutoSessionActive, false);

      // 2. Fix: 3 saniye sonra (histerezis henüz dolmadı)
      currentTime = currentTime.add(const Duration(seconds: 3));
      store.onLocation(lat: 41.0001, lon: 29.0, speedMps: 5.2, accuracy: 10.0, tsMs: currentTime.millisecondsSinceEpoch);
      expect(auto.mode, AutoMotionMode.potentialBike);
      expect(auto.isAutoSessionActive, false);

      // 3. Fix: 11 saniye sonra (10 sn ve 3 fix kuralı sağlandı!)
      currentTime = currentTime.add(const Duration(seconds: 8));
      store.onLocation(lat: 41.0004, lon: 29.0, speedMps: 5.5, accuracy: 10.0, tsMs: currentTime.millisecondsSinceEpoch);

      // Artık otomatik bisiklet sürüşü onaylanmış olmalı
      expect(auto.mode, AutoMotionMode.cycling);
      expect(auto.isAutoSessionActive, true);
      expect(store.bike, isNotNull);
      expect(store.bike!.isAuto, true);
    });

    test('3. Çift Ödül Koruması (Anti Double-Dipping): Bisiklet esnasındaki yapay adımlar adım ödülü üretmez', () {
      final auto = store.autoMotion;

      // Simülasyonla bisiklet başlat
      auto.simulateMotionFlow(
        targetMode: AutoMotionMode.cycling,
        speedKmh: 20.0,
        durationSeconds: 15,
        stepDelta: 0,
      );
      expect(auto.isAutoSessionActive, true);

      final initialWeeklyPoints = store.me!.weeklyPoints;

      // Bisiklet sürerken pedal kaynaklı 2000 donanım adımı geldi
      store.onSensorSteps(2000);

      // Adım bonusu bastırılmış olmalı, puan artmamalı
      expect(store.me!.weeklyPoints, initialWeeklyPoints);
      expect(store.telemetry.windowStatus, contains('çift ödül koruması'));
    });

    test('4. Kırmızı Işık / Trafik Duraklama Toleransı (45 sn tolerans)', () {
      final auto = store.autoMotion;

      // Bisiklet başlat
      auto.simulateMotionFlow(
        targetMode: AutoMotionMode.cycling,
        speedKmh: 18.0,
        durationSeconds: 15,
      );
      expect(auto.isAutoSessionActive, true);

      // Trafik ışığında duruldu (hız 0 km/sa, simülasyonun bittiği noktada)
      currentTime = currentTime.add(const Duration(seconds: 15));
      store.onLocation(lat: 41.0089, lon: 28.9784, speedMps: 0.0, accuracy: 8.0, tsMs: currentTime.millisecondsSinceEpoch);

      // Oturum hemen kapanmamalı, kısa duraklama durumunda beklemeli
      expect(auto.isAutoSessionActive, true);
      expect(auto.statusExplanation, contains('Trafik ışığı'));

      // 20 sn sonra tekrar hareket başlarsa sürüş devam eder
      currentTime = currentTime.add(const Duration(seconds: 20));
      store.onLocation(lat: 41.0095, lon: 28.9784, speedMps: 4.5, accuracy: 8.0, tsMs: currentTime.millisecondsSinceEpoch);
      expect(auto.isAutoSessionActive, true);
      expect(auto.statusExplanation, contains('Bisiklet'));

      // Şimdi 46 saniye boyunca durulursa otomatik oturum tamamlanmalı
      currentTime = currentTime.add(const Duration(seconds: 5));
      store.onLocation(lat: 41.0095, lon: 28.9784, speedMps: 0.0, accuracy: 8.0, tsMs: currentTime.millisecondsSinceEpoch);
      currentTime = currentTime.add(const Duration(seconds: 46));
      store.onLocation(lat: 41.0095, lon: 28.9784, speedMps: 0.0, accuracy: 8.0, tsMs: currentTime.millisecondsSinceEpoch);

      expect(auto.isAutoSessionActive, false);
      expect(auto.mode, AutoMotionMode.idle);
    });

    test('5. Zayıf GPS Koruması: Doğruluk > 30m olduğunda limitedMode devreye girer; bisiklet başlatılmaz', () {
      final auto = store.autoMotion;

      // Hız 20 km/sa ama GPS doğruluğu 45 metre (zayıf/güvensiz)
      store.onLocation(lat: 41.0, lon: 29.0, speedMps: 5.5, accuracy: 45.0, tsMs: currentTime.millisecondsSinceEpoch);

      expect(auto.mode, AutoMotionMode.limitedMode);
      expect(auto.isAutoSessionActive, false);
      expect(auto.statusExplanation, contains('Sınırlı mod'));
    });

    test('6. Manuel Bisiklet Önceliği: Kullanıcı manuel sürüş başlattığında otomatik motor müdahale etmez', () {
      final auto = store.autoMotion;

      // Kullanıcı manuel bisiklet başlattı
      store.startBike(tripId: 'manual_trip_1');
      expect(store.bike!.isAuto, false);

      // Otomatik hız fix'i geldi
      store.onLocation(lat: 41.0, lon: 29.0, speedMps: 6.0, accuracy: 10.0, tsMs: currentTime.millisecondsSinceEpoch);

      // Otomatik oturum açılmamalı, manuel kontrol korunmalı
      expect(auto.isAutoSessionActive, false);
      expect(auto.statusExplanation, contains('Manuel bisiklet sürüşü devrede'));
    });

    test('7. Kullanıcı İptali: cancelAutoTrip cezasız ve puansız oturumu temizler', () {
      final auto = store.autoMotion;

      auto.simulateMotionFlow(
        targetMode: AutoMotionMode.cycling,
        speedKmh: 18.0,
        durationSeconds: 20,
      );
      expect(auto.isAutoSessionActive, true);

      final r = auto.cancelAutoTrip();
      expect(r.ok, true);
      expect(auto.isAutoSessionActive, false);
      expect(store.bike, isNull);
      expect(auto.statusExplanation, contains('iptal edildi'));
    });

    test('8. CommandDispatcher: auto_motion_simulate ve auto_motion_finish komut sözleşmesi', () {
      final dispatcher = CommandDispatcher(store);

      final simRes = dispatcher.dispatch('auto_motion_simulate', {
        'speedKmh': 20.0,
        'durationSeconds': 30,
        'variance': 0.19,
      });
      expect(simRes.ok, true);
      expect(store.autoMotion.isAutoSessionActive, true);

      final finishRes = dispatcher.dispatch('auto_motion_finish', {});
      expect(finishRes.ok, true);
      expect(store.autoMotion.isAutoSessionActive, false);
    });
  });

  group('Aşama D — UI & Widget Entegrasyon Testleri', () {
    testWidgets('Ana sayfada otomatik bisiklet sürüşü algılandığında dinamik kart ve aksiyon butonları görünür', (tester) async {
      final backend = MemoryStore();
      final store = AppStore(backend: backend);
      await store.load();
      store.register(deviceId: 'dev_ui_d', name: 'Can', clanName: 'KTÜ Kanuni');
      AppStore.instance = store;

      // Otomatik bisiklet başlat (30 saniye sürüş > 100m)
      store.autoMotion.simulateMotionFlow(
        targetMode: AutoMotionMode.cycling,
        speedKmh: 20.0,
        durationSeconds: 30,
        variance: 0.18,
      );

      await tester.pumpWidget(const MaterialApp(
        home: HomeScreen(),
      ));
      await tester.pumpAndSettle();

      // Dinamik kart metni ve butonlar görünür olmalı
      expect(find.text('🚴 Otomatik Bisiklet Sürüşü Algılandı'), findsOneWidget);
      expect(find.text('Bitir & Kaydet'), findsOneWidget);
      expect(find.text('İptal'), findsOneWidget);

      // 'Bitir & Kaydet' butonuna dokunulur
      await tester.tap(find.text('Bitir & Kaydet'));
      await tester.pumpAndSettle();

      // Sürüş başarıyla tamamlanmış ve kart normal duruma dönmüş olmalı
      expect(store.autoMotion.isAutoSessionActive, false);
      expect(find.text('Bitir & Kaydet'), findsNothing);
    });
  });
}
