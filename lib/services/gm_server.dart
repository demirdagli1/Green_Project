import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'command_dispatcher.dart';
import 'sensor_controller.dart';

class GmServer {
  final CommandDispatcher dispatcher;
  final SensorController sensors;
  HttpServer? _server;
  String _token = '';
  int _port = 8088;
  bool enabled = true;

  GmServer({required this.dispatcher, required this.sensors});

  String get token => _token;
  int get port => _port;
  bool get isRunning => _server != null;

  Future<void> start({required String initialToken, int listenPort = 8088}) async {
    if (kReleaseMode || !enabled) {
      debugPrint('[GM_SERVER] Release modunda veya devre dışıyken başlatılamaz.');
      return;
    }
    _token = initialToken;
    _port = listenPort;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
      debugPrint('[GM_SERVER] Başlatıldı (Loopback): 127.0.0.1:$_port');
      _server!.listen(_handleRequest);
    } catch (e) {
      debugPrint('[GM_SERVER] Başlatılamadı (port $_port): $e');
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handleRequest(HttpRequest req) async {
    // 1) Host Başlığı Kontrolü (DNS Rebinding engeli)
    final host = req.headers.host;
    if (host != null && host.isNotEmpty) {
      final cleanHost = host.split(':').first;
      if (cleanHost != 'localhost' && cleanHost != '127.0.0.1') {
        req.response
          ..statusCode = HttpStatus.forbidden
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Geçersiz Host başlığı.'}))
          ..close();
        return;
      }
    }

    // 2) Origin Başlığı Tam Doğrulaması (Substring değil, tam URI ayrıştırma)
    final originHeader = req.headers.value('origin');
    if (originHeader != null && originHeader.isNotEmpty) {
      final originUri = Uri.tryParse(originHeader);
      final isAllowed = originUri != null &&
          originUri.scheme == 'http' &&
          (originUri.host == 'localhost' || originUri.host == '127.0.0.1') &&
          (originUri.port == _port || (originUri.port == 80 && _port == 80));

      if (!isAllowed) {
        req.response
          ..statusCode = HttpStatus.forbidden
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Origin reddedildi.'}))
          ..close();
        return;
      }

      // Origin geçerliyse sadece o origin'e izin ver (ASLA '*' KULLANMA)
      req.response.headers.set('Access-Control-Allow-Origin', originHeader);
      req.response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
      req.response.headers.set('Access-Control-Allow-Headers', 'Content-Type, X-GM-Token, Authorization');
    }

    if (req.method == 'OPTIONS') {
      req.response
        ..statusCode = HttpStatus.ok
        ..close();
      return;
    }

    // 3) İstek Gövdesini Güvenle Oku (Content-Length=-1 veya chunked akışlar dahil max 64 KB)
    final bodyBytes = await _readBodyBytes(req);
    if (bodyBytes == null) {
      // Boyut aşıldı, _readBodyBytes zaten 413 yanıtı döndü
      return;
    }

    // 4) Yetkilendirme / Token Kontrolü (Header, Bearer, Body veya URL param)
    Map<String, dynamic> jsonBody = {};
    if (bodyBytes.isNotEmpty) {
      try {
        final decoded = jsonDecode(utf8.decode(bodyBytes));
        if (decoded is Map<String, dynamic>) jsonBody = decoded;
      } catch (_) {}
    }

    final qToken = req.uri.queryParameters['token'];
    final hToken = req.headers.value('x-gm-token');
    final authHeader = req.headers.value('authorization')?.replaceFirst('Bearer ', '');
    final bToken = jsonBody['token'] as String?;
    final providedToken = hToken ?? authHeader ?? bToken ?? qToken;

    if (providedToken == null || providedToken.isEmpty || providedToken != _token) {
      // GÜVENLİK: Hata yanıtında ASLA gerçek token ifşa edilmez!
      req.response
        ..statusCode = HttpStatus.unauthorized
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'error': 'Unauthorized: Geçersiz veya eksik oturum tokenı.'}))
        ..close();
      return;
    }

    final path = req.uri.path;

    try {
      if (req.method == 'GET' && (path == '/' || path == '/panel')) {
        _serveHtmlPanel(req);
      } else if (req.method == 'GET' && path == '/api/state') {
        _serveStateJson(req);
      } else if (req.method == 'POST' && path == '/api/command') {
        _handleCommandWithBody(req, jsonBody);
      } else {
        req.response
          ..statusCode = HttpStatus.notFound
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Bilinmeyen endpoint'}))
          ..close();
      }
    } catch (_) {
      req.response
        ..statusCode = HttpStatus.internalServerError
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'error': 'İşlem sırasında sunucu hatası oluştu.'}))
        ..close();
    }
  }

  /// Hem Content-Length belirli olan hem chunked/belirsiz akışlar için
  /// kesin 64 KB (65536 bayt) sınır kontrolü.
  Future<List<int>?> _readBodyBytes(HttpRequest req) async {
    if (req.contentLength > 65536) {
      req.response
        ..statusCode = HttpStatus.requestEntityTooLarge
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'error': 'İstek boyutu çok büyük (maksimum 64 KB).'}))
        ..close();
      return null;
    }

    final bytes = <int>[];
    try {
      await for (final chunk in req) {
        bytes.addAll(chunk);
        if (bytes.length > 65536) {
          req.response
            ..statusCode = HttpStatus.requestEntityTooLarge
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'error': 'İstek akış boyutu sınırı aştı (maksimum 64 KB).'}))
            ..close();
          return null;
        }
      }
      return bytes;
    } catch (e) {
      req.response
        ..statusCode = HttpStatus.badRequest
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'error': 'Gövde okunamadı.'}))
        ..close();
      return null;
    }
  }

  void _serveStateJson(HttpRequest req) {
    final s = dispatcher.store;
    final u = s.me;
    final myClan = s.myClan;
    final jsonMap = {
      'user': u == null
          ? null
          : {
              'id': u.id,
              'username': u.username,
              'deviceId': u.deviceId,
              'clanId': u.clanId,
              'clanName': u.clanName,
              'bio': u.bio,
              'photoPath': u.photoPath,
              'todaySteps': u.todaySteps,
              'streakDays': u.streakDays,
              'goldCoins': u.goldCoins,
              'weeklyPoints': u.weeklyPoints,
              'allTimePoints': u.allTimePoints,
              'preventedCo2Kg': u.preventedCo2Kg,
              'weeklyCarTaxiTrips': u.weeklyCarTaxiTrips,
              'weeklyWastedCo2Kg': u.weeklyWastedCo2Kg,
              'equippedAvatar': u.equippedAvatar,
              'equippedFrame': u.equippedFrame,
              'equippedPet': u.equippedPet,
            },
      'clan': myClan == null
          ? null
          : {
              'id': myClan.id,
              'name': myClan.name,
              'weeklyPoints': myClan.weeklyPoints,
              'allTimePoints': myClan.allTimePoints,
              'memberCount': myClan.memberCount,
              'hybridScore': myClan.hybridScore,
            },
      'system': {
        'dayId': s.dayId,
        'weekId': s.weekId,
        'championUser': s.championUser,
        'championClan': s.championClan,
        'transitInLast45Min': s.transitInLast45Min,
        'settledWeeks': s.settledWeeks.toList(),
      },
      'telemetry': s.telemetry.toJson(),
      'hardware': {
        'caps': sensors.caps,
        'perms': sensors.perms,
        'sensorsRunning': sensors.sensorsRunning,
      },
      'log': s.log.take(25).map((e) => e.toJson()).toList(),
    };

    req.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(jsonMap))
      ..close();
  }

  void _handleCommandWithBody(HttpRequest req, Map<String, dynamic> jsonBody) {
    final cmd = jsonBody['cmd'] as String? ?? '';
    final params = (jsonBody['params'] as Map?)?.cast<String, dynamic>() ?? {};
    final idempotencyKey = jsonBody['idempotencyKey'] as String?;

    final result = dispatcher.dispatch(cmd, params, idempotencyKey: idempotencyKey);

    req.response
      ..statusCode = result.ok ? HttpStatus.ok : HttpStatus.badRequest
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(result.toJson()))
      ..close();
  }

  void _serveHtmlPanel(HttpRequest req) {
    req.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.html
      ..write(_htmlPage);
    req.response.close();
  }

  static const String _htmlPage = r'''<!DOCTYPE html>
<html lang="tr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Yeşil Adım — AppStore GM Kontrol Paneli</title>
  <style>
    :root {
      --bg: #0f172a;
      --card-bg: #1e293b;
      --card-border: #334155;
      --text: #f8fafc;
      --muted: #94a3b8;
      --primary: #8b5cf6;
      --primary-hover: #7c3aed;
      --emerald: #10b981;
      --amber: #f59e0b;
      --rose: #f43f5e;
      --blue: #38bdf8;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      background: var(--bg);
      color: var(--text);
      padding: 20px;
      line-height: 1.5;
    }
    .header {
      display: flex;
      flex-wrap: wrap;
      justify-content: space-between;
      align-items: center;
      gap: 12px;
      padding-bottom: 16px;
      border-bottom: 1px solid var(--card-border);
      margin-bottom: 20px;
    }
    .header h1 { font-size: 22px; font-weight: 800; color: #fff; display: flex; align-items: center; gap: 8px; }
    .badge {
      display: inline-block;
      padding: 4px 10px;
      border-radius: 999px;
      font-size: 11px;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.5px;
    }
    .badge-live { background: rgba(16, 185, 129, 0.2); color: #34d399; border: 1px solid rgba(16, 185, 129, 0.4); }
    .badge-demo { background: rgba(245, 158, 11, 0.2); color: #fbbf24; border: 1px solid rgba(245, 158, 11, 0.4); }
    .badge-alert { background: rgba(244, 63, 94, 0.2); color: #fb7185; border: 1px solid rgba(244, 63, 94, 0.4); }
    
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); gap: 16px; margin-bottom: 20px; }
    .card {
      background: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: 14px;
      padding: 16px;
      box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
    }
    .card h2 { font-size: 15px; font-weight: 700; color: var(--muted); text-transform: uppercase; margin-bottom: 12px; display: flex; justify-content: space-between; }
    
    .stat-row { display: flex; justify-content: space-between; padding: 6px 0; border-bottom: 1px solid rgba(255,255,255,0.05); font-size: 13px; }
    .stat-row:last-child { border-bottom: none; }
    .stat-label { color: var(--muted); }
    .stat-val { font-weight: 700; color: #fff; text-align: right; }
    
    .form-group { display: flex; gap: 8px; margin-bottom: 10px; align-items: center; }
    input[type="number"], input[type="text"] {
      background: #0f172a;
      border: 1px solid var(--card-border);
      color: #fff;
      padding: 8px 12px;
      border-radius: 8px;
      font-size: 13px;
      outline: none;
      width: 100px;
    }
    input[type="text"] { flex: 1; width: auto; }
    input:focus { border-color: var(--primary); }
    
    button {
      background: var(--primary);
      color: #fff;
      border: none;
      padding: 8px 14px;
      border-radius: 8px;
      font-size: 13px;
      font-weight: 700;
      cursor: pointer;
      transition: background 0.15s;
    }
    button:hover { background: var(--primary-hover); }
    button.btn-emerald { background: var(--emerald); }
    button.btn-emerald:hover { background: #059669; }
    button.btn-amber { background: var(--amber); color: #000; }
    button.btn-amber:hover { background: #d97706; }
    button.btn-rose { background: var(--rose); }
    button.btn-rose:hover { background: #e11d48; }
    button.btn-outline { background: transparent; border: 1px solid var(--card-border); color: var(--muted); }
    button.btn-outline:hover { background: rgba(255,255,255,0.05); color: #fff; }
    
    .btn-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin-top: 10px; }
    
    .banner {
      padding: 12px 16px;
      border-radius: 10px;
      font-size: 13px;
      font-weight: 600;
      margin-bottom: 16px;
      display: none;
    }
    .banner-success { background: rgba(16, 185, 129, 0.2); border: 1px solid var(--emerald); color: #a7f3d0; }
    .banner-error { background: rgba(244, 63, 94, 0.2); border: 1px solid var(--rose); color: #fecdd3; }
    
    table { width: 100%; border-collapse: collapse; font-size: 12px; margin-top: 10px; }
    th, td { text-align: left; padding: 8px; border-bottom: 1px solid rgba(255,255,255,0.05); }
    th { color: var(--muted); font-weight: 600; }
    
    .log-entry { margin-bottom: 8px; padding: 8px; background: rgba(0,0,0,0.2); border-radius: 6px; font-size: 12px; }
    .log-title { font-weight: 700; color: #fff; }
    .log-body { color: var(--muted); margin-top: 2px; }
  </style>
</head>
<body>

  <div class="header">
    <div>
      <h1>🌱 Yeşil Adım — AppStore GM Paneli <span class="badge badge-live">Yerel ADB/USB</span></h1>
      <p style="font-size: 12px; color: var(--muted); margin-top: 4px;">
        Samsung SM-A346E • Port 8088 • Oturum Yetkisi Doğrulandı
      </p>
    </div>
    <div style="display: flex; gap: 8px; align-items: center;">
      <button class="btn-outline" onclick="loadState()">🔄 Yenile</button>
      <label style="font-size: 12px; color: var(--muted); display: flex; align-items: center; gap: 4px;">
        <input type="checkbox" id="autoRefresh" checked onchange="toggleAuto()"> Otomatik Yenile (2sn)
      </label>
    </div>
  </div>

  <div id="msgBanner" class="banner"></div>

  <div class="grid">
    <!-- KULLANICI & LİG DURUMU -->
    <div class="card">
      <h2>👤 Kullanıcı ve Profil Durumu <span class="badge badge-live">Canlı State</span></h2>
      <div class="stat-row"><span class="stat-label">Kullanıcı Adı:</span><span class="stat-val" id="uName">—</span></div>
      <div class="stat-row"><span class="stat-label">Klanı:</span><span class="stat-val" id="uClan">—</span></div>
      <div class="stat-row"><span class="stat-label">Bugün Adım:</span><span class="stat-val" id="uSteps" style="color: #34d399; font-size: 16px;">0</span></div>
      <div class="stat-row"><span class="stat-label">Seri (Streak):</span><span class="stat-val" id="uStreak">0 Gün 🔥</span></div>
      <div class="stat-row"><span class="stat-label">Altın Bakiyesi:</span><span class="stat-val" id="uGold" style="color: #fbbf24;">0 🪙</span></div>
      <div class="stat-row"><span class="stat-label">Haftalık Puan:</span><span class="stat-val" id="uWeekPts">0 P</span></div>
      <div class="stat-row"><span class="stat-label">Tüm Zamanlar:</span><span class="stat-val" id="uAllPts">0 P</span></div>
      <div class="stat-row"><span class="stat-label">Önlenen CO₂:</span><span class="stat-val" id="uCo2">0.0 kg</span></div>
      <div class="stat-row"><span class="stat-label">Harcanan CO₂ (Ceza):</span><span class="stat-val" id="uWasted" style="color: #fb7185;">0.0 kg</span></div>
      <div class="stat-row"><span class="stat-label">Araba/Taksi Yolculuğu:</span><span class="stat-val" id="uTrips">0</span></div>
      <div class="stat-row"><span class="stat-label">Teknik Cihaz ID:</span><span class="stat-val" id="uDeviceId" style="font-size: 10px; font-family: monospace;">—</span></div>
    </div>

    <!-- SENSÖR VE DOĞRULAMA TELEMETRİSİ -->
    <div class="card">
      <h2>📡 Sensör Telemetrisi & Karar Pencereleri <span class="badge badge-live">Hardware</span></h2>
      <div class="stat-row"><span class="stat-label">Donanım Sayaç Toplamı:</span><span class="stat-val" id="telRawSteps">—</span></div>
      <div class="stat-row"><span class="stat-label">Sayaç Tabanı (Baseline):</span><span class="stat-val" id="telBaseline">—</span></div>
      <div class="stat-row"><span class="stat-label">Ham Sayaç Deltası:</span><span class="stat-val" id="telDelta">0</span></div>
      <div class="stat-row"><span class="stat-label">Bekleyen Pencere:</span><span class="stat-val" id="telPending" style="color: #38bdf8;">0 adım</span></div>
      <div class="stat-row"><span class="stat-label">Doğrulanan Gerçek Adım:</span><span class="stat-val" id="telVerified">0 adım</span></div>
      <div class="stat-row"><span class="stat-label">İvmeölçer Olay Sayısı:</span><span class="stat-val" id="telAccelCount">0 event</span></div>
      <div class="stat-row"><span class="stat-label">Son İvme Varyansı:</span><span class="stat-val" id="telAccelVar">—</span></div>
      <div class="stat-row"><span class="stat-label">GPS Servis Durumu:</span><span class="stat-val" id="telGpsStatus">—</span></div>
      <div class="stat-row"><span class="stat-label">GPS Fix Hassasiyeti:</span><span class="stat-val" id="telGpsAcc">—</span></div>
      <div class="stat-row"><span class="stat-label">Son Doğrulama Kararı:</span><span class="stat-val" id="telVerdict" style="color: #34d399;">—</span></div>
      <div class="stat-row"><span class="stat-label">Pencere Durumu:</span><span class="stat-val" id="telWindowStatus" style="font-size: 11px;">—</span></div>
    </div>
  </div>

  <!-- GM KOMUT KONTROLLERİ -->
  <div class="grid">
    <div class="card">
      <h2>⚙️ Parametreli Adım / Streak / Altın Kontrolleri</h2>
      
      <!-- Adım -->
      <div class="form-group">
        <span style="width: 70px; font-size: 13px;">Adım:</span>
        <input type="number" id="inStepAdd" value="334" min="1" step="1">
        <button class="btn-emerald" onclick="cmdAddSteps()">+X Adım Ekle</button>
        <input type="number" id="inStepSet" value="6666" min="0" step="1">
        <button class="btn-outline" onclick="cmdSetSteps()">X Yap (Set)</button>
      </div>

      <!-- Streak -->
      <div class="form-group">
        <span style="width: 70px; font-size: 13px;">Streak:</span>
        <input type="number" id="inStreakAdd" value="1" min="1" step="1">
        <button class="btn-amber" onclick="cmdAddStreak()">+Y Gün Ekle</button>
        <input type="number" id="inStreakSet" value="5" min="0" step="1">
        <button class="btn-outline" onclick="cmdSetStreak()">Y Yap (Set)</button>
      </div>

      <!-- Altın -->
      <div class="form-group">
        <span style="width: 70px; font-size: 13px;">Altın:</span>
        <input type="number" id="inGoldAdd" value="1000" min="1" step="1">
        <button class="btn-amber" onclick="cmdAddGold()">+Z Altın Ekle</button>
        <input type="number" id="inGoldSet" value="500" min="0" step="1">
        <button class="btn-outline" onclick="cmdSetGold()">Z Yap (Set)</button>
      </div>

      <div style="margin-top: 14px; border-top: 1px solid var(--card-border); padding-top: 10px;">
        <button class="btn-outline" style="width: 100%;" onclick="cmdFlushSteps()">⏳ Bekleyen 30sn Adım Penceresini Hemen Doğrula</button>
      </div>
    </div>

    <!-- TEST SENARYOLARI VE CEZA DENETİMLERİ -->
    <div class="card">
      <h2>🎯 Deterministik Jüri / Demo Senaryoları</h2>
      <div class="btn-grid">
        <button class="btn-rose" onclick="cmdTaxiIsolated()">🚕 68 km/sa Taksi (İzole Ceza)</button>
        <button class="btn-outline" onclick="cmdTaxiNormal()">🚕 68 km/sa Taksi (Muafiyetli Test)</button>
        <button class="btn-emerald" onclick="cmdTransit101()">🚌 TRB-BLD-101 Otobüs (+3 P)</button>
        <button class="btn-rose" onclick="cmdBikeSpeedSpoof()">🚴 72 km/sa Bisiklet (Hız Reddi)</button>
        <button class="btn-rose" onclick="cmdBikeVibration()">🚴 Titreşimsiz 28 km/sa (Araba)</button>
        <button class="btn-amber" onclick="cmdSettleWeek()">👑 Haftayı Kapat (Puan->Altın)</button>
      </div>

      <div style="margin-top: 14px;">
        <span style="font-size: 12px; color: var(--muted);">Özel Bildirim Gönder:</span>
        <div class="form-group" style="margin-top: 6px;">
          <input type="text" id="inNotifyText" value="Zeynep seni geçti, sen de anca yat!">
          <button onclick="cmdSendNotify()">Gönder</button>
        </div>
      </div>
    </div>
  </div>

  <!-- CANLI OLAY GÜNLÜĞÜ -->
  <div class="card">
    <h2>📜 AppStore Olay Günlüğü (Son 25 Olay)</h2>
    <div id="logContainer" style="max-height: 280px; overflow-y: auto; margin-top: 10px;"></div>
  </div>

  <script>
    // Token URL'den veya sessionStorage'dan alınır; tarayıcı geçmişinden temizlenir
    const urlParams = new URLSearchParams(window.location.search);
    let sessionToken = urlParams.get('token') || sessionStorage.getItem('gm_token') || '';
    if (urlParams.has('token')) {
      sessionStorage.setItem('gm_token', sessionToken);
      // URL'deki token parametresini geçmişten temizle (güvenlik)
      const cleanUrl = window.location.pathname;
      window.history.replaceState({}, document.title, cleanUrl);
    }

    let autoInterval = null;

    function showBanner(msg, isOk) {
      const b = document.getElementById('msgBanner');
      b.className = 'banner ' + (isOk ? 'banner-success' : 'banner-error');
      b.innerHTML = (isOk ? '✅ ' : '⚠️ ') + msg;
      b.style.display = 'block';
      setTimeout(() => { b.style.display = 'none'; }, 6000);
    }

    async function postCmd(cmd, params = {}) {
      const idempotencyKey = 'gm_' + Date.now() + '_' + Math.random().toString(36).substring(2, 8);
      try {
        const res = await fetch('/api/command', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-GM-Token': sessionToken
          },
          body: JSON.stringify({ cmd, params, idempotencyKey })
        });
        const data = await res.json();
        showBanner(data.message || (data.ok ? 'Başarılı' : 'Hata'), data.ok);
        loadState();
        return data;
      } catch (e) {
        showBanner('Bağlantı hatası: ' + e.message, false);
      }
    }

    async function loadState() {
      try {
        const res = await fetch('/api/state', {
          headers: { 'X-GM-Token': sessionToken }
        });
        if (res.status === 401) {
          showBanner('Yetkisiz: Geçersiz token!', false);
          return;
        }
        const data = await res.json();
        renderState(data);
      } catch (e) {
        console.error('State yüklenemedi:', e);
      }
    }

    function renderState(data) {
      const u = data.user || {};
      const tel = data.telemetry || {};
      const st = tel.steps || {};
      const acc = tel.accelerometer || {};
      const gps = tel.gps || {};
      const val = tel.validation || {};

      document.getElementById('uName').innerText = u.username || '—';
      document.getElementById('uClan').innerText = u.clanName || '—';
      document.getElementById('uSteps').innerText = (u.todaySteps || 0).toLocaleString() + ' Adım';
      document.getElementById('uStreak').innerText = (u.streakDays || 0) + ' Gün 🔥';
      document.getElementById('uGold').innerText = (u.goldCoins || 0).toLocaleString() + ' 🪙';
      document.getElementById('uWeekPts').innerText = (u.weeklyPoints || 0) + ' P';
      document.getElementById('uAllPts').innerText = (u.allTimePoints || 0) + ' P';
      document.getElementById('uCo2').innerText = (u.preventedCo2Kg || 0).toFixed(2) + ' kg';
      document.getElementById('uWasted').innerText = (u.weeklyWastedCo2Kg || 0).toFixed(2) + ' kg';
      document.getElementById('uTrips').innerText = (u.weeklyCarTaxiTrips || 0);
      document.getElementById('uDeviceId').innerText = u.deviceId || '—';

      document.getElementById('telRawSteps').innerText = st.rawTotal !== null && st.rawTotal !== undefined ? st.rawTotal : 'Sayaç yok/okunmadı';
      document.getElementById('telBaseline').innerText = st.baseline !== null && st.baseline !== undefined ? st.baseline : 'Taban yok';
      document.getElementById('telDelta').innerText = '+' + (st.delta || 0);
      document.getElementById('telPending').innerText = (st.pendingWindow || 0) + ' adım';
      document.getElementById('telVerified').innerText = st.hasUserWalkedTest ? (st.verifiedToday + ' adım') : '0 adım (Kullanıcı adımı bekleniyor)';
      
      document.getElementById('telAccelCount').innerText = (acc.eventCount || 0) + ' callback' + (acc.isLive ? ' (CANLI 🟢)' : '');
      document.getElementById('telAccelVar').innerText = acc.lastVariance !== null && acc.lastVariance !== undefined ? acc.lastVariance.toFixed(4) : '—';
      document.getElementById('telGpsStatus').innerText = gps.status || 'Bilinmiyor';
      document.getElementById('telGpsAcc').innerText = gps.accuracyM ? (gps.accuracyM.toFixed(1) + ' m') : 'Fix yok';
      document.getElementById('telVerdict').innerText = val.verdict || '—';
      document.getElementById('telWindowStatus').innerText = val.windowStatus || '—';

      // Log render
      const logCont = document.getElementById('logContainer');
      const logs = data.log || [];
      if (logs.length === 0) {
        logCont.innerHTML = '<p style="color: var(--muted); font-size: 12px;">Henüz olay kaydı yok.</p>';
      } else {
        logCont.innerHTML = logs.map(e => `
          <div class="log-entry">
            <div class="log-title">${e.d ? '<span class="badge badge-demo">DEMO</span> ' : '<span class="badge badge-live">GERÇEK</span> '}${e.t}</div>
            <div class="log-body">${e.b}</div>
          </div>
        `).join('');
      }
    }

    function toggleAuto() {
      const checked = document.getElementById('autoRefresh').checked;
      if (checked && !autoInterval) {
        autoInterval = setInterval(loadState, 2000);
      } else if (!checked && autoInterval) {
        clearInterval(autoInterval);
        autoInterval = null;
      }
    }

    // Komut handlerları
    function cmdAddSteps() {
      const n = parseInt(document.getElementById('inStepAdd').value) || 334;
      postCmd('add_steps', { count: n });
    }
    function cmdSetSteps() {
      const n = parseInt(document.getElementById('inStepSet').value) || 0;
      postCmd('set_steps', { total: n });
    }
    function cmdAddStreak() {
      const n = parseInt(document.getElementById('inStreakAdd').value) || 1;
      postCmd('add_streak', { days: n });
    }
    function cmdSetStreak() {
      const n = parseInt(document.getElementById('inStreakSet').value) || 0;
      postCmd('set_streak', { days: n });
    }
    function cmdAddGold() {
      const n = parseInt(document.getElementById('inGoldAdd').value) || 1000;
      postCmd('add_gold', { amount: n });
    }
    function cmdSetGold() {
      const n = parseInt(document.getElementById('inGoldSet').value) || 0;
      postCmd('set_gold', { total: n });
    }
    function cmdFlushSteps() {
      postCmd('flush_pending_steps');
    }
    function cmdTransit101() {
      postCmd('scan_transit', { payload: 'YESILADIM://TRANSIT/TRB-BLD-101', source: 'GM_PANEL' });
    }
    function cmdTaxiIsolated() {
      postCmd('evaluate_vehicle', { avgSpeedKmh: 68.0, distanceKm: 8.5, stepDelta: 0, ignoreTransitExemption: true });
    }
    function cmdTaxiNormal() {
      postCmd('evaluate_vehicle', { avgSpeedKmh: 68.0, distanceKm: 8.5, stepDelta: 0, ignoreTransitExemption: false });
    }
    function cmdBikeSpeedSpoof() {
      postCmd('evaluate_bike', { distanceKm: 5.0, maxSpeedKmh: 72.0, avgSpeedKmh: 40.0 });
    }
    function cmdBikeVibration() {
      postCmd('evaluate_bike', { distanceKm: 4.0, maxSpeedKmh: 30.0, avgSpeedKmh: 28.0, fastAccelVariance: 0.05 });
    }
    function cmdSettleWeek() {
      if (confirm('Bu haftayı kapatıp puanları altına dönüştürmek istiyor musunuz?')) {
        postCmd('settle_week');
      }
    }
    function cmdSendNotify() {
      const text = document.getElementById('inNotifyText').value || 'Yeşil Adım GM Bildirimi';
      postCmd('notify', { title: 'Yeşil Adım GM', body: text });
    }

    loadState();
    toggleAuto();
  </script>
</body>
</html>
''';
}
