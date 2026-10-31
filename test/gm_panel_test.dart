import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:green_project/models/app_user.dart';
import 'package:green_project/services/app_store.dart';
import 'package:green_project/services/command_dispatcher.dart';
import 'package:green_project/services/gm_server.dart';
import 'package:green_project/services/hardware_bridge.dart';
import 'package:green_project/services/sensor_controller.dart';
import 'package:green_project/services/storage.dart';

void main() {
  group('CommandDispatcher, Idempotency & Parameter Bounds', () {
    late AppStore store;
    late CommandDispatcher dispatcher;

    setUp(() async {
      store = AppStore(backend: MemoryStore(), clock: () => DateTime.utc(2026, 10, 26, 9));
      await store.load();
      store.register(deviceId: 'dev_test', name: 'TestUser', clanName: 'KTÜ Kanuni');
      dispatcher = CommandDispatcher(store);
    });

    test('add_steps ve set_steps parametreli çalışır ve 600k adım ile puan muhasebesi senkronize edilir', () {
      expect(store.me!.todaySteps, 0);
      expect(store.me!.weeklyPoints, 0);
      final initialClanPts = store.myClan?.weeklyPoints ?? 0;

      // add_steps 5000 adım -> 25 puan
      final r1 = dispatcher.dispatch('add_steps', {'count': 5000});
      expect(r1.ok, true);
      expect(store.me!.todaySteps, 5000);
      expect(store.me!.weeklyPoints, 25);

      // 600k set_steps: 600.000 adıma ayarlanır, toplam 3000 puan (fark +2975 puan eklenir)
      final r2 = dispatcher.dispatch('set_steps', {'total': 600000});
      expect(r2.ok, true);
      expect(store.me!.todaySteps, 600000);
      expect(store.me!.weeklyPoints, 3000);
      expect(store.myClan?.weeklyPoints, initialClanPts + 3000);

      // Bozuk 600k durumu simülasyonu: Kullanıcının adımı 600k ama puanı 0
      store.me = store.me!.copyWith(weeklyPoints: 0);
      store.dayRewardedThousands = 0;
      final r3 = dispatcher.dispatch('set_steps', {'total': 600000});
      expect(r3.ok, true);
      expect(store.me!.weeklyPoints, 3000); // Eksik +3000 puan başarıyla onarıldı

      // Tekrar set_steps(600000) çağrısında çift puan verilmez
      final r4 = dispatcher.dispatch('set_steps', {'total': 600000});
      expect(r4.ok, true);
      expect(store.me!.weeklyPoints, 3000);
    });

    test('sayısal sınır kontrolü: negatif veya aşırı değerler reddedilir ve state değişmez', () {
      final initialSteps = store.me!.todaySteps;
      final initialGold = store.me!.goldCoins;
      final initialStreak = store.me!.streakDays;

      // Adım sınırları (add_steps maks 100.000, set_steps maks 1.000.000)
      final rAddExceed = dispatcher.dispatch('add_steps', {'count': 100001});
      expect(rAddExceed.ok, false);
      expect(rAddExceed.message.contains('1 - 100.000 arası olmalı'), true);

      expect(dispatcher.dispatch('add_steps', {'count': -10}).ok, false);
      expect(dispatcher.dispatch('set_steps', {'total': -1}).ok, false);
      expect(dispatcher.dispatch('set_steps', {'total': 1000001}).ok, false);
      expect(store.me!.todaySteps, initialSteps);

      // Streak sınırları
      expect(dispatcher.dispatch('add_streak', {'days': 0}).ok, false);
      expect(dispatcher.dispatch('add_streak', {'days': 500}).ok, false);
      expect(dispatcher.dispatch('set_streak', {'days': -5}).ok, false);
      expect(dispatcher.dispatch('set_streak', {'days': 5000}).ok, false);
      expect(store.me!.streakDays, initialStreak);

      // Altın sınırları
      expect(dispatcher.dispatch('add_gold', {'amount': -50}).ok, false);
      expect(dispatcher.dispatch('add_gold', {'amount': 200000}).ok, false);
      expect(dispatcher.dispatch('set_gold', {'total': -1}).ok, false);
      expect(dispatcher.dispatch('set_gold', {'total': 5000000}).ok, false);
      expect(store.me!.goldCoins, initialGold);
    });

    test('idempotencyKey aynı anahtar ve aynı payload ile yinelenen çağrıda duplicate döner', () {
      const key = 'idem_key_unique_1';
      final r1 = dispatcher.dispatch('add_gold', {'amount': 100}, idempotencyKey: key);
      expect(r1.ok, true);
      expect(r1.duplicate, false);
      expect(store.me!.goldCoins, 100);

      // İkinci çağrı aynı key ve aynı payload ile duplicate döner
      final r2 = dispatcher.dispatch('add_gold', {'amount': 100}, idempotencyKey: key);
      expect(r2.ok, true);
      expect(r2.duplicate, true);
      expect(store.me!.goldCoins, 100);
    });

    test('idempotencyKey aynı anahtar fakat FARKLI payload ile çağrılırsa conflict hatası verir', () {
      const key = 'idem_key_conflict_test';
      final r1 = dispatcher.dispatch('add_steps', {'count': 500}, idempotencyKey: key);
      expect(r1.ok, true);
      expect(r1.duplicate, false);
      expect(store.me!.todaySteps, 500);

      // Aynı anahtar fakat farklı count parametresi
      final r2 = dispatcher.dispatch('add_steps', {'count': 1000}, idempotencyKey: key);
      expect(r2.ok, false);
      expect(r2.message, contains('İdempotency çakışması'));
      // State değişmemeli
      expect(store.me!.todaySteps, 500);

      // Aynı anahtar fakat tamamen farklı komut
      final r3 = dispatcher.dispatch('add_gold', {'amount': 50}, idempotencyKey: key);
      expect(r3.ok, false);
      expect(r3.message, contains('İdempotency çakışması'));
      expect(store.me!.goldCoins, 0);
    });

    test('deterministik taksi demosu: toplu taşıma kaydı olsa bile izole ceza yazar', () {
      // Önce otobüs binişi yap
      store.scanTransit('YESILADIM://TRANSIT/TRB-BLD-101', source: 'TEST');
      expect(store.transitInLast45Min, true);

      // Normal değerlendirme muafiyet nedeniyle tespit yapmaz
      final norm = dispatcher.dispatch('evaluate_vehicle', {
        'avgSpeedKmh': 68.0,
        'distanceKm': 8.5,
        'stepDelta': 0,
        'ignoreTransitExemption': false,
      });
      expect(norm.ok, false);
      expect(norm.message, contains('muafiyeti'));
      expect(store.me!.weeklyCarTaxiTrips, 0);

      // İzole deterministik demo butonu ise cezayı kesin uygular
      final iso = dispatcher.dispatch('evaluate_vehicle', {
        'avgSpeedKmh': 68.0,
        'distanceKm': 8.5,
        'stepDelta': 0,
        'ignoreTransitExemption': true,
      });
      expect(iso.ok, true);
      expect(iso.message, contains('Yakalandın'));
      expect(store.me!.weeklyCarTaxiTrips, 1);
      expect(store.me!.weeklyWastedCo2Kg, closeTo(8.5 * 0.192, 1e-9));
    });

    test('bisiklet titreşimsiz ceza ve hız reddi net ayrılır', () {
      // 1) Hız reddi (>= 50 km/sa): Utanç tablosuna ceza yazılmaz
      final speedSpoof = dispatcher.dispatch('evaluate_bike', {
        'distanceKm': 5.0,
        'maxSpeedKmh': 72.0,
        'avgSpeedKmh': 40.0,
      });
      expect(speedSpoof.ok, false);
      expect(speedSpoof.message, contains('Hız reddi'));
      expect(store.me!.weeklyCarTaxiTrips, 0);

      // 2) Titreşimsiz ivme (< 0.12): Utanç tablosuna ceza yazılır
      final vibration = dispatcher.dispatch('evaluate_bike', {
        'distanceKm': 4.0,
        'maxSpeedKmh': 30.0,
        'avgSpeedKmh': 28.0,
        'fastAccelVariance': 0.05,
      });
      expect(vibration.ok, false);
      expect(vibration.message, contains('Araba şüphesi'));
      expect(store.me!.weeklyCarTaxiTrips, 1);
    });
  });

  group('GmServer HTTP Güvenlik, Origin & Sınır Regresyon Testleri', () {
    late AppStore store;
    late CommandDispatcher dispatcher;
    late SensorController sensors;
    late GmServer server;
    late HttpClient client;
    const token = 'test_gm_secret_tok_991827364';

    setUp(() async {
      client = HttpClient();
      store = AppStore(backend: MemoryStore(), clock: () => DateTime.utc(2026, 10, 26, 9));
      await store.load();
      store.register(deviceId: 'dev_http', name: 'Zeynep', clanName: 'KTÜ Kanuni');
      sensors = SensorController(bridge: NoHardwareBridge(), store: store);
      dispatcher = CommandDispatcher(store);
      server = GmServer(dispatcher: dispatcher, sensors: sensors);
      await server.start(initialToken: token, listenPort: 8099);
    });

    tearDown(() async {
      await server.stop();
      client.close();
    });

    test('yetkisiz 401 yanıtı ASLA gerçek tokenı ifşa etmez', () async {
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:8099/api/state'));
      final res = await req.close();
      expect(res.statusCode, HttpStatus.unauthorized);
      final body = await utf8.decodeStream(res);
      // GÜVENLİK KONTROLÜ: Token sızdırılmamalı!
      expect(body.contains(token), false, reason: '401 hata yanıtı gerçek tokenı içermemelidir!');
      expect(body, contains('Unauthorized'));
    });

    test('yanlış token ile istek 401 Unauthorized döner ve token sızdırmaz', () async {
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:8099/api/state?token=invalid_attack_token'));
      final res = await req.close();
      expect(res.statusCode, HttpStatus.unauthorized);
      final body = await utf8.decodeStream(res);
      expect(body.contains(token), false);
    });

    test('origin substring açığı: localhost.evil.example ve 127.0.0.1.attacker.com 403 Forbidden döner', () async {
      // 1) localhost.evil.com
      final req1 = await client.getUrl(Uri.parse('http://127.0.0.1:8099/api/state?token=$token'));
      req1.headers.set('Origin', 'http://localhost.evil.example:8099');
      final res1 = await req1.close();
      expect(res1.statusCode, HttpStatus.forbidden);

      // 2) 127.0.0.1.attacker.com
      final req2 = await client.getUrl(Uri.parse('http://127.0.0.1:8099/api/state?token=$token'));
      req2.headers.set('Origin', 'http://127.0.0.1.attacker.com:8099');
      final res2 = await req2.close();
      expect(res2.statusCode, HttpStatus.forbidden);

      // 3) Yanlış port
      final req3 = await client.getUrl(Uri.parse('http://127.0.0.1:8099/api/state?token=$token'));
      req3.headers.set('Origin', 'http://localhost:3000');
      final res3 = await req3.close();
      expect(res3.statusCode, HttpStatus.forbidden);
    });

    test('geçerli origin ile çağrıldığında wildcard değil tam origin başlığı döner', () async {
      const validOrigin = 'http://127.0.0.1:8099';
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:8099/api/state?token=$token'));
      req.headers.set('Origin', validOrigin);
      final res = await req.close();
      expect(res.statusCode, HttpStatus.ok);
      expect(res.headers.value('Access-Control-Allow-Origin'), validOrigin);
      expect(res.headers.value('Access-Control-Allow-Origin'), isNot('*'));
    });

    test('chunked / Content-Length=-1 gövdede 64 KB üstü istek 413 Payload Too Large döner', () async {
      final req = await client.postUrl(Uri.parse('http://127.0.0.1:8099/api/command?token=$token'));
      req.headers.contentType = ContentType.json;
      // 70 KB büyük chunked veri akışı
      final hugeData = List.filled(70 * 1024, 'a').join();
      req.write(jsonEncode({'cmd': 'add_steps', 'huge': hugeData}));
      final res = await req.close();
      expect(res.statusCode, HttpStatus.requestEntityTooLarge);
    });

    test('header yoluyla (X-GM-Token) token doğrulaması çalışır', () async {
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:8099/api/state'));
      req.headers.set('X-GM-Token', token);
      final res = await req.close();
      expect(res.statusCode, HttpStatus.ok);
      final body = jsonDecode(await utf8.decodeStream(res)) as Map<String, dynamic>;
      expect(body['user']['username'], 'Zeynep');
    });

    test('release engeli: sunucu devre dışı (enabled=false) olduğunda başlatılmaz', () async {
      final disabledServer = GmServer(dispatcher: dispatcher, sensors: sensors);
      disabledServer.enabled = false;
      await disabledServer.start(initialToken: 'sec', listenPort: 8105);
      expect(disabledServer.isRunning, false);
    });

    test('utanç panosu: sunucu snapshotı boşsa demo fallback yapılmaz, online liste esastır', () {
      // 1. Sunucu snapshot'ı yoksa demo sıralaması gösterilmez
      store.isServerShameLoaded = false;
      final offlineList = store.shameBoard();
      expect(offlineList, isEmpty);

      // 2. Sunucu snapshotı başarıyla yüklendi ancak boş (0 israfçı var):
      store.isServerShameLoaded = true;
      store.serverShameUsers = [];
      final emptySnapshotList = store.shameBoard();
      // Demo fallback olmamalı, liste boş dönmeli
      expect(emptySnapshotList.isEmpty, true);

      // 3. Puan top50 dışındaki (0 puanlı) ancak yüksek araç israfı olan kullanıcı snapshotta korunur
      store.serverShameUsers = [
        const AppUser(
          id: 'user-shame-001',
          deviceId: 'SRV-user-shame-001',
          username: 'Giz***',
          clanId: '',
          clanName: 'Karadeniz Fırtınası',
          weeklyPoints: 0, // Puanı 0, top50 puan listesinde ASLA yer alamaz!
          weeklyCarTaxiTrips: 15,
          weeklyWastedCo2Kg: 45.5,
        ),
      ];
      final onlineShameList = store.shameBoard();
      expect(onlineShameList.length, 1);
      expect(onlineShameList.first.username, 'Giz***');
      expect(onlineShameList.first.weeklyWastedCo2Kg, 45.5);

      // 4. Cezası olmayan cihaz kullanıcısı (me) listeye zorla enjekte edilmez
      expect(store.me?.weeklyCarTaxiTrips ?? 0, 0);
      expect(onlineShameList.any((u) => u.id == store.me!.id), false);
    });

    test('evaluate_vehicle sınır kontrolleri, demo izolasyonu ve sunucu utanç panosu tutarlılığı', () {
      final initialTrips = store.me!.weeklyCarTaxiTrips;
      final initialWasted = store.me!.weeklyWastedCo2Kg;
      final initialPoints = store.me!.weeklyPoints;
      final initialGold = store.me!.goldCoins;

      // Geçersiz parametreler reddedilir
      final rInvalid = dispatcher.dispatch('evaluate_vehicle', {'distanceKm': -5.0});
      expect(rInvalid.ok, false);
      expect(store.me!.weeklyCarTaxiTrips, initialTrips);

      // Geçerli yerel demo araç cezası
      final rValid = dispatcher.dispatch('evaluate_vehicle', {
        'distanceKm': 10.0,
        'avgSpeedKmh': 60.0,
        'stepDelta': 0,
        'ignoreTransitExemption': true,
      });
      expect(rValid.ok, true);
      expect(store.me!.weeklyCarTaxiTrips, initialTrips + 1);
      expect(store.me!.weeklyWastedCo2Kg, closeTo(initialWasted + 1.92, 0.01));
      // Puan ve altın kesinlikle korunur
      expect(store.me!.weeklyPoints, initialPoints);
      expect(store.me!.goldCoins, initialGold);

      // Tekrarlanan aynı tripId çift ceza yazmaz (idempotent)
      final rDup = dispatcher.dispatch('evaluate_vehicle', {
        'tripId': 'trip_same_123',
        'distanceKm': 10.0,
        'avgSpeedKmh': 60.0,
        'stepDelta': 0,
        'ignoreTransitExemption': true,
      });
      expect(rDup.ok, true);
      final tripsAfterFirst = store.me!.weeklyCarTaxiTrips;
      final rDup2 = dispatcher.dispatch('evaluate_vehicle', {
        'tripId': 'trip_same_123',
        'distanceKm': 10.0,
        'avgSpeedKmh': 60.0,
        'stepDelta': 0,
        'ignoreTransitExemption': true,
      });
      expect(rDup2.ok, false);
      expect(store.me!.weeklyCarTaxiTrips, tripsAfterFirst); // Tekrar artmaz
    });
  });
}
