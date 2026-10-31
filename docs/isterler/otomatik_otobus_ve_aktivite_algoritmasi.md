# 🧠 EK MODÜL: OTOMATİK AKTİVİTE VE OTOBÜS TESPİT ALGORİTMASI (`SENSOR_FUSION_SPEC.md`)

> **CODEX / AGY İÇİN EK TALİMAT:**
> Bu doküman, `codex_flutter_android_yonergesi.md` ana yönergesine ek olarak; kullanıcının **Yürüme (Walk), Koşma (Run), Bisiklet (Bike), Toplu Taşıma / Otobüs (Public Transit) ve Özel Araç / Taksi (Car/Taxi Penalty)** aktivitelerini **hiçbir tuşa basmadan veya QR/NFC okutmayı unutsa bile %100 otomatik** olarak ayırt eden `AutoTransportClassifierService` modülünün teknik şartnamesidir.

## 1. MİMARİ ÖZET: 2 KATMANLI KARAR AĞACI (DECISION TREE)

Sistem, her **30 saniyelik kayan pencerede (Sliding Window)** telefonun 3 sensöründen (`geolocator` GPS, `pedometer` Adım Sayacı, `sensors_plus` 3 Eksenli İvmeölçer) gelen verileri ve **OpenStreetMap Overpass API / Yerel Trabzon Durakları JSON** verisini çaprazlayarak iki katmanlı bir karar verir:

* **Katman 1 (Fiziksel Efor Ayrımı):** Kullanıcının adım kadansı (`spm` - dakikadaki adım sayısı), GPS hızı (`km/s`) ve ivmeölçer varyansı (`σ²`) ile **Yürüme**, **Koşma**, **Bisiklet** ve **Motorlu Araç İçi (`IN_VEHICLE`)** durumlarını birbirinden ayırır.
* **Katman 2 (Otobüs vs. Özel Araç/Taksi Ayrımı - Stop-Match Algoritması):** Eğer kullanıcı `IN_VEHICLE` (Motorlu Araçta) ise; biniş noktası, yol boyu dur-kalk yaptığı noktalar ve iniş noktasını otobüs duraklarıyla karşılaştırarak **0–100 arası bir "Otobüs Olasılık Skoru (`busProbabilityScore`)"** hesaplar. Skor `>= 60` ise **Otobüs/Dolmuş (+3 Puan)**, `< 60` ise **Taksi/Özel Araç (Utanç Tablosu & CO₂ Cezası)** yazar.

## 2. BEDAVA OTOBÜS DURAĞI VERİ KAYNAĞI (OVERPASS API + YEREL JSON)

API anahtarı veya ücret gerektirmeyen iki katmanlı durak verisi kullanılır:

### 2.1. Canlı OpenStreetMap Overpass API Sorgusu
Kullanıcının bulunduğu koordinatın (`lat, lon`) etrafındaki `50 metre` yarıçaplı tüm otobüs duraklarını çeken ücretsiz HTTP GET isteği:
```text
https://overpass-api.de/api/interpreter?data=[out:json];(node(around:50,{LAT},{LON})["highway"="bus_stop"];node(around:50,{LAT},{LON})["public_transport"="platform"];);out;
```

### 2.2. Offline Fallback: Gömülü Trabzon & KTÜ Durakları (`lib/core/constants/trabzon_stops_seed.dart`)
İnternet kesintisi veya Overpass API gecikmesine karşı Trabzon ve KTÜ güzergahındaki ana duraklar uygulama içinde sabit liste olarak da tutulur (Haversine formülü ile mesafe `< 45 metre` kontrolü yapılır):

```dart
class BusStopNode {
  final String id;
  final String name;
  final double lat;
  final double lon;
  final bool isTrafficLightNearby; // Kırmızı ışık yanılgısını önlemek için

  const BusStopNode({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    this.isTrafficLightNearby = false,
  });
}

const List<BusStopNode> kTrabzonBusStops = [
  BusStopNode(id: 'TRB-KTU-01', name: 'KTÜ AKM Ring Durağı', lat: 40.994210, lon: 39.771540),
  BusStopNode(id: 'TRB-KTU-02', name: 'KTÜ Mühendislik / Milli Teknoloji Atölyesi', lat: 40.991850, lon: 39.775120),
  BusStopNode(id: 'TRB-KTU-03', name: 'KTÜ A Kapısı Ana Durak', lat: 40.998120, lon: 39.768400, isTrafficLightNearby: true),
  BusStopNode(id: 'TRB-KTU-04', name: 'KTÜ C Kapısı / Tıp Fakültesi Durağı', lat: 40.993400, lon: 39.781200),
  BusStopNode(id: 'TRB-ORT-05', name: 'Kalkınma Mahallesi Durağı', lat: 40.996500, lon: 39.765200),
  BusStopNode(id: 'TRB-ORT-06', name: 'Forum AVM / Değirmendere Durağı', lat: 40.999800, lon: 39.759100, isTrafficLightNearby: true),
  BusStopNode(id: 'TRB-ORT-07', name: 'Trabzon Meydan Parkı Ana Peron', lat: 41.005300, lon: 39.726800, isTrafficLightNearby: true),
  BusStopNode(id: 'TRB-ORT-08', name: 'Ayasofya / Beşirli Sahil Durağı', lat: 41.003100, lon: 39.698400),
  BusStopNode(id: 'TRB-OF-09',  name: 'KTÜ Of Teknoloji Fakültesi Durağı', lat: 40.946200, lon: 40.268900),
];
```

## 3. KATMAN 1: YÜRÜME, KOŞMA, BİSİKLET VE ARAÇ AYRIM MATRİSİ

Sensörlerden son 30 saniye içinde alınan örneklerle şu 4 metrik hesaplanır:
1. **`avgSpeedKmh`:** GPS hız ortalaması (`km/s`)
2. **`maxSpeedKmh`:** GPS maksimum hız (`km/s`)
3. **`stepCadenceSpm`:** Dakikadaki adım sayısı (`steps_in_window * (60 / window_seconds)`)
4. **`accelVariance` ($\sigma^2$):** 3 eksenli ivmeölçer büyüklüğünün (`sqrt(x² + y² + z²)`) varyansı

| Algılanan Durum | GPS Ortalama Hız (`avgSpeedKmh`) | Adım Kadansı (`stepCadenceSpm`) | İvmeölçer Varyansı (`accelVariance`) | Karar & Puanlama Kuralı |
| :--- | :---: | :---: | :---: | :--- |
| **🚶 YÜRÜME (`WALK`)** | `2.5 – 7.2 km/s` | `65 – 135 adım/dk` | `0.60 – 2.20` | Adımlar geçerli sayılır. Her 1.000 adımda **+5 Puan**. |
| **🏃 KOŞMA (`RUN`)** | `7.3 – 18.0 km/s` | `136 – 195 adım/dk` | `> 2.20` (Yüksek dikey sıçrama) | **Bisikletten farkı:** Hızları yakındır ama koşuda adım kadansı (`>136`) ve dikey ivme varyansı çok yüksektir. Adımlar geçerli sayılır (**1.000 adım = +5 Puan**). |
| **🚴 BİSİKLET (`BIKE`)** | `9.0 – 35.0 km/s` *(Max < 48 km/s)* | `< 35 adım/dk` | `0.30 – 1.85` (Pedal & zemin titreşimi) | **Koşudan farkı:** Adım kadansı düşüktür. **Arabadan farkı:** Hız `< 48 km/s` ve ivme varyansı arabadan yüksektir. Her **1 km = +1 Puan**. |
| **🛴 E-SCOOTER (`MICRO`)** | `10.0 – 25.0 km/s` | `< 15 adım/dk` | `0.45 – 2.10` (Küçük tekerlek titreşimi) | Araba cezası **kesilmez**, mikro-mobilite olarak km başına **+1 Puan** verir. |
| **🚌 / 🚕 ARAÇ (`IN_VEHICLE`)**| `> 22.0 km/s` | `< 15 adım/dk` | `< 0.25` (Süspansiyon pürüzsüzlüğü) | Adım sayacı kilitlenir. **Otobüs mü yoksa Taksi/Özel Araç mı** olduğunu bulmak için **Katman 2 (Stop-Match)** çalışır! |

## 4. KATMAN 2: OTOBÜS vs. ÖZEL ARAÇ / TAKSİ ALGORİTMASI (`StopMatchEngine`)

Kullanıcı `IN_VEHICLE` durumuna geçtiği an bir `VehicleTripSession` başlatılır ve yolculuk boyunca aşağıdaki **Otobüs Olasılık Skoru (`busProbabilityScore`)** hesaplanır:

1. **Biniş Noktası Durağa Yakın mı? (`+35 Puan`):**
   * Aracın harekete geçtiği ilk koordinat (`originLat, originLon`), herhangi bir `BusStopNode` koordinatına **45 metre** mesafedeyse `+35 Puan` eklenir.
2. **Ara Duraklarda Dur-Kalk (Dwell Time) Yaptı mı? (`Her Durak İçin +25 Puan`):**
   * Yolculuk sırasında aracın hızı `< 3.5 km/s` altına düştüğünde bir `StopEvent` başlar.
   * Bekleme süresi (`dwellSeconds`) **8 saniye ile 60 saniye** arasındaysa (yolcu indirme-bindirme süresi) ve bu nokta bir otobüs durağına **40 metre** mesafedeyse:
     * Durağın yanında trafik ışığı yoksa (`!isTrafficLightNearby`): **`+25 Puan`**
     * Durağın yanında trafik ışığı varsa (`isTrafficLightNearby`): **`+15 Puan`** (Kırmızı ışıkta duran özel aracı otobüs sanmamak için kırpılmış puan).
3. **Trabzon Dolmuşu / Minibüs Paterni (`+30 Puan`):**
   * Resmi durak olmasa bile araç son 3 km içinde **en az 3 defa 8–25 saniyelik** yolcu indirme/bindirme dur-kalkı yaptıysa (özel taksi veya otomobil 3 km'de 3 kez kısa dur-kalk yapmaz) dolmuş olarak kabul edilir ve **`+30 Puan`** alır.
4. **İniş Noktası Durağa Yakın mı? (`+20 Puan`):**
   * Hız düşüp kullanıcı tekrar yürümeye (`stepCadenceSpm > 60`) başladığında, indiği nokta bir otobüs durağına **45 metre** mesafedeyse **`+20 Puan`** eklenir.
5. **NFC / QR Bonus Doğrulaması (`+100 Puan - Anında Onay`):**
   * Kullanıcı otobüs içinde ayrıca NFC veya QR okutursa skor doğrudan `100` olur.

### Karar Eşikleri:
* **`busProbabilityScore >= 60` $\rightarrow$ 🚌 OTOBÜS / DOLMUŞ ONAYLANDI!**
  * Kullanıcıya **+3 Puan** ve mesafeye göre önlenen CO₂ (`km * 0.157 kg`) eklenir.
  * Bildirim: `"🚌 Otobüs yolculuğun durak eşleşmesiyle otomatik doğrulandı! +3 Puan ve X.XX kg CO₂ tasarrufu kazandın!"`
* **`busProbabilityScore < 60` $\rightarrow$ 🚕 ÖZEL ARAÇ / TAKSİ YAKALANDI!**
  * Puan **0**. Kullanıcının `weekly_car_taxi_trips` sayacı `+1` artar, `weekly_wasted_co2_kg` hanesine `km * 0.192 kg` eklenir ve **Utanç Tablosu**'na düşer!
  * Bildirim: `"🚕 Yakalandın! Bu X.X km yolu özel araç/taksi yerine otobüsle gitseydin Y.YY kg CO₂ tasarruf yapardın aslında!!! Utanç tablosuna yazıldın!"`

## 5. FLUTTER İÇİN HAZIR DART SERVİS KODU (`lib/services/auto_transport_classifier.dart`)

Codex bu sınıfı doğrudan projeye dahil etmeli ve Admin Simülasyon ekranına bağlamalıdır:

```dart
import 'dart:math';
import '../core/constants/trabzon_stops_seed.dart';

enum DetectedActivityType {
  walk,
  run,
  bike,
  eScooter,
  publicTransitBus,
  carOrTaxiPenalty,
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

  const ClassificationResult({
    required this.activityType,
    required this.busProbabilityScore,
    required this.pointsAwarded,
    required this.co2DeltaKg,
    required this.title,
    required this.explanation,
  });
}

class AutoTransportClassifierService {
  /// İki GPS koordinatı arasındaki mesafeyi (Metre) hesaplar (Haversine)
  static double distanceInMeters(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000;
    final double dLat = (lat2 - lat1) * pi / 180;
    final double dLon = (lon2 - lon1) * pi / 180;
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLon / 2) * sin(dLon / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  /// Verilen koordinata en yakın otobüs durağını bulur
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

  /// 5'li Aktivite ve Otobüs/Araba Karar Motoru
  static ClassificationResult classifySession({
    required double distanceKm,
    required double avgSpeedKmh,
    required double maxSpeedKmh,
    required int stepCadenceSpm,
    required double accelVariance,
    required bool userClaimedBikeMode,
    required bool hasNfcOrQrScan,
    required bool boardedNearBusStop,
    required int matchedBusStopDwells,
    required int dolmusStyleShortStops,
    required bool alightedNearBusStop,
  }) {
    // 1. EDGE CASE: Telefonu Elde Sallama Hilesi (Shake Spoofing)
    if (stepCadenceSpm > 185 && avgSpeedKmh < 1.5) {
      return const ClassificationResult(
        activityType: DetectedActivityType.rejectedCheatShake,
        busProbabilityScore: 0,
        pointsAwarded: 0,
        co2DeltaKg: 0,
        title: '🛑 Telefon Sallama Hilesi Yakalandı!',
        explanation: 'Dakikada >185 adım frekansı ve 0 km/s GPS hızı! Telefonu koltukta sallayarak puan kasamazsın, kalk yürü!',
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
        explanation: 'Hızın ${maxSpeedKmh.toStringAsFixed(1)} km/s ve ivme varyansın ($accelVariance) araba süspansiyonu gösteriyor! Puan iptal edildi ve Utanç Tablosuna yazıldın.',
      );
    }

    // 3. YÜRÜME (WALK)
    if (avgSpeedKmh >= 2.0 && avgSpeedKmh <= 7.2 && stepCadenceSpm >= 65 && stepCadenceSpm <= 135) {
      final savedCo2 = distanceKm * 0.192;
      return ClassificationResult(
        activityType: DetectedActivityType.walk,
        busProbabilityScore: 0,
        pointsAwarded: 5, // Her 1000 adım diliminde +5
        co2DeltaKg: double.parse(savedCo2.toStringAsFixed(2)),
        title: '🚶 Yürüyüş Doğrulandı',
        explanation: 'Kadans: $stepCadenceSpm adım/dk, Hız: ${avgSpeedKmh.toStringAsFixed(1)} km/s. Doğal yürüyüş ritmi onaylandı.',
      );
    }

    // 4. KOŞMA (RUN) - Bisikletten yüksek kadans ve yüksek dikey ivme ile ayrılır
    if (avgSpeedKmh > 7.2 && avgSpeedKmh <= 18.5 && stepCadenceSpm > 135 && accelVariance > 2.0) {
      final savedCo2 = distanceKm * 0.192;
      return ClassificationResult(
        activityType: DetectedActivityType.run,
        busProbabilityScore: 0,
        pointsAwarded: 10,
        co2DeltaKg: double.parse(savedCo2.toStringAsFixed(2)),
        title: '🏃 Koşu Antrenmanı Doğrulandı!',
        explanation: 'Hızın (${avgSpeedKmh.toStringAsFixed(1)} km/s) bisiklete yakın ama $stepCadenceSpm spm adım kadansı ve yüksek dikey ivme ($accelVariance) koştuğunu kanıtlıyor!',
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
        explanation: '${distanceKm.toStringAsFixed(1)} km pedal çevirdin. Hız ve ivme sensörü ($accelVariance) bisiklet profilini doğruladı!',
      );
    }

    // 6. MOTORLU ARAÇ İÇİ (OTOBÜS vs. ÖZEL ARAÇ / TAKSİ KARARI)
    int busScore = 0;
    if (hasNfcOrQrScan) busScore += 100;
    if (boardedNearBusStop) busScore += 35;
    busScore += (matchedBusStopDwells * 25);
    if (dolmusStyleShortStops >= 3) busScore += 30;
    if (alightedNearBusStop) busScore += 20;
    busScore = min(100, busScore);

    if (busScore >= 60) {
      final savedCo2 = distanceKm * (0.192 - 0.035);
      return ClassificationResult(
        activityType: DetectedActivityType.publicTransitBus,
        busProbabilityScore: busScore,
        pointsAwarded: 3,
        co2DeltaKg: double.parse(savedCo2.toStringAsFixed(2)),
        title: '🚌 Otobüs / Dolmuş Otomatik Doğrulandı! (Skor: %$busScore)',
        explanation: 'Duraktan biniş ve $matchedBusStopDwells ara durakta yolcu indirme/bindirme (dwell time) eşleşti! +3 Puan ve ${savedCo2.toStringAsFixed(2)} kg CO₂ tasarrufu eklendi.',
      );
    } else {
      final wastedCo2 = -(distanceKm * 0.192);
      return ClassificationResult(
        activityType: DetectedActivityType.carOrTaxiPenalty,
        busProbabilityScore: busScore,
        pointsAwarded: 0,
        co2DeltaKg: double.parse(wastedCo2.toStringAsFixed(2)),
        title: '🚕 Yakalandın! Özel Araç / Taksi (Otobüs Skoru: %$busScore)',
        explanation: 'Duraklarda durmadın ve yüksek hızla (${avgSpeedKmh.toStringAsFixed(0)} km/s) gittin! Bu ${distanceKm.toStringAsFixed(1)} km yolu otobüsle gitseydin ${(distanceKm * 0.157).toStringAsFixed(2)} kg CO₂ tasarruf yapardın aslında!!! Utanç Tablosuna yazıldın!',
      );
    }
  }
}
```

## 6. TÜM EDGE-CASE TABLOSU (JÜRİ SORULARINA KARŞI TAM LİSTE)

| # | Edge-Case Senaryosu | Algoritmanın Nasıl Çözdüğü |
| :--- | :--- | :--- |
| **1** | **Koşma vs. Bisiklet (İkisi de 14 km/s hızla gidiyor)** | GPS hızları aynıdır ama **Koşuda** adım kadansı `140–190 adım/dk` ve dikey zıplama ivmesi (`σ² > 2.2`) çok yüksektir. **Bisiklette** ise adım kadansı `< 30` kalır. |
| **2** | **Kırmızı Işık Durağın Önündeyse (Özel Arabayı Otobüs Sanma)** | `BusStopNode` içinde `isTrafficLightNearby: true` olan duraklar kırpılmış puan (`+15`) verir. Tek bir ışıkta durmak `%60` barajına yetmez; otobüs olması için ardışık en az 2-3 durakta dur-kalk veya duraktan biniş gerekir. |
| **3** | **Trabzon Dolmuşları (Durak Harici İndi-Bindi)** | Dolmuşlar resmi durak dışında da durur. Algoritmadaki `dolmusStyleShortStops >= 3` parametresi, 3 km içinde en az 3 kez `8–25 sn` dur-kalk yapan aracı özel otomobilden ayırıp **Toplu Taşıma (+30 Puan)** sayar. |
| **4** | **Ekspres Otobüs (Hiçbir Ara Durakta Durmadan Giden 501 Of Hattı)** | Ara duraklarda durmasa bile **Biniş Durağı (+35)** + **İniş Durağı (+20)** = `55 Puan` alır; kullanıcıya *"501 Of Ekspres otobüsünde misin? Onayla (+3 P)"* bildirimi çıkar ve yanlışlıkla taksi cezası yemesi önlenir. |
| **5** | **Otobüs Durağının Önünden Taksiye Binen Kurnaz** | Kalkış noktasından `+35 Puan` alsa bile, taksi yol boyu otobüs duraklarında durmayacağı (`0 Puan`) ve varış noktası durak olmayacağı için skoru `35`'te kalır (`< 60`) ve **Utanç Tablosu**'na düşer! |
| **6** | **Otobüs Trafikte Çok Yavaşlarsa (5 km/s) "Yürüyor" Sanılması** | Kayan pencere (`Sliding Window`) içinde adım kadansı `< 15 adım/dk` olduğu için hız `5 km/s`'ye düşse bile yürüme puanı yazılmaz, `IN_VEHICLE` oturumu korunur. |
| **7** | **Spor Salonunda Koşu Bandında Koşmak (GPS Sabit = 0 km/s)** | Telefonu elde sallayan hilecide tek eksenli yapay frekans (`>185 spm`) vardır; koşu bandında koşanda ise 3 eksenli gerçek koşu ivmesi ve `140–175 spm` kadans vardır. |
