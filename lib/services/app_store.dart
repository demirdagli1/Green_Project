import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/demo_data.dart';
import '../models/app_user.dart';
import '../models/clan.dart';
import '../models/shop_item.dart';
import '../models/transit_stop.dart';
import 'activity_validation_service.dart';
import 'auto_motion_engine.dart';
import 'auto_transport_classifier.dart';
import 'sensor_telemetry.dart';
import 'storage.dart';
import 'supabase_service.dart';

/// Eylem sonucu. [ok] false ise durum/puan değişmemiştir.
class ActionResult {
  final bool ok;
  final bool duplicate;
  final String message;
  final int points;
  final double co2Kg;
  const ActionResult(this.ok, this.message, {this.points = 0, this.co2Kg = 0, this.duplicate = false});
}

class LogEntry {
  final String title;
  final String body;
  final int tsMs;
  final bool demo;
  const LogEntry(this.title, this.body, this.tsMs, this.demo);
  Map<String, dynamic> toJson() => {'t': title, 'b': body, 'ts': tsMs, 'd': demo};
  factory LogEntry.fromJson(Map<String, dynamic> j) =>
      LogEntry(j['t'] as String, j['b'] as String, (j['ts'] as num).toInt(), j['d'] as bool? ?? false);
}

class BikeSession {
  final String tripId;
  final int startMs;
  final bool isAuto;
  bool paused = false;
  double distanceM = 0;
  double maxKmh = 0;
  double currentKmh = 0;
  int movingMs = 0;
  int validFixes = 0;
  int jumps = 0;
  int lowAccuracy = 0;
  _Fix? last;
  final List<double> fastVariances = [];
  BikeSession(this.tripId, this.startMs, {this.isAuto = false});
  double get distanceKm => distanceM / 1000.0;
  double get avgKmh => movingMs > 0 ? (distanceM / (movingMs / 1000.0)) * 3.6 : 0;
}

class _Fix {
  final double lat, lon;
  final int ts;
  final double accuracy;
  const _Fix(this.lat, this.lon, this.ts, this.accuracy);
}

/// Yerel kalıcı durum + iş kuralları. CANLI BACKEND YOKTUR (Supabase uygulanmadı):
/// tüm veri cihazda saklanır; cihazlar arası senkron/Realtime/admin bildirimi garantisi yoktur.
class AppStore extends ChangeNotifier {
  static AppStore? _instance;
  static AppStore get instance => _instance ??= AppStore(backend: MemoryStore());
  static set instance(AppStore s) => _instance = s;

  static const String storageKey = 'app_state_v2';
  static const int currentSeedVersion = 3;
  static const double demoTreeCo2Kg = 2.0; // YALNIZCA demo eşdeğer; bilimsel katsayı değil

  final KeyValueStore backend;
  final DateTime Function() clock;
  final Future<bool> Function(String title, String body)? systemNotify;
  final ActivityValidationService rules = const ActivityValidationService();

  AppStore({required this.backend, DateTime Function()? clock, this.systemNotify})
      : clock = clock ?? DateTime.now {
    autoMotion.addListener(notifyListeners);
  }

  // ---- durum ----
  bool loaded = false;
  int seedVersion = currentSeedVersion;
  AppUser? me;
  List<AppUser> demoUsers = List.of(DemoData.users());
  List<Clan> clans = List.of(DemoData.clans());
  List<AppUser> serverUsers = [];
  final Set<String> owned = {'default_avatar'};
  final Map<String, int> transitLast = {};
  final List<String> processed = [];
  String dayId = '';
  String weekId = '';
  String? lastStreakDay;
  String? lastShamePokeDate;
  int dayRewardedThousands = 0;
  int? stepBaseline;
  int stepBaselineMs = 0;
  String championUser = '—';
  String championClan = '—';
  final Set<String> settledWeeks = {};
  List<LogEntry> log = [];
  int totalCarTaxiTripsAllTime = 0;
  final SensorTelemetry telemetry = SensorTelemetry();
  late final AutoMotionEngine autoMotion = AutoMotionEngine(this);

  int pendingWindowSteps = 0;
  Timer? _stepWindowTimer;
  int? _windowStartMs;

  // geçici (kalıcı olmayan) sensör durumu
  BikeSession? bike;
  final List<_Fix> _fixes = [];
  double? _shakeHz;
  int _shakeMs = 0;

  List<ShopItem> get shopItems => DemoData.shopItems;
  List<TransitStop> get stops => DemoData.stops;

  // ---------- zaman ----------
  static const Duration _tz = Duration(hours: 3); // Europe/Istanbul sabit UTC+3 (2016'dan beri DST yok)
  DateTime get _istanbul => clock().toUtc().add(_tz);
  int get _nowMs => clock().millisecondsSinceEpoch;

  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String dayIdOf(DateTime utcPlus3) => _fmt(utcPlus3);

  /// Pazartesi 00:00 (Europe/Istanbul) hafta kimliği.
  static String weekIdOf(DateTime utcPlus3) {
    final d = DateTime.utc(utcPlus3.year, utcPlus3.month, utcPlus3.day);
    return _fmt(d.subtract(Duration(days: d.weekday - 1)));
  }

  static String nextWeekId(String id) => _fmt(DateTime.parse('${id}T00:00:00Z').add(const Duration(days: 7)));

  // ---------- yükleme / kayıt ----------
  Future<void> load() async {
    final raw = await backend.read(storageKey);
    if (raw != null) {
      try {
        _decode(jsonDecode(raw) as Map<String, dynamic>);
      } catch (e) {
        debugPrint('Kayıt okunamadı, temiz başlangıç: $e');
      }
    }
    _applyDataMigrationIfNeeded();
    if (dayId.isEmpty) {
      dayId = dayIdOf(_istanbul);
      weekId = weekIdOf(_istanbul);
    }
    _sync();
    loaded = true;
    notifyListeners();
  }

  void _applyDataMigrationIfNeeded() {
    if (seedVersion >= currentSeedVersion) {
      return;
    }

    // 1. Gerçek kullanıcı profili ('me') ve tüm alanları KORUNUR (Sen Efe ile ASLA ezilmez).
    // 2. Demo kullanıcıları SQL verisinden yüklenir (Sen (Efe) isDemo=true olan demo kaydıdır).
    demoUsers = List.of(DemoData.users());

    // 3. Klanlar: SQLdeki 11 klan güncellenir, SQL dışı mevcut klanlar (ör. Yalnız Gezginler) ve kullanıcının klan katkıları korunur.
    final defaultClans = DemoData.clans();
    final Map<String, Clan> clanMap = {for (final c in defaultClans) c.id: c};

    for (final oldClan in clans) {
      if (!clanMap.containsKey(oldClan.id)) {
        clanMap[oldClan.id] = oldClan;
      }
    }

    if (me != null && clanMap.containsKey(me!.clanId)) {
      final userClan = clanMap[me!.clanId]!;
      final userAlreadyCounted = clans.any((c) => c.id == me!.clanId && c.memberCount > userClan.memberCount);
      clanMap[me!.clanId] = userClan.copyWith(
        memberCount: userClan.memberCount + (userAlreadyCounted ? 1 : 0),
        weeklyPoints: userClan.weeklyPoints + me!.weeklyPoints,
        allTimePoints: userClan.allTimePoints + me!.allTimePoints,
      );
    }
    clans = clanMap.values.toList();

    // 4. Envanter: Satın alınmış ürünler korunur ve legacy aliaslar eklenir.
    final aliasesToAdd = <String>{};
    for (final id in owned) {
      final alias = DemoData.legacyItemAliases[id];
      if (alias != null) aliasesToAdd.add(alias);
      final rev = DemoData.itemToLegacyAliases[id];
      if (rev != null) aliasesToAdd.add(rev);
    }
    owned.addAll(aliasesToAdd);

    seedVersion = currentSeedVersion;
    _commit();
  }

  Future<void> _persistChain = Future.value();
  void _commit() {
    final snapshot = jsonEncode(_encode());
    _persistChain = _persistChain.then((_) => backend.write(storageKey, snapshot)).catchError((Object e) {
      debugPrint('Kayıt hatası: $e');
    });
    notifyListeners();
  }

  /// Bekleyen yazmaların bitmesini bekler (test/kapanış).
  Future<void> flush() => _persistChain;

  void commitDirect() {
    _commit();
  }

  Map<String, dynamic> _encode() => {
        'seedVersion': seedVersion,
        'me': me?.toJson(),
        'demoUsers': demoUsers.map((u) => u.toJson()).toList(),
        'clans': clans.map((c) => c.toJson()).toList(),
        'owned': owned.toList(),
        'transitLast': transitLast,
        'processed': processed,
        'dayId': dayId,
        'weekId': weekId,
        'lastStreakDay': lastStreakDay,
        'lastShamePokeDate': lastShamePokeDate,
        'dayRewardedThousands': dayRewardedThousands,
        'stepBaseline': stepBaseline,
        'stepBaselineMs': stepBaselineMs,
        'championUser': championUser,
        'championClan': championClan,
        'settledWeeks': settledWeeks.toList(),
        'log': log.map((e) => e.toJson()).toList(),
        'totalCarTaxi': totalCarTaxiTripsAllTime,
      };

  void _decode(Map<String, dynamic> j) {
    seedVersion = (j['seedVersion'] as num?)?.toInt() ?? 1;
    me = j['me'] == null ? null : AppUser.fromJson(j['me'] as Map<String, dynamic>);
    demoUsers = (j['demoUsers'] as List).map((e) => AppUser.fromJson(e as Map<String, dynamic>)).toList();
    clans = (j['clans'] as List).map((e) => Clan.fromJson(e as Map<String, dynamic>)).toList();
    owned
      ..clear()
      ..addAll((j['owned'] as List).cast<String>());
    transitLast
      ..clear()
      ..addAll((j['transitLast'] as Map).map((k, v) => MapEntry(k as String, (v as num).toInt())));
    processed
      ..clear()
      ..addAll((j['processed'] as List).cast<String>());
    dayId = j['dayId'] as String? ?? '';
    weekId = j['weekId'] as String? ?? '';
    lastStreakDay = j['lastStreakDay'] as String?;
    lastShamePokeDate = j['lastShamePokeDate'] as String?;
    dayRewardedThousands = (j['dayRewardedThousands'] as num?)?.toInt() ?? 0;
    stepBaseline = (j['stepBaseline'] as num?)?.toInt();
    stepBaselineMs = (j['stepBaselineMs'] as num?)?.toInt() ?? 0;
    championUser = j['championUser'] as String? ?? '—';
    championClan = j['championClan'] as String? ?? '—';
    settledWeeks
      ..clear()
      ..addAll((j['settledWeeks'] as List).cast<String>());
    log = (j['log'] as List).map((e) => LogEntry.fromJson(e as Map<String, dynamic>)).toList();
    totalCarTaxiTripsAllTime = (j['totalCarTaxi'] as num?)?.toInt() ?? 0;
  }

  // ---------- onboarding ----------
  bool get hasProfile => me != null;

  /// Gerçek kullanıcı oluşturur (demo "Efe" kimliği KULLANILMAZ). Zaten varsa değiştirmez.
  ActionResult register({required String deviceId, required String name, required String clanName}) {
    if (me != null) return const ActionResult(false, 'Profil zaten var.', duplicate: true);
    final n = name.trim();
    if (n.isEmpty) return const ActionResult(false, 'İsim boş olamaz.');
    final idx = clans.indexWhere((c) => c.name == clanName);
    if (idx < 0) return const ActionResult(false, 'Klan bulunamadı.');
    me = AppUser(id: 'me_$deviceId', deviceId: deviceId, username: n, clanId: clans[idx].id, clanName: clans[idx].name);
    clans[idx] = clans[idx].copyWith(memberCount: clans[idx].memberCount + 1);
    SupabaseService.instance.syncInitialProfile(this);
    _commit();
    return const ActionResult(true, 'Hoş geldin!');
  }

  // ---------- periyotlar ----------
  void _sync() {
    final today = dayIdOf(_istanbul);
    if (dayId.isNotEmpty && dayId != today) {
      final yesterday = _fmt(DateTime.parse('${today}T00:00:00Z').subtract(const Duration(days: 1)));
      if (me != null) {
        var u = me!;
        if (lastStreakDay != null && lastStreakDay != yesterday && lastStreakDay != today) {
          u = u.copyWith(streakDays: 0);
        }
        me = u.copyWith(todaySteps: 0);
      }
      dayRewardedThousands = 0;
      dayId = today;
    }
    final realWeek = weekIdOf(_istanbul);
    while (weekId.isNotEmpty && weekId.compareTo(realWeek) < 0) {
      _settle(weekId);
    }
  }

  /// Dışarıdan (ör. uygulama öne gelince) periyot kontrolü.
  void tick() {
    _sync();
    _commit();
  }

  // ---------- puan ----------
  void _award(int points, {double co2 = 0}) {
    if (me == null) return;
    var u = me!;
    me = u.copyWith(
      weeklyPoints: u.weeklyPoints + points,
      allTimePoints: u.allTimePoints + points,
      preventedCo2Kg: u.preventedCo2Kg + co2,
    );
    final i = clans.indexWhere((c) => c.id == u.clanId);
    if (i >= 0 && points != 0) {
      clans[i] = clans[i].copyWith(
        weeklyPoints: clans[i].weeklyPoints + points,
        allTimePoints: clans[i].allTimePoints + points,
      );
    }
  }

  void _note(String title, String body, {bool demo = false}) {
    log.insert(0, LogEntry(title, body, _nowMs, demo));
    if (log.length > 40) log.removeRange(40, log.length);
    systemNotify?.call(title, body);
  }

  bool _seen(String id) => processed.contains(id);
  void _mark(String id) {
    processed.add(id);
    if (processed.length > 500) processed.removeRange(0, processed.length - 500);
  }

  bool get hasSentShameMessageToday => lastShamePokeDate == dayId;

  void markShameMessageSent() {
    lastShamePokeDate = dayId;
    _commit();
  }

  void resetShameQuota() {
    lastShamePokeDate = null;
    _commit();
  }

  // ---------- adım ----------
  ActionResult _creditSteps(int delta, {required bool demo}) {
    var u = me!;
    final newTotal = u.todaySteps + delta;
    final thousands = newTotal ~/ 1000;
    final pts = (thousands - dayRewardedThousands) > 0 ? (thousands - dayRewardedThousands) * 5 : 0;
    dayRewardedThousands = thousands > dayRewardedThousands ? thousands : dayRewardedThousands;
    var streak = u.streakDays;
    final today = dayId;
    if (newTotal >= 6000 && lastStreakDay != today) {
      final yesterday = _fmt(DateTime.parse('${today}T00:00:00Z').subtract(const Duration(days: 1)));
      streak = (lastStreakDay == yesterday) ? streak + 1 : 1;
      lastStreakDay = today;
    }
    me = u.copyWith(todaySteps: newTotal, streakDays: streak);
    _award(pts);
    if (pts > 0) _note('🎯 +$pts puan', '$newTotal adıma ulaştın.', demo: demo);
    if (!demo && delta > 0) {
      SupabaseService.instance.recordSteps(
        stepCount: delta,
        distanceKm: delta * 0.00075,
        pointsEarned: pts,
        co2SavedKg: 0.0,
      );
    }
    _commit();
    return ActionResult(true, pts > 0 ? '+$pts puan' : 'Adım eklendi', points: pts);
  }

  ActionResult flushPendingStepsWindow() {
    _stepWindowTimer?.cancel();
    _stepWindowTimer = null;
    if (me == null || pendingWindowSteps <= 0) {
      telemetry.windowStatus = 'Boşta / bekleyen adım yok';
      return const ActionResult(false, 'Bekleyen adım yok.');
    }
    final now = _nowMs;
    final start = _windowStartMs ?? stepBaselineMs;
    final elapsedMs = now - start;
    final minutes = elapsedMs > 0 ? elapsedMs / 60000.0 : 0.5;

    final verdict = rules.checkSteps(
      deltaSteps: pendingWindowSteps,
      minutes: minutes,
      shakeHz: _freshShake(),
      gpsMovementMeters: gpsPathMeters(),
    );

    final stepsToCommit = pendingWindowSteps;
    final currentTotal = (stepBaseline ?? 0) + pendingWindowSteps;
    stepBaseline = currentTotal;
    stepBaselineMs = now;
    _windowStartMs = now;
    pendingWindowSteps = 0;
    telemetry.pendingStepsWindow = 0;
    telemetry.stepBaseline = stepBaseline;
    telemetry.lastValidationTs = now;
    telemetry.lastValidationOk = verdict.ok;
    telemetry.lastValidationVerdict = verdict.ok ? 'Onaylandı (+${stepsToCommit ~/ 1000 * 5} P)' : verdict.message;

    if (!verdict.ok) {
      telemetry.windowStatus = 'Reddedildi: ${verdict.message}';
      _note('⚠️ Adım reddedildi', verdict.message);
      _commit();
      return ActionResult(false, verdict.message);
    }

    telemetry.windowStatus = 'Doğrulandı ($stepsToCommit adım eklendi)';
    telemetry.verifiedStepsToday = (me?.todaySteps ?? 0) + stepsToCommit;
    return _creditSteps(stepsToCommit, demo: false);
  }

  /// GERÇEK sensör (TYPE_STEP_COUNTER toplamı). Cihaz yeniden başlatma (azalma) puan üretmez.
  ActionResult onSensorSteps(int total) {
    if (me == null) return const ActionResult(false, 'Profil yok.');
    _sync();
    final now = _nowMs;
    telemetry.rawStepTotal = total;
    telemetry.lastStepEventTs = now;
    autoMotion.onSensorSteps(total);
    telemetry.autoMotion = autoMotion.toJson();

    if (autoMotion.isAutoSessionActive) {
      // Bisiklet sürüşü esnasındaki pedal adımları yürüyüş ödülüne katılmayarak çift ödül önlenir
      stepBaseline = total;
      pendingWindowSteps = 0;
      telemetry.pendingStepsWindow = 0;
      telemetry.windowStatus = 'Bisiklet sürüşü aktif: Adım ödülü bastırıldı (çift ödül koruması)';
      notifyListeners();
      return const ActionResult(false, 'Bisiklet sürüşü aktif; adım bonusu bastırıldı.');
    }

    if (stepBaseline == null || total < stepBaseline!) {
      stepBaseline = total;
      stepBaselineMs = now;
      _windowStartMs = now;
      pendingWindowSteps = 0;
      telemetry.stepBaseline = total;
      telemetry.rawStepDelta = 0;
      telemetry.pendingStepsWindow = 0;
      telemetry.windowStatus = 'Sayaç (yeniden) başlatıldı; ilk taban çizgi kaydedildi.';
      _commit();
      return const ActionResult(false, 'Sayaç (yeniden) başlatıldı; puan yok.');
    }
    final delta = total - stepBaseline!;
    telemetry.stepBaseline = stepBaseline;
    telemetry.rawStepDelta = delta;

    if (delta == 0) return const ActionResult(false, 'Tekrarlanan olay.', duplicate: true);

    _windowStartMs ??= stepBaselineMs;
    final elapsedMs = now - _windowStartMs!;
    pendingWindowSteps = delta;
    telemetry.pendingStepsWindow = pendingWindowSteps;

    if (elapsedMs < 30000) {
      telemetry.windowStatus = 'Pencere doluyor ($pendingWindowSteps adım bekliyor, ${(30 - elapsedMs ~/ 1000)} sn)';
      _stepWindowTimer?.cancel();
      final remainingMs = 30000 - elapsedMs;
      _stepWindowTimer = Timer(Duration(milliseconds: remainingMs + 100), () {
        flushPendingStepsWindow();
      });
      notifyListeners();
      return const ActionResult(false, 'Pencere dolmadı.');
    }

    return flushPendingStepsWindow();
  }

  /// DEMO: sensör değil, jüri simülasyonu.
  ActionResult demoAddSteps(int n) {
    if (me == null || n <= 0) return const ActionResult(false, 'Geçersiz.');
    _sync();
    return _creditSteps(n, demo: true);
  }

  // ---------- ivme / GPS ----------
  void onAccel({required double freqHz, required double variance, int sampleCount = 1}) {
    if (freqHz.isNaN || variance.isNaN || variance < 0) return;
    autoMotion.onAccel(freqHz: freqHz, variance: variance);
    _shakeHz = freqHz;
    _shakeMs = _nowMs;
    telemetry.accelEventCount++;
    telemetry.accelSampleCount += sampleCount;
    telemetry.lastAccelFreqHz = freqHz;
    telemetry.lastAccelVariance = variance;
    telemetry.lastAccelEventTs = _nowMs;
    telemetry.autoMotion = autoMotion.toJson();
    final b = bike;
    if (b != null && !b.paused && b.currentKmh > 25) b.fastVariances.add(variance);
    notifyListeners();
  }

  double? _freshShake() => (_nowMs - _shakeMs) <= 20000 ? _shakeHz : null;

  void onLocation({
    required double lat,
    required double lon,
    double? speedMps,
    double? accuracy,
    int? tsMs,
    String? provider,
  }) {
    final ts = tsMs ?? _nowMs;
    autoMotion.onLocation(
      lat: lat,
      lon: lon,
      speedMps: speedMps,
      accuracy: accuracy,
      tsMs: ts,
    );
    telemetry.autoMotion = autoMotion.toJson();

    if (lat.isNaN || lon.isNaN || accuracy == null || accuracy.isNaN || accuracy > 30) {
      bike?.lowAccuracy++;
      telemetry.gpsStatus = 'Düşük hassasiyet (>30m) veya geçersiz konum';
      notifyListeners();
      return;
    }
    telemetry.lastLat = lat;
    telemetry.lastLon = lon;
    telemetry.lastAccuracy = accuracy;
    telemetry.lastSpeedKmh = (speedMps != null && speedMps >= 0) ? speedMps * 3.6 : null;
    telemetry.lastGpsFixTs = ts;
    telemetry.gpsProvider = provider;
    telemetry.gpsStatus = 'Fix alındı (${accuracy.toStringAsFixed(1)} m)';

    final fix = _Fix(lat, lon, ts, accuracy);
    _fixes.add(fix);
    _fixes.removeWhere((f) => ts - f.ts > 60000);
    final b = bike;
    if (b != null) _bikeFix(b, fix, speedMps);
    notifyListeners();
  }

  /// Son 60 sn GPS yolu (m); en az 2 doğru fix ve >=20 sn aralık yoksa null (bilinmiyor, 0 DEĞİL).
  double? gpsPathMeters() {
    if (_fixes.length < 2) return null;
    if (_fixes.last.ts - _fixes.first.ts < 20000) return null;
    var d = 0.0;
    for (var i = 1; i < _fixes.length; i++) {
      d += ActivityValidationService.distanceMeters(_fixes[i - 1].lat, _fixes[i - 1].lon, _fixes[i].lat, _fixes[i].lon);
    }
    return d;
  }

  // ---------- toplu taşıma ----------
  /// NFC UID (kolonlu/kolonsuz) veya QR/kod payload'ından kanonik durak bulur.
  TransitStop? findStopByPayload(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    // 1. NFC UID (04:A1:2B:9C:11:80:01 veya 04A12B9C118001 kolonlu/kolonsuz hex)
    final cleanHex = trimmed.replaceAll(':', '').replaceAll('-', '').toUpperCase();
    for (final s in stops) {
      if (s.nfcUid != null) {
        final stopCleanHex = s.nfcUid!.replaceAll(':', '').replaceAll('-', '').toUpperCase();
        if (stopCleanHex == cleanHex) return s;
      }
    }

    // 2. QR payload veya durak kodu (YESILADIM://TRANSIT/TRB-KTU-01?sig=9f8a7b veya TRB-KTU-01)
    final code = rules.parseTransitPayload(raw);
    if (code != null) {
      final found = stops.where((s) => s.code == code).firstOrNull;
      if (found != null) return found;
    }
    return null;
  }

  /// [payload] QR/NFC metni, NFC UID veya çıplak kod. Cooldown durak kodu başına, QR ve NFC ortak.
  ActionResult scanTransit(String? payload, {required String source, DateTime? at}) {
    if (me == null) return const ActionResult(false, 'Profil yok.');
    _sync();
    final stop = findStopByPayload(payload);
    if (stop == null) {
      final code = rules.parseTransitPayload(payload);
      return ActionResult(false, code != null ? 'Bilinmeyen durak: $code' : 'Geçersiz QR/NFC verisi.');
    }
    final code = stop.code;
    final now = at ?? clock();
    final lastMs = transitLast[code];
    final remaining = rules.transitRemaining(
        lastMs == null ? null : DateTime.fromMillisecondsSinceEpoch(lastMs), now);
    if (remaining != null) {
      final mins = (remaining.inSeconds / 60).ceil();
      return ActionResult(false,
          'Aynı otobüsü iki kere mi satın aldın? Sonraki biniş puanı için $mins dk bekle!');
    }
    transitLast[code] = now.millisecondsSinceEpoch;
    _award(stop.pointsReward, co2: stop.co2SavingKg);
    _note('🚌 Biniş onaylandı ($source)', '${stop.name}: +${stop.pointsReward} puan, ${stop.co2SavingKg.toStringAsFixed(2)} kg CO₂ önlendi.');
    SupabaseService.instance.recordTransit(
      stopCode: stop.code,
      verificationMethod: source,
      pointsEarned: stop.pointsReward,
      co2SavedKg: stop.co2SavingKg,
    );
    _commit();
    return ActionResult(true, '+${stop.pointsReward} puan', points: stop.pointsReward, co2Kg: stop.co2SavingKg);
  }

  bool get transitInLast45Min {
    final now = _nowMs;
    return transitLast.values.any((t) => now - t >= 0 && now - t < 45 * 60000);
  }

  /// Otobüs yolculuğu ödülü (+3 puan, CO2 tasarrufu).
  ActionResult creditBusTrip({
    required double distanceKm,
    required int busScore,
    String? explanation,
    bool demo = false,
  }) {
    if (me == null) return const ActionResult(false, 'Profil yok.');
    _sync();
    const pts = 3;
    final co2 = double.parse((distanceKm * (0.192 - 0.035)).toStringAsFixed(2));
    _award(pts, co2: co2);
    transitLast['BUS_TRIP'] = _nowMs;

    final tripEventId = 'bus_${_nowMs}_${Random().nextInt(9999)}';
    if (!demo) {
      unawaited(SupabaseService.instance.recordBusTrip(
        eventId: tripEventId,
        distanceKm: distanceKm,
        busScore: busScore,
        isShortPenalty: false,
        explanation: explanation,
      ));
    }
    _commit();
    final msg = explanation ?? 'Otobüs yolculuğu doğrulandı! (+3 Puan, $co2 kg CO₂ tasarrufu)';
    _note('Otobüs / Dolmuş Doğrulandı', msg);
    return ActionResult(true, msg, points: pts, co2Kg: co2);
  }

  /// Kısa otobüs yolculuğu cezası (0 < mesafe <= 500m -> -3 haftalık puan, 0 CO2).
  ActionResult applyShortBusPenalty({
    required double distanceKm,
    required int busScore,
    String? explanation,
    bool demo = false,
  }) {
    if (me == null) return const ActionResult(false, 'Profil yok.');
    _sync();
    final actualDeducted = min(me!.weeklyPoints, 3);
    _award(-actualDeducted, co2: 0);
    transitLast['BUS_TRIP'] = _nowMs;

    final tripEventId = 'short_bus_${_nowMs}_${Random().nextInt(9999)}';
    if (!demo) {
      unawaited(SupabaseService.instance.recordBusTrip(
        eventId: tripEventId,
        distanceKm: distanceKm,
        busScore: busScore,
        isShortPenalty: true,
        explanation: explanation,
      ));
    }
    _commit();
    final msg = explanation ?? 'Kısa otobüs yolculuğu (≤500m): -$actualDeducted puan ceza kesildi.';
    _note('Kısa Otobüs Cezası', msg);
    return ActionResult(true, msg, points: -actualDeducted, co2Kg: 0.0);
  }

  /// Otomatik aktivite ve toplu taşıma sınıflandırıcısı değerlendirmesi (Revizyon 03).
  ClassificationResult evaluateTransportClassification({
    required double distanceKm,
    required double avgSpeedKmh,
    required double maxSpeedKmh,
    required int stepCadenceSpm,
    required double accelVariance,
    bool userClaimedBikeMode = false,
    bool hasNfcOrQrScan = false,
    bool boardedNearBusStop = false,
    int matchedBusStopDwells = 0,
    int dolmusStyleShortStops = 0,
    bool alightedNearBusStop = false,
    bool isGpsReliable = true,
    double gpsAccuracyMeters = 10.0,
    bool demo = false,
  }) {
    final result = AutoTransportClassifierService.classifySession(
      distanceKm: distanceKm,
      avgSpeedKmh: avgSpeedKmh,
      maxSpeedKmh: maxSpeedKmh,
      stepCadenceSpm: stepCadenceSpm,
      accelVariance: accelVariance,
      userClaimedBikeMode: userClaimedBikeMode,
      hasNfcOrQrScan: hasNfcOrQrScan,
      boardedNearBusStop: boardedNearBusStop,
      matchedBusStopDwells: matchedBusStopDwells,
      dolmusStyleShortStops: dolmusStyleShortStops,
      alightedNearBusStop: alightedNearBusStop,
      isGpsReliable: isGpsReliable,
      gpsAccuracyMeters: gpsAccuracyMeters,
    );

    if (result.activityType == DetectedActivityType.shortBusPenalty) {
      applyShortBusPenalty(
        distanceKm: distanceKm,
        busScore: result.busProbabilityScore,
        explanation: result.explanation,
        demo: demo,
      );
    } else if (result.activityType == DetectedActivityType.publicTransitBus) {
      creditBusTrip(
        distanceKm: distanceKm,
        busScore: result.busProbabilityScore,
        explanation: result.explanation,
        demo: demo,
      );
    }

    notifyListeners();
    return result;
  }

  // ---------- bisiklet ----------
  BikeSession startBike({String? tripId}) {
    final b = BikeSession(tripId ?? 'bike_$_nowMs', _nowMs);
    bike = b;
    notifyListeners();
    return b;
  }

  void pauseBike() {
    if (bike != null) {
      bike!.paused = true;
      bike!.last = null;
      notifyListeners();
    }
  }

  void resumeBike() {
    if (bike != null) {
      bike!.paused = false;
      bike!.last = null;
      notifyListeners();
    }
  }

  void _bikeFix(BikeSession b, _Fix f, double? speedMps) {
    if (b.paused) return;
    final last = b.last;
    b.last = f;
    if (last == null) {
      b.validFixes++;
      return;
    }
    final dt = (f.ts - last.ts) / 1000.0;
    if (dt <= 0) return;
    final d = ActivityValidationService.distanceMeters(last.lat, last.lon, f.lat, f.lon);
    final derivedKmh = d / dt * 3.6;
    if (derivedKmh > 150) {
      b.jumps++; // GPS sıçraması: mesafeye katma
      return;
    }
    final kmh = (speedMps != null && !speedMps.isNaN && speedMps >= 0) ? speedMps * 3.6 : derivedKmh;
    b.validFixes++;
    b.currentKmh = kmh;
    if (kmh > b.maxKmh) b.maxKmh = kmh;
    b.distanceM += d;
    b.movingMs += (dt * 1000).round();
  }

  /// Sürüşü bitirir ve değerlendirir. Aynı tripId ikinci kez işlenmez (çift ödül/ceza yok).
  ActionResult finishBike() {
    final b = bike;
    if (b == null) return const ActionResult(false, 'Aktif sürüş yok.');
    bike = null;
    return evaluateBike(
      tripId: b.tripId,
      distanceKm: b.distanceKm,
      maxSpeedKmh: b.maxKmh,
      avgSpeedKmh: b.avgKmh,
      fastAccelVariance: b.fastVariances.isEmpty
          ? null
          : b.fastVariances.reduce((a, c) => a + c) / b.fastVariances.length,
      validFixes: b.validFixes,
      demo: false,
    );
  }

  ActionResult evaluateBike({
    required String tripId,
    required double distanceKm,
    required double maxSpeedKmh,
    required double avgSpeedKmh,
    double? fastAccelVariance,
    int validFixes = 2,
    required bool demo,
  }) {
    if (me == null) return const ActionResult(false, 'Profil yok.');
    _sync();
    if (_seen(tripId)) return const ActionResult(false, 'Bu yolculuk zaten işlendi.', duplicate: true);
    if (validFixes < 2 && distanceKm == 0) {
      return const ActionResult(false, 'Yetersiz GPS verisi; puan/ceza yok.');
    }
    final v = rules.checkBike(
      distanceKm: distanceKm,
      maxSpeedKmh: maxSpeedKmh,
      avgSpeedKmh: avgSpeedKmh,
      fastAccelVariance: fastAccelVariance,
    );
    _mark(tripId);
    switch (v.status) {
      case BikeStatus.accepted:
        _award(v.points, co2: v.co2SavedKg);
        _note('🚴 Bisiklet tamamlandı', v.message, demo: demo);
        if (!demo) {
          SupabaseService.instance.recordBike(
            tripId: tripId,
            distanceKm: distanceKm,
            avgSpeedKmh: avgSpeedKmh,
            maxSpeedKmh: maxSpeedKmh,
            accelVariance: fastAccelVariance ?? 0.0,
            pointsEarned: v.points,
            co2SavedKg: v.co2SavedKg,
            isSpoof: false,
          );
        }
        _commit();
        return ActionResult(true, v.message, points: v.points, co2Kg: v.co2SavedKg);
      case BikeStatus.carTaxiPenalty:
        _penalty(v.wastedCo2Kg);
        _note('🚨 Araba/taksi cezası', v.message, demo: demo);
        if (!demo) {
          SupabaseService.instance.recordVehiclePenalty(
            tripId: tripId,
            distanceKm: distanceKm,
            wastedCo2Kg: v.wastedCo2Kg,
            avgSpeedKmh: avgSpeedKmh,
          );
        }
        _commit();
        return ActionResult(false, v.message);
      case BikeStatus.rejectedSpeedSpoof:
        _note('❌ Bisiklet reddedildi', v.message, demo: demo);
        if (!demo) {
          SupabaseService.instance.recordBike(
            tripId: tripId,
            distanceKm: distanceKm,
            avgSpeedKmh: avgSpeedKmh,
            maxSpeedKmh: maxSpeedKmh,
            accelVariance: fastAccelVariance ?? 0.0,
            pointsEarned: 0,
            co2SavedKg: 0.0,
            isSpoof: true,
            rejectReason: v.message,
          );
        }
        _commit();
        return ActionResult(false, v.message);
      case BikeStatus.invalidData:
      case BikeStatus.insufficientData:
        _note('❌ Bisiklet reddedildi', v.message, demo: demo);
        _commit();
        return ActionResult(false, v.message);
    }
  }

  void _penalty(double wasted) {
    final u = me!;
    me = u.copyWith(
      weeklyCarTaxiTrips: u.weeklyCarTaxiTrips + 1,
      weeklyWastedCo2Kg: u.weeklyWastedCo2Kg + wasted,
    );
    totalCarTaxiTripsAllTime++;
  }

  /// Araba/taksi değerlendirmesi. Gerçek pasif tespit (arka plan) YOKTUR; yalnız verilen ölçümle çalışır.
  ActionResult evaluateVehicle({
    required String tripId,
    double? avgSpeedKmh,
    double? distanceKm,
    int? stepDelta,
    required bool demo,
    bool ignoreTransitExemption = false,
  }) {
    if (me == null) return const ActionResult(false, 'Profil yok.');
    _sync();
    if (_seen(tripId)) return const ActionResult(false, 'Bu yolculuk zaten işlendi.', duplicate: true);
    final hasTransit = !ignoreTransitExemption && transitInLast45Min;
    final v = rules.checkVehicle(
      avgSpeedKmh: avgSpeedKmh,
      distanceKm: distanceKm,
      stepDelta: stepDelta,
      transitInLast45Min: hasTransit,
    );
    if (!v.detected) return ActionResult(false, v.message);
    _mark(tripId);
    _penalty(v.wastedCo2Kg);
    _note('🚕 Yakalandın!', v.message, demo: demo);
    if (!demo) {
      SupabaseService.instance.recordVehiclePenalty(
        tripId: tripId,
        distanceKm: distanceKm ?? 0.0,
        wastedCo2Kg: v.wastedCo2Kg,
        avgSpeedKmh: avgSpeedKmh ?? 0.0,
      );
    }
    _commit();
    return ActionResult(true, v.message, co2Kg: v.wastedCo2Kg);
  }

  // ---------- mağaza ----------
  /// Aktif katalog, legacy alias ve eski katalogdan ürün bulur.
  ShopItem? findShopItem(String id) {
    var found = shopItems.where((s) => s.id == id).firstOrNull;
    if (found != null) return found;
    final legacy = DemoData.legacyShopItems.where((s) => s.id == id).firstOrNull;
    if (legacy != null) return legacy;
    final alias = DemoData.legacyItemAliases[id];
    if (alias != null) {
      found = shopItems.where((s) => s.id == alias).firstOrNull;
      if (found != null) return found;
    }
    final revAlias = DemoData.itemToLegacyAliases[id];
    if (revAlias != null) {
      found = shopItems.where((s) => s.id == revAlias).firstOrNull;
      if (found != null) return found;
    }
    return null;
  }

  /// Bir ürünün veya legacy aliasının kullanıcıda olup olmadığını kontrol eder.
  bool isItemOwned(String id) {
    if (owned.contains(id)) return true;
    final alias = DemoData.legacyItemAliases[id];
    if (alias != null && owned.contains(alias)) return true;
    final rev = DemoData.itemToLegacyAliases[id];
    if (rev != null && owned.contains(rev)) return true;
    return false;
  }

  ActionResult buy(String itemId) {
    if (me == null) return const ActionResult(false, 'Profil yok.');
    final item = findShopItem(itemId);
    if (item == null) return const ActionResult(false, 'Ürün yok.');
    if (isItemOwned(itemId)) return const ActionResult(false, 'Zaten sahipsin.', duplicate: true);
    if (me!.goldCoins < item.price) return const ActionResult(false, 'Yetersiz altın.');
    me = me!.copyWith(goldCoins: me!.goldCoins - item.price);
    owned.add(item.id);
    owned.add(itemId);
    if (DemoData.legacyItemAliases.containsKey(item.id)) owned.add(DemoData.legacyItemAliases[item.id]!);
    if (DemoData.itemToLegacyAliases.containsKey(item.id)) owned.add(DemoData.itemToLegacyAliases[item.id]!);
    _equip(item);
    SupabaseService.instance.buyShopItem(item.id);
    _commit();
    return ActionResult(true, '${item.title} alındı.');
  }

  ActionResult equip(String itemId) {
    if (me == null) return const ActionResult(false, 'Profil yok.');
    if (itemId == 'default_avatar') {
      me = me!.copyWith(equippedAvatar: 'default_avatar');
      SupabaseService.instance.equipShopItem('default_avatar');
      _commit();
      return const ActionResult(true, 'Varsayılan avatar kuşanıldı.');
    }
    final item = findShopItem(itemId);
    if (item == null) return const ActionResult(false, 'Ürün yok.');
    if (!isItemOwned(itemId)) return const ActionResult(false, 'Ürün kilitli.');
    _equip(item);
    SupabaseService.instance.equipShopItem(itemId);
    _commit();
    return const ActionResult(true, 'Kuşanıldı.');
  }

  void _equip(ShopItem item) {
    switch (item.category) {
      case ShopCategory.avatar:
        me = me!.copyWith(equippedAvatar: item.id);
      case ShopCategory.frame:
        me = me!.copyWith(equippedFrame: item.id);
      case ShopCategory.pet:
        me = me!.copyWith(equippedPet: item.id);
    }
  }

  /// Profil biyografisini günceller (en fazla 160 karakter).
  ActionResult updateBio(String bioText) {
    if (me == null) return const ActionResult(false, 'Profil yok.');
    final trimmed = bioText.trim();
    if (trimmed.runes.length > 160) {
      return const ActionResult(false, 'Biyografi en fazla 160 karakter olabilir.');
    }
    me = me!.copyWith(bio: trimmed);
    SupabaseService.instance.updateBio(trimmed);
    _commit();
    return const ActionResult(true, 'Biyografi güncellendi.');
  }

  /// Profil fotoğrafı yolunu günceller veya temizler.
  ActionResult updateProfilePhoto(String? path) {
    if (me == null) return const ActionResult(false, 'Profil yok.');
    if (path == null) {
      me = me!.copyWith(clearPhoto: true);
      _commit();
      return const ActionResult(true, 'Profil fotoğrafı kaldırıldı.');
    }
    me = me!.copyWith(photoPath: path);
    SupabaseService.instance.uploadProfilePhoto(path);
    _commit();
    return const ActionResult(true, 'Profil fotoğrafı güncellendi.');
  }

  /// DEMO: jüri masası altın.
  ActionResult demoGrantGold(int n) {
    if (me == null || n <= 0) return const ActionResult(false, 'Geçersiz.');
    me = me!.copyWith(goldCoins: me!.goldCoins + n);
    _note('🪙 Demo altın', '+$n altın (demo).', demo: true);
    _commit();
    return ActionResult(true, '+$n altın');
  }

  // ---------- haftalık reset ----------
  /// [weekIdToSettle] UI'nin gösterdiği hafta. Yalnız mevcut hafta kapatılabilir ve her hafta
  /// bir kez; tekrar çağrı false döner ve altın üretmez.
  bool settleWeek(String weekIdToSettle) {
    if (weekIdToSettle != weekId || settledWeeks.contains(weekIdToSettle)) return false;
    _settle(weekIdToSettle);
    _commit();
    return true;
  }

  void _settle(String id) {
    // 1) şampiyonlar reset ÖNCESİ
    final everyone = [if (me != null) me!, ...demoUsers].where((u) => u.weeklyPoints > 0).toList()
      ..sort(compareUsers);
    if (everyone.isNotEmpty) championUser = everyone.first.username;
    final cl = clans.where((c) => c.isEligibleForRanking && c.weeklyPoints > 0).toList()
      ..sort((a, b) => compareClans(a, b, hybrid: true));
    if (cl.isNotEmpty) championClan = cl.first.name;
    // 2) puan → altın (bir kez), haftalık alanlar sıfır; günlük adım/streak/envanter korunur
    AppUser conv(AppUser u) => u.copyWith(
          goldCoins: u.goldCoins + u.weeklyPoints,
          weeklyPoints: 0,
          weeklyCarTaxiTrips: 0,
          weeklyWastedCo2Kg: 0,
        );
    if (me != null) me = conv(me!);
    demoUsers = demoUsers.map(conv).toList();
    clans = clans.map((c) => c.copyWith(weeklyPoints: 0)).toList();
    settledWeeks.add(id);
    weekId = nextWeekId(id);
    _note('👑 Hafta kapandı', 'Puanlar altına çevrildi. Şampiyonlar: $championUser & $championClan');
  }

  // ---------- sıralama ----------
  /// Puan azalan, eşitlikte ad, sonra id (kararlı).
  static int compareUsers(AppUser a, AppUser b) {
    final c = b.weeklyPoints.compareTo(a.weeklyPoints);
    if (c != 0) return c;
    final n = a.username.compareTo(b.username);
    return n != 0 ? n : a.id.compareTo(b.id);
  }

  static int compareClans(Clan a, Clan b, {bool hybrid = true, bool allTime = false}) {
    final av = hybrid ? a.hybridScoreFor(allTime: allTime) : (allTime ? a.allTimePoints.toDouble() : a.weeklyPoints.toDouble());
    final bv = hybrid ? b.hybridScoreFor(allTime: allTime) : (allTime ? b.allTimePoints.toDouble() : b.weeklyPoints.toDouble());
    final c = bv.compareTo(av);
    if (c != 0) return c;
    final n = a.name.compareTo(b.name);
    return n != 0 ? n : a.id.compareTo(b.id);
  }

  List<AppUser> rankedUsers({bool allTime = false}) {
    final Map<String, AppUser> deduped = {};

    // 1. Canlı sunucu kullanıcıları
    for (final su in serverUsers) {
      deduped[su.serverUserId ?? su.id] = su;
    }

    // 2. Demo kullanıcıları (Sunucu verisi yoksa veya demo kayıtları)
    for (final du in demoUsers) {
      if (!deduped.containsKey(du.id)) {
        deduped[du.id] = du;
      }
    }

    // 3. Kendi profilimiz (Sunucu ID'si veya yerel ID ile tekil olarak ekle)
    if (me != null) {
      final myKey = me!.serverUserId ?? me!.id;
      deduped[myKey] = me!;
    }

    final l = deduped.values.toList();
    l.sort((a, b) {
      final c = allTime ? b.allTimePoints.compareTo(a.allTimePoints) : b.weeklyPoints.compareTo(a.weeklyPoints);
      if (c != 0) return c;
      final n = a.username.compareTo(b.username);
      return n != 0 ? n : a.id.compareTo(b.id);
    });
    return l;
  }

  List<Clan> rankedClans({bool hybrid = true, bool allTime = false}) =>
      clans.where((c) => c.isEligibleForRanking).toList()..sort((a, b) => compareClans(a, b, hybrid: hybrid, allTime: allTime));

  /// Klan Utanç Listesi: En çok israf yapan klanlar deterministik sıralanır.
  List<Clan> worstClans() {
    final Map<String, double> wastedByClan = {};
    for (final u in serverUsers) {
      if (u.clanId.isNotEmpty && u.weeklyWastedCo2Kg > 0) {
        wastedByClan[u.clanId] = (wastedByClan[u.clanId] ?? 0.0) + u.weeklyWastedCo2Kg;
      }
    }
    for (final du in demoUsers) {
      if (du.clanId.isNotEmpty && du.weeklyWastedCo2Kg > 0) {
        wastedByClan[du.clanId] = (wastedByClan[du.clanId] ?? 0.0) + du.weeklyWastedCo2Kg;
      }
    }
    if (me != null && me!.clanId.isNotEmpty && me!.weeklyWastedCo2Kg > 0) {
      wastedByClan[me!.clanId] = (wastedByClan[me!.clanId] ?? 0.0) + me!.weeklyWastedCo2Kg;
    }

    final list = clans.map((c) {
      final totalWasted = max(c.weeklyWastedCo2Kg, wastedByClan[c.id] ?? 0.0);
      return c.copyWith(weeklyWastedCo2Kg: totalWasted);
    }).toList();

    list.sort((a, b) {
      final w = b.weeklyWastedCo2Kg.compareTo(a.weeklyWastedCo2Kg);
      if (w != 0) return w;
      final p = a.weeklyPoints.compareTo(b.weeklyPoints);
      if (p != 0) return p;
      final n = a.name.compareTo(b.name);
      return n != 0 ? n : a.id.compareTo(b.id);
    });

    return list;
  }

  List<AppUser> shameBoard() {
    final Map<String, AppUser> deduped = {};
    for (final su in serverUsers) {
      if (su.weeklyCarTaxiTrips > 0) {
        deduped[su.serverUserId ?? su.id] = su;
      }
    }
    for (final du in demoUsers) {
      if (du.weeklyCarTaxiTrips > 0 && !deduped.containsKey(du.id)) {
        deduped[du.id] = du;
      }
    }
    if (me != null && me!.weeklyCarTaxiTrips > 0) {
      final myKey = me!.serverUserId ?? me!.id;
      deduped[myKey] = me!;
    }
    final l = deduped.values.toList();
    l.sort((a, b) {
      final c = b.weeklyWastedCo2Kg.compareTo(a.weeklyWastedCo2Kg);
      if (c != 0) return c;
      final t = b.weeklyCarTaxiTrips.compareTo(a.weeklyCarTaxiTrips);
      if (t != 0) return t;
      return a.id.compareTo(b.id);
    });
    return l;
  }

  Clan? get myClan {
    final u = me;
    if (u == null) return null;
    final i = clans.indexWhere((c) => c.id == u.clanId);
    return i < 0 ? null : clans[i];
  }

  /// Admin/demo bildirimi (yalnızca bu cihaza; cihazlar arası değil).
  void demoNotify(String title, String body) {
    _note(title, body, demo: true);
    _commit();
  }
}
