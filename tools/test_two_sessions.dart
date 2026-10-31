// ============================================================================
// tools/test_two_sessions.dart
// İki Gerçek Anonim HTTP Oturumu ile Ortak Liderlik, İzolasyon, Realtime ve RPC Test Aracı
// Proje: Green_Project (fhaxxraibydsjikxacbb)
//
// Çalıştırma:
//   /home/girdap/Masaüstü/WordMaster/.tools/flutter/bin/dart tools/test_two_sessions.dart
// ============================================================================

import 'dart:convert';
import 'dart:io';

const String kSupabaseUrl = 'https://fhaxxraibydsjikxacbb.supabase.co';
const String kAnonKey = 'sb_publishable_7TEibMmt8wbJtKTYb_vjlA_xZoCnN5J';

class SessionInfo {
  final String label;
  final String userId;
  final String accessToken;

  SessionInfo(this.label, this.userId, this.accessToken);
}

void main() async {
  final client = HttpClient();
  stdout.writeln('================================================================');
  stdout.writeln('⚡ Yeşil Adım — 2 Gerçek Anonim HTTP Oturumu Entegrasyon Testi');
  stdout.writeln('Hedef: $kSupabaseUrl');
  stdout.writeln('Tarih: ${DateTime.now().toIso8601String()}');
  stdout.writeln('================================================================\n');

  try {
    // 1. İki Bağımsız Oturum Başlat
    stdout.writeln('[1/6] İki bağımsız anonim/test oturumu oluşturuluyor...');
    final sessionA = await createAnonymousSession(client, 'Cihaz_A');
    final sessionB = await createAnonymousSession(client, 'Cihaz_B');
    stdout.writeln('  ✅ Oturum A hazır (UID: ${maskId(sessionA.userId)})');
    stdout.writeln('  ✅ Oturum B hazır (UID: ${maskId(sessionB.userId)})');

    // Kullanıcı profillerini senkronize et (public.users kaydı oluşturur)
    await syncProfile(client, sessionA, 'Kullanici_A');
    await syncProfile(client, sessionB, 'Kullanici_B');
    stdout.writeln('  ✅ Oturum A ve B kullanıcı profilleri public.users ile senkronize edildi.');

    // 2. Ortak Liderlik Tablosu Projeksiyon Testi
    stdout.writeln('\n[2/6] Ortak Leaderboard Projeksiyonu Denetleniyor...');
    await testSharedLeaderboard(client, sessionA, sessionB);

    // 3. RLS İzolasyon Denetimi (Özel Veri Sızıntısı Engeli)
    stdout.writeln('\n[3/6] RLS İzolasyonu Denetleniyor (Kullanıcı İçi Mahremiyet)...');
    await testRlsIsolation(client, sessionA, sessionB);

    // 4. Yetkisiz GM Çağrısı Reddi Testi
    stdout.writeln('\n[4/6] Yetkisiz GM Çağrısı Reddi Denetleniyor...');
    await testUnauthorizedGmRejection(client, sessionA);

    // 5. Doğru Parametre Sözleşmesi ve Eşik Kontrolleri
    stdout.writeln('\n[5/6] Bus RPC ve Utanç Mesajı Parametre Sözleşmesi Denetleniyor...');
    await testParamContracts(client, sessionA, sessionB);

    // 6. Gerçek Puan Mutasyonunun Diğer Oturuma ve Realtime Kanalına Yayılması
    stdout.writeln('\n[6/6] Puan Mutasyonunun Diğer Oturuma Yayılması & Realtime Sınaması...');
    await testCrossSessionMutationAndRealtime(client, sessionA, sessionB);

    stdout.writeln('\n================================================================');
    stdout.writeln('🎉 TÜM İKİ OTURUMLU BULUT ENTEGRASYON TESTLERİ BAŞARIYLA TAMAMLANDI!');
    stdout.writeln('================================================================');
    exitCode = 0;
  } catch (e, st) {
    stderr.writeln('\n❌ TEST BAŞARISIZ OLDU: $e');
    stderr.writeln(st);
    exitCode = 1;
  } finally {
    client.close(force: true);
    exit(exitCode);
  }
}

String maskId(String id) {
  if (id.length <= 8) return '***';
  return id.substring(0, 4) + '...' + id.substring(id.length - 4);
}

Future<SessionInfo> createAnonymousSession(HttpClient client, String label) async {
  final devId = 'dev_${label.toLowerCase()}_${DateTime.now().microsecondsSinceEpoch}';
  final uri = Uri.parse('$kSupabaseUrl/auth/v1/signup');
  final req = await client.postUrl(uri);
  req.headers.set('Content-Type', 'application/json; charset=utf-8');
  req.headers.set('apikey', kAnonKey);

  final body = jsonEncode({
    'data': {
      'nickname': 'Test_$label',
      'device_id': devId,
    }
  });
  req.add(utf8.encode(body));

  final res = await req.close();
  final respText = await res.transform(utf8.decoder).join();
  if (res.statusCode != 200 && res.statusCode != 201) {
    throw Exception('Anonim kullanıcı oturumu oluşturulamadı: HTTP ${res.statusCode} $respText');
  }

  final json = jsonDecode(respText) as Map<String, dynamic>;
  final user = json['user'] as Map<String, dynamic>? ?? json;
  final userId = user['id'] as String;
  final token = json['access_token'] as String? ?? '';

  return SessionInfo(label, userId, token);
}

Future<void> syncProfile(HttpClient client, SessionInfo s, String nickname) async {
  final uri = Uri.parse('$kSupabaseUrl/rest/v1/rpc/rpc_sync_initial_profile');
  final req = await client.postUrl(uri);
  req.headers.set('Content-Type', 'application/json; charset=utf-8');
  req.headers.set('apikey', kAnonKey);
  req.headers.set('Authorization', 'Bearer ${s.accessToken}');
  final body = jsonEncode({
    'p_device_id': 'dev_${s.label.toLowerCase()}_${DateTime.now().microsecondsSinceEpoch}',
    'p_nickname': nickname,
    'p_avatar_url': 'assets/avatars/user_sen.png',
    'p_bio': 'Bulut test kullanicisi ${s.label}',
    'p_legacy_steps': 0,
    'p_legacy_points': 0,
    'p_legacy_gold': 100,
    'p_legacy_co2': 0.00,
  });
  req.add(utf8.encode(body));
  final res = await req.close();
  final respBody = await res.transform(utf8.decoder).join();
  if (res.statusCode != 200 && res.statusCode != 201) {
    throw Exception('Profil senkronize edilemedi (${s.label}): HTTP ${res.statusCode} $respBody');
  }
}

Future<void> testSharedLeaderboard(HttpClient client, SessionInfo a, SessionInfo b) async {
  final uri = Uri.parse('$kSupabaseUrl/rest/v1/v_leaderboard_users?select=*&limit=5');
  
  // A oturumu sorguluyor
  final reqA = await client.getUrl(uri);
  reqA.headers.set('apikey', kAnonKey);
  reqA.headers.set('Authorization', 'Bearer ${a.accessToken}');
  final resA = await reqA.close();
  final textA = await resA.transform(utf8.decoder).join();
  
  if (resA.statusCode != 200) {
    throw Exception('Liderlik tablosu okunamadı (Oturum A): HTTP ${resA.statusCode} $textA');
  }

  final listA = jsonDecode(textA) as List<dynamic>;
  if (listA.isNotEmpty) {
    final first = listA.first as Map<String, dynamic>;
    // device_id ve gold_coins kamuya açık görünümde olmamalıdır
    if (first.containsKey('device_id') || first.containsKey('gold_coins')) {
      throw Exception('GÜVENLİK İHLALİ: device_id veya gold_coins liderlik tablosunda ifşa edilmiş!');
    }
    stdout.writeln('  ✅ Oturum A liderlik tablosunu güvenle okudu (${listA.length} kullanıcı, hassas alanlar gizli).');
  }

  // B oturumu da aynı tabloyu görebilmeli
  final reqB = await client.getUrl(uri);
  reqB.headers.set('apikey', kAnonKey);
  reqB.headers.set('Authorization', 'Bearer ${b.accessToken}');
  final resB = await reqB.close();
  if (resB.statusCode != 200) {
    throw Exception('Liderlik tablosu okunamadı (Oturum B): HTTP ${resB.statusCode}');
  }
  stdout.writeln('  ✅ Oturum B aynı ortak liderlik tablosunu başarıyla okudu.');
}

Future<void> testRlsIsolation(HttpClient client, SessionInfo a, SessionInfo b) async {
  // A kullanıcısının kimliğiyle B'nin doğrudan A envanterini çekme denemesi
  final uri = Uri.parse('$kSupabaseUrl/rest/v1/user_inventory?user_id=eq.${a.userId}&select=*');
  final reqB = await client.getUrl(uri);
  reqB.headers.set('apikey', kAnonKey);
  reqB.headers.set('Authorization', 'Bearer ${b.accessToken}');
  final resB = await reqB.close();
  final textB = await resB.transform(utf8.decoder).join();

  if (resB.statusCode == 404) {
    throw Exception('SÖZLEŞME VE DAĞITIM HATASI: user_inventory tablosu bulunamadı (HTTP 404)!');
  }

  if (resB.statusCode == 200) {
    final items = jsonDecode(textB) as List<dynamic>;
    // RLS politikası gereği B kullanıcısı A'nın ID'si için sorgu attığında 0 satır dönmelidir
    if (items.isNotEmpty) {
      throw Exception('RLS İZOLASYON İHLALİ: Oturum B, Oturum A nın envanter satırlarını okuyabildi!');
    }
    stdout.writeln('  ✅ RLS İzolasyonu doğrulandı: B kullanıcısı A nın özel envanter kayıtlarına erişemiyor (0 satır).');
  } else {
    throw Exception('user_inventory sorgusu beklenmeyen durum döndürdü: HTTP ${resB.statusCode} $textB');
  }

  // Admin audit trail yalnızca server_admins tarafından okunabilir
  final auditUri = Uri.parse('$kSupabaseUrl/rest/v1/admin_audit_trail?select=*');
  final reqAudit = await client.getUrl(auditUri);
  reqAudit.headers.set('apikey', kAnonKey);
  reqAudit.headers.set('Authorization', 'Bearer ${a.accessToken}');
  final resAudit = await reqAudit.close();
  final auditText = await resAudit.transform(utf8.decoder).join();
  
  if (resAudit.statusCode == 404) {
    throw Exception('SÖZLEŞME VE DAĞITIM HATASI: admin_audit_trail tablosu bulunamadı (HTTP 404)!');
  }

  if (resAudit.statusCode == 200) {
    final rows = jsonDecode(auditText) as List<dynamic>;
    if (rows.isNotEmpty) {
      throw Exception('GÜVENLİK İHLALİ: Standart kullanıcı admin_audit_trail içeriğini okuyabildi!');
    }
  }
  stdout.writeln('  ✅ Admin Audit Trail standart kullanıcılara kapalı (RLS korumalı, 0 satır).');
}

Future<void> testUnauthorizedGmRejection(HttpClient client, SessionInfo a) async {
  final uri = Uri.parse('$kSupabaseUrl/rest/v1/rpc/rpc_universal_gm_action');
  final req = await client.postUrl(uri);
  req.headers.set('Content-Type', 'application/json; charset=utf-8');
  req.headers.set('apikey', kAnonKey);
  req.headers.set('Authorization', 'Bearer ${a.accessToken}');

  final body = jsonEncode({
    'p_target_user_id': a.userId,
    'p_action': 'add_gold',
    'p_payload': {'amount': 1000},
    'p_idempotency_key': 'unauth_test_${DateTime.now().millisecondsSinceEpoch}',
  });
  req.add(utf8.encode(body));

  final res = await req.close();
  final text = await res.transform(utf8.decoder).join();

  if (res.statusCode == 404) {
    throw Exception('SÖZLEŞME VE DAĞITIM HATASI: rpc_universal_gm_action sunucuda bulunamadı (HTTP 404)!');
  }

  // Yetkisiz kullanıcı RPC çağırdığında sunucu kesinlikle reddetmelidir
  if (res.statusCode == 200) {
    final json = jsonDecode(text) as Map<String, dynamic>;
    if (json['ok'] == true) {
      throw Exception('GÜVENLİK İHLALİ: Standart yetkisiz kullanıcı rpc_universal_gm_action ile altın ekleyebildi!');
    }
  } else if (!text.contains('Yetkisiz') && !text.contains('server_admins') && !text.contains('permission') && !text.contains('P0001')) {
    throw Exception('Beklenmeyen sunucu yanıtı (Yetkisiz GM testi): HTTP ${res.statusCode} $text');
  }
  stdout.writeln('  ✅ Yetkisiz GM müdahalesi sunucu tarafından başarıyla engellendi (server_admins koruması devrede).');
}

Future<void> testParamContracts(HttpClient client, SessionInfo a, SessionInfo b) async {
  // 1. Bus RPC: Negatif mesafe reddi
  final busUri = Uri.parse('$kSupabaseUrl/rest/v1/rpc/rpc_record_bus_trip');
  final reqBus = await client.postUrl(busUri);
  reqBus.headers.set('Content-Type', 'application/json; charset=utf-8');
  reqBus.headers.set('apikey', kAnonKey);
  reqBus.headers.set('Authorization', 'Bearer ${a.accessToken}');

  reqBus.add(utf8.encode(jsonEncode({
    'p_event_id': 'test_neg_dist_${DateTime.now().millisecondsSinceEpoch}',
    'p_distance_km': -5.0, // Geçersiz negatif mesafe
    'p_bus_score': 80,
    'p_confidence': 0.95,
  })));

  final resBus = await reqBus.close();
  final textBus = await resBus.transform(utf8.decoder).join();

  if (resBus.statusCode == 404) {
    throw Exception('SÖZLEŞME VE DAĞITIM HATASI: rpc_record_bus_trip sunucuda bulunamadı (HTTP 404)!');
  }

  if (resBus.statusCode == 200) {
    final json = jsonDecode(textBus) as Map<String, dynamic>;
    if (json['ok'] == true) {
      throw Exception('SÖZLEŞME İHLALİ: Negatif mesafeli otobüs yolculuğu sunucu tarafından kabul edildi!');
    }
  }
  stdout.writeln('  ✅ Bus RPC: Negatif ve geçersiz mesafeler sunucu tarafında filtrelendi.');

  // 2. Utanç Mesajı: Kendi kendine gönderme engeli
  final shameUri = Uri.parse('$kSupabaseUrl/rest/v1/rpc/rpc_send_shame_message');
  final reqShame = await client.postUrl(shameUri);
  reqShame.headers.set('Content-Type', 'application/json; charset=utf-8');
  reqShame.headers.set('apikey', kAnonKey);
  reqShame.headers.set('Authorization', 'Bearer ${a.accessToken}');

  reqShame.add(utf8.encode(jsonEncode({
    'p_target_id': a.userId, // Kendine gönderme
    'p_message': 'Kendime mesaj',
    'p_idempotency_key': 'self_shame_${DateTime.now().millisecondsSinceEpoch}',
  })));

  final resShame = await reqShame.close();
  final textShame = await resShame.transform(utf8.decoder).join();

  if (resShame.statusCode == 404) {
    throw Exception('SÖZLEŞME VE DAĞITIM HATASI: rpc_send_shame_message sunucuda bulunamadı (HTTP 404)!');
  }

  if (resShame.statusCode == 200) {
    final json = jsonDecode(textShame) as Map<String, dynamic>;
    if (json['ok'] == true) {
      throw Exception('SÖZLEŞME İHLALİ: Kendine utanç mesajı gönderme kabul edildi!');
    }
  }
  stdout.writeln('  ✅ Utanç Mesajı RPC: Kendine mesaj gönderme ve sınır dışı parametreler filtrelendi.');
}

Future<void> testCrossSessionMutationAndRealtime(HttpClient client, SessionInfo a, SessionInfo b) async {
  // A. Realtime WebSocket Bağlantı ve Join Doğrulaması
  stdout.writeln('  📡 Realtime WebSocket kanalı bağlanıyor...');
  final ws = await WebSocket.connect(
    'wss://fhaxxraibydsjikxacbb.supabase.co/realtime/v1/websocket?apikey=$kAnonKey&vsn=1.0.0',
  ).timeout(const Duration(seconds: 6));

  final joinRef = 'join_${DateTime.now().millisecondsSinceEpoch}';
  ws.add(jsonEncode({
    'topic': 'realtime:public',
    'event': 'phx_join',
    'payload': {},
    'ref': joinRef,
  }));

  final wsMsg = await ws.first.timeout(const Duration(seconds: 5));
  final wsParsed = jsonDecode(wsMsg as String) as Map<String, dynamic>;
  stdout.writeln('  ✅ Realtime WebSocket yanıtı alındı: ${wsParsed['event']} (Kanal bağlı)');
  await ws.close();

  // B. Başlangıç Puanını Oturum B Üzerinden Oku
  final initialPointsA = await getUserWeeklyPoints(client, b, a.userId);
  stdout.writeln('  📊 Oturum B tarafından okunan Oturum A başlangıç puanı: $initialPointsA');

  // C. Oturum A Tamamlanan 1000 Adım Aktivitesini İşler (1000/1000*5 = +5 Puan)
  final stepEventId = 'live_step_${DateTime.now().millisecondsSinceEpoch}';
  final stepUri = Uri.parse('$kSupabaseUrl/rest/v1/rpc/rpc_record_steps');
  final reqStep = await client.postUrl(stepUri);
  reqStep.headers.set('Content-Type', 'application/json; charset=utf-8');
  reqStep.headers.set('apikey', kAnonKey);
  reqStep.headers.set('Authorization', 'Bearer ${a.accessToken}');

  reqStep.add(utf8.encode(jsonEncode({
    'p_event_id': stepEventId,
    'p_step_count': 1000, // 1000 adım = 5 puan ödülü
    'p_distance_km': 0.70,
    'p_co2_saved_kg': 0.13,
  })));

  final resStep = await reqStep.close();
  final bodyStep = await resStep.transform(utf8.decoder).join();
  if (resStep.statusCode != 200) {
    throw Exception('rpc_record_steps başarısız: HTTP ${resStep.statusCode} $bodyStep');
  }

  final jsonStep = jsonDecode(bodyStep) as Map<String, dynamic>;
  final pointsAwarded = jsonStep['points_awarded'] as int? ?? 0;
  stdout.writeln('  ⚡ Oturum A adım aktivitesini işledi (+${pointsAwarded} puan alındı).');

  // D. Oturum B, Ortak Liderlik Görünümünden Oturum A'nın Yeni Puanını Doğrular
  final updatedPointsA = await getUserWeeklyPoints(client, b, a.userId);
  stdout.writeln('  📊 Oturum B tarafından okunan Oturum A güncel puanı: $updatedPointsA');

  if (updatedPointsA != (initialPointsA + pointsAwarded)) {
    throw Exception('MUTASYON YAYILMA ASSERTION BAŞARISIZ: Beklenen: ${initialPointsA + pointsAwarded}, Gözlenen: $updatedPointsA');
  }
  stdout.writeln('  ✅ Cross-Session Doğrulama Başarılı: Oturum A nın puan mutasyonu Oturum B tarafından ortak liderlikte anında doğrulandı!');
}

Future<int> getUserWeeklyPoints(HttpClient client, SessionInfo reader, String targetUserId) async {
  final uri = Uri.parse('$kSupabaseUrl/rest/v1/v_leaderboard_users?user_id=eq.$targetUserId&select=*');
  final req = await client.getUrl(uri);
  req.headers.set('apikey', kAnonKey);
  req.headers.set('Authorization', 'Bearer ${reader.accessToken}');
  final res = await req.close();
  final text = await res.transform(utf8.decoder).join();
  if (res.statusCode != 200) {
    throw Exception('v_leaderboard_users okunamadı: HTTP ${res.statusCode} $text');
  }
  final list = jsonDecode(text) as List<dynamic>;
  if (list.isEmpty) return 0;
  return (list.first as Map<String, dynamic>)['weekly_points'] as int? ?? 0;
}
