import 'package:flutter_test/flutter_test.dart';
import 'package:green_project/core/constants/trabzon_stops_seed.dart';
import 'package:green_project/data/demo_data.dart';
import 'package:green_project/models/clan.dart';
import 'package:green_project/models/league_tier.dart';
import 'package:green_project/services/app_store.dart';
import 'package:green_project/services/auto_transport_classifier.dart';
import 'package:green_project/services/command_dispatcher.dart';
import 'package:green_project/services/storage.dart';
import 'package:green_project/services/supabase_outbox.dart';

void main() {
  group('Revizyon 03 — Otomatik Aktivite & Otobüs Karar Motoru Testleri', () {
    test('1.1 Normal yürüyüş ritmi (cadence 100, hız 4.5 km/sa) yürüyüş olarak onaylanır', () {
      final res = AutoTransportClassifierService.classifySession(
        distanceKm: 1.2,
        avgSpeedKmh: 4.5,
        maxSpeedKmh: 5.5,
        stepCadenceSpm: 100,
        accelVariance: 1.2,
      );

      expect(res.activityType, DetectedActivityType.walk);
      expect(res.pointsAwarded, 5);
      expect(res.co2DeltaKg, greaterThan(0));
    });

    test('1.2 Koşu antrenmanı (cadence 160, hız 11 km/sa, yüksek dikey ivme) koşu olarak onaylanır', () {
      final res = AutoTransportClassifierService.classifySession(
        distanceKm: 3.0,
        avgSpeedKmh: 11.0,
        maxSpeedKmh: 14.0,
        stepCadenceSpm: 160,
        accelVariance: 2.5,
      );

      expect(res.activityType, DetectedActivityType.run);
      expect(res.pointsAwarded, 10);
    });

    test('1.3 Bisiklet sürüşü (düşük adım kadansı, 18 km/sa hız, bisiklet ivmesi) onaylanır', () {
      final res = AutoTransportClassifierService.classifySession(
        distanceKm: 4.2,
        avgSpeedKmh: 18.0,
        maxSpeedKmh: 24.0,
        stepCadenceSpm: 12,
        accelVariance: 0.85,
        userClaimedBikeMode: true,
      );

      expect(res.activityType, DetectedActivityType.bike);
      expect(res.pointsAwarded, 4);
    });

    test('1.4 Zayıf GPS veya düşük güvenilirlikte ASLA otomatik suçlama veya ceza kesilmez', () {
      final res = AutoTransportClassifierService.classifySession(
        distanceKm: 5.0,
        avgSpeedKmh: 45.0,
        maxSpeedKmh: 60.0,
        stepCadenceSpm: 0,
        accelVariance: 0.10,
        isGpsReliable: false,
        gpsAccuracyMeters: 45.0,
      );

      expect(res.activityType, DetectedActivityType.inconclusiveLowGps);
      expect(res.pointsAwarded, 0);
      expect(res.co2DeltaKg, 0.0);
    });

    test('1.5 Durak eşleşmeli otobüs yolculuğu (%60+ skor) otobüs olarak onaylanır ve CO2 kazandırır', () {
      final res = AutoTransportClassifierService.classifySession(
        distanceKm: 3.5,
        avgSpeedKmh: 28.0,
        maxSpeedKmh: 45.0,
        stepCadenceSpm: 0,
        accelVariance: 0.15,
        boardedNearBusStop: true, // +35
        matchedBusStopDwells: 2,   // +50
      );

      expect(res.activityType, DetectedActivityType.publicTransitBus);
      expect(res.busProbabilityScore, greaterThanOrEqualTo(60));
      expect(res.pointsAwarded, 3);
      expect(res.co2DeltaKg, greaterThan(0));
      expect(res.isShortBusPenalty, false);
    });

    test('1.6 Duraksız araç yolculuğu (<%60 skor) taksi/özel araç cezası ve CO2 israfı yazar', () {
      final res = AutoTransportClassifierService.classifySession(
        distanceKm: 6.0,
        avgSpeedKmh: 65.0,
        maxSpeedKmh: 80.0,
        stepCadenceSpm: 0,
        accelVariance: 0.10,
        boardedNearBusStop: false,
        matchedBusStopDwells: 0,
        alightedNearBusStop: false,
      );

      expect(res.activityType, DetectedActivityType.carOrTaxiPenalty);
      expect(res.busProbabilityScore, lessThan(60));
      expect(res.pointsAwarded, 0);
      expect(res.co2DeltaKg, lessThan(0));
    });

    test('1.7 Trabzon durak listesi seed verisi geçerlidir ve Haversine mesafe fonksiyonu çalışır', () {
      expect(kTrabzonBusStops.length, greaterThanOrEqualTo(9));
      final stop1 = kTrabzonBusStops.first;
      final distSelf = AutoTransportClassifierService.distanceInMeters(stop1.lat, stop1.lon, stop1.lat, stop1.lon);
      expect(distSelf, 0.0);

      final nearest = AutoTransportClassifierService.findNearestStop(stop1.lat, stop1.lon);
      expect(nearest, isNotNull);
      expect(nearest!.id, stop1.id);
    });
  });

  group('Revizyon 03 — Madde 2: Kısa Otobüs Yolculuğu Cezası (<= 500m)', () {
    test('2.1 Kesin doğrulanmış otobüs mesafesi 300m (<= 500m) ise -3 ceza verilir ve CO2 ödülü verilmez', () {
      final res = AutoTransportClassifierService.classifySession(
        distanceKm: 0.3, // 300 metre
        avgSpeedKmh: 20.0,
        maxSpeedKmh: 35.0,
        stepCadenceSpm: 0,
        accelVariance: 0.18,
        hasNfcOrQrScan: true, // Otobüs kesin doğrulandı (Skor 100)
      );

      expect(res.activityType, DetectedActivityType.shortBusPenalty);
      expect(res.isShortBusPenalty, true);
      expect(res.pointsAwarded, -3);
      expect(res.co2DeltaKg, 0.0);
      expect(res.explanation, contains('≤500m'));
    });

    test('2.2 Tam 500m sınırında (0.5 km) kısa otobüs cezası uygulanır', () {
      final res = AutoTransportClassifierService.classifySession(
        distanceKm: 0.5, // 500 metre
        avgSpeedKmh: 22.0,
        maxSpeedKmh: 38.0,
        stepCadenceSpm: 0,
        accelVariance: 0.16,
        boardedNearBusStop: true,
        alightedNearBusStop: true,
        matchedBusStopDwells: 1,
      );

      expect(res.isShortBusPenalty, true);
      expect(res.pointsAwarded, -3);
      expect(res.co2DeltaKg, 0.0);
    });

    test('2.3 501 metre (0.501 km) otobüs yolculuğu ceza yemez, +3 ödül alır', () {
      final res = AutoTransportClassifierService.classifySession(
        distanceKm: 0.51, // 510 metre
        avgSpeedKmh: 22.0,
        maxSpeedKmh: 38.0,
        stepCadenceSpm: 0,
        accelVariance: 0.16,
        hasNfcOrQrScan: true,
      );

      expect(res.isShortBusPenalty, false);
      expect(res.pointsAwarded, 3);
      expect(res.co2DeltaKg, greaterThan(0));
    });
  });

  group('Revizyon 03 — Madde 3: Klan Utanç Listesi (En Kötü Klanlar)', () {
    late AppStore store;

    setUp(() async {
      store = AppStore(backend: MemoryStore());
      await store.load();
    });

    test('3.1 worstClans() en yüksek CO2 israfı yapan klanları deterministik sıralar', () {
      final worst = store.worstClans();
      expect(worst, isNotEmpty);

      for (int i = 0; i < worst.length - 1; i++) {
        final a = worst[i];
        final b = worst[i + 1];
        if (a.weeklyWastedCo2Kg != b.weeklyWastedCo2Kg) {
          expect(a.weeklyWastedCo2Kg, greaterThanOrEqualTo(b.weeklyWastedCo2Kg));
        } else if (a.weeklyPoints != b.weeklyPoints) {
          expect(a.weeklyPoints, lessThanOrEqualTo(b.weeklyPoints));
        }
      }
    });

    test('3.2 Klan utanç listesi 5 üyeden az olan klanlarda çökmeksizin çalışır', () {
      final smallClan = const Clan(id: 'clan_small', name: 'Küçük Klan', memberCount: 2, weeklyPoints: 10, weeklyWastedCo2Kg: 8.5);
      store.clans.add(smallClan);

      final worst = store.worstClans();
      expect(worst.any((c) => c.id == 'clan_small'), isTrue);
    });
  });

  group('Revizyon 03 — Öncelik 1: Outbox Zehirli Paket & Head-of-Line Koruması', () {
    late SupabaseOutbox outbox;

    setUp(() {
      outbox = SupabaseOutbox(storage: MemoryStore());
    });

    test('4.1 Kalıcı şema veya kullanıcı hatası olay karantinaya alınır ve sonraki öğeleri engellemez', () async {
      // 1. Zehirli olay ekle (Kullanıcı bulunamadı hatası fırlatacak)
      final poisonItem = await outbox.enqueue(
        actionType: 'record_steps',
        payload: {'p_event_id': 'bad_step'},
      );

      // 2. Geçerli olay ekle
      final validItem = await outbox.enqueue(
        actionType: 'record_transit',
        payload: {'p_event_id': 'good_transit'},
      );

      expect(outbox.pendingCount, 2);

      // Zehirli paketi kalıcı hata ile işaretle
      await outbox.markFailed(poisonItem.id, 'Exception: Kullanıcı bulunamadı', forceQuarantine: true);

      // Zehirli paket karantinaya geçtiğinden pendingItems listesinden düşer!
      final remainingPending = outbox.pendingItems;
      expect(remainingPending.length, 1);
      expect(remainingPending.first.id, validItem.id);
      expect(outbox.quarantinedCount, 1);
    });

    test('4.2 5 kez başarısız olan olay otomatik karantinaya alınır', () async {
      final item = await outbox.enqueue(
        actionType: 'buy_shop_item',
        payload: {'p_item_slug': 'item_x'},
      );

      for (int i = 0; i < 5; i++) {
        await outbox.markFailed(item.id, 'Ağ kesintisi');
      }

      final found = outbox.items.firstWhere((i) => i.id == item.id);
      expect(found.status, OutboxItemStatus.quarantined);
      expect(outbox.pendingItems.any((i) => i.id == item.id), isFalse);
    });
  });

  group('Revizyon 03 — Madde 7 & 8: Utanç Dürtme Kotası & Pet Görselleri', () {
    late AppStore store;

    setUp(() async {
      store = AppStore(backend: MemoryStore());
      await store.load();
    });

    test('7.1 Utanç mesajı takvim gününde en fazla 1 kez gönderilebilir', () {
      expect(store.hasSentShameMessageToday, isFalse);

      store.markShameMessageSent();
      expect(store.hasSentShameMessageToday, isTrue);

      // GM komutu ile sıfırlanabilmelidir
      final dispatcher = CommandDispatcher(store);
      final r = dispatcher.dispatch('reset_shame_quota', {});
      expect(r.ok, isTrue);
      expect(store.hasSentShameMessageToday, isFalse);
    });

    test('8.1 Biyo-mekanik arı (bit-bee) ve Ozon Perisi Aura görsel dosya yolları doğru eşlenir', () {
      expect(DemoData.getPetAssetPath('pet_robo_bee'), 'Logolar/kozmetik/petler/bit-bee.png');
      expect(DemoData.getPetAssetPath('biomech_bee'), 'Logolar/kozmetik/petler/bit-bee.png');

      // Orman tilkisi yerine Ozon Perisi Aura (migrasyon korunur)
      expect(DemoData.getPetAssetPath('pet_leaf_fox'), 'Logolar/kozmetik/petler/auro-fairy.png');
      expect(DemoData.getPetAssetPath('forest_fox'), 'Logolar/kozmetik/petler/auro-fairy.png');
      expect(DemoData.getPetAssetPath('auro_fairy'), 'Logolar/kozmetik/petler/auro-fairy.png');
      expect(DemoData.getPetAssetPath('none'), isNull);
    });

    test('8.2 Klan lig logoları 1..6 sıralı olarak erişilebilir ve base görsel mevcuttur', () {
      for (int i = 1; i <= 6; i++) {
        final tier = LeagueTier.allTiers[i - 1];
        expect(tier.clanAssetPath, 'Logolar/logo-klan/logo-klan-$i.png');
      }
      expect(LeagueTier.clanBaseAssetPath, 'Logolar/logo-klan/logo-klan-base.png');
    });

    test('8.3 evaluateTransportClassification ve GM classify_transport komutu entegrasyonu', () {
      store.register(deviceId: 'dev_test', name: 'Ayşe', clanName: 'KTÜ Kanuni');
      store.me = store.me!.copyWith(weeklyPoints: 10);
      final dispatcher = CommandDispatcher(store);
      final initialPoints = store.me!.weeklyPoints;

      // GM komutu ile kısa otobüs simülasyonu
      final rShort = dispatcher.dispatch('classify_transport', {
        'distanceKm': 0.40,
        'hasNfcOrQrScan': true,
        'demo': true,
      });
      expect(rShort.ok, isTrue);
      expect(rShort.data!['isShortBusPenalty'], isTrue);
      expect(store.me!.weeklyPoints, initialPoints - 3);

      // GM komutu ile normal otobüs simülasyonu (3.5 km)
      final rNormal = dispatcher.dispatch('classify_transport', {
        'distanceKm': 3.5,
        'hasNfcOrQrScan': true,
        'demo': true,
      });
      expect(rNormal.ok, isTrue);
      expect(rNormal.data!['activityType'], 'publicTransitBus');
      expect(store.me!.weeklyPoints, initialPoints); // -3 + 3 = initialPoints
    });
  });
}
