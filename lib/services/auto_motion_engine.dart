import 'dart:math';
import 'package:flutter/foundation.dart';
import 'activity_validation_service.dart';
import 'app_store.dart';

/// Otomatik hareket algılama modları.
enum AutoMotionMode {
  idle,           // Durgun veya düşük hareket (< 1.5 km/sa)
  walking,        // Düzenli adım / yürüyüş (1.5 - 7.5 km/sa veya adımlı)
  potentialBike,  // Olası bisiklet: Histerezis penceresi süresi sayılıyor
  cycling,        // Onaylanmış aktif otomatik bisiklet sürüşü
  limitedMode,    // Eksik/zayıf GPS (>30m): Yalnızca güvenli adım modu
}

/// Aşama D — Otomatik Hareket ve Aktivite Algılama Motoru.
///
/// Temel Prensipler ve Uygulama Kararları:
/// 1. Ön Planda Çalışma Sınırı: Ön planda süreli pencerelerle çalışır; arka plan garantisi verilmez.
/// 2. Manuel Öncelik: Kullanıcı manuel bisiklet başlattıysa otomatik motor müdahale etmez.
/// 3. Başlama Histerezisi: Tek GPS hızına güvenilmez. En az 10 saniye ve ardışık 3 geçerli fix boyunca
///    hız 9-45 km/sa, adım artışı <= 8 ve ivme varyansı >= 0.10 olmalıdır.
/// 4. Durma Histerezisi & Trafik Işığı: Hız < 3 km/sa olduğunda sürüş hemen kapatılmaz.
///    45 saniyelik kırmızı ışık/kısa duraklama toleransı tanınır; 45 sn hareketsiz kalırsa otomatik kaydedilir.
/// 5. Eksik/Zayıf Sensör: GPS yoksa veya doğruluk > 30m ise limitedMode'a geçer; ASLA otomatik ceza vermez.
/// 6. Çift Ödül Koruması: Bisiklet oturumu aktifken gelen yapay adımlar adım bonusuna katılmaz; aynı yol
///    tekil `tripId` ile yalnızca bir kez ödüllendirilir.
/// 7. Kullanıcı Kontrolü: Otomatik sürüşü kullanıcı dilediği an durdurabilir veya cezasız iptal edebilir.
class AutoMotionEngine extends ChangeNotifier {
  final AppStore store;

  AutoMotionMode _mode = AutoMotionMode.idle;
  AutoMotionMode get mode => _mode;

  bool _isAutoSessionActive = false;
  bool get isAutoSessionActive => _isAutoSessionActive;

  // Histerezis eşikleri (README'de belgelenecektir)
  static const double minBikeSpeedKmh = 9.0;
  static const double maxBikeSpeedKmh = 45.0;
  static const double walkMaxSpeedKmh = 7.5;
  static const double minWalkSpeedKmh = 1.2;
  static const double maxGpsAccuracyM = 30.0;
  static const int minHysteresisFixCount = 3;
  static const Duration hysteresisWindow = Duration(seconds: 10);
  static const Duration trafficPauseTolerance = Duration(seconds: 45);

  // Sayaçlar ve durum değişkenleri
  int _consecutiveBikeFixes = 0;
  DateTime? _firstBikeCandidateTime;
  DateTime? _lastMovementTime;
  DateTime? _sessionStartTime;
  int _lastKnownStepTotal = 0;
  int _stepsDuringCandidate = 0;
  double _candidateDistanceM = 0.0;

  double _currentSpeedKmh = 0.0;
  double get currentSpeedKmh => _currentSpeedKmh;

  double _tripDistanceM = 0.0;
  double get tripDistanceM => _tripDistanceM;

  double _maxSpeedKmh = 0.0;
  double get maxSpeedKmh => _maxSpeedKmh;

  final List<double> _sessionVariances = [];
  String _statusExplanation = 'Durgun / Beklemede';
  String get statusExplanation => _statusExplanation;

  String? _activeTripId;
  String? get activeTripId => _activeTripId;

  _FixPoint? _lastFix;

  AutoMotionEngine(this.store);

  /// Donanım adım sayacı olayı geldiğinde çağrılır.
  void onSensorSteps(int totalSteps) {
    if (_lastKnownStepTotal == 0) {
      _lastKnownStepTotal = totalSteps;
      return;
    }
    final delta = totalSteps - _lastKnownStepTotal;
    _lastKnownStepTotal = totalSteps;

    if (delta > 0) {
      if (_isAutoSessionActive) {
        // Bisiklet sürüşü esnasında pedal çevirme hareketinden kaynaklı küçük yanlış adımlar olabilir.
        // Çift ödüllendirme olmaması için bu adımlar sürüş boyunca izlenir ancak
        // eğer aşırı adım gelirse (delta > 20) kullanıcının bisiklet değil koştuğu anlaşılır.
        if (delta > 20 && _currentSpeedKmh < 15.0) {
          // Bisiklet değil, hızlı koşu! Oturumu güvenle kapat.
          finishAutoTrip(reason: 'Yüksek adım artışı tespit edildi (koşu modu)');
          _setMode(AutoMotionMode.walking, 'Koşu / Hızlı Yürüyüş');
        }
      } else if (_mode == AutoMotionMode.potentialBike) {
        _stepsDuringCandidate += delta;
        if (_stepsDuringCandidate > 10) {
          // Çok fazla adım var; bisiklet adayı iptal edilir, yürüyüşe dönülür.
          _resetBikeCandidate();
          _setMode(AutoMotionMode.walking, 'Yürüyüş tespit edildi (adım artışı: +$_stepsDuringCandidate)');
        }
      } else if (_mode == AutoMotionMode.idle && delta >= 5) {
        _setMode(AutoMotionMode.walking, 'Yürüyüş algılandı');
      }
    }
  }

  /// İvmeölçer olayı geldiğinde çağrılır.
  void onAccel({required double freqHz, required double variance}) {
    if (!variance.isNaN && variance >= 0) {
      if (_isAutoSessionActive && _currentSpeedKmh > 10.0) {
        _sessionVariances.add(variance);
      }
    }
  }

  /// Konum fix olayı geldiğinde çağrılır.
  void onLocation({
    required double lat,
    required double lon,
    double? speedMps,
    double? accuracy,
    int? tsMs,
  }) {
    // Manuel sürüş önceliği: Eğer kullanıcı manuel sürüş başlattıysa otomatik motor pasif kalır.
    if (store.bike != null && !store.bike!.isAuto) {
      _statusExplanation = 'Manuel bisiklet sürüşü devrede (Otomatik motor beklemede)';
      return;
    }

    final now = tsMs != null ? DateTime.fromMillisecondsSinceEpoch(tsMs) : store.clock();
    final speed = (speedMps != null && !speedMps.isNaN && speedMps >= 0) ? speedMps * 3.6 : 0.0;
    _currentSpeedKmh = speed;

    // 1. Zayıf GPS Koruması
    if (accuracy == null || accuracy.isNaN || accuracy > maxGpsAccuracyM) {
      if (!_isAutoSessionActive) {
        _setMode(AutoMotionMode.limitedMode, 'Zayıf GPS sinyali (>${maxGpsAccuracyM.toInt()}m): Sınırlı mod');
      }
      return;
    }

    // 2. GPS Sıçraması (Jump) Koruması
    if (_lastFix != null) {
      final dt = (tsMs != null ? tsMs - _lastFix!.tsMs : 1000) / 1000.0;
      if (dt > 0) {
        final dist = ActivityValidationService.distanceMeters(_lastFix!.lat, _lastFix!.lon, lat, lon);
        final derivedKmh = (dist / dt) * 3.6;
        if (derivedKmh > 150.0) {
          // İmkansız GPS sıçraması: Yoksay
          _statusExplanation = 'GPS sıçraması filtrelendi (${derivedKmh.toStringAsFixed(0)} km/sa)';
          return;
        }
        if (_isAutoSessionActive && speed > 2.0) {
          _tripDistanceM += dist;
        } else if (_mode == AutoMotionMode.potentialBike && speed > 2.0) {
          _candidateDistanceM += dist;
        }
      }
    }
    _lastFix = _FixPoint(lat, lon, tsMs ?? now.millisecondsSinceEpoch);

    // 3. Hız Durum Değerlendirmesi
    if (speed >= minBikeSpeedKmh && speed <= maxBikeSpeedKmh) {
      _lastMovementTime = now;
      if (speed > _maxSpeedKmh) _maxSpeedKmh = speed;

      if (_isAutoSessionActive) {
        _statusExplanation = 'Bisiklet sürülüyor (${speed.toStringAsFixed(1)} km/sa)';
        notifyListeners();
      } else {
        // Başlama Histerezisi
        _firstBikeCandidateTime ??= now;
        _consecutiveBikeFixes++;

        final elapsed = now.difference(_firstBikeCandidateTime!);
        if (_consecutiveBikeFixes >= minHysteresisFixCount && elapsed >= hysteresisWindow) {
          // Histerezis tamamlandı -> Otomatik bisiklet oturumu başlat!
          _startAutoBikeSession(now);
        } else {
          _setMode(
            AutoMotionMode.potentialBike,
            'Olası bisiklet doğrulanıyor (${elapsed.inSeconds}/${hysteresisWindow.inSeconds} sn)',
          );
        }
      }
    } else if (speed < 3.0) {
      // Hareketsiz veya yavaşlama
      if (_isAutoSessionActive) {
        // Trafik ışığı / kısa duraklama histerezisi
        _lastMovementTime ??= now;
        final pauseElapsed = now.difference(_lastMovementTime!);
        if (pauseElapsed >= trafficPauseTolerance) {
          // 45 saniye duruldu: Otomatik tamamla!
          finishAutoTrip(reason: 'Kullanıcı durdu (45 sn tolerans tamamlandı)');
        } else {
          final left = trafficPauseTolerance.inSeconds - pauseElapsed.inSeconds;
          _statusExplanation = 'Kısa duraklama / Trafik ışığı ($left sn bekleme)';
          notifyListeners();
        }
      } else {
        _resetBikeCandidate();
        if (speed < minWalkSpeedKmh) {
          _setMode(AutoMotionMode.idle, 'Durgun / Beklemede');
        } else {
          _setMode(AutoMotionMode.walking, 'Yürüyüş hızı (${speed.toStringAsFixed(1)} km/sa)');
        }
      }
    } else if (speed > maxBikeSpeedKmh) {
      // > 45 km/sa: Araç şüphesi veya yüksek hız
      if (_isAutoSessionActive) {
        // Araç şüphesi: Oturumu ceza vermeden veya kurallara uygun bitir
        finishAutoTrip(reason: 'Yüksek hız tespit edildi (>45 km/sa)');
      }
      _resetBikeCandidate();
      // Muğlak taşıtta doğrudan ceza verme; güvenli tarafta kal
      _setMode(AutoMotionMode.idle, 'Yüksek hız algılandı (${speed.toStringAsFixed(0)} km/sa): Taşıt şüphesi');
    }
  }

  void _startAutoBikeSession(DateTime now) {
    _isAutoSessionActive = true;
    _sessionStartTime = _firstBikeCandidateTime ?? now;
    _lastMovementTime = now;
    _tripDistanceM = _candidateDistanceM;
    _candidateDistanceM = 0.0;
    _maxSpeedKmh = _currentSpeedKmh;
    _sessionVariances.clear();
    _activeTripId = 'auto_bike_${now.millisecondsSinceEpoch}';

    // Store'da aktif bir bisiklet oturumu temsil et
    final session = BikeSession(_activeTripId!, now.millisecondsSinceEpoch, isAuto: true);
    store.bike = session;

    _setMode(AutoMotionMode.cycling, 'Otomatik bisiklet sürüşü başladı! 🚴');
    store.demoNotify('Yeşil Adım 🚴', 'Otomatik bisiklet sürüşü algılandı ve başlatıldı!');
  }

  /// Otomatik sürüşü tamamlar ve puanı hesaba işler.
  ActionResult finishAutoTrip({String reason = 'Sürüş tamamlandı'}) {
    if (!_isAutoSessionActive) return const ActionResult(false, 'Aktif otomatik sürüş yok.');

    final tripId = _activeTripId ?? 'auto_bike_${store.clock().millisecondsSinceEpoch}';
    final distanceKm = _tripDistanceM / 1000.0;
    final now = _lastFix != null ? DateTime.fromMillisecondsSinceEpoch(_lastFix!.tsMs) : store.clock();
    final durationSec = _sessionStartTime != null ? max(1, now.difference(_sessionStartTime!).inSeconds) : 1;
    final avgSpeedKmh = durationSec > 0 ? (distanceKm / (durationSec / 3600.0)) : 0.0;

    double? avgVar;
    if (_sessionVariances.isNotEmpty) {
      avgVar = _sessionVariances.reduce((a, b) => a + b) / _sessionVariances.length;
    }

    _isAutoSessionActive = false;
    _activeTripId = null;
    store.bike = null;
    _resetBikeCandidate();
    _setMode(AutoMotionMode.idle, reason);

    // Minimum mesafe eşiği: 100 metreden az sürüşler için puan/kayıt açılmaz
    if (distanceKm < 0.1) {
      return const ActionResult(false, 'Çok kısa mesafe (<100m); kayıt oluşturulmadı.');
    }

    // Değerlendir ve ödüllendir
    final res = store.evaluateBike(
      tripId: tripId,
      distanceKm: distanceKm,
      maxSpeedKmh: _maxSpeedKmh,
      avgSpeedKmh: avgSpeedKmh,
      fastAccelVariance: avgVar,
      demo: false,
    );

    notifyListeners();
    return res;
  }

  /// Kullanıcı sürüşü iptal etmek istediğinde (cezasız/puansız sıfırlama).
  ActionResult cancelAutoTrip() {
    if (!_isAutoSessionActive) return const ActionResult(false, 'Aktif otomatik sürüş yok.');
    _isAutoSessionActive = false;
    _activeTripId = null;
    store.bike = null;
    _resetBikeCandidate();
    _setMode(AutoMotionMode.idle, 'Otomatik sürüş kullanıcı tarafından iptal edildi.');
    notifyListeners();
    return const ActionResult(true, 'Otomatik sürüş iptal edildi.');
  }

  void _resetBikeCandidate() {
    _consecutiveBikeFixes = 0;
    _firstBikeCandidateTime = null;
    _stepsDuringCandidate = 0;
    _candidateDistanceM = 0.0;
  }

  void _setMode(AutoMotionMode m, String explanation) {
    _mode = m;
    _statusExplanation = explanation;
    notifyListeners();
  }

  // ---------- Deterministik Simülasyon (GM Paneli ve Testler İçin) ----------
  /// Belirli bir süre, hız ve adım akışını hızlandırılmış olarak simüle eder.
  void simulateMotionFlow({
    required AutoMotionMode targetMode,
    required double speedKmh,
    required int durationSeconds,
    int stepDelta = 0,
    double variance = 0.18,
    double accuracy = 10.0,
  }) {
    final startMs = store.clock().millisecondsSinceEpoch;
    final fixIntervalSec = 3;
    final fixCount = max(1, durationSeconds ~/ fixIntervalSec);

    var currentLat = 41.0082;
    var currentLon = 28.9784;

    for (var i = 0; i < fixCount; i++) {
      final nowMs = startMs + (i * fixIntervalSec * 1000);
      final speedMps = speedKmh / 3.6;
      final stepInc = (stepDelta / fixCount).round();

      if (stepInc > 0) {
        _lastKnownStepTotal += stepInc;
        onSensorSteps(_lastKnownStepTotal);
      }

      onAccel(freqHz: 2.0, variance: variance);

      // Metre başına koordinat kayması
      final distM = speedMps * fixIntervalSec;
      currentLat += (distM / 111111.0);

      onLocation(
        lat: currentLat,
        lon: currentLon,
        speedMps: speedMps,
        accuracy: accuracy,
        tsMs: nowMs,
      );
    }
  }

  Map<String, dynamic> toJson() => {
        'mode': _mode.name,
        'isAutoSessionActive': _isAutoSessionActive,
        'statusExplanation': _statusExplanation,
        'currentSpeedKmh': _currentSpeedKmh,
        'tripDistanceM': _tripDistanceM,
        'maxSpeedKmh': _maxSpeedKmh,
        'consecutiveBikeFixes': _consecutiveBikeFixes,
        'activeTripId': _activeTripId,
      };
}

class _FixPoint {
  final double lat;
  final double lon;
  final int tsMs;
  const _FixPoint(this.lat, this.lon, this.tsMs);
}
