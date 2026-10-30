/// Sensör ve doğrulama telemetrisi modeli.
/// Gerçek donanım olayları ile DEMO enjeksiyonları açıkça ayrı etiketlenir.
class SensorTelemetry {
  // Step Counter
  int? rawStepTotal;
  int? stepBaseline;
  int rawStepDelta = 0;
  int verifiedStepsToday = 0;
  int pendingStepsWindow = 0;
  int? lastStepEventTs;

  // Accelerometer
  int accelEventCount = 0;
  int accelSampleCount = 0;
  double? lastAccelVariance;
  double? lastAccelFreqHz;
  int? lastAccelEventTs;

  // GPS
  String gpsStatus = 'Kapalı / Başlatılmadı';
  String? gpsProvider;
  double? lastLat;
  double? lastLon;
  double? lastAccuracy;
  double? lastSpeedKmh;
  int? lastGpsFixTs;

  // Validation & Processing Window
  int? lastValidationTs;
  bool? lastValidationOk;
  String lastValidationVerdict = 'Henüz doğrulama kararı yok';
  String windowStatus = 'Boşta (Sayaç bekleniyor)';

  Map<String, dynamic> toJson() => {
        'steps': {
          'rawTotal': rawStepTotal,
          'baseline': stepBaseline,
          'delta': rawStepDelta,
          'pendingWindow': pendingStepsWindow,
          'verifiedToday': verifiedStepsToday,
          'lastEventTs': lastStepEventTs,
          'hasUserWalkedTest': rawStepDelta > 0,
        },
        'accelerometer': {
          'eventCount': accelEventCount,
          'sampleCount': accelSampleCount,
          'lastVariance': lastAccelVariance,
          'lastFreqHz': lastAccelFreqHz,
          'lastEventTs': lastAccelEventTs,
          'isLive': lastAccelEventTs != null && (DateTime.now().millisecondsSinceEpoch - lastAccelEventTs! < 10000),
        },
        'gps': {
          'status': gpsStatus,
          'provider': gpsProvider,
          'lat': lastLat,
          'lon': lastLon,
          'accuracyM': lastAccuracy,
          'speedKmh': lastSpeedKmh,
          'lastFixTs': lastGpsFixTs,
        },
        'validation': {
          'lastTs': lastValidationTs,
          'ok': lastValidationOk,
          'verdict': lastValidationVerdict,
          'windowStatus': windowStatus,
        },
      };
}
