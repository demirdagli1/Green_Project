// ============================================================================
// tools/universal_gm/setup_admin_session.dart
// Root İçin Güvenli, Tek Seferlik GM Oturumu ve Yetkilendirme Üretim Aracı
//
// Özellikler:
// - service_role GEREKTİRMEZ; kamusal publishable key ile çalışır.
// - Terminale token YAZDIRMAZ (Sır sızıntısını önler).
// - Oturum dosyasını web root dışındaki .gm-private/ dizinine yazar (chmod 600, .gitignore korumalı).
// - Başarılı anon oturumu hemen kaydeder; retry durumunda mevcut oturumu yeniden kullanır.
// - Tüm HTTP isteklerinde açık utf-8 byte encoding ve Content-Type charset=utf-8 kullanır.
// - Admin profilini 'rpc_sync_initial_profile' ile public.users içine yazar (Audit FK uyumu).
// - Root için incelenebilir tek satırlık 'supabase/migrations/grant_admin.sql' oluşturur.
//
// Çalıştırma:
//   /home/girdap/Masaüstü/WordMaster/.tools/flutter/bin/dart tools/universal_gm/setup_admin_session.dart
// ============================================================================

import 'dart:convert';
import 'dart:io';

const String kSupabaseUrl = 'https://fhaxxraibydsjikxacbb.supabase.co';
const String kAnonKey = 'sb_publishable_7TEibMmt8wbJtKTYb_vjlA_xZoCnN5J';

void main() async {
  final client = HttpClient();
  stdout.writeln('================================================================');
  stdout.writeln('⚡ Yeşil Adım — Evrensel GM Konsol Oturumu Kurulum Aracı');
  stdout.writeln('================================================================\n');

  try {
    final sessionFilePath = '.gm-private/gm_admin_session.private.json';
    final sessionFile = File(sessionFilePath);

    final privateDir = Directory('.gm-private');
    if (!privateDir.existsSync()) {
      privateDir.createSync(recursive: true);
    }
    try {
      await Process.run('chmod', ['700', '.gm-private']);
    } catch (_) {}

    String uid;
    String accessToken;
    String refreshToken = '';
    String adminEmail;
    String devId;

    // 1. Mevcut Oturumu Kontrol Et ve Yeniden Kullan (Auth veritabanını kirletmeme)
    if (sessionFile.existsSync()) {
      stdout.writeln('[1/4] Mevcut .gm-private oturum dosyası bulundu, yeniden kullanılıyor...');
      final existingJson = jsonDecode(await sessionFile.readAsString()) as Map<String, dynamic>;
      uid = existingJson['adminUid'] as String;
      accessToken = existingJson['accessToken'] as String;
      refreshToken = existingJson['refreshToken'] as String? ?? '';
      adminEmail = existingJson['adminEmail'] as String? ?? 'gm_admin@internal.local';
      devId = existingJson['devId'] as String? ?? 'gm_console_existing';
      stdout.writeln('  ✅ Mevcut UID devralındı: $uid');
    } else {
      stdout.writeln('[1/4] Supabase Auth servisinde yeni GM oturumu oluşturuluyor (Anonim Oturum)...');
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      adminEmail = 'gm_admin_$nowMs@internal.local';
      devId = 'gm_console_$nowMs';

      final uri = Uri.parse('$kSupabaseUrl/auth/v1/signup');
      final req = await client.postUrl(uri);
      req.headers.set('Content-Type', 'application/json; charset=utf-8');
      req.headers.set('apikey', kAnonKey);

      final payload = {
        'data': {
          'nickname': 'GM_Root_Console',
          'device_id': devId,
        }
      };
      req.add(utf8.encode(jsonEncode(payload)));

      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();

      if (res.statusCode != 200 && res.statusCode != 201) {
        throw Exception('Supabase Auth kaydı başarısız: HTTP ${res.statusCode} $body');
      }

      final json = jsonDecode(body) as Map<String, dynamic>;
      final user = json['user'] as Map<String, dynamic>? ?? json;
      uid = user['id'] as String;
      accessToken = json['access_token'] as String;
      refreshToken = json['refresh_token'] as String? ?? '';

      // Başarılı Auth oturumunu hemen dosyaya yaz (Erken kayıt: sonraki adımlarda hata olursa oturum kaybolmaz)
      final earlyData = {
        'supabaseUrl': kSupabaseUrl,
        'anonKey': kAnonKey,
        'adminUid': uid,
        'adminEmail': adminEmail,
        'devId': devId,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'createdAt': DateTime.now().toIso8601String(),
      };
      await sessionFile.writeAsString(const JsonEncoder.withIndent('  ').convert(earlyData));
      try {
        await Process.run('chmod', ['600', sessionFilePath]);
      } catch (_) {}
      stdout.writeln('  ✅ Auth kaydı başarılı, oturum dosyaya erken kaydedildi.');
    }

    // 2. public.users tablosunda profil oluştur (Audit log foreign key gereksinimi için)
    stdout.writeln('[2/4] public.users tablosunda GM profili senkronize ediliyor (rpc_sync_initial_profile)...');
    final rpcUri = Uri.parse('$kSupabaseUrl/rest/v1/rpc/rpc_sync_initial_profile');
    final rpcReq = await client.postUrl(rpcUri);
    rpcReq.headers.set('Content-Type', 'application/json; charset=utf-8');
    rpcReq.headers.set('apikey', kAnonKey);
    rpcReq.headers.set('Authorization', 'Bearer $accessToken');

    final rpcPayload = {
      'p_device_id': devId,
      'p_nickname': 'GM_Root_Console',
      'p_avatar_url': 'assets/avatars/user_sen.png',
      'p_bio': 'Evrensel GM Konsol Yoneticisi',
      'p_legacy_steps': 0,
      'p_legacy_points': 0,
      'p_legacy_gold': 100,
      'p_legacy_co2': 0.00,
    };
    rpcReq.add(utf8.encode(jsonEncode(rpcPayload)));

    final rpcRes = await rpcReq.close();
    final rpcBody = await rpcRes.transform(utf8.decoder).join();
    if (rpcRes.statusCode != 200 && rpcRes.statusCode != 201) {
      throw Exception('Admin profili rpc_sync_initial_profile ile oluşturulamadı: HTTP ${rpcRes.statusCode} $rpcBody');
    }
    stdout.writeln('  ✅ public.users tablosunda GM profili doğrulandı.');

    // 3. Web root dışındaki .gm-private/ dosyasını güncelle
    stdout.writeln('[3/4] Web root dışındaki .gm-private/ oturum dosyası mühürleniyor (chmod 600)...');
    final sessionData = {
      'supabaseUrl': kSupabaseUrl,
      'anonKey': kAnonKey,
      'adminUid': uid,
      'adminEmail': adminEmail,
      'devId': devId,
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'createdAt': DateTime.now().toIso8601String(),
      'profileSynced': true,
    };
    await sessionFile.writeAsString(const JsonEncoder.withIndent('  ').convert(sessionData));
    try {
      await Process.run('chmod', ['600', sessionFilePath]);
    } catch (_) {}

    // 4. Root İçin İncelenebilir SQL Yetki Dosyasını Oluştur
    stdout.writeln('[4/4] Root için server_admins yetkilendirme SQL dosyası hazırlanıyor...');
    final sqlFilePath = 'supabase/migrations/grant_admin.sql';
    final sqlContent = '''-- ============================================================================
-- grant_admin.sql
-- Root Evrensel GM Konsol Yetkilendirme SQL'i
-- Üretim Tarihi: ${DateTime.now().toIso8601String()}
-- ============================================================================

INSERT INTO public.server_admins (user_id, notes)
VALUES ('$uid', 'Evrensel GM Web Konsolu ($adminEmail)')
ON CONFLICT (user_id) 
DO UPDATE SET notes = 'Evrensel GM Web Konsolu (Güncellendi ${DateTime.now().toIso8601String()})';
''';

    final sqlFile = File(sqlFilePath);
    await sqlFile.writeAsString(sqlContent);

    stdout.writeln('\n================================================================');
    stdout.writeln('✅ GM KURULUMU BAŞARIYLA TAMAMLANDI!');
    stdout.writeln('----------------------------------------------------------------');
    stdout.writeln('Yönetici UID       : $uid');
    stdout.writeln('public.users Kaydı : Senkronize edildi (Audit FK hazır)');
    stdout.writeln('Özel Oturum Dosyası: $sessionFilePath (chmod 600, web root dışı)');
    stdout.writeln('Yetkilendirme SQL\'i: $sqlFilePath');
    stdout.writeln('----------------------------------------------------------------');
    stdout.writeln('📋 Root Kullanım Adımları:');
    stdout.writeln('1. Root, \'$sqlFilePath\' dosyasını Supabase Dashboard SQL Editöründe inceler ve çalıştırır.');
    stdout.writeln('2. PC Web Paneli (index.html) açıldığında "📁 Oturum Dosyası İçe Aktar" butonuna');
    stdout.writeln('   basılarak \'$sessionFilePath\' dosyası seçilir.');
    stdout.writeln('3. Token terminale basılmamış ve repoya açık şifre eklenmemiştir.');
    stdout.writeln('================================================================\n');
    exitCode = 0;
  } catch (e, st) {
    stderr.writeln('❌ Kurulum Hatası: $e');
    stderr.writeln(st);
    exitCode = 1;
  } finally {
    client.close(force: true);
    exit(exitCode);
  }
}
