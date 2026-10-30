import 'package:flutter_test/flutter_test.dart';
import 'package:green_project/core/utils/name_masker.dart';
import 'package:green_project/models/clan.dart';
import 'package:green_project/models/league_tier.dart';
import 'package:green_project/services/activity_validation_service.dart';

void main() {
  const r = ActivityValidationService();

  group('Adım puanı', () {
    test('0/900/999/1000/1999/2000 eşikleri', () {
      expect(r.stepPoints(0, 0), 0);
      expect(r.stepPoints(0, 900), 0);
      expect(r.stepPoints(0, 999), 0);
      expect(r.stepPoints(0, 1000), 5);
      expect(r.stepPoints(0, 1999), 5);
      expect(r.stepPoints(0, 2000), 10);
    });
    test('6666 +334 = 7000 yalnız +5; azalma/negatif puan yaratmaz', () {
      expect(r.stepPoints(6666, 7000), 5);
      expect(r.stepPoints(7000, 6666), 0);
      expect(r.stepPoints(-5, 100), 0);
    });
  });

  group('Adım hile kuralı', () {
    test('kadans 185 geçerli, 186 reddedilir', () {
      expect(r.checkSteps(deltaSteps: 185, minutes: 1).ok, true);
      expect(r.checkSteps(deltaSteps: 186, minutes: 1).ok, false);
    });
    test('sallama 3.5 Hz sınırı + hareketsiz GPS', () {
      expect(r.checkSteps(deltaSteps: 50, minutes: 1, shakeHz: 3.5, gpsMovementMeters: 0).ok, true);
      expect(r.checkSteps(deltaSteps: 50, minutes: 1, shakeHz: 3.6, gpsMovementMeters: 0).ok, false);
      expect(r.checkSteps(deltaSteps: 50, minutes: 1, shakeHz: 3.6, gpsMovementMeters: 50).ok, true);
    });
    test('GPS ölçümü yoksa (null) hareket=0 varsayılmaz, suçlama yok', () {
      expect(r.checkSteps(deltaSteps: 50, minutes: 1, shakeHz: 5.0, gpsMovementMeters: null).ok, true);
    });
    test('geçersiz artış reddedilir', () {
      expect(r.checkSteps(deltaSteps: 0).ok, false);
      expect(r.checkSteps(deltaSteps: -3).ok, false);
    });
  });

  group('Transit', () {
    test('payload ayrıştırma', () {
      expect(r.parseTransitPayload('YESILADIM://TRANSIT/TRB-KTU-01'), 'TRB-KTU-01');
      expect(r.parseTransitPayload('yesiladim://transit/trb-ktu-01'), 'TRB-KTU-01');
      expect(r.parseTransitPayload(' TRB-BLD-101 '), 'TRB-BLD-101');
      expect(r.parseTransitPayload(''), isNull);
      expect(r.parseTransitPayload(null), isNull);
      expect(r.parseTransitPayload('http://evil/x y'), isNull);
    });
    test('cooldown 44:59 reddet, 45:00 kabul, geri alınmış saat reddedilir', () {
      final t = DateTime(2026, 10, 26, 12);
      expect(r.transitRemaining(null, t), isNull);
      expect(r.transitRemaining(t, t.add(const Duration(minutes: 44, seconds: 59))), isNotNull);
      expect(r.transitRemaining(t, t.add(const Duration(minutes: 45))), isNull);
      expect(r.transitRemaining(t, t.subtract(const Duration(minutes: 5))), isNotNull);
    });
  });

  group('Bisiklet', () {
    BikeVerdict b(double km, {double max = 20, double avg = 15, double? v}) =>
        r.checkBike(distanceKm: km, maxSpeedKmh: max, avgSpeedKmh: avg, fastAccelVariance: v);
    test('0.999/1/1.999/2 km puan', () {
      expect(b(0.999).points, 0);
      expect(b(1).points, 1);
      expect(b(1.999).points, 1);
      expect(b(2).points, 2);
    });
    test('anlık 50 ve üstü, ortalama 35 ve üstü reddedilir', () {
      expect(b(3, max: 49.99).status, BikeStatus.accepted);
      expect(b(3, max: 50).status, BikeStatus.rejectedSpeedSpoof);
      expect(b(3, avg: 34.99, max: 40).status, BikeStatus.accepted);
      expect(b(3, avg: 35, max: 40).status, BikeStatus.rejectedSpeedSpoof);
    });
    test('25 km/sa ve 0.12 varyans sınırı', () {
      expect(b(3, avg: 25, v: 0.01).status, BikeStatus.accepted);
      expect(b(3, avg: 25.01, v: 0.11).status, BikeStatus.carTaxiPenalty);
      expect(b(3, avg: 25.01, v: 0.12).status, BikeStatus.accepted);
      expect(b(3, avg: 28, v: null).status, BikeStatus.accepted); // veri yok = suçlama yok
    });
    test('ceza CO₂ = km × 0.192; ödül yok', () {
      final v = b(10, avg: 28, max: 30, v: 0.05);
      expect(v.wastedCo2Kg, closeTo(1.92, 1e-9));
      expect(v.points, 0);
      expect(v.co2SavedKg, 0);
    });
    test('negatif/NaN/sonsuz geçersiz', () {
      expect(b(-1).status, BikeStatus.invalidData);
      expect(b(double.nan).status, BikeStatus.invalidData);
      expect(b(1, max: double.nan).status, BikeStatus.invalidData);
      expect(b(1, avg: double.infinity).status, BikeStatus.invalidData);
      expect(b(1, max: -3).status, BikeStatus.invalidData);
    });
  });

  group('Araba/taksi', () {
    test('30 km/sa sınırı ve adım artışı', () {
      expect(r.checkVehicle(avgSpeedKmh: 30, distanceKm: 5, stepDelta: 0, transitInLast45Min: false).detected, false);
      expect(r.checkVehicle(avgSpeedKmh: 30.1, distanceKm: 5, stepDelta: 0, transitInLast45Min: false).detected, true);
      expect(r.checkVehicle(avgSpeedKmh: 68, distanceKm: 5, stepDelta: 500, transitInLast45Min: false).detected, false);
    });
    test('son 45 dk transit varsa tespit yok', () {
      expect(r.checkVehicle(avgSpeedKmh: 68, distanceKm: 5, stepDelta: 0, transitInLast45Min: true).detected, false);
    });
    test('veri yoksa suçlama yok; mesafe×0.192', () {
      expect(r.checkVehicle(avgSpeedKmh: null, distanceKm: 5, stepDelta: 0, transitInLast45Min: false).detected, false);
      expect(r.checkVehicle(avgSpeedKmh: 60, distanceKm: 5, stepDelta: null, transitInLast45Min: false).detected, false);
      expect(r.checkVehicle(avgSpeedKmh: double.nan, distanceKm: 5, stepDelta: 0, transitInLast45Min: false).detected, false);
      final v = r.checkVehicle(avgSpeedKmh: 68, distanceKm: 8.5, stepDelta: 0, transitInLast45Min: false);
      expect(v.wastedCo2Kg, closeTo(8.5 * 0.192, 1e-9));
      expect(v.message, contains('1.63'));
    });
  });

  group('Klan / maske / lig', () {
    test('4 üye hariç, 5 üye dahil', () {
      expect(const Clan(id: 'a', name: 'a', memberCount: 4, weeklyPoints: 1).isEligibleForRanking, false);
      expect(const Clan(id: 'a', name: 'a', memberCount: 5, weeklyPoints: 1).isEligibleForRanking, true);
    });
    test('hibrit formül ve boş klan', () {
      expect(const Clan(id: 'a', name: 'a', memberCount: 10, weeklyPoints: 1000).hybridScore, 2600.0);
      expect(const Clan(id: 'a', name: 'a', memberCount: 0, weeklyPoints: 1000).hybridScore, 0.0);
    });
    test('maskeleme: boş, 1-2 harf, Türkçe, emoji', () {
      expect(NameMasker.maskShameName(''), '***');
      expect(NameMasker.maskShameName('  '), '***');
      expect(NameMasker.maskShameName('A'), 'A***');
      expect(NameMasker.maskShameName('Su'), 'Su***');
      expect(NameMasker.maskShameName('Oğuzhan'), 'Oğu***');
      expect(NameMasker.maskShameName('İşıl'), 'İşı***');
      expect(NameMasker.maskShameName('🦁🐯🐻🐼'), '🦁🐯🐻***');
      expect(NameMasker.maskShameName('👨‍👩‍👧Ali'), '👨‍👩‍👧Al***');
    });
    test('lig eşikleri (8.960 puan eşiklere göre Sönmez Biyosfer)', () {
      String ind(int p) => LeagueTier.fromPoints(p, category: LeagueCategory.individual).individualName;
      expect(ind(0), 'Karbonmonoksit');
      expect(ind(149), 'Karbonmonoksit');
      expect(ind(150), 'Karbondioksit');
      expect(ind(649), 'Azot');
      expect(ind(650), 'Oksijen');
      expect(ind(1800), 'Sönmez Biyosfer');
      expect(ind(8960), 'Sönmez Biyosfer');
      expect(LeagueTier.fromPoints(24999, category: LeagueCategory.clan).clanName, 'Koruyucu İttifak');
      expect(LeagueTier.fromPoints(25000, category: LeagueCategory.clan).clanName, 'Ozon Muhafızları');
    });
  });
}
