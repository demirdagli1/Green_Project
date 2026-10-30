class TransitStop {
  final String code;
  final String name;
  final String line;
  final double co2SavingKg;
  final String? nfcUid;
  final String? qrPayload;
  final double avgTripKm;
  final int pointsReward;

  const TransitStop({
    required this.code,
    required this.name,
    required this.line,
    required this.co2SavingKg,
    this.nfcUid,
    this.qrPayload,
    this.avgTripKm = 6.5,
    this.pointsReward = 3,
  });
}
