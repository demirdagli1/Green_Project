class Clan {
  final String id;
  final String name;
  final int memberCount;
  final int weeklyPoints;
  final int allTimePoints;
  final double weeklyWastedCo2Kg;

  const Clan({
    required this.id,
    required this.name,
    required this.memberCount,
    required this.weeklyPoints,
    this.allTimePoints = 0,
    this.weeklyWastedCo2Kg = 0.0,
  });

  /// 5'ten az üyesi olan klan sıralamaya alınmaz (4 hariç, 5 dahil).
  bool get isEligibleForRanking => memberCount >= 5;

  /// SQL tablosundaki tamsayı ID ile istemci klan ID eşlemesi.
  static int? idToSql(String? clanId) {
    if (clanId == null || clanId.isEmpty) return null;
    final parsed = int.tryParse(clanId);
    if (parsed != null) return parsed;
    const map = {
      'clan_ktu_kanuni': 1,
      'clan_ktu_of': 2,
      'clan_odtu': 3,
      'clan_koc': 4,
      'clan_sabanci': 5,
      'clan_itu': 6,
      'clan_ytu': 7,
      'clan_gazi': 8,
      'clan_ktu_dagcilik': 9,
      'clan_sincan': 10,
      'clan_kirikkale': 11,
    };
    return map[clanId];
  }

  static String sqlToId(int sqlId) {
    const map = {
      1: 'clan_ktu_kanuni',
      2: 'clan_ktu_of',
      3: 'clan_odtu',
      4: 'clan_koc',
      5: 'clan_sabanci',
      6: 'clan_itu',
      7: 'clan_ytu',
      8: 'clan_gazi',
      9: 'clan_ktu_dagcilik',
      10: 'clan_sincan',
      11: 'clan_kirikkale',
    };
    return map[sqlId] ?? 'clan_$sqlId';
  }

  /// Hibrit formül: (Toplam Puan * 0.6) + (Üye Ortalaması * 50 * 0.4)
  /// [allTime] true ise allTimePoints üzerinden hesaplanır.
  double hybridScoreFor({bool allTime = false}) {
    final pts = allTime ? allTimePoints : weeklyPoints;
    if (memberCount <= 0) return 0.0;
    final avg = pts / memberCount;
    return (pts * 0.6) + (avg * 50 * 0.4);
  }

  double get hybridScore => hybridScoreFor(allTime: false);

  Clan copyWith({
    int? memberCount,
    int? weeklyPoints,
    int? allTimePoints,
    double? weeklyWastedCo2Kg,
  }) =>
      Clan(
        id: id,
        name: name,
        memberCount: memberCount ?? this.memberCount,
        weeklyPoints: weeklyPoints ?? this.weeklyPoints,
        allTimePoints: allTimePoints ?? this.allTimePoints,
        weeklyWastedCo2Kg: weeklyWastedCo2Kg ?? this.weeklyWastedCo2Kg,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'member_count': memberCount,
        'weekly_points': weeklyPoints,
        'all_time_points': allTimePoints,
        'weekly_wasted_co2_kg': weeklyWastedCo2Kg,
      };

  factory Clan.fromJson(Map<String, dynamic> j) => Clan(
        id: j['id'] as String,
        name: j['name'] as String,
        memberCount: (j['member_count'] as num).toInt(),
        weeklyPoints: (j['weekly_points'] as num).toInt(),
        allTimePoints: (j['all_time_points'] as num?)?.toInt() ?? 0,
        weeklyWastedCo2Kg: (j['weekly_wasted_co2_kg'] as num?)?.toDouble() ?? 0.0,
      );
}
