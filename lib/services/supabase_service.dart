import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user.dart';
import '../models/clan.dart';
import 'app_store.dart';
import 'storage.dart';
import 'supabase_config.dart';
import 'supabase_outbox.dart';

enum SupabaseSyncStatus {
  uninitialized,
  connecting,
  connected,
  offline,
  error,
}

/// Supabase istemci çağrılarını soyutlayan gateway arayüzü.
/// Canlı SDK ve birim test mockgateway desteği sağlar.
abstract class SupabaseGateway {
  Future<AuthResponse> signInAnonymously();
  User? get currentUser;
  Session? get currentSession;
  Future<dynamic> rpc(String functionName, {Map<String, dynamic>? params});
  Future<List<Map<String, dynamic>>> queryTableOrView(
    String name, {
    int? limit,
    String? orderBy,
    bool ascending = false,
  });
  RealtimeChannel createChannel(String channelName);
  Future<void> removeChannel(RealtimeChannel channel);
  Future<String?> uploadAvatar({
    required String userId,
    required List<int> fileBytes,
    required String fileExt,
  });
}

/// Canlı Supabase SDK uygulayıcısı.
class LiveSupabaseGateway implements SupabaseGateway {
  final SupabaseClient client;
  LiveSupabaseGateway(this.client);

  @override
  Future<AuthResponse> signInAnonymously() => client.auth.signInAnonymously();

  @override
  User? get currentUser => client.auth.currentUser;

  @override
  Session? get currentSession => client.auth.currentSession;

  @override
  Future<dynamic> rpc(String functionName, {Map<String, dynamic>? params}) {
    return client.rpc(functionName, params: params);
  }

  @override
  Future<List<Map<String, dynamic>>> queryTableOrView(
    String name, {
    int? limit,
    String? orderBy,
    bool ascending = false,
  }) async {
    dynamic query = client.from(name).select();
    if (orderBy != null) {
      query = query.order(orderBy, ascending: ascending);
    }
    if (limit != null) {
      query = query.limit(limit);
    }
    final dynamic res = await query;
    if (res is List) {
      return res.cast<Map<String, dynamic>>();
    }
    return [];
  }

  @override
  RealtimeChannel createChannel(String channelName) => client.channel(channelName);

  @override
  Future<void> removeChannel(RealtimeChannel channel) => client.removeChannel(channel);

  @override
  Future<String?> uploadAvatar({
    required String userId,
    required List<int> fileBytes,
    required String fileExt,
  }) async {
    final fileName = '$userId/avatar_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
    await client.storage.from('avatars').uploadBinary(
          fileName,
          Uint8List.fromList(fileBytes),
          fileOptions: const FileOptions(upsert: true),
        );
    return client.storage.from('avatars').getPublicUrl(fileName);
  }
}

/// Canlı Supabase İstemci Servisi.
/// Anonymous Auth, Session Reuse, First-Sync, Outbox/Retry, Realtime ve Server Source of Truth yönetir.
class SupabaseService extends ChangeNotifier {
  static SupabaseService? _instance;
  static SupabaseService get instance => _instance ??= SupabaseService();
  static set instance(SupabaseService s) => _instance = s;

  SupabaseGateway? _gateway;
  SupabaseOutbox? _outbox;
  RealtimeChannel? _realtimeChannel;

  SupabaseSyncStatus _status = SupabaseSyncStatus.uninitialized;
  String? _lastError;
  bool _isInitialSyncDone = false;
  DateTime? _lastSyncTime;
  bool _isEchoSuppressed = false;

  SupabaseSyncStatus get status => _status;
  String? get lastError => _lastError;
  bool get isInitialSyncDone => _isInitialSyncDone;
  DateTime? get lastSyncTime => _lastSyncTime;
  SupabaseOutbox? get outbox => _outbox;
  SupabaseGateway? get gateway => _gateway;
  bool get isConnected => _status == SupabaseSyncStatus.connected;
  bool get isAvailable => _gateway != null;
  bool get isConfigured => _gateway != null;
  String? get currentUserId => _gateway?.currentUser?.id;

  SupabaseService({SupabaseGateway? gateway, SupabaseOutbox? outbox})
      : _gateway = gateway,
        _outbox = outbox;

  /// Supabase SDK'yı başlatır (canlıda Supabase.initialize çağırır).
  Future<void> initialize({KeyValueStore? storage}) async {
    if (_outbox == null) {
      _outbox = SupabaseOutbox(storage: storage ?? MemoryStore());
      await _outbox!.load();
      _outbox!.addListener(notifyListeners);
    }

    if (_gateway != null) {
      _status = SupabaseSyncStatus.connecting;
      notifyListeners();
      return;
    }

    if (!SupabaseConfig.isConfigured) {
      _status = SupabaseSyncStatus.offline;
      _lastError = 'Supabase URL veya Anon Key yapılandırılmamış.';
      notifyListeners();
      return;
    }

    try {
      _status = SupabaseSyncStatus.connecting;
      notifyListeners();

      await Supabase.initialize(
        url: SupabaseConfig.supabaseUrl,
        publishableKey: SupabaseConfig.supabasePublishableKey,
      );

      _gateway = LiveSupabaseGateway(Supabase.instance.client);
    } catch (e) {
      debugPrint('[SupabaseService] SDK başlatma uyarısı: $e');
      _status = SupabaseSyncStatus.offline;
      _lastError = e.toString();
      notifyListeners();
    }
  }

  /// Oturum kontrolü ve yeniden kullanımı (Session Reuse).
  /// Mevcut geçerli anonim oturum varsa onu korur; gereksiz yeni anon hesap açmaz.
  Future<bool> ensureSession() async {
    final gw = _gateway;
    if (gw == null) {
      _status = SupabaseSyncStatus.offline;
      notifyListeners();
      return false;
    }

    // 1. Zaten oturum açık mı?
    if (gw.currentSession != null && gw.currentUser != null) {
      _status = SupabaseSyncStatus.connected;
      _lastError = null;
      notifyListeners();
      return true;
    }

    // 2. Anonim oturum aç
    try {
      final res = await gw.signInAnonymously();
      if (res.user != null) {
        _status = SupabaseSyncStatus.connected;
        _lastError = null;
        notifyListeners();
        return true;
      }
      _status = SupabaseSyncStatus.error;
      _lastError = 'Anonim oturum oluşturulamadı.';
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('[SupabaseService] Anonim oturum hatası: $e');
      _status = SupabaseSyncStatus.offline;
      _lastError = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// İlk Profil Senkronizasyonu (Legacy First-Sync & Local State Migration).
  /// Cihazdaki eski puan/adım/envanteri kontrollü bir defalık sunucuya aktarır.
  /// Sunucuda kullanıcı önceden varsa sunucu verisi üstün kabul edilir (Tek Gerçek Kaynak).
  Future<bool> syncInitialProfile(AppStore store) async {
    final gw = _gateway;
    if (gw == null || store.me == null) return false;

    final hasSession = await ensureSession();
    if (!hasSession) return false;

    final me = store.me!;
    final clanSqlId = Clan.idToSql(me.clanId);

    try {
      final res = await gw.rpc('rpc_sync_initial_profile', params: {
        'p_device_id': me.deviceId,
        'p_nickname': me.username,
        'p_clan_id': clanSqlId,
        'p_avatar_url': me.equippedAvatar,
        'p_bio': me.bio,
        'p_legacy_steps': me.todaySteps,
        'p_legacy_points': me.weeklyPoints,
        'p_legacy_gold': me.goldCoins,
        'p_legacy_co2': me.preventedCo2Kg,
      });

      if (res is Map && res['ok'] == true) {
        final isNew = res['is_new'] as bool? ?? false;
        final sUser = res['user'] as Map<String, dynamic>?;

        if (sUser != null) {
          final serverUid = sUser['id'] as String;
          if (isNew) {
            // Yeni kullanıcı: sunucu ID'sini eşle
            store.me = store.me!.copyWith(serverUserId: serverUid);
          } else {
            // Zaten kayıtlı kullanıcı: sunucu verisini esas al
            store.me = store.me!.copyWith(
              serverUserId: serverUid,
              username: sUser['nickname'] as String? ?? me.username,
              weeklyPoints: (sUser['weekly_points'] as num?)?.toInt() ?? me.weeklyPoints,
              allTimePoints: (sUser['all_time_points'] as num?)?.toInt() ?? me.allTimePoints,
              goldCoins: (sUser['gold_coins'] as num?)?.toInt() ?? me.goldCoins,
              todaySteps: (sUser['today_steps'] as num?)?.toInt() ?? me.todaySteps,
              bio: sUser['bio'] as String? ?? me.bio,
            );
          }
          store.commitDirect();
        }

        _isInitialSyncDone = true;
        _lastSyncTime = DateTime.now();
        _status = SupabaseSyncStatus.connected;
        _lastError = null;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[SupabaseService] rpc_sync_initial_profile hatası: $e');
      _status = SupabaseSyncStatus.offline;
      _lastError = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Realtime Aboneliklerini Kurar.
  /// Bildirimler, klan puanları, kullanıcılar ve şampiyonlar tablosunu dinler.
  void setupRealtimeSubscriptions(AppStore store) {
    final gw = _gateway;
    if (gw == null) return;

    // Önceki aboneliği temizle (Abonelik sızıntısını önler)
    if (_realtimeChannel != null) {
      gw.removeChannel(_realtimeChannel!);
      _realtimeChannel = null;
    }

    try {
      final ch = gw.createChannel('public_realtime_sync');

      // 1. Canlı Yönetici / Dürtücü Bildirimler
      ch.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'admin_notifications_log',
        callback: (payload) {
          final rec = payload.newRecord;
          final targetUid = rec['target_user_id'] as String?;
          final myUid = store.me?.serverUserId;
          if (targetUid != null && myUid != null && targetUid != myUid) {
            return;
          }
          final title = rec['title'] as String? ?? 'Sunucu Bildirimi';
          final body = rec['message_body'] as String? ?? '';
          store.demoNotify(title, body);
        },
      );

      // 2. Canlı Klan Puan Değişimleri
      ch.onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'clans',
        callback: (payload) {
          final rec = payload.newRecord;
          final clanSqlId = (rec['id'] as num).toInt();
          final dartClanId = Clan.sqlToId(clanSqlId);
          final idx = store.clans.indexWhere((c) => c.id == dartClanId);
          if (idx >= 0) {
            final old = store.clans[idx];
            store.clans[idx] = old.copyWith(
              weeklyPoints: (rec['weekly_points'] as num?)?.toInt() ?? old.weeklyPoints,
              allTimePoints: (rec['all_time_points'] as num?)?.toInt() ?? old.allTimePoints,
              memberCount: (rec['member_count'] as num?)?.toInt() ?? old.memberCount,
            );
            store.commitDirect();
          }
        },
      );

      // 3. Canlı Kullanıcı Puanları
      ch.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'users',
        callback: (payload) {
          final rec = payload.newRecord;
          final uid = rec['id'] as String?;
          if (uid == null) return;

          // Remote echo engeli: kendi oturumumuzun olayıysa yerel observer döngüsü başlatma
          if (uid == store.me?.serverUserId) {
            _isEchoSuppressed = true;
            try {
              store.me = store.me!.copyWith(
                weeklyPoints: (rec['weekly_points'] as num?)?.toInt() ?? store.me!.weeklyPoints,
                goldCoins: (rec['gold_coins'] as num?)?.toInt() ?? store.me!.goldCoins,
                todaySteps: (rec['today_steps'] as num?)?.toInt() ?? store.me!.todaySteps,
              );
              store.commitDirect();
            } finally {
              _isEchoSuppressed = false;
            }
          } else {
            // Canlı diğer kullanıcı güncellemeleri (hibiscus vb.)
            final idx = store.serverUsers.indexWhere((u) => (u.serverUserId ?? u.id) == uid);
            if (idx >= 0) {
              final old = store.serverUsers[idx];
              store.serverUsers[idx] = old.copyWith(
                weeklyPoints: (rec['weekly_points'] as num?)?.toInt() ?? old.weeklyPoints,
                allTimePoints: (rec['all_time_points'] as num?)?.toInt() ?? old.allTimePoints,
                todaySteps: (rec['today_steps'] as num?)?.toInt() ?? old.todaySteps,
                username: rec['nickname'] as String? ?? old.username,
                equippedAvatar: rec['avatar_url'] as String? ?? old.equippedAvatar,
                equippedPet: rec['pet_slug'] as String? ?? old.equippedPet,
                equippedFrame: rec['frame_slug'] as String? ?? old.equippedFrame,
              );
            } else {
              final rawClan = (rec['clan_id'] as num?)?.toInt();
              store.serverUsers.add(AppUser(
                id: uid,
                deviceId: 'SRV-$uid',
                serverUserId: uid,
                username: rec['nickname'] as String? ?? 'Gezgin',
                clanId: rawClan != null ? Clan.sqlToId(rawClan) : '',
                clanName: '',
                isDemo: false,
                todaySteps: (rec['today_steps'] as num?)?.toInt() ?? 0,
                weeklyPoints: (rec['weekly_points'] as num?)?.toInt() ?? 0,
                allTimePoints: (rec['all_time_points'] as num?)?.toInt() ?? 0,
                streakDays: (rec['streak_days'] as num?)?.toInt() ?? 0,
                equippedAvatar: rec['avatar_url'] as String? ?? 'default_avatar',
                equippedFrame: rec['frame_slug'] as String? ?? 'none',
                equippedPet: rec['pet_slug'] as String? ?? 'none',
                clanRole: rec['clan_role'] as String? ?? 'member',
              ));
            }
            store.commitDirect();
          }
        },
      );

      // 4. Canlı Şampiyon Değişimi
      ch.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'weekly_champions',
        callback: (payload) {
          final rec = payload.newRecord;
          final uPoints = (rec['champion_user_points'] as num?)?.toInt() ?? 0;
          final cPoints = (rec['champion_clan_points'] as num?)?.toInt() ?? 0;
          if (rec['week_label'] != null) {
            store.championUser = 'Bireysel Şampiyon ($uPoints P)';
            store.championClan = 'Klan Şampiyonu ($cPoints P)';
            store.commitDirect();
          }
        },
      );

      ch.subscribe();
      _realtimeChannel = ch;
    } catch (e) {
      debugPrint('[SupabaseService] Realtime bağlantı uyarısı: $e');
    }
  }

  /// Sunucudan Canlı Liderlik Verisini Çeker (Görünümler Üzerinden).
  Future<bool> fetchServerLeaderboard(AppStore store) async {
    final gw = _gateway;
    if (gw == null) return false;

    try {
      final userRows = await gw.queryTableOrView(
        'v_leaderboard_users',
        limit: 50,
        orderBy: 'weekly_points',
        ascending: false,
      );

      if (userRows.isNotEmpty) {
        final serverUsers = <AppUser>[];
        for (final row in userRows) {
          final uid = row['user_id'] as String;
          final isMe = uid == store.me?.serverUserId;
          if (!isMe) {
            final rawClan = (row['clan_id'] as num?)?.toInt();
            serverUsers.add(AppUser(
              id: uid,
              deviceId: 'SRV-$uid',
              serverUserId: uid,
              username: row['nickname'] as String? ?? 'Gezgin',
              clanId: rawClan != null ? Clan.sqlToId(rawClan) : '',
              clanName: row['clan_name'] as String? ?? '',
              isDemo: row['is_demo'] as bool? ?? false,
              todaySteps: (row['today_steps'] as num?)?.toInt() ?? 0,
              weeklyPoints: (row['weekly_points'] as num?)?.toInt() ?? 0,
              allTimePoints: (row['all_time_points'] as num?)?.toInt() ?? 0,
              preventedCo2Kg: (row['weekly_saved_co2_kg'] as num?)?.toDouble() ?? 0.0,
              streakDays: (row['streak_days'] as num?)?.toInt() ?? 0,
              equippedAvatar: row['avatar_url'] as String? ?? 'default_avatar',
              equippedFrame: row['frame_slug'] as String? ?? 'none',
              equippedPet: row['pet_slug'] as String? ?? 'none',
              clanRole: row['clan_role'] as String? ?? 'member',
            ));
          }
        }
        store.serverUsers = serverUsers;
        store.commitDirect();
      }

      final clanRows = await gw.queryTableOrView(
        'v_clan_leaderboard',
        limit: 20,
        orderBy: 'weekly_points',
        ascending: false,
      );

      if (clanRows.isNotEmpty) {
        for (final row in clanRows) {
          final sqlId = (row['clan_id'] as num).toInt();
          final dartId = Clan.sqlToId(sqlId);
          final idx = store.clans.indexWhere((c) => c.id == dartId);
          if (idx >= 0) {
            store.clans[idx] = store.clans[idx].copyWith(
              weeklyPoints: (row['weekly_points'] as num?)?.toInt() ?? store.clans[idx].weeklyPoints,
              allTimePoints: (row['all_time_points'] as num?)?.toInt() ?? store.clans[idx].allTimePoints,
              memberCount: (row['member_count'] as num?)?.toInt() ?? store.clans[idx].memberCount,
            );
          }
        }
        store.commitDirect();
      }

      _lastSyncTime = DateTime.now();
      _status = SupabaseSyncStatus.connected;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[SupabaseService] Liderlik çekme uyarısı: $e');
      _status = SupabaseSyncStatus.offline;
      _lastError = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void>? _outboxFuture;

  /// Çevrimdışı Kuyruğu (Outbox) Sunucuya İletir.
  Future<void> processOutbox(AppStore store) {
    if (_outboxFuture != null) return _outboxFuture!;
    return _outboxFuture = _doProcessOutbox(store).whenComplete(() {
      _outboxFuture = null;
    });
  }

  Future<void> _doProcessOutbox(AppStore store) async {
    final ob = _outbox;
    final gw = _gateway;
    if (ob == null || gw == null) return;

    final pending = ob.pendingItems;
    if (pending.isEmpty) return;

    try {
      final hasSession = await ensureSession();
      if (!hasSession) return;

      for (final item in pending) {
        try {
          bool itemDone = false;
          switch (item.actionType) {
            case 'record_steps':
              final res = await gw.rpc('rpc_record_steps', params: item.payload);
              itemDone = (res is Map && (res['ok'] == true || res['duplicate'] == true));
              break;

            case 'record_transit':
              final res = await gw.rpc('rpc_record_transit', params: item.payload);
              itemDone = (res is Map && (res['ok'] == true || res['duplicate'] == true));
              break;

            case 'record_bike':
              final res = await gw.rpc('rpc_record_bike', params: item.payload);
              itemDone = (res is Map && (res['ok'] == true || res['duplicate'] == true || res['rejected'] == true));
              break;

            case 'record_vehicle_penalty':
              final res = await gw.rpc('rpc_record_vehicle_penalty', params: item.payload);
              itemDone = (res is Map && (res['ok'] == true || res['duplicate'] == true));
              break;

            case 'record_bus_trip':
              final res = await gw.rpc('rpc_record_bus_trip', params: item.payload);
              itemDone = (res is Map && (res['ok'] == true || res['duplicate'] == true || res['dormant'] == true));
              break;

            case 'send_shame_message':
              final res = await gw.rpc('rpc_send_shame_message', params: item.payload);
              itemDone = (res is Map && (res['ok'] == true || res['duplicate'] == true));
              break;

            case 'buy_shop_item':
              final res = await gw.rpc('rpc_buy_shop_item', params: item.payload);
              itemDone = (res is Map && res['ok'] == true);
              break;

            case 'equip_shop_item':
              final res = await gw.rpc('rpc_equip_shop_item', params: item.payload);
              itemDone = (res is Map && res['ok'] == true);
              break;

            case 'join_clan':
              final res = await gw.rpc('rpc_join_clan', params: item.payload);
              itemDone = (res is Map && res['ok'] == true);
              break;

            case 'update_bio':
              final nick = store.me?.username ?? 'Kullanıcı';
              final bio = (item.payload['bio'] as String?) ?? '';
              final res = await gw.rpc('rpc_update_profile', params: {
                'p_nickname': nick,
                'p_bio': bio,
              });
              itemDone = (res is Map && (res['ok'] == true || res['duplicate'] == true));
              break;

            default:
              itemDone = true;
              break;
          }

          if (itemDone) {
            await ob.markCompleted(item.id);
          } else {
            await ob.markFailed(item.id, 'Sunucu işlemi reddetti', forceQuarantine: false);
          }
        } catch (e) {
          final errStr = e.toString();
          debugPrint('[SupabaseService] Outbox işlem hatası (${item.actionType}): $errStr');
          final isPerm = SupabaseOutbox.isPermanentError(errStr);
          await ob.markFailed(item.id, errStr, forceQuarantine: isPerm);
          if (!isPerm) {
            // Yalnızca geçici ağ hatalarında kuyruğu durdur
            break;
          }
          // Zehirli paket karantinaya alındı; kuyruktaki diğer geçerli olaylara devam et
        }
      }
    } finally {
      notifyListeners();
    }
  }

  // ---------- Olay Kuyruklama API (Semantic Action Wrappers) ----------

  Future<void> recordSteps({
    required int stepCount,
    required double distanceKm,
    required int pointsEarned,
    required double co2SavedKg,
    String? eventId,
  }) async {
    if (_isEchoSuppressed) return;
    await _outbox?.enqueue(
      actionType: 'record_steps',
      eventId: eventId,
      payload: {
        'p_event_id': eventId ?? 'step_${DateTime.now().microsecondsSinceEpoch}',
        'p_step_count': stepCount,
        'p_distance_km': distanceKm,
        'p_points_earned': pointsEarned,
        'p_co2_saved_kg': co2SavedKg,
      },
    );
    unawaited(_triggerOutboxFlush());
  }

  Future<void> recordTransit({
    required String stopCode,
    required String verificationMethod,
    required int pointsEarned,
    required double co2SavedKg,
    String? eventId,
  }) async {
    if (_isEchoSuppressed) return;
    await _outbox?.enqueue(
      actionType: 'record_transit',
      eventId: eventId,
      payload: {
        'p_event_id': eventId ?? 'transit_${DateTime.now().microsecondsSinceEpoch}',
        'p_stop_code': stopCode,
        'p_verification_method': verificationMethod,
      },
    );
    unawaited(_triggerOutboxFlush());
  }

  Future<void> recordBike({
    required String tripId,
    required double distanceKm,
    required double avgSpeedKmh,
    required double maxSpeedKmh,
    required double accelVariance,
    required int pointsEarned,
    required double co2SavedKg,
    required bool isSpoof,
    String? rejectReason,
  }) async {
    if (_isEchoSuppressed) return;
    await _outbox?.enqueue(
      actionType: 'record_bike',
      eventId: tripId,
      payload: {
        'p_event_id': tripId,
        'p_distance_km': distanceKm,
        'p_avg_speed_kmh': avgSpeedKmh,
        'p_max_speed_kmh': maxSpeedKmh,
        'p_accel_variance': accelVariance,
        'p_points_earned': pointsEarned,
        'p_co2_saved_kg': co2SavedKg,
        'p_is_spoof': isSpoof,
        'p_reject_reason': rejectReason,
      },
    );
    unawaited(_triggerOutboxFlush());
  }

  Future<void> recordVehiclePenalty({
    required String tripId,
    required double distanceKm,
    required double wastedCo2Kg,
    required double avgSpeedKmh,
  }) async {
    if (_isEchoSuppressed) return;
    await _outbox?.enqueue(
      actionType: 'record_vehicle_penalty',
      eventId: tripId,
      payload: {
        'p_event_id': tripId,
        'p_distance_km': distanceKm,
        'p_wasted_co2_kg': wastedCo2Kg,
        'p_avg_speed_kmh': avgSpeedKmh,
      },
    );
    unawaited(_triggerOutboxFlush());
  }

  Future<void> buyShopItem(String itemSlug) async {
    await _outbox?.enqueue(
      actionType: 'buy_shop_item',
      payload: {'p_item_slug': itemSlug},
    );
    unawaited(_triggerOutboxFlush());
  }

  Future<void> equipShopItem(String itemSlug) async {
    await _outbox?.enqueue(
      actionType: 'equip_shop_item',
      payload: {'p_item_slug': itemSlug},
    );
    unawaited(_triggerOutboxFlush());
  }

  Future<void> joinClan(int clanId) async {
    await _outbox?.enqueue(
      actionType: 'join_clan',
      payload: {'p_clan_id': clanId},
    );
    unawaited(_triggerOutboxFlush());
  }

  Future<void> updateBio(String bio) async {
    await _outbox?.enqueue(
      actionType: 'update_bio',
      payload: {'bio': bio},
    );
    unawaited(_triggerOutboxFlush());
  }

  Future<String?> uploadProfilePhoto(String localPath) async {
    final gw = _gateway;
    final uid = currentUserId;
    if (gw == null || uid == null) return null;

    try {
      final file = File(localPath);
      if (!file.existsSync()) return null;
      final bytes = await file.readAsBytes();
      final ext = localPath.split('.').lastOrNull ?? 'jpg';
      return await gw.uploadAvatar(userId: uid, fileBytes: bytes, fileExt: ext);
    } catch (e) {
      debugPrint('[SupabaseService] Storage yükleme uyarısı (Backend Storage hazırlanıyor): $e');
      return null;
    }
  }

  Future<void> _triggerOutboxFlush() async {
    if (AppStore.instance.loaded) {
      await processOutbox(AppStore.instance);
    }
  }

  Future<void> recordBusTrip({
    required String eventId,
    required double distanceKm,
    required int busScore,
    required bool isShortPenalty,
    String? explanation,
  }) async {
    if (_isEchoSuppressed) return;
    await _outbox?.enqueue(
      actionType: 'record_bus_trip',
      eventId: eventId,
      payload: {
        'p_event_id': eventId,
        'p_distance_km': distanceKm,
        'p_bus_score': busScore,
        'p_is_short_penalty': isShortPenalty,
        'p_explanation': explanation,
      },
    );
    unawaited(_triggerOutboxFlush());
  }

  Future<Map<String, dynamic>> sendShameMessage({
    required String targetUserId,
    required String message,
  }) async {
    final gw = _gateway;
    final idempotencyKey = 'shame_${DateTime.now().microsecondsSinceEpoch}';
    if (gw == null) {
      return {'ok': true, 'message': 'Yerel oturumda utanç mesajı kaydedildi.'};
    }
    try {
      final res = await gw.rpc('rpc_send_shame_message', params: {
        'p_target_id': targetUserId,
        'p_message': message,
        'p_idempotency_key': idempotencyKey,
      });
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
      return {'ok': true, 'message': 'Mesaj iletildi.'};
    } catch (e) {
      debugPrint('[SupabaseService] sendShameMessage hatası: $e');
      return {'ok': false, 'message': e.toString()};
    }
  }

  /// Uygulama arka plandan ön plana döndüğünde çağrılır (Lifecycle Resume).
  Future<void> onAppResume(AppStore store) async {
    final ok = await ensureSession();
    if (ok) {
      if (_realtimeChannel == null) {
        setupRealtimeSubscriptions(store);
      }
      await fetchServerLeaderboard(store);
      await processOutbox(store);
    }
  }

  /// Arka planda tam senkronizasyon döngüsü başlatır.
  Future<void> startSync(AppStore store) async {
    final ok = await ensureSession();
    if (ok) {
      await syncInitialProfile(store);
      setupRealtimeSubscriptions(store);
      await fetchServerLeaderboard(store);
      await processOutbox(store);
    }
  }
}
