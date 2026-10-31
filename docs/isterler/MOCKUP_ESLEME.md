# Yeşil Adım — Mock-up Veri ve Bireysel Lig Logoları Eşleme Sözleşmesi

Bu doküman, kullanıcı tarafından sağlanan `supabase_schema_ve_mockup_veriler.sql` şeması/seed verisi ile `Logolar/logo-bireysel/` altındaki 6 adet lig logosunun uygulamaya entegrasyonunu belgeler.

---

## 1. Kaynak Veri Sayıları ve Kapsam

- **Supabase SQL Kaynağı:** `supabase_schema_ve_mockup_veriler.sql` dosyasındaki veriler doğrudan yerel seed ve şema kaynağı olarak kullanılmıştır. Dosya hiçbir canlı veritabanında çalıştırılmamıştır; canlı Supabase bağlantısı veya uzak backend mevcut değildir.
- **Kullanıcı Sayısı:** SQL users tablosunda tam 15 kullanıcı kaydı (`Sen (Efe)` dahil) tanımlıdır (SQL başlık yorumundaki "20" ifadesi yerine tablodaki 15 gerçek satır baz alınmış; 100'e tamamlamak için kullanıcı uydurulmamıştır).
- **Klan Sayısı:** SQL clans tablosunda 11 klan tanımlıdır. SQL dışı mevcut klan `clan_micro` (Yalnız Gezginler, 3 üye) ve kullanıcı klanları korunmuştur.
- **Toplu Taşıma Durakları:** SQL tablosunda 6 durak/hat tanımlıdır. Geriye dönük uyumluluk için `TRB-OF-204` aliası korunmuştur.
- **Mağaza Ürünleri:** SQL tablosunda 8 aktif ürün tanımlıdır.
- **Bireysel Lig Logoları:** `Logolar/logo-bireysel/lig-bireysel-1.png` ... `lig-bireysel-6.png` kod-native asset olarak sisteme dahil edilmiş, `BoxFit.contain` ile oranları korunmuştur. Toplu `erasebg-transformed.png` görseli kullanılmamıştır.

---

## 2. SQL Tamsayı Klan ID → Kalıcı String ID Deterministik Eşlemesi

SQL dosyasındaki tamsayı (integer) `clans.id` değerleri, uygulamanın mevcut kalıcı string ID yapısıyla deterministik olarak eşlenmiştir:

| SQL ID | Klan Adı | Kalıcı String ID | Üye Sayısı | Haftalık Puan | Tüm Zamanlar Puan |
|:---:|:---|:---|:---:|:---:|:---:|
| 1 | KTÜ Kanuni | `clan_ktu_kanuni` | 142 | 125.430 | 480.200 |
| 2 | KTÜ OF | `clan_ktu_of` | 98 | 98.210 | 365.000 |
| 3 | ODTÜ | `clan_odtu` | 115 | 87.540 | 410.500 |
| 4 | Koç Üni | `clan_koc` | 84 | 76.320 | 290.100 |
| 5 | Sabancı Üni | `clan_sabanci` | 76 | 69.430 | 255.400 |
| 6 | İTÜ | `clan_itu` | 92 | 54.210 | 310.000 |
| 7 | YTÜ | `clan_ytu` | 68 | 48.960 | 198.000 |
| 8 | Gazi Üni | `clan_gazi` | 61 | 42.180 | 175.300 |
| 9 | KTÜ Dağcılık Kulübü | `clan_ktu_dagcilik` | 34 | 38.450 | 142.000 |
| 10 | Sincanlılar Derneği | `clan_sincan` | 45 | 29.800 | 112.000 |
| 11 | Kırıkkale_45 | `clan_kirikkale` | 29 | 18.400 | 64.500 |
| — | Yalnız Gezginler (Mevcut) | `clan_micro` | 3 | 9.500 | 30.000 |

*Not: Gerçek kullanıcının SQL dışındaki klan referansları (örneğin `clan_micro`), kendi oluşturduğu klanlar ve yaptığı katkılar veri yükseltmesinde tamamen korunur.*

---

## 3. SQL `league_tier` Uyumsuzlukları ve Gerçek Eşik Kuralı

Şartname ve SQL `leagues` tablosundaki gerçek bireysel lig eşikleri:
1. **Karbonmonoksit (Tier 1):** 0 P
2. **Karbondioksit (Tier 2):** 150 P
3. **Azot (Tier 3):** 350 P
4. **Oksijen (Tier 4):** 650 P
5. **Ozon (Tier 5):** 1.100 P
6. **Sönmez Biyosfer (Tier 6):** 1.800 P

**Uyumsuzluk Notu:**
SQL seed verisinde `Sen (Efe)` 8.960 puan ile Tier 4 (Oksijen) olarak, `Burak Demir` (11.230 P) Tier 5 olarak etiketlenmiştir. Ancak şartname ve lig kuralları gereği 1.800 puan ve üzeri Tier 6 (Sönmez Biyosfer) ligine karşılık gelir. Uygulamamız demo görünümü uğruna puan hesaplama motorunu bozmamış; `LeagueTier.fromPoints` fonksiyonu puandan türetilen gerçek lig derecesini dinamik ve tutarlı olarak hesaplamaktadır.

---

## 4. Mağaza Ürünleri ve Legacy Envanter Alias Eşlemesi

SQL dosyasındaki 8 ürün aktif katalog olarak sunulmuştur. Önceki sürümlerde satın alınmış ürünler ve kuşanılmış kimlikler alias eşlemesiyle korunmuş, kullanıcıdan tekrar para alınması önlenmiştir:

| SQL Item Slug | Kategori | Fiyat (🪙) | Başlık | Eski (Legacy) Alias |
|:---|:---:|:---:|:---|:---|
| `frame_oxygen_glow` | Çerçeve | 450 | Oksijen Neon Çerçevesi | `oxygen_frame` |
| `frame_ozone_purple` | Çerçeve | 800 | Ozon Kalkanı Çerçevesi | — |
| `frame_biosfer_gold` | Çerçeve | 1500 | Sönmez Biyosfer Tacı | `biosphere_crown` |
| `pet_pine_sprout` | Yoldaş | 600 | Yürüyen Çam Fidanı (Pet) | `pine_seedling` |
| `pet_robo_bee` | Yoldaş | 950 | Biyo-Mekanik Arı (Pet) | `biomech_bee` |
| `pet_leaf_fox` | Yoldaş | 1200 | Orman Tilkisi (Pet) | `forest_fox` |
| `ava_cycling_pro` | Avatar | 350 | Aero Bisikletçi Avatarı | `solar_guardian` |
| `ava_ktu_mountaineer` | Avatar | 500 | Kaçkar Dağcısı Avatarı | `leaf_warrior` |

*Kullanıcı `oxygen_frame` veya `leaf_warrior` almışsa, yükseltme sonrasında hem eski hem yeni slug'a sahip sayılır (`owned`); kuşanılmış eşya insan okunur başlığıyla profil kartında gösterilir.*

---

## 5. Transit Durakları & QR / NFC Normalizasyonu

| Kod | Durak Adı | Hat | CO₂ Tasarrufu | NFC UID | QR Payload |
|:---|:---|:---|:---:|:---|:---|
| `TRB-KTU-01` | KTÜ Atatürk Kültür Merkezi Durağı | Kampüs Ring - Hat 1 | 0.58 kg | `04:A1:2B:9C:11:80:01` | `YESILADIM://TRANSIT/TRB-KTU-01?sig=9f8a7b` |
| `TRB-KTU-02` | KTÜ Mühendislik / MTA | Kampüs Ring - Hat 2 | 0.63 kg | `04:A1:2B:9C:11:80:02` | `YESILADIM://TRANSIT/TRB-KTU-02?sig=3c4d5e` |
| `TRB-BLD-101`| KTÜ A Kapısı - Meydan | Belediye Otobüsü 101 | 1.22 kg | `04:B2:4C:8D:22:90:10` | `YESILADIM://TRANSIT/TRB-BLD-101?sig=7e6f5a` |
| `TRB-BLD-104`| Kalkınma - Beşirli - Ayasofya | Belediye Otobüsü 104 | 2.05 kg | `04:B2:4C:8D:22:90:14` | `YESILADIM://TRANSIT/TRB-BLD-104?sig=1a2b3c` |
| `TRB-BLD-501`| KTÜ Kanuni - Of Teknoloji Fak. | Belediye Ekspres 501 | 9.36 kg | `04:C3:5D:7E:33:A0:50` | `YESILADIM://TRANSIT/TRB-BLD-501?sig=8d9e0f` |
| `ANK-EGO-411`| ODTÜ Metro - Kızılay Aktarma | EGO 411 & Başkentray | 1.65 kg | `04:D4:6E:6F:44:B0:41` | `YESILADIM://TRANSIT/ANK-EGO-411?sig=4f5a6b` |

- QR payload'ındaki `?sig=...` demo parametresi ayıklanarak durak koduna indirgenir; sahte imza doğrulaması iddiasında bulunulmaz.
- NFC UID kolonlu (`04:A1:2B:...`) ve kolonsuz (`04A12B...`) hex formatlarında desteklenir; canonical durak koduna dönüştürülür.
- Ortak 45 dakika kuralı QR ve NFC binişleri arasında durak kodu bazında ortak işletilir.

---

## 6. Sürümlü Veri Yükseltmesi (Migration Seed v3)

- `AppStore` yükleme sırasında `seedVersion < 3` kontrolü yapar.
- Gerçek profil (`me`), adı, biyografisi, fotoğraf yolu, adımları, streak'i, altınları ve klan puan katkıları **asla sıfırlanmaz veya ezilmez**.
- SQL dosyasındaki `Sen (Efe)` kaydı `isDemo: true` olan ayrı bir demo kaydıdır; gerçek cihaz sahibinin yerine geçmez.
- Geçiş sonrasında `seedVersion = 3` olarak kaydedilir. İkinci açılış veya yeniden başlatma **idempotenttir**; veriler tekrar ezilmez.

---

## 7. Bireysel Lig Logoları ve Klan Ayrımı

- `IndividualLeagueBadge` ortak bileşeni:
  - 1..6 numaralı PNG dosyalarını (`Logolar/logo-bireysel/lig-bireysel-1.png` ... `6.png`) `BoxFit.contain` ile gösterir.
  - Ana sayfa bireysel lig kartında (34x34) ve sıralama satırlarındaki bireysel lig rozetlerinde (20x20) kullanılır.
  - Görsel yüklenemediğinde veya test ortamında renkli/sembollü dekoratif fallback'e döner.
- **Klan Ligleri:** Klan görselleri henüz bulunmadığından klanlara bu bireysel logolar atanmamış; klanlar mevcut kalkan ve renk rozetini korumuştur.

---

## 8. Eksik Varlıklar ve Canlı Özellik Sınırları

- Avatar, çerçeve ve pet görselleri kullanıcı tarafından henüz sağlanmadığından insan okunur başlıklar ve emoji sembolleri fallback olarak kullanılmaktadır.
- SQL'deki `activities` logları ve Realtime admin RPC fonksiyonları canlı backend gerektirdiğinden bu aşamada yerel referans olarak kalmıştır; yerel veritabanında uydurma canlı özellik yapılmamıştır.
