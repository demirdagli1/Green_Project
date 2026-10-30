class AppUser {
  final String id;
  final String deviceId;
  final String username;
  final String clanId;
  final String clanName;
  final bool isDemo;
  final int todaySteps;
  final int weeklyPoints;
  final int allTimePoints;
  final double preventedCo2Kg; // tüm zamanlar, haftalık reset'te silinmez
  final int goldCoins;
  final int streakDays;
  final int weeklyCarTaxiTrips;
  final double weeklyWastedCo2Kg;
  final String equippedAvatar;
  final String equippedFrame;
  final String equippedPet;

  const AppUser({
    required this.id,
    required this.deviceId,
    required this.username,
    required this.clanId,
    required this.clanName,
    this.isDemo = false,
    this.todaySteps = 0,
    this.weeklyPoints = 0,
    this.allTimePoints = 0,
    this.preventedCo2Kg = 0.0,
    this.goldCoins = 0,
    this.streakDays = 0,
    this.weeklyCarTaxiTrips = 0,
    this.weeklyWastedCo2Kg = 0.0,
    this.equippedAvatar = 'default_avatar',
    this.equippedFrame = 'none',
    this.equippedPet = 'none',
  });

  AppUser copyWith({
    String? username,
    String? clanId,
    String? clanName,
    int? todaySteps,
    int? weeklyPoints,
    int? allTimePoints,
    double? preventedCo2Kg,
    int? goldCoins,
    int? streakDays,
    int? weeklyCarTaxiTrips,
    double? weeklyWastedCo2Kg,
    String? equippedAvatar,
    String? equippedFrame,
    String? equippedPet,
  }) {
    return AppUser(
      id: id,
      deviceId: deviceId,
      username: username ?? this.username,
      clanId: clanId ?? this.clanId,
      clanName: clanName ?? this.clanName,
      isDemo: isDemo,
      todaySteps: todaySteps ?? this.todaySteps,
      weeklyPoints: weeklyPoints ?? this.weeklyPoints,
      allTimePoints: allTimePoints ?? this.allTimePoints,
      preventedCo2Kg: preventedCo2Kg ?? this.preventedCo2Kg,
      goldCoins: goldCoins ?? this.goldCoins,
      streakDays: streakDays ?? this.streakDays,
      weeklyCarTaxiTrips: weeklyCarTaxiTrips ?? this.weeklyCarTaxiTrips,
      weeklyWastedCo2Kg: weeklyWastedCo2Kg ?? this.weeklyWastedCo2Kg,
      equippedAvatar: equippedAvatar ?? this.equippedAvatar,
      equippedFrame: equippedFrame ?? this.equippedFrame,
      equippedPet: equippedPet ?? this.equippedPet,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'device_id': deviceId,
        'username': username,
        'clan_id': clanId,
        'clan_name': clanName,
        'is_demo': isDemo,
        'today_steps': todaySteps,
        'weekly_points': weeklyPoints,
        'all_time_points': allTimePoints,
        'prevented_co2_kg': preventedCo2Kg,
        'gold_coins': goldCoins,
        'streak_days': streakDays,
        'weekly_car_taxi_trips': weeklyCarTaxiTrips,
        'weekly_wasted_co2_kg': weeklyWastedCo2Kg,
        'equipped_avatar': equippedAvatar,
        'equipped_frame': equippedFrame,
        'equipped_pet': equippedPet,
      };

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String? ?? '',
        deviceId: j['device_id'] as String? ?? '',
        username: j['username'] as String? ?? 'Kullanıcı',
        clanId: j['clan_id'] as String? ?? '',
        clanName: j['clan_name'] as String? ?? '',
        isDemo: j['is_demo'] as bool? ?? false,
        todaySteps: (j['today_steps'] as num?)?.toInt() ?? 0,
        weeklyPoints: (j['weekly_points'] as num?)?.toInt() ?? 0,
        allTimePoints: (j['all_time_points'] as num?)?.toInt() ?? 0,
        preventedCo2Kg: (j['prevented_co2_kg'] as num?)?.toDouble() ?? 0.0,
        goldCoins: (j['gold_coins'] as num?)?.toInt() ?? 0,
        streakDays: (j['streak_days'] as num?)?.toInt() ?? 0,
        weeklyCarTaxiTrips: (j['weekly_car_taxi_trips'] as num?)?.toInt() ?? 0,
        weeklyWastedCo2Kg: (j['weekly_wasted_co2_kg'] as num?)?.toDouble() ?? 0.0,
        equippedAvatar: j['equipped_avatar'] as String? ?? 'default_avatar',
        equippedFrame: j['equipped_frame'] as String? ?? 'none',
        equippedPet: j['equipped_pet'] as String? ?? 'none',
      );
}
