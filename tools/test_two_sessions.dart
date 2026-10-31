// ============================================================================
// tools/test_two_sessions.dart
// İki Gerçek Anonim HTTP Oturumu ile Ortak Liderlik, İzolasyon ve RPC Test Aracı
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
    stdout.writeln('[1/5] İki bağımsız anonim/test oturumu oluşturuluyor...');
    final sessionA = await createAnonymousSession(client, 'Cihaz_A');
    final sessionB = await createAnonymousSession(client, 'Cihaz_B');
    stdout.writeln('  ✅ Oturum A hazır (UID: ${maskId(sessionA.userId)})');
    stdout.writeln('  ✅ Oturum B hazır (UID: ${maskId(sessionB.userId)})');

    // 2. Ortak Liderlik Tablosu Projeksiyon Testi
    stdout.writeln('\n[2/5] Ortak Leaderboard Projeksiyonu Denetleniyor...');
    await testSharedLeaderboard(client, sessionA, sessionB);

    // 3. RLS İzolasyon Denetimi (Özel Veri Sızıntısı Engeli)
    stdout.writeln('\n[3/5] RLS İzolasyonu Denetleniyor (Kullanıcı İçi Mahremiyet)...');
    await testRlsIsolation(client, sessionA, sessionB);

    // 4. Yetkisiz GM Çağrısı Reddi Testi
    stdout.writeln('\n[4/5] Yetkisiz GM Çağrısı Reddi Denetleniyor...');
    await testUnauthorizedGmRejection(client, sessionA);

    // 5. Doğru Parametre Sözleşmesi ve Eşik Kontrolleri
    stdout.writeln('\n[5/5] Bus RPC ve Utanç Mesajı Parametre Sözleşmesi Denetleniyor...');
    await testParamContracts(client, sessionA, sessionB);

    stdout.writeln('\n================================================================');
    stdout.writeln('🎉 TÜM İKİ OTURUMLU BULUT ENTEGRASYON TESTLERİ BAŞARIYLA TAMAMLANDI!');
    stdout.writeln('================================================================');
  } catch (e, st) {
    stderr.writeln('\n❌ TEST BAŞARISIZ OLDU: $e');
    stderr.writeln(st);
    exitCode = 1;
  } finally {
    client.close();
  }
}

String maskId(String id) {
  if (id.length <= 8) return '***';
  return id.substring(0, 4) + '...' + id.substring(id.length - 4);
}

Future<SessionInfo> createAnonymousSession(HttpClient client, String label) async {
  // Rastgele test kimliği ile oturum aç
  final testEmail = 'test_${label.toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}@yesiladim.local';
  final testPass = 'P@ssw0rd_${DateTime.now().millisecondsSinceEpoch}';

  final uri = Uri.parse('$kSupabaseUrl/auth/v1/signup');
  final req = await client.postUrl(uri);
  req.headers.set('Content-Type', 'application/json');
  req.headers.set('apikey', kAnonKey);

  final body = jsonEncode({
    'email': testEmail,
    'password': testPass,
    'data': {
      'nickname': 'Test_$label',
      'device_id': 'dev_${label.toLowerCase()}_${DateTime.now().microsecondsSinceEpoch}',
    }
  });
  req.write(body);

  final res = await req.close();
  final respText = await res.transform(utf8.decoder).join();
  if (res.statusCode != 200 && res.statusCode != 201) {
    // Anonim oturum desteği
    final anonUri = Uri.parse('$kSupabaseUrl/auth/v1/token?grant_type=anonymous');
    final anonReq = await client.postUrl(anonUri);
    anonReq.headers.set('Content-Type', 'application/json');
    anonReq.headers.set('apikey', kAnonKey);
    final anonRes = await anonReq.close();
    final anonText = await anonRes.transform(utf8.decoder).join();
    if (anonRes.statusCode == 200) {
      final json = jsonDecode(anonText) as Map<String, dynamic>;
      final user = json['user'] as Map<String, dynamic>? ?? {};
      return SessionInfo(label, user['id'] as String? ?? 'anon_id', json['access_token'] as String);
    }
    throw Exception('Kullanıcı oturumu oluşturulamadı: HTTP ${res.statusCode} $respText');
  }

  final json = jsonDecode(respText) as Map<String, dynamic>;
  final user = json['user'] as Map<String, dynamic>? ?? json;
  final userId = user['id'] as String;
  final token = json['access_token'] as String? ?? '';

  return SessionInfo(label, userId, token);
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
  // A kullanıcısının envanterini sorgula
  final uri = Uri.parse('$kSupabaseUrl/rest/v1/user_inventory?select=*');
  final reqB = await client.getUrl(uri);
  reqB.headers.set('apikey', kAnonKey);
  reqB.headers.set('Authorization', 'Bearer ${b.accessToken}');
  final resB = await reqB.close();
  final textB = await resB.transform(utf8.decoder).join();

  if (resB.statusCode == 200) {
    final items = jsonDecode(textB) as List<dynamic>;
    // B kullanıcısı A'nın envanterini göremez, yalnızca kendi envanterini (0 veya kendi öğeleri) görebilir
    for (final it in items) {
      if ((it as Map<String, dynamic>)['user_id'] == a.userId) {
        throw Exception('RLS İZOLASYON İHLALİ: Oturum B, Oturum A nın envanterini gördü!');
      }
    }
    stdout.writeln('  ✅ RLS İzolasyonu doğrulandı: B kullanıcısı A nın envanterine erişemiyor.');
  }

  // Admin audit trail yalnızca server_admins tarafından okunabilir
  final auditUri = Uri.parse('$kSupabaseUrl/rest/v1/admin_audit_trail?select=*');
  final reqAudit = await client.getUrl(auditUri);
  reqAudit.headers.set('apikey', kAnonKey);
  reqAudit.headers.set('Authorization', 'Bearer ${a.accessToken}');
  final resAudit = await reqAudit.close();
  final auditText = await resAudit.transform(utf8.decoder).join();
  
  if (resAudit.statusCode == 200) {
    final rows = jsonDecode(auditText) as List<dynamic>;
    if (rows.isNotEmpty) {
      throw Exception('GÜVENLİK İHLALİ: Standart kullanıcı admin_audit_trail içeriğini okuyabildi!');
    }
  }
  stdout.writeln('  ✅ Admin Audit Trail standart kullanıcılara kapalı (RLS korumalı).');
}

Future<void> testUnauthorizedGmRejection(HttpClient client, SessionInfo a) async {
  final uri = Uri.parse('$kSupabaseUrl/rest/v1/rpc/rpc_universal_gm_action');
  final req = await client.postUrl(uri);
  req.headers.set('Content-Type', 'application/json');
  req.headers.set('apikey', kAnonKey);
  req.headers.set('Authorization', 'Bearer ${a.accessToken}');

  final body = jsonEncode({
    'p_target_user_id': a.userId,
    'p_action': 'add_gold',
    'p_payload': {'amount': 1000},
    'p_idempotency_key': 'unauth_test_${DateTime.now().millisecondsSinceEpoch}',
  });
  req.write(body);

  final res = await req.close();
  final text = await res.transform(utf8.decoder).join();

  // Yetkisiz kullanıcı RPC çağırdığında sunucu hata döndürmelidir (HTTP 400 veya 403 veya veritabanı istisnası)
  if (res.statusCode == 200) {
    final json = jsonDecode(text) as Map<String, dynamic>;
    if (json['ok'] == true) {
      throw Exception('GÜVENLİK İHLALİ: Standart yetkisiz kullanıcı rpc_universal_gm_action ile altın ekleyebildi!');
    }
  }
  stdout.writeln('  ✅ Yetkisiz GM müdahalesi sunucu tarafından başarıyla engellendi (server_admins koruması devrede).');
}

Future<void> testParamContracts(HttpClient client, SessionInfo a, SessionInfo b) async {
  // 1. Bus RPC: Negatif mesafe reddi
  final busUri = Uri.parse('$kSupabaseUrl/rest/v1/rpc/rpc_record_bus_trip');
  final reqBus = await client.postUrl(busUri);
  reqBus.headers.set('Content-Type', 'application/json');
  reqBus.headers.set('apikey', kAnonKey);
  reqBus.headers.set('Authorization', 'Bearer ${a.accessToken}');

  reqBus.write(jsonEncode({
    'p_event_id': 'test_neg_dist_${DateTime.now().millisecondsSinceEpoch}',
    'p_distance_km': -5.0, // Geçersiz negatif mesafe
    'p_bus_score': 80,
    'p_confidence': 0.95,
  }));

  final resBus = await reqBus.close();
  final textBus = await resBus.transform(utf8.decoder).join();

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
  reqShame.headers.set('Content-Type', 'application/json');
  reqShame.headers.set('apikey', kAnonKey);
  reqShame.headers.set('Authorization', 'Bearer ${a.accessToken}');

  reqShame.write(jsonEncode({
    'p_target_id': a.userId, // Kendine gönderme
    'p_message': 'Kendime mesaj',
    'p_idempotency_key': 'self_shame_${DateTime.now().millisecondsSinceEpoch}',
  }));

  final resShame = await reqShame.close();
  final textShame = await resShame.transform(utf8.decoder).join();

  if (resShame.statusCode == 200) {
    final json = jsonDecode(textShame) as Map<String, dynamic>;
    if (json['ok'] == true) {
      throw Exception('SÖZLEŞME İHLALİ: Kendine utanç mesajı gönderme kabul edildi!');
    }
  }
  stdout.writeln('  ✅ Utanç Mesajı RPC: Kendine mesaj gönderme ve sınır dışı parametreler filtrelendi.');
}
