import 'dart:math';
import '../core/constants/trabzon_stops_seed.dart';

enum DetectedActivityType {
  walk,
  run,
  bike,
  eScooter,
  publicTransitBus,
  shortBusPenalty,
  carOrTaxiPenalty,
  inconclusiveLowGps,
  rejectedCheatShake,
  rejectedCheatCarAsBike,
}

class ClassificationResult {
  final DetectedActivityType activityType;
  final int busProbabilityScore;
  final int pointsAwarded;
  final double co2DeltaKg; // Pozitif: Tasarruf, Negatif: İsraf
  final String title;
  final String explanation;
  final bool isShortBusPenalty;

  const ClassificationResult({
    required this.activityType,
    required this.busProbabilityScore,
    required this.pointsAwarded,
    required this.co2DeltaKg,
    required this.title,
    required this.explanation,
    this.isShortBusPenalty = false,
  });

  Map<String, dynamic> toJson() => {
        'activityType': activityType.name,
        'busProbabilityScore': busProbabilityScore,
        'pointsAwarded': pointsAwarded,
        'co2DeltaKg': co2DeltaKg,
        'title': title,
        'explanation': explanation,
        'isShortBusPenalty': isShortBusPenalty,
      };
}

class AutoTransportClassifierService {
  /// İki GPS koordinatı arasındaki mesafeyi (Metre) Haversine formülü ile hesaplar
  static double distanceInMeters(double lat1, double lon1, double lat2, double lon2) {
    if (lat1 == lat2 && lon1 == lon2) return 0.0;
    const double earthRadius = 6371000;
    final double dLat = (lat2 - lat1) * pi / 180;
    final double dLon = (lon2 - lon1) * pi / 180;
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLon / 2) * sin(dLon / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  /// Verilen koordinata en yakın otobüs durağını bulur (Varsayılan max 45 metre)
  static BusStopNode? findNearestStop(double lat, double lon, {double maxRadiusMeters = 45.0}) {
    BusStopNode? nearest;
    double minDistance = maxRadiusMeters;
    for (final stop in kTrabzonBusStops) {
      final dist = distanceInMeters(lat, lon, stop.lat, stop.lon);
      if (dist <= minDistance) {
        minDistance = dist;
        nearest = stop;
      }
    }
    return nearest;
  }

  /// 5'li Aktivite ve Otobüs / Taksi Karar Motoru
  static ClassificationResult classifySession({
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
  }) {
    // 0. SENSÖR GÜVENİRLİK KONTROLÜ (Ham GPS / Güven düşükken otomatik suçlama yok!)
    if (!isGpsReliable || gpsAccuracyMeters > 35.0 || distanceKm.isNaN || distanceKm < 0.01) {
      return const ClassificationResult(
        activityType: DetectedActivityType.inconclusiveLowGps,
        busProbabilityScore: 0,
        pointsAwarded: 0,
        co2DeltaKg: 0.0,
        title: 'ℹ️ Belirsiz / Düşük Hassasiyetli Oturum',
        explanation: 'GPS sinyali zayıf veya yetersiz (>35m). Hatalı işlem yapmamak için otomatik ceza veya ödül kesilmedi.',
      );
    }

    // 1. EDGE CASE: Telefonu Elde Sallama Hilesi (Shake Spoofing)
    if (stepCadenceSpm > 185 && avgSpeedKmh < 1.5) {
      return const ClassificationResult(
        activityType: DetectedActivityType.rejectedCheatShake,
        busProbabilityScore: 0,
        pointsAwarded: 0,
        co2DeltaKg: 0.0,
        title: '🛑 Telefon Sallama Hilesi Yakalandı!',
        explanation: 'Dakikada >185 adım frekansı ve 0 km/sa GPS hızı! Telefonu sallayarak puan kazanamazsın, kalk yürü!',
      );
    }

    // 2. EDGE CASE: Arabayla Giderken "Bisiklet" Modunu Açma Hilesi
    if (userClaimedBikeMode && (maxSpeedKmh > 48.0 || (avgSpeedKmh > 28.0 && accelVariance < 0.15))) {
      final wastedCo2 = -(distanceKm * 0.192);
      return ClassificationResult(
        activityType: DetectedActivityType.rejectedCheatCarAsBike,
        busProbabilityScore: 0,
        pointsAwarded: 0,
        co2DeltaKg: double.parse(wastedCo2.toStringAsFixed(2)),
        title: '🚴‍♂️❌ Bisiklet Hilesi Yakalandı!',
        explanation: 'Maksimum hız ${maxSpeedKmh.toStringAsFixed(1)} km/sa ve ivme varyansı (${accelVariance.toStringAsFixed(2)}) araba süspansiyonu gösteriyor! Puan iptal edildi ve Utanç Tablosuna yazıldın.',
      );
    }

    // 3. YÜRÜME (WALK)
    if (avgSpeedKmh >= 1.5 && avgSpeedKmh <= 7.2 && stepCadenceSpm >= 60 && stepCadenceSpm <= 135) {
      final savedCo2 = distanceKm * 0.192;
      return ClassificationResult(
        activityType: DetectedActivityType.walk,
        busProbabilityScore: 0,
        pointsAwarded: 5,
        co2DeltaKg: double.parse(savedCo2.toStringAsFixed(2)),
        title: '🚶 Yürüyüş Doğrulandı',
        explanation: 'Kadans: $stepCadenceSpm adım/dk, Hız: ${avgSpeedKmh.toStringAsFixed(1)} km/sa. Doğal yürüyüş ritmi onaylandı.',
      );
    }

    // 4. KOŞMA (RUN)
    if (avgSpeedKmh > 7.2 && avgSpeedKmh <= 18.5 && stepCadenceSpm > 135 && accelVariance > 2.0) {
      final savedCo2 = distanceKm * 0.192;
      return ClassificationResult(
        activityType: DetectedActivityType.run,
        busProbabilityScore: 0,
        pointsAwarded: 10,
        co2DeltaKg: double.parse(savedCo2.toStringAsFixed(2)),
        title: '🏃 Koşu Antrenmanı Doğrulandı!',
        explanation: 'Adım kadansı $stepCadenceSpm spm ve yüksek ivme varyansı (${accelVariance.toStringAsFixed(2)}) koştuğunu kanıtlıyor!',
      );
    }

    // 5. BİSİKLET (BIKE)
    if (avgSpeedKmh >= 8.5 && avgSpeedKmh <= 35.0 && maxSpeedKmh <= 48.0 && stepCadenceSpm < 35 && accelVariance >= 0.30) {
      final pts = max(1, distanceKm.round());
      final savedCo2 = distanceKm * 0.192;
      return ClassificationResult(
        activityType: DetectedActivityType.bike,
        busProbabilityScore: 0,
        pointsAwarded: pts,
        co2DeltaKg: double.parse(savedCo2.toStringAsFixed(2)),
        title: '🚴 Bisiklet Sürüşü Doğrulandı (+$pts Puan)',
        explanation: '${distanceKm.toStringAsFixed(1)} km sürüş onaylandı. İvme sensörü (${accelVariance.toStringAsFixed(2)}) bisiklet profilini doğruladı.',
      );
    }

    // 6. MOTORLU ARAÇ İÇİ (OTOBÜS vs. ÖZEL ARAÇ / TAKSİ KARARI)
    int busScore = 0;
    if (hasNfcOrQrScan) busScore += 100;
    if (boardedNearBusStop) busScore += 35;
    busScore += (matchedBusStopDwells * 25);
    if (dolmusStyleShortStops >= 3) busScore += 30;
    if (alightedNearBusStop) busScore += 20;

    // Ekspres hat toleransı (501 Of Ekspres gibi ara durakta durmayan otobüsler)
    if (boardedNearBusStop && alightedNearBusStop && busScore < 60) {
      busScore = 60; // Biniş ve iniş durağı eşleşmişse ekspres otobüs sayılır
    }

    busScore = min(100, busScore);

    if (busScore >= 60) {
      // 2. KISA MESAFE OTOBÜS YOLCULUĞU KURALI (0 < Mesafe <= 500m):
      // Kesin doğrulanmış mesafe 0 < mesafe <= 500m ise +3/CO2 ödülü yok, tek kez -3 puan cezası!
      if (distanceKm > 0 && distanceKm <= 0.5) {
        final meters = (distanceKm * 1000).round();
        return ClassificationResult(
          activityType: DetectedActivityType.shortBusPenalty,
          busProbabilityScore: busScore,
          pointsAwarded: -3,
          co2DeltaKg: 0.0,
          isShortBusPenalty: true,
          title: '🚌⚠️ Kısa Otobüs Yolculuğu Cezası (-3 Puan)',
          explanation: 'Mesafe: $meters metre (≤500m). $meters metreyi otobüsle gitmek yerine yürüyebilirdin! +3 Puan ve CO₂ ödülü verilmedi, -3 puan haftalık ceza uygulandı.',
        );
      }

      final savedCo2 = distanceKm * (0.192 - 0.035);
      return ClassificationResult(
        activityType: DetectedActivityType.publicTransitBus,
        busProbabilityScore: busScore,
        pointsAwarded: 3,
        co2DeltaKg: double.parse(savedCo2.toStringAsFixed(2)),
        title: '🚌 Otobüs / Dolmuş Doğrulandı (Skor: %$busScore)',
        explanation: 'Durak eşleşmesi ve yolcu iniş-biniş paterni onaylandı! +3 Puan ve ${savedCo2.toStringAsFixed(2)} kg CO₂ tasarrufu eklendi.',
      );
    } else {
      final wastedCo2 = -(distanceKm * 0.192);
      return ClassificationResult(
        activityType: DetectedActivityType.carOrTaxiPenalty,
        busProbabilityScore: busScore,
        pointsAwarded: 0,
        co2DeltaKg: double.parse(wastedCo2.toStringAsFixed(2)),
        title: '🚕 Yakalandın! Özel Araç / Taksi (Otobüs Skoru: %$busScore)',
        explanation: 'Otobüs duraklarıyla eşleşmedi ve ortalama hız ${avgSpeedKmh.toStringAsFixed(0)} km/sa! Bu ${distanceKm.toStringAsFixed(1)} km yolu otobüsle gitseydin ${(distanceKm * 0.157).toStringAsFixed(2)} kg CO₂ tasarruf ederdin. Utanç Tablosuna yazıldın!',
      );
    }
  }
}
