import '../models/app_user.dart';
import '../models/clan.dart';
import '../models/shop_item.dart';
import '../models/transit_stop.dart';

/// Şartnamedeki örnek (DEMO) veriler. Gerçek kullanıcı/backend verisi DEĞİLDİR.
class DemoData {
  DemoData._();

  static List<Clan> clans() => const [
        Clan(id: 'clan_ktu_kanuni', name: 'KTÜ Kanuni', memberCount: 142, weeklyPoints: 125430, allTimePoints: 840000),
        Clan(id: 'clan_ktu_of', name: 'KTÜ OF', memberCount: 88, weeklyPoints: 98210, allTimePoints: 620000),
        Clan(id: 'clan_odtu', name: 'ODTÜ', memberCount: 95, weeklyPoints: 87540, allTimePoints: 590000),
        Clan(id: 'clan_itu', name: 'İTÜ', memberCount: 76, weeklyPoints: 72100, allTimePoints: 480000),
        Clan(id: 'clan_ytu', name: 'YTÜ', memberCount: 64, weeklyPoints: 66000, allTimePoints: 430000),
        Clan(id: 'clan_koc', name: 'Koç Üni', memberCount: 42, weeklyPoints: 61500, allTimePoints: 410000),
        Clan(id: 'clan_sabanci', name: 'Sabancı Üni', memberCount: 38, weeklyPoints: 54200, allTimePoints: 370000),
        Clan(id: 'clan_gazi', name: 'Gazi Üni', memberCount: 52, weeklyPoints: 49800, allTimePoints: 320000),
        Clan(id: 'clan_ktu_dagcilik', name: 'KTÜ Dağcılık Kulübü', memberCount: 29, weeklyPoints: 43200, allTimePoints: 290000),
        Clan(id: 'clan_sincan', name: 'Sincanlılar Derneği', memberCount: 22, weeklyPoints: 31000, allTimePoints: 195000),
        Clan(id: 'clan_kirikkale', name: 'Kırıkkale_45', memberCount: 16, weeklyPoints: 18400, allTimePoints: 110000),
        Clan(id: 'clan_micro', name: 'Yalnız Gezginler', memberCount: 3, weeklyPoints: 9500, allTimePoints: 30000),
      ];

  static List<AppUser> users() => const [
        AppUser(id: 'demo_1', deviceId: 'demo', username: 'Zeynep Kaya', clanId: 'clan_ktu_kanuni', clanName: 'KTÜ Kanuni', isDemo: true, weeklyPoints: 1850, allTimePoints: 13500),
        AppUser(id: 'demo_2', deviceId: 'demo', username: 'Ahmet Yılmaz', clanId: 'clan_ktu_of', clanName: 'KTÜ OF', isDemo: true, weeklyPoints: 1200, allTimePoints: 11000),
        AppUser(id: 'demo_3', deviceId: 'demo', username: 'Elif Demir', clanId: 'clan_odtu', clanName: 'ODTÜ', isDemo: true, weeklyPoints: 700, allTimePoints: 9800, weeklyCarTaxiTrips: 1, weeklyWastedCo2Kg: 2.1),
        AppUser(id: 'demo_s1', deviceId: 'demo', username: 'Pelin Aydın', clanId: 'clan_koc', clanName: 'Koç Üni', isDemo: true, weeklyPoints: 120, weeklyCarTaxiTrips: 14, weeklyWastedCo2Kg: 52.6),
        AppUser(id: 'demo_s2', deviceId: 'demo', username: 'Berkcan Yıldız', clanId: 'clan_sabanci', clanName: 'Sabancı Üni', isDemo: true, weeklyPoints: 240, weeklyCarTaxiTrips: 11, weeklyWastedCo2Kg: 44.2),
        AppUser(id: 'demo_s3', deviceId: 'demo', username: 'Oğuzhan Çelik', clanId: 'clan_sincan', clanName: 'Sincanlılar Derneği', isDemo: true, weeklyPoints: 310, weeklyCarTaxiTrips: 9, weeklyWastedCo2Kg: 38.7),
      ];

  static const List<TransitStop> stops = [
    TransitStop(code: 'TRB-KTU-01', name: 'KTÜ Kampüs Ring', line: 'A-1 Kampüs İçi', co2SavingKg: 1.22),
    TransitStop(code: 'TRB-BLD-101', name: 'Meydan - KTÜ 101', line: '101 Belediye Hattı', co2SavingKg: 1.22),
    TransitStop(code: 'TRB-OF-204', name: 'Trabzon - Of Hattı', line: '204 Of', co2SavingKg: 2.45),
  ];

  static const List<ShopItem> shopItems = [
    ShopItem(id: 'leaf_warrior', title: 'Yaprak Savaşçısı Avatarı', description: 'Yeşil profil avatarı.', category: ShopCategory.avatar, price: 500, iconCode: 'leaf'),
    ShopItem(id: 'solar_guardian', title: 'Güneş Muhafızı Avatarı', description: 'Parlayan avatar.', category: ShopCategory.avatar, price: 800, iconCode: 'sun'),
    ShopItem(id: 'oxygen_frame', title: 'Oksijen Neon Çerçevesi', description: 'Turkuaz oksijen çerçevesi.', category: ShopCategory.frame, price: 650, iconCode: 'frame'),
    ShopItem(id: 'biosphere_crown', title: 'Sönmez Biyosfer Tacı', description: 'Altın yaprak tacı.', category: ShopCategory.frame, price: 1500, iconCode: 'crown'),
    ShopItem(id: 'pine_seedling', title: 'Yürüyen Çam Fidanı', description: 'Fidan yoldaş.', category: ShopCategory.pet, price: 900, iconCode: 'tree'),
    ShopItem(id: 'biomech_bee', title: 'Biyo-Mekanik Arı', description: 'Robotik arı yoldaş.', category: ShopCategory.pet, price: 1200, iconCode: 'bug'),
    ShopItem(id: 'forest_fox', title: 'Orman Tilkisi', description: 'Tilki yoldaş.', category: ShopCategory.pet, price: 1800, iconCode: 'paw'),
  ];
}
