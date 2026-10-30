class Clan {
  final String id;
  final String name;
  final int memberCount;
  final int weeklyPoints;
  final int allTimePoints;

  const Clan({
    required this.id,
    required this.name,
    required this.memberCount,
    required this.weeklyPoints,
    this.allTimePoints = 0,
  });

  /// 5'ten az üyesi olan klan sıralamaya alınmaz (4 hariç, 5 dahil).
  bool get isEligibleForRanking => memberCount >= 5;

  /// Hibrit formül: (Toplam Puan * 0.6) + (Üye Ortalaması * 50 * 0.4)
  /// [allTime] true ise allTimePoints üzerinden hesaplanır.
  double hybridScoreFor({bool allTime = false}) {
    final pts = allTime ? allTimePoints : weeklyPoints;
    if (memberCount <= 0) return 0.0;
    final avg = pts / memberCount;
    return (pts * 0.6) + (avg * 50 * 0.4);
  }

  double get hybridScore => hybridScoreFor(allTime: false);

  Clan copyWith({int? memberCount, int? weeklyPoints, int? allTimePoints}) => Clan(
        id: id,
        name: name,
        memberCount: memberCount ?? this.memberCount,
        weeklyPoints: weeklyPoints ?? this.weeklyPoints,
        allTimePoints: allTimePoints ?? this.allTimePoints,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'member_count': memberCount,
        'weekly_points': weeklyPoints,
        'all_time_points': allTimePoints,
      };

  factory Clan.fromJson(Map<String, dynamic> j) => Clan(
        id: j['id'] as String,
        name: j['name'] as String,
        memberCount: (j['member_count'] as num).toInt(),
        weeklyPoints: (j['weekly_points'] as num).toInt(),
        allTimePoints: (j['all_time_points'] as num?)?.toInt() ?? 0,
      );
}
