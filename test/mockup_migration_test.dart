import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:green_project/models/league_tier.dart';
import 'package:green_project/services/app_store.dart';
import 'package:green_project/services/storage.dart';

void main() {
  group('Mock-up Veri Yükseltmesi & Kalıcılık Regresyon Testleri', () {
    test('Veri Yükseltmesi (Migration): Gerçek profil, envanter, bio ve SQL dışı klan korunur; Sen Efe gerçek profilin yerine geçmez', () async {
      final disk = MemoryStore();

      // Eski v2 sürümünden kalmış persisted JSON simülasyonu
      final oldPersisted = {
        'seedVersion': 1,
        'me': {
          'id': 'me_device_real_99',
          'device_id': 'device_real_99',
          'username': 'Ahmet Gerçek Kullanıcı',
          'clan_id': 'clan_micro', // SQL'de olmayan mevcut klan (Yalnız Gezginler)
          'clan_name': 'Yalnız Gezginler',
          'is_demo': false,
          'today_steps': 4500,
          'weekly_points': 50,
          'all_time_points': 320,
          'prevented_co2_kg': 4.5,
          'gold_coins': 750,
          'streak_days': 9,
          'weekly_car_taxi_trips': 0,
          'weekly_wasted_co2_kg': 0.0,
          'equipped_avatar': 'leaf_warrior',
          'equipped_frame': 'oxygen_frame',
          'equipped_pet': 'pine_seedling',
          'photo_path': '/storage/emulated/0/Pictures/profile.jpg',
          'bio': 'Trabzon sahilinde yeşil adımlar atıyorum!',
        },
        'demoUsers': [
          {
            'id': 'old_demo_1',
            'device_id': 'demo',
            'username': 'Eski Demo Kullanıcı',
            'clan_id': 'clan_ktu_kanuni',
            'clan_name': 'KTÜ Kanuni',
            'is_demo': true,
            'weekly_points': 100,
            'all_time_points': 500,
          }
        ],
        'clans': [
          {'id': 'clan_micro', 'name': 'Yalnız Gezginler', 'member_count': 3, 'weekly_points': 9500, 'all_time_points': 30000},
          {'id': 'clan_ktu_kanuni', 'name': 'KTÜ Kanuni', 'member_count': 142, 'weekly_points': 125430, 'all_time_points': 840000},
        ],
        'owned': ['default_avatar', 'leaf_warrior', 'oxygen_frame', 'pine_seedling'],
        'transitLast': {'TRB-KTU-01': 100000},
        'processed': <String>[],
        'dayId': '2026-10-30',
        'weekId': '2026-10-26',
        'lastStreakDay': '2026-10-30',
        'dayRewardedThousands': 4,
        'championUser': '—',
        'championClan': '—',
        'settledWeeks': <String>[],
        'log': <Map<String, dynamic>>[],
        'totalCarTaxi': 0,
      };

      await disk.write(AppStore.storageKey, jsonEncode(oldPersisted));

      final store = AppStore(backend: disk, clock: () => DateTime.utc(2026, 10, 30, 12));
      await store.load();

      // 1. Sürüm yükseltildi
      expect(store.seedVersion, AppStore.currentSeedVersion);

      // 2. Gerçek kullanıcı profili ('me') ve tüm alanları KORUNDU
      expect(store.me, isNotNull);
      expect(store.me!.username, 'Ahmet Gerçek Kullanıcı');
      expect(store.me!.isDemo, false);
      expect(store.me!.bio, 'Trabzon sahilinde yeşil adımlar atıyorum!');
      expect(store.me!.photoPath, '/storage/emulated/0/Pictures/profile.jpg');
      expect(store.me!.goldCoins, 750);
      expect(store.me!.streakDays, 9);
      expect(store.me!.todaySteps, 4500);
      expect(store.me!.weeklyPoints, 50);

      // 3. SQL dışı klan 'Yalnız Gezginler' (clan_micro) korundu
      expect(store.me!.clanId, 'clan_micro');
      expect(store.clans.any((c) => c.id == 'clan_micro'), true);
      expect(store.clans.firstWhere((c) => c.id == 'clan_micro').name, 'Yalnız Gezginler');

      // 4. SQL demo kullanıcıları (15 kullanıcı) yüklendi; Sen (Efe) ayrı demo kullanıcısıdır
      expect(store.demoUsers.length, 15);
      final senEfe = store.demoUsers.firstWhere((u) => u.username == 'Sen (Efe)');
      expect(senEfe.isDemo, true);
      expect(senEfe.todaySteps, 6666);
      expect(senEfe.weeklyPoints, 8960);
      expect(senEfe.id, '11111111-1111-1111-1111-111111111104');

      // 5. Envanter korundu ve yeni SQL aliasları otomatik eklendi
      expect(store.owned.contains('leaf_warrior'), true);
      expect(store.owned.contains('ava_ktu_mountaineer'), true);
      expect(store.owned.contains('oxygen_frame'), true);
      expect(store.owned.contains('frame_oxygen_glow'), true);
      expect(store.owned.contains('pine_seedling'), true);
      expect(store.owned.contains('pet_pine_sprout'), true);
    });

    test('Tekrar Yükleme / Restart Etkisizliği (Idempotency): Veriler sıfırlanmaz', () async {
      final disk = MemoryStore();
      final store1 = AppStore(backend: disk, clock: () => DateTime.utc(2026, 10, 30, 12));
      await store1.load();

      // Gerçek kullanıcı kaydolur
      store1.register(deviceId: 'real_test_dev', name: 'Mustafa', clanName: 'KTÜ OF');
      store1.demoAddSteps(1000); // +5 puan
      store1.demoGrantGold(200);
      await store1.flush();

      final savedUser = store1.me!;
      expect(savedUser.todaySteps, 1000);
      expect(savedUser.weeklyPoints, 5);
      expect(savedUser.goldCoins, 200);

      // İkinci kez yükleme / restart (uygulama yeniden açıldı)
      final store2 = AppStore(backend: disk, clock: () => DateTime.utc(2026, 10, 30, 13));
      await store2.load();

      // Değerler ezilmedi, tekrar seed uygulanmadı
      expect(store2.seedVersion, AppStore.currentSeedVersion);
      expect(store2.me!.username, 'Mustafa');
      expect(store2.me!.todaySteps, 1000);
      expect(store2.me!.weeklyPoints, 5);
      expect(store2.me!.goldCoins, 200);
      expect(store2.demoUsers.length, 15);
    });

    test('Transit Durakları: 6 SQL durağı, NFC UID kolonlu/kolonsuz eşleme ve ortak 45 dk cooldown', () async {
      final disk = MemoryStore();
      var now = DateTime.utc(2026, 10, 30, 10, 0);
      final store = AppStore(backend: disk, clock: () => now);
      await store.load();
      store.register(deviceId: 'dev_transit', name: 'Can', clanName: 'KTÜ Kanuni');

      // 6 SQL durağı mevcut
      expect(store.stops.length, greaterThanOrEqualTo(6));
      expect(store.stops.any((s) => s.code == 'TRB-KTU-01'), true);
      expect(store.stops.any((s) => s.code == 'TRB-KTU-02'), true);
      expect(store.stops.any((s) => s.code == 'TRB-BLD-101'), true);
      expect(store.stops.any((s) => s.code == 'TRB-BLD-104'), true);
      expect(store.stops.any((s) => s.code == 'TRB-BLD-501'), true);
      expect(store.stops.any((s) => s.code == 'ANK-EGO-411'), true);

      // 1. QR ile biniş: ?sig= parametreli payload ayıklanır ve onaylanır
      final rQr = store.scanTransit('YESILADIM://TRANSIT/TRB-KTU-01?sig=9f8a7b', source: 'QR');
      expect(rQr.ok, true);
      expect(rQr.points, 3);
      expect(store.me!.weeklyPoints, 3);

      // 2. 5 dakika sonra aynı durak için kolonlu NFC UID taraması: Ortak 45 dk cooldown reddetmeli
      now = now.add(const Duration(minutes: 5));
      final rNfcColon = store.scanTransit('04:A1:2B:9C:11:80:01', source: 'NFC');
      expect(rNfcColon.ok, false);
      expect(rNfcColon.message, contains('bekle'));

      // 3. Kolonsuz küçük harf hex UID: Aynı durak olduğu için reddedilir
      final rNfcNoColon = store.scanTransit('04a12b9c118001', source: 'NFC');
      expect(rNfcNoColon.ok, false);

      // 4. Farklı durak (TRB-BLD-101): Ayrı cooldown, kabul edilir
      final rDifferent = store.scanTransit('04:B2:4C:8D:22:90:10', source: 'NFC');
      expect(rDifferent.ok, true);
      expect(store.me!.weeklyPoints, 6);

      // 5. 40 dakika sonra ilk durak (toplam 45 dk): Kabul edilir
      now = now.add(const Duration(minutes: 40));
      final rAccepted = store.scanTransit('04a12b9c118001', source: 'NFC');
      expect(rAccepted.ok, true);
      expect(store.me!.weeklyPoints, 9);
    });

    test('Bireysel Lig Rozet Yolları & Klan Ayrımı Sözleşmesi', () {
      expect(LeagueTier.allTiers.length, 6);

      // Bireysel lig PNG yolları 1..6 sırasıyla eşlenir
      expect(LeagueTier.allTiers[0].individualAssetPath, 'Logolar/logo-bireysel/lig-bireysel-1.png');
      expect(LeagueTier.allTiers[1].individualAssetPath, 'Logolar/logo-bireysel/lig-bireysel-2.png');
      expect(LeagueTier.allTiers[2].individualAssetPath, 'Logolar/logo-bireysel/lig-bireysel-3.png');
      expect(LeagueTier.allTiers[3].individualAssetPath, 'Logolar/logo-bireysel/lig-bireysel-4.png');
      expect(LeagueTier.allTiers[4].individualAssetPath, 'Logolar/logo-bireysel/lig-bireysel-5.png');
      expect(LeagueTier.allTiers[5].individualAssetPath, 'Logolar/logo-bireysel/lig-bireysel-6.png');

      // Eşikler şartname ve SQL ile tutarlı
      expect(LeagueTier.allTiers[0].individualThreshold, 0);
      expect(LeagueTier.allTiers[1].individualThreshold, 150);
      expect(LeagueTier.allTiers[2].individualThreshold, 350);
      expect(LeagueTier.allTiers[3].individualThreshold, 650);
      expect(LeagueTier.allTiers[4].individualThreshold, 1100);
      expect(LeagueTier.allTiers[5].individualThreshold, 1800);
    });
  });
}
