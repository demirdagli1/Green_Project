import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:green_project/core/utils/name_masker.dart';
import 'package:green_project/models/clan.dart';
import 'package:green_project/screens/leaderboard/leaderboard_screen.dart';
import 'package:green_project/screens/main_shell.dart';
import 'package:green_project/services/app_store.dart';
import 'package:green_project/services/command_dispatcher.dart';
import 'package:green_project/services/hardware_bridge.dart';
import 'package:green_project/services/hub.dart';
import 'package:green_project/services/sensor_controller.dart';
import 'package:green_project/services/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Aşama B & C İş Mantığı ve Kalıcılık Testleri', () {
    test('Klan hibrit puanı: 0.6×toplam + 0.4×50×üye ortalaması; haftalık ve tüm zamanlar ayrımı', () {
      // 10 üye, 1000 puan
      // avg = 100
      // hybrid = (1000 * 0.6) + (100 * 50 * 0.4) = 600 + 2000 = 2600.0
      const clan = Clan(
        id: 'c1',
        name: 'Doğa Klanı',
        memberCount: 10,
        weeklyPoints: 1000,
        allTimePoints: 5000,
      );
      expect(clan.hybridScoreFor(allTime: false), 2600.0);
      // Tüm zamanlar: total=5000, avg=500 -> 3000 + 10000 = 13000.0
      expect(clan.hybridScoreFor(allTime: true), 13000.0);
    });

    test('Klan sıralaması: 5\'ten az üyeli klanlar sıralamaya alınmaz', () {
      const clan4 = Clan(id: 'c_small', name: 'Küçük Klan', memberCount: 4, weeklyPoints: 50000);
      const clan5 = Clan(id: 'c_valid', name: 'Geçerli Klan', memberCount: 5, weeklyPoints: 100);
      expect(clan4.isEligibleForRanking, false);
      expect(clan5.isEligibleForRanking, true);
    });

    test('Profil bio güncelleme: 160 karakter sınır, Türkçe ve emoji güvenliği, restart kalıcılığı', () async {
      final backend = MemoryStore();
      final store = AppStore(backend: backend);
      await store.load();
      store.register(deviceId: 'dev_test', name: 'Ahmet', clanName: 'KTÜ Kanuni');

      // Geçerli bio (Türkçe + emoji)
      const validBio = '🌿 Trabzon KTÜ doğa aşığı! 🌲 Yeşil bir gelecek için her gün 10.000 adım. 🍃';
      final res = store.updateBio(validBio);
      expect(res.ok, true);
      expect(store.me!.bio, validBio);

      // Yeniden başlatma (restart) kalıcılığı
      await store.flush();
      final storeRestart = AppStore(backend: backend);
      await storeRestart.load();
      expect(storeRestart.me!.bio, validBio);

      // Sınır aşımı (161+ karakter) reddedilmeli
      final longBio = 'A' * 161;
      final failRes = store.updateBio(longBio);
      expect(failRes.ok, false);
      expect(store.me!.bio, validBio); // Değişmemeli
    });

    test('Profil fotoğrafı güncelleme ve kaldırma, kalıcılık', () async {
      final backend = MemoryStore();
      final store = AppStore(backend: backend);
      await store.load();
      store.register(deviceId: 'dev_test', name: 'Ahmet', clanName: 'KTÜ Kanuni');

      expect(store.me!.photoPath, isNull);

      // Fotoğraf yolu ata
      const photoPath = '/data/user/0/com.yesiladim.ecoclan/files/profile_photo.jpg';
      final r1 = store.updateProfilePhoto(photoPath);
      expect(r1.ok, true);
      expect(store.me!.photoPath, photoPath);

      // Restart kontrolü
      await store.flush();
      final store2 = AppStore(backend: backend);
      await store2.load();
      expect(store2.me!.photoPath, photoPath);

      // Fotoğrafı kaldır
      final r2 = store2.updateProfilePhoto(null);
      expect(r2.ok, true);
      expect(store2.me!.photoPath, isNull);
    });

    test('CommandDispatcher set_bio komut sözleşmesi', () async {
      final backend = MemoryStore();
      final store = AppStore(backend: backend);
      await store.load();
      store.register(deviceId: 'dev_test', name: 'Ahmet', clanName: 'KTÜ Kanuni');

      final dispatcher = CommandDispatcher(store);
      final r = dispatcher.dispatch('set_bio', {'bio': 'Yeni test biyografisi 🌱'});
      expect(r.ok, true);
      expect(store.me!.bio, 'Yeni test biyografisi 🌱');

      // 160 karakter üzeri sınır kontrolü
      final rTooLong = dispatcher.dispatch('set_bio', {'bio': 'X' * 161});
      expect(rTooLong.ok, false);
    });

    test('Utanç tablosu: kullanıcının araç cezası yoksa tabloda uydurma veri yer almaz', () async {
      final backend = MemoryStore();
      final store = AppStore(backend: backend);
      await store.load();
      store.register(deviceId: 'dev_test', name: 'Temiz Kullanıcı', clanName: 'KTÜ Kanuni');

      final shame = store.shameBoard();
      // Temiz kullanıcının cezası 0 olduğundan tabloda yer almamalıdır
      expect(shame.any((u) => u.id == store.me!.id), false);
      // Tüm tabloda sadece weeklyCarTaxiTrips > 0 olanlar yer alır
      expect(shame.every((u) => u.weeklyCarTaxiTrips > 0), true);

      // Maskelenmiş isim testi: asla açık tam ad sızmaz
      for (final u in shame) {
        final masked = NameMasker.maskShameName(u.username);
        expect(masked.contains('***'), true);
        expect(masked == u.username, false);
      }
    });

    test('Geçen hafta şampiyonları: sonuç yokken açık DEMO fallback; reset sonrası gerçek sonuç', () async {
      final backend = MemoryStore();
      final store = AppStore(backend: backend, clock: () => DateTime.utc(2026, 10, 26, 9));
      await store.load();
      store.register(deviceId: 'dev_test', name: 'Ahmet', clanName: 'KTÜ Kanuni');

      // İlk başta şampiyon yok
      expect(store.championUser, '—');
      expect(store.championClan, '—');

      // Hafta kapatıldığında en yüksek puanlı gerçek kullanıcı şampiyon olur
      store.demoAddSteps(5000); // 25 puan
      store.settleWeek(store.weekId);

      expect(store.championUser, isNot('—'));
      expect(store.championClan, isNot('—'));
    });
  });

  group('Aşama B & C UI & Gezinme Widget Testleri', () {
    testWidgets('MainShell: 4 öğeli bottom navigation, varsayılan Ana Menü (index 1), Floating FAB yok', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore(backend: MemoryStore(), clock: () => DateTime.utc(2026, 10, 26, 9));
      await store.load();
      store.register(deviceId: 'dev_ui', name: 'Zeynep', clanName: 'KTÜ Kanuni');
      AppStore.instance = store;
      Hub.sensors = SensorController(bridge: NoHardwareBridge(), store: store);

      await tester.pumpWidget(const MaterialApp(home: MainShell()));
      await tester.pumpAndSettle();

      // FloatingActionButton olmamalı
      expect(find.byType(FloatingActionButton), findsNothing);

      // 4 öğeli BottomNavigationBar
      final navBarFinder = find.byType(BottomNavigationBar);
      expect(navBarFinder, findsOneWidget);
      final navBar = tester.widget<BottomNavigationBar>(navBarFinder);
      expect(navBar.items.length, 4);
      expect(navBar.items[0].label, 'QR / NFC');
      expect(navBar.items[1].label, 'Ana Menü');
      expect(navBar.items[2].label, 'Sıralamalar');
      expect(navBar.items[3].label, 'Profil');

      // Varsayılan sayfa: Ana Menü (index 1) görünür
      expect(navBar.currentIndex, 1);
      expect(find.text('Daha yeşil bir gelecek için adım at!'), findsOneWidget);

      // Geri tuşu davranışı: Profil sekmesindeyken geri basılırsa Ana Menüye döner
      await tester.tap(find.text('Profil'));
      await tester.pumpAndSettle();
      expect(find.text('Profil ve Mağaza'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Daha yeşil bir gelecek için adım at!'), findsOneWidget);
    });

    testWidgets('Ana sayfa birleşik kartlar: tıklanınca doğru sekmeye ve satır vurgusuna gider', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore(backend: MemoryStore(), clock: () => DateTime.utc(2026, 10, 26, 9));
      await store.load();
      store.register(deviceId: 'dev_ui2', name: 'Mehmet', clanName: 'KTÜ Kanuni');
      AppStore.instance = store;
      Hub.sensors = SensorController(bridge: NoHardwareBridge(), store: store);

      await tester.pumpWidget(const MaterialApp(home: MainShell()));
      await tester.pumpAndSettle();

      // Birleşik Klan kartı tıklanır
      final clanCard = find.text('Klanım & Sıram');
      expect(clanCard, findsOneWidget);
      await tester.tap(clanCard);
      await tester.pumpAndSettle();

      // Sıralamalar sekmesi açılmış ve Klan seçili olmalı
      expect(find.text('🏆 Gurur Tablosu'), findsOneWidget);
      expect(find.textContaining('Klanın'), findsWidgets);

      // Ana sayfaya geri dön
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Bireysel karta tıkla
      final indCard = find.text('Bireysel Ligim & Sıram');
      expect(indCard, findsOneWidget);
      await tester.tap(indCard);
      await tester.pumpAndSettle();

      // Bireysel sekmesi açılmış ve 'Mehmet (Sen)' vurgulanmış olmalı
      final meFinder = find.textContaining('Mehmet (Sen)');
      await tester.scrollUntilVisible(meFinder, 50.0);
      expect(meFinder, findsOneWidget);
    });

    testWidgets('Ana sayfa Utanç Tablosu özeti: Tam tabloya geçiş Utanç listesini açar', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore(backend: MemoryStore(), clock: () => DateTime.utc(2026, 10, 26, 9));
      await store.load();
      store.register(deviceId: 'dev_ui3', name: 'Ayşe', clanName: 'KTÜ Kanuni');
      AppStore.instance = store;
      Hub.sensors = SensorController(bridge: NoHardwareBridge(), store: store);

      await tester.pumpWidget(const MaterialApp(home: MainShell()));
      await tester.pumpAndSettle();

      // Utanç özeti kartı ana sayfada görünür
      expect(find.text('🚨 Utanç Tablosu Özeti'), findsOneWidget);

      // 'Tam Tabloyu Gör >' tıkla
      final viewAllBtn = find.text('Tam Tabloyu Gör >');
      expect(viewAllBtn, findsOneWidget);
      await tester.tap(viewAllBtn);
      await tester.pumpAndSettle();

      // Sıralamalarda Utanç Tablosu açılmış olmalı
      expect(find.text('🚨 Utanç Tablosu'), findsOneWidget);
    });

    testWidgets('Sıralamalarda lig buton şeridi (yatay scroll filtresi) tamamen kaldırıldı', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore(backend: MemoryStore(), clock: () => DateTime.utc(2026, 10, 26, 9));
      await store.load();
      store.register(deviceId: 'dev_ui4', name: 'Ali', clanName: 'KTÜ Kanuni');
      AppStore.instance = store;
      Hub.sensors = SensorController(bridge: NoHardwareBridge(), store: store);

      await tester.pumpWidget(const MaterialApp(home: LeaderboardScreen()));
      await tester.pumpAndSettle();

      // Eski üst lig buton şeridi öğeleri aranır; bulunmamalı
      expect(find.byType(ListView), findsOneWidget); // Sadece ana sıralama listesi olmalı, üstte yatay scroll ListView yok
    });
  });
}
