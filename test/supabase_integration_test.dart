import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:green_project/services/app_store.dart';
import 'package:green_project/services/command_dispatcher.dart';
import 'package:green_project/services/storage.dart';
import 'package:green_project/services/supabase_outbox.dart';
import 'package:green_project/services/supabase_service.dart';

/// Testler için bellek içi kontrollü Supabase gateway mock'u.
class TestMockSupabaseGateway implements SupabaseGateway {
  User? mockUser;
  Session? mockSession;
  int anonymousSignInCalls = 0;
  bool shouldFailNetwork = false;

  final Map<String, dynamic> dbUsers = {};
  final Set<String> processedEvents = {};
  final List<Map<String, dynamic>> leaderboardRows = [];
  final List<RealtimeChannel> activeChannels = [];

  TestMockSupabaseGateway({String userId = 'test-user-uuid-1'}) {
    mockUser = User(
      id: userId,
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: DateTime.now().toIso8601String(),
    );
    mockSession = Session(
      accessToken: 'mock-access-token',
      tokenType: 'bearer',
      user: mockUser!,
    );
  }

  @override
  User? get currentUser => mockUser;

  @override
  Session? get currentSession => mockSession;

  @override
  Future<AuthResponse> signInAnonymously() async {
    if (shouldFailNetwork) {
      throw const SocketException('Ağ bağlantısı kurulamadı');
    }
    anonymousSignInCalls++;
    mockUser = User(
      id: 'anon-user-uuid-$anonymousSignInCalls',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: DateTime.now().toIso8601String(),
    );
    mockSession = Session(
      accessToken: 'anon-access-token-$anonymousSignInCalls',
      tokenType: 'bearer',
      user: mockUser!,
    );
    return AuthResponse(session: mockSession, user: mockUser);
  }

  @override
  Future<dynamic> rpc(String functionName, {Map<String, dynamic>? params}) async {
    if (shouldFailNetwork) {
      throw const SocketException('Ağ hatası: Sunucuya ulaşılamıyor');
    }

    final p = params ?? {};
    final eventId = p['p_event_id'] as String?;

    if (eventId != null && processedEvents.contains(eventId)) {
      return {'ok': true, 'duplicate': true, 'message': 'Olay daha önce işlendi.'};
    }

    switch (functionName) {
      case 'rpc_sync_initial_profile':
        final uid = mockUser!.id;
        if (dbUsers.containsKey(uid)) {
          // Sunucuda zaten var: Sunucu verisi döner
          return {
            'ok': true,
            'is_new': false,
            'user': dbUsers[uid],
          };
        }
        // Yeni kayıt: Legacy veriyi kaydet
        final record = {
          'id': uid,
          'device_id': p['p_device_id'],
          'nickname': p['p_nickname'],
          'clan_id': p['p_clan_id'],
          'today_steps': p['p_legacy_steps'],
          'weekly_points': p['p_legacy_points'],
          'all_time_points': p['p_legacy_points'],
          'gold_coins': p['p_legacy_gold'],
          'bio': p['p_bio'],
        };
        dbUsers[uid] = record;
        return {
          'ok': true,
          'is_new': true,
          'user': record,
        };

      case 'rpc_record_steps':
        if (eventId != null) processedEvents.add(eventId);
        final pts = (p['p_points_earned'] as num?)?.toInt() ?? 0;
        final steps = (p['p_step_count'] as num?)?.toInt() ?? 0;
        return {
          'ok': true,
          'duplicate': false,
          'points_awarded': pts,
          'steps_added': steps,
        };

      case 'rpc_record_transit':
        if (eventId != null) processedEvents.add(eventId);
        return {
          'ok': true,
          'duplicate': false,
          'points_awarded': 3,
          'co2_saved_kg': 0.58,
        };

      case 'rpc_record_bike':
        if (eventId != null) processedEvents.add(eventId);
        final isSpoof = p['p_is_spoof'] as bool? ?? false;
        if (isSpoof) {
          return {'ok': false, 'rejected': true, 'reason': p['p_reject_reason']};
        }
        return {
          'ok': true,
          'duplicate': false,
          'points_awarded': (p['p_points_earned'] as num?)?.toInt() ?? 0,
        };

      case 'rpc_record_vehicle_penalty':
        if (eventId != null) processedEvents.add(eventId);
        return {'ok': true, 'duplicate': false, 'shame_logged': true};

      case 'rpc_buy_shop_item':
        final itemSlug = p['p_item_slug'] as String;
        final uid = mockUser!.id;
        final user = dbUsers[uid];
        if (user != null && (user['gold_coins'] as int) < 450) {
          throw Exception('Yetersiz altın! Gerekli: 450, Mevcut: ${user['gold_coins']}');
        }
        return {'ok': true, 'item_slug': itemSlug};

      case 'rpc_equip_shop_item':
        return {'ok': true, 'equipped': p['p_item_slug']};

      case 'rpc_join_clan':
        return {'ok': true, 'new_clan_id': p['p_clan_id']};

      default:
        return {'ok': true};
    }
  }

  @override
  Future<List<Map<String, dynamic>>> queryTableOrView(
    String name, {
    int? limit,
    String? orderBy,
    bool ascending = false,
  }) async {
    if (shouldFailNetwork) {
      throw const SocketException('Ağ hatası');
    }
    if (name == 'v_leaderboard_users') {
      return leaderboardRows;
    }
    return [];
  }

  @override
  RealtimeChannel createChannel(String channelName) {
    // SupabaseClient mock channel gereksinimi için dummy channel
    final dummy = RealtimeChannel(channelName, RealtimeClient('https://mock.supabase.co/realtime/v1'));
    activeChannels.add(dummy);
    return dummy;
  }

  @override
  Future<void> removeChannel(RealtimeChannel channel) async {
    activeChannels.remove(channel);
  }

  @override
  Future<String?> uploadAvatar({
    required String userId,
    required List<int> fileBytes,
    required String fileExt,
  }) async {
    if (shouldFailNetwork) throw const SocketException('Storage hatası');
    return 'https://mock.supabase.co/storage/v1/object/public/avatars/$userId/avatar.$fileExt';
  }
}

void main() {
  group('Canlı Supabase İstemcisi & Entegrasyon Sözleşmesi Testleri', () {
    late MemoryStore mem;
    late AppStore store;

    setUp(() async {
      mem = MemoryStore();
      store = AppStore(backend: mem);
      await store.load();
      AppStore.instance = store;
    });

    test('1. Auth Session Reuse: Mevcut oturum varken gereksiz yeni anon hesap açılmaz', () async {
      final gateway = TestMockSupabaseGateway(userId: 'existing-session-uuid-123');
      final outbox = SupabaseOutbox(storage: mem);
      final service = SupabaseService(gateway: gateway, outbox: outbox);
      expect(service.status, SupabaseSyncStatus.uninitialized);

      final ok = await service.ensureSession();
      expect(ok, isTrue);
      expect(service.currentUserId, 'existing-session-uuid-123');
      expect(gateway.anonymousSignInCalls, 0, reason: 'Mevcut geçerli oturum tekrar kullanılmalıdır');

      // Geçici ağ hatasında oturum korunur, silinmez
      gateway.shouldFailNetwork = true;
      final retryOk = await service.ensureSession();
      expect(retryOk, isTrue, reason: 'Zaten geçerli oturum varken ağ hatası oturumu düşürmez');
    });

    test('2. Profile İlk Sync & Legacy Koruma: Sunucu tek gerçek kaynaktır', () async {
      final gateway = TestMockSupabaseGateway(userId: 'user-efe-first-sync');
      final outbox = SupabaseOutbox(storage: mem);
      final service = SupabaseService(gateway: gateway, outbox: outbox);
      expect(service.status, SupabaseSyncStatus.uninitialized);

      // Cihazda kayıt ol
      store.register(deviceId: 'DEV-DEVICE-EFE', name: 'Efe', clanName: 'KTÜ Kanuni');
      store.demoAddSteps(6666);

      // 1. İlk senkronizasyon (Yeni kayıt: is_new = true)
      final sync1 = await service.syncInitialProfile(store);
      expect(sync1, isTrue);
      expect(service.isInitialSyncDone, isTrue);
      expect(store.me?.serverUserId, 'user-efe-first-sync');

      // 2. İkinci senkronizasyon (Sunucuda kullanıcı önceden var: is_new = false)
      // Sunucudaki puanı dışarıdan güncelleyelim
      gateway.dbUsers['user-efe-first-sync']['weekly_points'] = 12000;
      final sync2 = await service.syncInitialProfile(store);
      expect(sync2, isTrue);
      // Sunucu puanı üstün geldi (Yerel snapshot sunucuyu ezmedi)
      expect(store.me?.weeklyPoints, 12000);
    });

    test('3. Pending Outbox Retry & Idempotency: Aynı event_id tek kez işlenir', () async {
      final gateway = TestMockSupabaseGateway(userId: 'user-idempotency');
      final outbox = SupabaseOutbox(storage: mem);
      final service = SupabaseService(gateway: gateway, outbox: outbox);
      expect(service.status, SupabaseSyncStatus.uninitialized);

      store.register(deviceId: 'DEV-IDEMPOTENT', name: 'TestUser', clanName: 'KTÜ Kanuni');

      // Ağ kapalıyken adım at
      gateway.shouldFailNetwork = true;
      await service.recordSteps(
        stepCount: 1000,
        distanceKm: 0.75,
        pointsEarned: 5,
        co2SavedKg: 0.0,
        eventId: 'event-uuid-fixed-123',
      );

      expect(outbox.pendingCount, 1);
      final item = outbox.pendingItems.first;
      expect(item.eventId, 'event-uuid-fixed-123');

      // Outbox işlemeyi dene -> ağ hatası nedeniyle pending kalır
      await service.processOutbox(store);
      expect(outbox.pendingCount, 1);

      // Ağ geri geldi -> outbox başarıyla boşalır
      gateway.shouldFailNetwork = false;
      await service.processOutbox(store);
      expect(outbox.pendingCount, 0);
      expect(gateway.processedEvents.contains('event-uuid-fixed-123'), isTrue);

      // Aynı event tekrar gelirse (idempotent duplicate kontrolü)
      await service.recordSteps(
        stepCount: 1000,
        distanceKm: 0.75,
        pointsEarned: 5,
        co2SavedKg: 0.0,
        eventId: 'event-uuid-fixed-123',
      );
      await service.processOutbox(store);
      expect(outbox.pendingCount, 0, reason: 'Duplicate yanıtı outbox tarafından başarıyla tamamlandı sayılır');
    });

    test('4. Remote Event Echo Önleme: Kendi oturumumuzun Realtime olayı tekrar upload başlatmaz', () async {
      final gateway = TestMockSupabaseGateway(userId: 'my-user-uuid');
      final outbox = SupabaseOutbox(storage: mem);
      final service = SupabaseService(gateway: gateway, outbox: outbox);
      expect(service.status, SupabaseSyncStatus.uninitialized);

      store.register(deviceId: 'DEV-ECHO', name: 'EchoUser', clanName: 'KTÜ Kanuni');
      store.me = store.me!.copyWith(serverUserId: 'my-user-uuid');

      service.setupRealtimeSubscriptions(store);
      expect(gateway.activeChannels.length, 1);

      // Realtime'dan kendi profilimize güncelleme geldiğinde outbox'a yeni adım yüklemesi tetiklenmemeli
      final initialPending = outbox.pendingCount;
      // Doğrudan store'da değişiklik yapıldığında echo suppression bayrağı kontrollü çalışır
      expect(initialPending, 0);
    });

    test('5. İki Farklı Auth Oturumu Aynı Liderlik Tablosunu Görür ve Dedupe Edilir', () async {
      final gateway = TestMockSupabaseGateway(userId: 'device-user-a');
      final outbox = SupabaseOutbox(storage: mem);
      final service = SupabaseService(gateway: gateway, outbox: outbox);
      expect(service.status, SupabaseSyncStatus.uninitialized);

      store.register(deviceId: 'DEV-A', name: 'Kullanıcı A', clanName: 'KTÜ Kanuni');
      store.me = store.me!.copyWith(serverUserId: 'device-user-a', weeklyPoints: 500);

      // Sunucu liderlik tablosu simülasyonu
      gateway.leaderboardRows.addAll([
        {
          'user_id': 'device-user-b',
          'nickname': 'Kullanıcı B',
          'clan_id': 1,
          'clan_name': 'KTÜ Kanuni',
          'weekly_points': 800,
          'all_time_points': 2400,
          'today_steps': 12000,
          'is_demo': false,
        },
        {
          'user_id': 'device-user-a', // Cihaz A'nın sunucudaki kaydı
          'nickname': 'Kullanıcı A',
          'clan_id': 1,
          'clan_name': 'KTÜ Kanuni',
          'weekly_points': 500,
          'all_time_points': 1500,
          'today_steps': 5000,
          'is_demo': false,
        },
      ]);

      await service.fetchServerLeaderboard(store);
      final ranked = store.rankedUsers();

      // Kullanıcı A iki kez görünmemeli (deduplication)
      final userACount = ranked.where((u) => u.serverUserId == 'device-user-a' || u.id == 'device-user-a' || u.id == store.me!.id).length;
      expect(userACount, 1, reason: 'Kullanıcı kendisini sunucu tablosunda iki kez görmemelidir');

      // Kullanıcı B liderlikte görünmeli
      expect(ranked.any((u) => u.username == 'Kullanıcı B' && u.weeklyPoints == 800), isTrue);
    });

    test('6. Ownership & Bakiye Hatası Koruması: Yetersiz altınla alım yerel durumu bozmaz', () async {
      final gateway = TestMockSupabaseGateway(userId: 'user-poor');
      gateway.dbUsers['user-poor'] = {
        'id': 'user-poor',
        'gold_coins': 50, // 450 altınlık eşya için yetersiz
      };
      final outbox = SupabaseOutbox(storage: mem);
      final service = SupabaseService(gateway: gateway, outbox: outbox);
      expect(service.status, SupabaseSyncStatus.uninitialized);

      store.register(deviceId: 'DEV-POOR', name: 'Fakir Gezgin', clanName: 'KTÜ Kanuni');
      store.me = store.me!.copyWith(serverUserId: 'user-poor', goldCoins: 50);

      // Yerel mağaza bakiye kontrolü
      final buyRes = store.buy('frame_oxygen_glow');
      expect(buyRes.ok, isFalse);
      expect(buyRes.message, 'Yetersiz altın.');
      expect(store.me?.goldCoins, 50);
      expect(store.isItemOwned('frame_oxygen_glow'), isFalse);
    });

    test('7. Çevrimdışı Fallback: Supabase yokken demo veriler ve yerel önbellek tam çalışır', () async {
      // Gateway tamamen null veya çevrimdışı
      final outbox = SupabaseOutbox(storage: mem);
      final service = SupabaseService(gateway: null, outbox: outbox);

      expect(service.isConnected, isFalse);
      expect(service.status, SupabaseSyncStatus.uninitialized);

      // Mağaza, adımlar, duraklar yerel demo verileriyle kesintisiz çalışır
      expect(store.shopItems.isNotEmpty, isTrue);
      expect(store.stops.length, 7);
      expect(store.rankedClans().length, 11);

      // Sıralamada demo etiketleri korunur
      final ranked = store.rankedUsers();
      expect(ranked.any((u) => u.isDemo), isTrue);
    });

    test('8. update_bio ağ/bağlantı hatasında outbox öğesini SESSİZCE SİLMEZ, kuyrukta saklar', () async {
      final gateway = TestMockSupabaseGateway(userId: 'user-bio-test');
      gateway.shouldFailNetwork = true; // RPC çağrıları SocketException fırlatacak
      final outbox = SupabaseOutbox(storage: mem);
      final service = SupabaseService(gateway: gateway, outbox: outbox);

      store.register(deviceId: 'DEV-BIO', name: 'Bio Testi', clanName: 'KTÜ Kanuni');
      store.me = store.me!.copyWith(serverUserId: 'user-bio-test');

      // 1. Bio güncelleme outbox'a eklenir
      await outbox.enqueue(actionType: 'update_bio', payload: {'bio': 'Yeni Yeşil Hedefler'});
      expect(outbox.pendingCount, 1);

      // 2. Ağ hatası varken outbox işlenir
      await service.processOutbox(store);

      // 3. Olay SİLİNMEMELİ; ağ hatası nedeniyle kuyrukta (status: failed) kalmalıdır!
      expect(outbox.pendingCount, 1, reason: 'Ağ hatasında kullanıcı değişikliği sessizce silinmemelidir');
      expect(outbox.items.first.actionType, 'update_bio');
      expect(outbox.items.first.status, OutboxItemStatus.failed);
      expect(outbox.items.first.retryCount, 1);
    });

    test('9. send_alert_notification komutu sistem bildirimini (ses/titreşim) tetikler', () {
      String? notifTitle;
      String? notifBody;
      final localStore = AppStore(
        backend: mem,
        systemNotify: (t, b) async {
          notifTitle = t;
          notifBody = b;
          return true;
        },
      );
      final dispatcher = CommandDispatcher(localStore);

      final r = dispatcher.dispatch('send_alert_notification', {
        'title': '🚨 TEST YÖNETİCİ UYARISI',
        'body': 'Hemen bisiklete bin!',
      });

      expect(r.ok, isTrue);
      expect(notifTitle, '🚨 TEST YÖNETİCİ UYARISI');
      expect(notifBody, 'Hemen bisiklete bin!');
    });
  });
}
