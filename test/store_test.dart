import 'package:flutter_test/flutter_test.dart';
import 'package:green_project/services/app_store.dart';
import 'package:green_project/services/storage.dart';

class Env {
  final MemoryStore disk = MemoryStore();
  DateTime now = DateTime.utc(2026, 10, 26, 9, 0); // Pzt 12:00 İstanbul
  late AppStore store;
  Env() {
    store = _make();
  }
  AppStore _make() => AppStore(backend: disk, clock: () => now);
  Future<AppStore> fresh({bool register = true}) async {
    store = _make();
    await store.load();
    if (register && !store.hasProfile) {
      store.register(deviceId: 'dev1', name: 'Ayşe', clanName: 'KTÜ Kanuni');
    }
    return store;
  }

  /// Yeniden başlatma: aynı disk, yeni örnek.
  Future<AppStore> restart() async {
    await store.flush();
    store = _make();
    await store.load();
    return store;
  }

  void advance(Duration d) => now = now.add(d);
}

void main() {
  group('Kayıt / onboarding', () {
    test('gerçek kullanıcı sıfır puanla başlar, demo Efe değildir; çift kayıt etkisiz', () async {
      final e = Env();
      final s = await e.fresh();
      expect(s.me!.username, 'Ayşe');
      expect(s.me!.weeklyPoints, 0);
      expect(s.me!.todaySteps, 0);
      expect(s.me!.goldCoins, 0);
      expect(s.register(deviceId: 'x', name: 'Efe', clanName: 'ODTÜ').ok, false);
      expect(s.me!.username, 'Ayşe');
      final kanuni = s.clans.firstWhere((c) => c.id == 'clan_ktu_kanuni');
      expect(kanuni.memberCount, 143);
    });
    test('boş isim ve bilinmeyen klan reddedilir', () async {
      final e = Env();
      final s = await e.fresh(register: false);
      expect(s.register(deviceId: 'd', name: '  ', clanName: 'ODTÜ').ok, false);
      expect(s.register(deviceId: 'd', name: 'A', clanName: 'Yok').ok, false);
      expect(s.hasProfile, false);
    });
    test('kayıt restart sonrası korunur (üyelik, klan sayısı)', () async {
      final e = Env();
      await e.fresh();
      final s = await e.restart();
      expect(s.me!.username, 'Ayşe');
      expect(s.clans.firstWhere((c) => c.id == 'clan_ktu_kanuni').memberCount, 143);
    });
  });

  group('Sensör adımları', () {
    test('ilk örnek taban çizgisidir; tekrar olay ve pencere dolmadan puan yok', () async {
      final e = Env();
      final s = await e.fresh();
      expect(s.onSensorSteps(5000).ok, false);
      expect(s.me!.todaySteps, 0);
      expect(s.onSensorSteps(5000).duplicate, true);
      e.advance(const Duration(seconds: 10));
      expect(s.onSensorSteps(5010).ok, false); // 30 sn dolmadı
      expect(s.me!.todaySteps, 0);
    });
    test('geçerli artış sayılır; 1000 sınırı +5; tekrar olay çift saymaz', () async {
      final e = Env();
      final s = await e.fresh();
      s.onSensorSteps(0);
      e.advance(const Duration(minutes: 10));
      expect(s.onSensorSteps(999).points, 0);
      expect(s.me!.todaySteps, 999);
      e.advance(const Duration(minutes: 1));
      expect(s.onSensorSteps(1000).points, 5);
      expect(s.onSensorSteps(1000).duplicate, true);
      expect(s.me!.weeklyPoints, 5);
      expect(s.myClan!.weeklyPoints, 125430 + 5);
    });
    test('yeniden başlatma sayaç azalması puan üretmez, sonra normal sayar', () async {
      final e = Env();
      final s = await e.fresh();
      s.onSensorSteps(50000);
      e.advance(const Duration(minutes: 5));
      s.onSensorSteps(50100);
      expect(s.me!.todaySteps, 100);
      e.advance(const Duration(minutes: 5));
      expect(s.onSensorSteps(30).ok, false); // reboot
      expect(s.me!.todaySteps, 100);
      e.advance(const Duration(minutes: 5));
      s.onSensorSteps(80);
      expect(s.me!.todaySteps, 150);
    });
    test('kadans > 185 reddedilir ve tekrar sayılmaz', () async {
      final e = Env();
      final s = await e.fresh();
      s.onSensorSteps(0);
      e.advance(const Duration(seconds: 30));
      final r = s.onSensorSteps(200); // 400/dk
      expect(r.ok, false);
      expect(s.me!.todaySteps, 0);
      e.advance(const Duration(minutes: 1));
      s.onSensorSteps(250);
      expect(s.me!.todaySteps, 50);
    });
    test('sallama + GPS hareketsiz reddeder; GPS yoksa kabul', () async {
      final e = Env();
      final s = await e.fresh();
      s.onSensorSteps(0);
      e.advance(const Duration(minutes: 1));
      s.onAccel(freqHz: 4.0, variance: 3.0);
      expect(s.onSensorSteps(60).ok, true); // GPS ölçümü yok -> suçlama yok
      // GPS: 30 sn arayla aynı nokta
      s.onLocation(lat: 41.0, lon: 39.7, accuracy: 5, tsMs: e.now.millisecondsSinceEpoch - 30000);
      s.onLocation(lat: 41.0, lon: 39.7, accuracy: 5, tsMs: e.now.millisecondsSinceEpoch);
      e.advance(const Duration(minutes: 1));
      s.onAccel(freqHz: 4.0, variance: 3.0);
      s.onLocation(lat: 41.0, lon: 39.7, accuracy: 5, tsMs: e.now.millisecondsSinceEpoch);
      expect(s.onSensorSteps(120).ok, false);
      expect(s.me!.todaySteps, 60);
    });
    test('demo +334 ile 6666 -> 7000 yalnız +5', () async {
      final e = Env();
      final s = await e.fresh();
      s.demoAddSteps(6666);
      expect(s.me!.weeklyPoints, 30);
      final r = s.demoAddSteps(334);
      expect(r.points, 5);
      expect(s.me!.weeklyPoints, 35);
      expect(s.me!.todaySteps, 7000);
    });
  });

  group('Gün / streak', () {
    test('6000 streak aynı gün tek artış; gün değişimi adım sıfırlar ve 1000 ödülü yeniden açılır', () async {
      final e = Env();
      final s = await e.fresh();
      s.demoAddSteps(6000);
      expect(s.me!.streakDays, 1);
      s.demoAddSteps(500);
      expect(s.me!.streakDays, 1);
      e.advance(const Duration(days: 1));
      s.tick();
      expect(s.me!.todaySteps, 0);
      expect(s.me!.streakDays, 1); // dün yapıldı, bugün henüz yok
      s.demoAddSteps(6000);
      expect(s.me!.streakDays, 2);
      expect(s.me!.weeklyPoints, 30 + 30);
    });
    test('kaçırılan gün seriyi sıfırlar', () async {
      final e = Env();
      final s = await e.fresh();
      s.demoAddSteps(6000);
      e.advance(const Duration(days: 2));
      s.tick();
      expect(s.me!.streakDays, 0);
      s.demoAddSteps(6000);
      expect(s.me!.streakDays, 1);
    });
    test('gün değişimi ve streak restart sonrası da tutarlı', () async {
      final e = Env();
      final s = await e.fresh();
      s.demoAddSteps(6000);
      await e.restart();
      e.store.demoAddSteps(10);
      expect(e.store.me!.streakDays, 1);
      expect(e.store.me!.todaySteps, 6010);
    });
  });

  group('Transit', () {
    test('QR ve NFC aynı durak ortak cooldown; 44:59 red, 45:00 kabul; tek +3 tek CO₂', () async {
      final e = Env();
      final s = await e.fresh();
      final a = s.scanTransit('YESILADIM://TRANSIT/TRB-KTU-01', source: 'QR');
      expect(a.ok, true);
      expect(a.points, 3);
      expect(s.me!.preventedCo2Kg, closeTo(0.58, 1e-9));
      e.advance(const Duration(minutes: 44, seconds: 59));
      final b = s.scanTransit('TRB-KTU-01', source: 'NFC');
      expect(b.ok, false);
      expect(b.message, contains('1 dk'));
      expect(s.me!.weeklyPoints, 3);
      e.advance(const Duration(seconds: 1));
      expect(s.scanTransit('TRB-KTU-01', source: 'NFC').ok, true);
      expect(s.me!.weeklyPoints, 6);
    });
    test('farklı durak ayrı cooldown; bilinmeyen/geçersiz payload reddedilir', () async {
      final e = Env();
      final s = await e.fresh();
      expect(s.scanTransit('TRB-KTU-01', source: 'QR').ok, true);
      expect(s.scanTransit('TRB-BLD-101', source: 'QR').ok, true);
      expect(s.scanTransit('TRB-YOK-99', source: 'QR').ok, false);
      expect(s.scanTransit('%%%', source: 'QR').ok, false);
      expect(s.scanTransit(null, source: 'NFC').ok, false);
      expect(s.me!.weeklyPoints, 6);
    });
    test('art arda hızlı tekrar tarama tek ödül', () async {
      final e = Env();
      final s = await e.fresh();
      final rs = List.generate(5, (_) => s.scanTransit('TRB-OF-204', source: 'QR'));
      expect(rs.where((r) => r.ok).length, 1);
      expect(s.me!.weeklyPoints, 3);
    });
    test('cooldown restart sonrası korunur; telefon saati geri alınırsa reddedilir', () async {
      final e = Env();
      final s = await e.fresh();
      s.scanTransit('TRB-KTU-01', source: 'QR');
      final s2 = await e.restart();
      expect(s2.scanTransit('TRB-KTU-01', source: 'QR').ok, false);
      e.now = e.now.subtract(const Duration(hours: 5));
      expect(s2.scanTransit('TRB-KTU-01', source: 'QR').ok, false);
    });
  });

  group('Bisiklet', () {
    test('aynı tripId iki kez ödül/ceza yaratmaz', () async {
      final e = Env();
      final s = await e.fresh();
      final a = s.evaluateBike(tripId: 't1', distanceKm: 2.5, maxSpeedKmh: 22, avgSpeedKmh: 18, demo: true);
      expect(a.points, 2);
      final b = s.evaluateBike(tripId: 't1', distanceKm: 2.5, maxSpeedKmh: 22, avgSpeedKmh: 18, demo: true);
      expect(b.duplicate, true);
      expect(s.me!.weeklyPoints, 2);
      final p = s.evaluateBike(tripId: 't2', distanceKm: 4, maxSpeedKmh: 30, avgSpeedKmh: 28, fastAccelVariance: 0.05, demo: true);
      expect(p.ok, false);
      s.evaluateBike(tripId: 't2', distanceKm: 4, maxSpeedKmh: 30, avgSpeedKmh: 28, fastAccelVariance: 0.05, demo: true);
      expect(s.me!.weeklyCarTaxiTrips, 1);
      expect(s.me!.weeklyWastedCo2Kg, closeTo(4 * 0.192, 1e-9));
    });
    test('hız hilesi reddedilir: puan, CO₂ ve ceza kalmaz', () async {
      final e = Env();
      final s = await e.fresh();
      final r = s.evaluateBike(tripId: 'x', distanceKm: 5, maxSpeedKmh: 72, avgSpeedKmh: 40, demo: true);
      expect(r.ok, false);
      expect(s.me!.weeklyPoints, 0);
      expect(s.me!.preventedCo2Kg, 0);
      expect(s.me!.weeklyCarTaxiTrips, 0);
    });
    test('yetersiz GPS: puan da ceza da yok ve tripId tüketilmez', () async {
      final e = Env();
      final s = await e.fresh();
      expect(s.evaluateBike(tripId: 'y', distanceKm: 0, maxSpeedKmh: 0, avgSpeedKmh: 0, validFixes: 1, demo: false).ok, false);
      expect(s.me!.weeklyCarTaxiTrips, 0);
      expect(s.evaluateBike(tripId: 'y', distanceKm: 1.2, maxSpeedKmh: 20, avgSpeedKmh: 15, demo: false).points, 1);
    });
    test('GPS oturumu: mesafe birikir, sıçrama ve düşük doğruluk atlanır, duraklatma mesafe katmaz', () async {
      final e = Env();
      final s = await e.fresh();
      final b = s.startBike(tripId: 'g1');
      final t0 = e.now.millisecondsSinceEpoch;
      // ~111 m kuzeye her 20 sn (~20 km/sa)
      double lat(int i) => 41.0 + i * 0.001;
      for (var i = 0; i < 4; i++) {
        s.onLocation(lat: lat(i), lon: 39.7, accuracy: 5, tsMs: t0 + i * 20000);
      }
      expect(b.distanceM, closeTo(3 * 111.2, 3));
      s.onLocation(lat: 45.0, lon: 39.7, accuracy: 5, tsMs: t0 + 4 * 20000); // sıçrama
      expect(b.jumps, 1);
      s.onLocation(lat: lat(5), lon: 39.7, accuracy: 80, tsMs: t0 + 5 * 20000); // kötü doğruluk
      expect(b.lowAccuracy, 1);
      final before = b.distanceM;
      s.pauseBike();
      s.onLocation(lat: lat(10), lon: 39.7, accuracy: 5, tsMs: t0 + 6 * 20000);
      s.resumeBike();
      s.onLocation(lat: lat(10), lon: 39.7, accuracy: 5, tsMs: t0 + 7 * 20000);
      expect(b.distanceM, before);
      final r = s.finishBike();
      expect(r.points, 0); // 1 km altı: geçerli ama 0 puan
      expect(s.me!.weeklyPoints, 0);
      expect(s.me!.weeklyCarTaxiTrips, 0);
    });
    test('GPS oturumu: 1 km üstü sürüş puan verir; bitince oturum kapanır', () async {
      final e = Env();
      final s = await e.fresh();
      s.startBike(tripId: 'g2');
      final t0 = e.now.millisecondsSinceEpoch;
      for (var i = 0; i < 15; i++) {
        s.onLocation(lat: 41.0 + i * 0.001, lon: 39.7, accuracy: 5, tsMs: t0 + i * 25000);
      }
      final r = s.finishBike();
      expect(r.ok, true);
      expect(r.points, 1);
      expect(s.bike, isNull);
      expect(s.finishBike().ok, false);
    });
  });

  group('Araba/taksi', () {
    test('aynı yolculuk tek sayaç; veri yoksa suçlama yok; transit sonrası yok', () async {
      final e = Env();
      final s = await e.fresh();
      expect(s.evaluateVehicle(tripId: 'v0', avgSpeedKmh: null, distanceKm: 5, stepDelta: 0, demo: true).ok, false);
      expect(s.me!.weeklyCarTaxiTrips, 0);
      expect(s.evaluateVehicle(tripId: 'v1', avgSpeedKmh: 68, distanceKm: 8.5, stepDelta: 0, demo: true).ok, true);
      expect(s.evaluateVehicle(tripId: 'v1', avgSpeedKmh: 68, distanceKm: 8.5, stepDelta: 0, demo: true).duplicate, true);
      expect(s.me!.weeklyCarTaxiTrips, 1);
      expect(s.me!.weeklyWastedCo2Kg, closeTo(8.5 * 0.192, 1e-9));
      expect(s.me!.preventedCo2Kg, 0); // önlenen ve harcanan ayrı
      s.scanTransit('TRB-KTU-01', source: 'QR');
      expect(s.evaluateVehicle(tripId: 'v2', avgSpeedKmh: 68, distanceKm: 8.5, stepDelta: 0, demo: true).ok, false);
      expect(s.me!.weeklyCarTaxiTrips, 1);
    });
  });

  group('Mağaza', () {
    test('yetersiz bakiye, tam bakiye, çift dokunma, kilitli equip, restart', () async {
      final e = Env();
      final s = await e.fresh();
      expect(s.buy('leaf_warrior').ok, false);
      expect(s.me!.goldCoins, 0);
      expect(s.equip('leaf_warrior').ok, false); // kilitli
      s.demoGrantGold(500);
      expect(s.buy('leaf_warrior').ok, true);
      expect(s.me!.goldCoins, 0); // tam bakiye, negatif yok
      expect(s.buy('leaf_warrior').duplicate, true);
      expect(s.me!.goldCoins, 0);
      expect(s.me!.equippedAvatar, 'leaf_warrior');
      expect(s.equip('default_avatar').ok, true);
      final s2 = await e.restart();
      expect(s2.owned.contains('leaf_warrior'), true);
      expect(s2.me!.equippedAvatar, 'default_avatar');
      expect(s2.me!.goldCoins, 0);
      expect(s2.equip('leaf_warrior').ok, true);
      expect(s2.buy('yok').ok, false);
    });
  });

  group('Haftalık reset', () {
    test('puan altına bir kez; tekrar çağrı etkisiz; günlük adım/envanter/streak korunur', () async {
      final e = Env();
      final s = await e.fresh();
      s.demoAddSteps(6000);
      s.scanTransit('TRB-KTU-01', source: 'QR');
      s.evaluateVehicle(tripId: 'v', avgSpeedKmh: 68, distanceKm: 5, stepDelta: 0, demo: true);
      final week = s.weekId;
      expect(week, '2026-10-26');
      final pts = s.me!.weeklyPoints; // 30 + 3
      expect(pts, 33);
      expect(s.settleWeek(week), true);
      expect(s.me!.goldCoins, pts);
      expect(s.me!.weeklyPoints, 0);
      expect(s.me!.weeklyCarTaxiTrips, 0);
      expect(s.me!.weeklyWastedCo2Kg, 0);
      expect(s.me!.allTimePoints, pts);
      expect(s.me!.todaySteps, 6000);
      expect(s.me!.streakDays, 1);
      expect(s.me!.preventedCo2Kg, greaterThan(0));
      expect(s.owned.contains('default_avatar'), true);
      expect(s.myClan!.weeklyPoints, 0);
      // tekrar çağrı: çift altın yok
      expect(s.settleWeek(week), false);
      expect(s.me!.goldCoins, pts);
      // yeni puan kazan, eski hafta kimliğiyle tekrar reset: yine etkisiz
      e.advance(const Duration(minutes: 50));
      s.scanTransit('TRB-BLD-101', source: 'QR');
      expect(s.settleWeek(week), false);
      expect(s.me!.goldCoins, pts);
      expect(s.me!.weeklyPoints, 3);
    });
    test('şampiyonlar reset öncesi seçilir ve restart sonrası kalır', () async {
      final e = Env();
      final s = await e.fresh();
      s.settleWeek(s.weekId);
      // demo: Zeynep Kaya 1850 ile bireysel şampiyon, KTÜ Kanuni klan şampiyonu
      expect(s.championUser, 'Zeynep Kaya');
      expect(s.championClan, 'KTÜ Kanuni');
      final s2 = await e.restart();
      expect(s2.championUser, 'Zeynep Kaya');
      expect(s2.championClan, 'KTÜ Kanuni');
      expect(s2.settledWeeks.contains('2026-10-26'), true);
      expect(s2.settleWeek('2026-10-26'), false);
    });
    test('gerçek hafta değişimi (Pzt 00:00 İstanbul) otomatik ve idempotent kapatır', () async {
      final e = Env();
      final s = await e.fresh();
      s.demoAddSteps(1000);
      // Pazar 23:59 İstanbul = 20:59 UTC
      e.now = DateTime.utc(2026, 11, 1, 20, 59);
      s.tick();
      expect(s.weekId, '2026-10-26');
      expect(s.me!.goldCoins, 0);
      // Pazartesi 00:00 İstanbul = Pazar 21:00 UTC
      e.now = DateTime.utc(2026, 11, 1, 21, 0);
      s.tick();
      expect(s.weekId, '2026-11-02');
      expect(s.me!.goldCoins, 5);
      s.tick();
      expect(s.me!.goldCoins, 5);
      final s2 = await e.restart();
      expect(s2.me!.goldCoins, 5);
      expect(s2.weekId, '2026-11-02');
    });
    test('uygulama haftalarca kapalı kaldıysa her hafta bir kez kapanır', () async {
      final e = Env();
      final s = await e.fresh();
      s.demoAddSteps(2000);
      e.now = DateTime.utc(2026, 11, 20, 9);
      s.tick();
      expect(s.weekId, '2026-11-16');
      expect(s.me!.goldCoins, 10);
    });
  });

  group('Sıralama', () {
    test('eşit puanda kararlı sıra (ad, sonra id); sıralama dışı klan hariç', () async {
      final e = Env();
      final s = await e.fresh();
      final ranked = s.rankedClans();
      expect(ranked.any((c) => c.id == 'clan_micro'), false);
      expect(ranked.first.id, 'clan_ktu_kanuni');
      final users = s.rankedUsers();
      expect(users.first.username, 'Zeynep Kaya');
      // Tekil puan kontrolü
      final tied = s.rankedUsers().where((u) => u.weeklyPoints == 5860).length;
      expect(tied, 1);
    });
    test('utanç tablosu: israf CO₂ azalan; cezasızlar hariç', () async {
      final e = Env();
      final s = await e.fresh();
      final board = s.shameBoard();
      expect(board.first.username, 'Pelinsu Yılmaz');
      expect(board.every((u) => u.weeklyCarTaxiTrips > 0), true);
      s.evaluateVehicle(tripId: 'z', avgSpeedKmh: 70, distanceKm: 300, stepDelta: 0, demo: true);
      expect(s.shameBoard().first.id, s.me!.id);
    });
    test('tüm zamanlar ve haftalık ayrımı reset sonrası', () async {
      final e = Env();
      final s = await e.fresh();
      s.demoAddSteps(2000);
      s.settleWeek(s.weekId);
      expect(s.rankedUsers().firstWhere((u) => u.id == s.me!.id).weeklyPoints, 0);
      expect(s.rankedUsers(allTime: true).firstWhere((u) => u.id == s.me!.id).allTimePoints, 10);
    });
  });

  group('Dayanıklılık', () {
    test('bozuk kayıt çökertmez, temiz başlar', () async {
      final e = Env();
      e.disk.data[AppStore.storageKey] = '{bozuk';
      final s = await e.fresh(register: false);
      expect(s.hasProfile, false);
      expect(s.loaded, true);
    });
    test('profilsiz işlemler güvenle reddedilir', () async {
      final e = Env();
      final s = await e.fresh(register: false);
      expect(s.demoAddSteps(10).ok, false);
      expect(s.scanTransit('TRB-KTU-01', source: 'QR').ok, false);
      expect(s.buy('leaf_warrior').ok, false);
      expect(s.onSensorSteps(5).ok, false);
    });
  });
}
