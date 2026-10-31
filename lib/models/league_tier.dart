import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';

enum LeagueCategory { individual, clan }

class LeagueTier {
  final int tierNumber;
  final String individualName;
  final String clanName;
  final int individualThreshold;
  final int clanThreshold;
  final Color color;
  final String symbol;

  const LeagueTier({
    required this.tierNumber,
    required this.individualName,
    required this.clanName,
    required this.individualThreshold,
    required this.clanThreshold,
    required this.color,
    required this.symbol,
  });

  /// Bireysel lig PNG logo yolu (Logolar/logo-bireysel/lig-bireysel-1.png ... 6.png).
  String get individualAssetPath => 'Logolar/logo-bireysel/lig-bireysel-$tierNumber.png';

  /// Klan lig PNG logo yolu (Logolar/logo-klan/logo-klan-1.png ... 6.png).
  String get clanAssetPath => 'Logolar/logo-klan/logo-klan-$tierNumber.png';
  static const String clanBaseAssetPath = 'Logolar/logo-klan/logo-klan-base.png';

  static const List<LeagueTier> allTiers = [
    LeagueTier(
      tierNumber: 1,
      individualName: 'Karbonmonoksit',
      clanName: 'Kül Birliği',
      individualThreshold: 0,
      clanThreshold: 0,
      color: AppColors.tier1CarbonMonoxide,
      symbol: 'CO',
    ),
    LeagueTier(
      tierNumber: 2,
      individualName: 'Karbondioksit',
      clanName: 'Sis Loncası',
      individualThreshold: 150,
      clanThreshold: 2500,
      color: AppColors.tier2CarbonDioxide,
      symbol: 'CO₂',
    ),
    LeagueTier(
      tierNumber: 3,
      individualName: 'Azot',
      clanName: 'Akım Cephesi',
      individualThreshold: 350,
      clanThreshold: 6000,
      color: AppColors.tier3Nitrogen,
      symbol: 'N₂',
    ),
    LeagueTier(
      tierNumber: 4,
      individualName: 'Oksijen',
      clanName: 'Koruyucu İttifak',
      individualThreshold: 650,
      clanThreshold: 12000,
      color: AppColors.tier4Oxygen,
      symbol: 'O₂',
    ),
    LeagueTier(
      tierNumber: 5,
      individualName: 'Ozon',
      clanName: 'Ozon Muhafızları',
      individualThreshold: 1100,
      clanThreshold: 25000,
      color: AppColors.tier5Ozone,
      symbol: 'O₃',
    ),
    LeagueTier(
      tierNumber: 6,
      individualName: 'Sönmez Biyosfer',
      clanName: 'Biyosfer Konseyi',
      individualThreshold: 1800,
      clanThreshold: 50000,
      color: AppColors.tier6Biosphere,
      symbol: 'BIO',
    ),
  ];

  static LeagueTier fromPoints(int points, {required LeagueCategory category}) {
    LeagueTier result = allTiers.first;
    for (final tier in allTiers) {
      final threshold = (category == LeagueCategory.individual)
          ? tier.individualThreshold
          : tier.clanThreshold;
      if (points >= threshold) {
        result = tier;
      }
    }
    return result;
  }
}
