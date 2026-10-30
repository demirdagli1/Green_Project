import 'dart:math';

/// Saf (durumsuz) iş kuralları. Sensör eşikleri şartnameden gelir ve araç türünü
/// KESİN kanıtlamaz; veri yokluğu (null) asla suçlama/ceza üretmez.
class ActivityValidationService {
  const ActivityValidationService();

  // ---------- Adım ----------
  static const double maxCadence = 185.0; // adım/dk, > ise hile
  static const double maxShakeHz = 3.5; // Hz, > ise (ve hareketsizlik varsa) hile
  static const double stationaryPathMeters = 3.0; // bu yoldan az = konum değişimi yok

  /// [deltaSteps] pencere içindeki artış, [minutes] pencere süresi (null = bilinmiyor),
  /// [shakeHz] ivmeölçer frekansı (null = bilinmiyor), [gpsMovementMeters] GPS yolu
  /// (null = GEÇERLİ ÖLÇÜM YOK; 0 varsayılmaz).
  StepVerdict checkSteps({
    required int deltaSteps,
    double? minutes,
    double? shakeHz,
    double? gpsMovementMeters,
  }) {
    if (deltaSteps <= 0) {
      return const StepVerdict(false, 'Geçersiz veya sıfır adım artışı.');
    }
    if (minutes != null && minutes > 0 && deltaSteps / minutes > maxCadence) {
      return const StepVerdict(false, 'Telefonu sallayarak sadece kol kası yaparsın, kalk yürü!');
    }
    final stationary = gpsMovementMeters != null && gpsMovementMeters < stationaryPathMeters;
    if (shakeHz != null && shakeHz > maxShakeHz && stationary) {
      return const StepVerdict(false, 'Telefonu sallayarak sadece kol kası yaparsın, kalk yürü!');
    }
    return const StepVerdict(true, '');
  }

  /// Her tamamlanan 1.000 adım = 5 puan. previous/new günlük toplamlar.
  int stepPoints(int previousSteps, int newSteps) {
    if (newSteps <= previousSteps || previousSteps < 0) return 0;
    return ((newSteps ~/ 1000) - (previousSteps ~/ 1000)) * 5;
  }

  // ---------- Toplu taşıma ----------
  static const Duration transitCooldown = Duration(minutes: 45);

  /// "YESILADIM://TRANSIT/<KOD>" veya çıplak durak kodu → büyük harf kod; geçersizse null.
  String? parseTransitPayload(String? raw) {
    if (raw == null) return null;
    var s = raw.trim();
    if (s.isEmpty) return null;
    // URL query string'i varsa (?sig=... demo imzası vb.) ayıkla
    final qIdx = s.indexOf('?');
    if (qIdx >= 0) {
      s = s.substring(0, qIdx).trim();
    }
    const prefix = 'YESILADIM://TRANSIT/';
    if (s.toUpperCase().startsWith(prefix)) s = s.substring(prefix.length);
    s = s.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9][A-Z0-9_-]{1,31}$').hasMatch(s)) return null;
    return s;
  }

  /// null = izin verilir; aksi halde kalan süre. Saat geriye alınırsa (now < last) reddedilir.
  Duration? transitRemaining(DateTime? last, DateTime now) {
    if (last == null) return null;
    final elapsed = now.difference(last);
    if (elapsed.isNegative) return transitCooldown;
    if (elapsed >= transitCooldown) return null;
    return transitCooldown - elapsed;
  }

  // ---------- Bisiklet ----------
  BikeVerdict checkBike({
    required double distanceKm,
    required double maxSpeedKmh,
    required double avgSpeedKmh,
    double? fastAccelVariance,
  }) {
    bool bad(double v) => v.isNaN || v.isInfinite || v < 0;
    if (bad(distanceKm) || bad(maxSpeedKmh) || bad(avgSpeedKmh)) {
      return const BikeVerdict(BikeStatus.invalidData, 0, 0, 0, 'Geçersiz sürüş verisi.');
    }
    if (maxSpeedKmh >= 50.0 || avgSpeedKmh >= 35.0) {
      return const BikeVerdict(BikeStatus.rejectedSpeedSpoof, 0, 0, 0,
          '❌ Hız reddi: Saatte 50 km giden bisiklet olmaz! Aktivite reddedildi (puan verilmedi, Utanç Tablosu cezası uygulanmadı).');
    }
    if (avgSpeedKmh > 25.0 && fastAccelVariance != null && fastAccelVariance < 0.12) {
      final wasted = distanceKm * 0.192;
      return BikeVerdict(BikeStatus.carTaxiPenalty, 0, 0, wasted,
          '🚨 Araba şüphesi (titreşimsiz ivme: varyans ${fastAccelVariance.toStringAsFixed(3)} < 0.12): Aktivite puanı verilmedi. Haftalık araba/taksi sayacına +1 eklendi ve ${wasted.toStringAsFixed(2)} kg harcanan CO₂ Utanç Tablosu siciline işlendi (altın/puan kesintisi yapılmaz).');
    }
    final pts = distanceKm.floor();
    return BikeVerdict(BikeStatus.accepted, pts, distanceKm * 0.19, 0,
        'Sürüş onaylandı: +$pts puan.');
  }

  // ---------- Araba / taksi ----------
  static const int vehicleMaxStepDelta = 10;

  /// Herhangi bir girdi null ise (veri yok) tespit YOK.
  VehicleVerdict checkVehicle({
    double? avgSpeedKmh,
    double? distanceKm,
    int? stepDelta,
    required bool transitInLast45Min,
  }) {
    if (avgSpeedKmh == null || distanceKm == null || stepDelta == null) {
      return const VehicleVerdict(false, 0, 'Yeterli ölçüm yok; suçlama yapılmadı.');
    }
    if (avgSpeedKmh.isNaN || distanceKm.isNaN || avgSpeedKmh < 0 || distanceKm <= 0) {
      return const VehicleVerdict(false, 0, 'Geçersiz ölçüm; suçlama yapılmadı.');
    }
    if (transitInLast45Min) {
      return const VehicleVerdict(false, 0,
          'Son 45 dk içinde toplu taşıma kaydın olduğu için araba/taksi muafiyeti devrede; ceza uygulanmadı.');
    }
    if (avgSpeedKmh > 30.0 && stepDelta <= vehicleMaxStepDelta) {
      final w = distanceKm * 0.192;
      return VehicleVerdict(true, w,
          '🚕 Yakalandın! Hız: ${avgSpeedKmh.toStringAsFixed(0)} km/sa, mesafe: ${distanceKm.toStringAsFixed(1)} km. Son aktiviteyi araba/taksi yerine toplu taşımayla gitseydin ${w.toStringAsFixed(2)} kg CO₂ tasarruf yapardın aslında!!! Utanç tablosuna yazıldın!');
    }
    return const VehicleVerdict(false, 0, 'Araba/taksi koşulları sağlanmadı (Hız ≤ 30 km/sa veya adım artışı > 10).');
  }

  /// Haversine, metre.
  static double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    double rad(double d) => d * pi / 180.0;
    final dLat = rad(lat2 - lat1);
    final dLon = rad(lon2 - lon1);
    final a = pow(sin(dLat / 2), 2) + cos(rad(lat1)) * cos(rad(lat2)) * pow(sin(dLon / 2), 2);
    return 2 * r * asin(min(1.0, sqrt(a)));
  }
}

class StepVerdict {
  final bool ok;
  final String message;
  const StepVerdict(this.ok, this.message);
}

enum BikeStatus { accepted, rejectedSpeedSpoof, carTaxiPenalty, invalidData, insufficientData }

class BikeVerdict {
  final BikeStatus status;
  final int points;
  final double co2SavedKg;
  final double wastedCo2Kg;
  final String message;
  const BikeVerdict(this.status, this.points, this.co2SavedKg, this.wastedCo2Kg, this.message);
}

class VehicleVerdict {
  final bool detected;
  final double wastedCo2Kg;
  final String message;
  const VehicleVerdict(this.detected, this.wastedCo2Kg, this.message);
}
