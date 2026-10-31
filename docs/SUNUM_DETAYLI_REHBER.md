# Yeşil Adım — Detaylı Sunum ve Ders Rehberi

Bu rehber, kısa sunum notu ([SUNUM_CALISMA_REHBERI.md](SUNUM_CALISMA_REHBERI.md)) yetmediğinde çalışmak içindir. Algoritma ayrıntısı için [ALGORITMALAR_VE_MIMARI.md](ALGORITMALAR_VE_MIMARI.md) yardımcı kaynaktır; **çelişki olursa bu rehber ve kaynak kod esas alınır** (bkz. bölüm 16, o belgedeki eski QR anlatımı).

> [!IMPORTANT]
> **Doğrulanacak not (sunumdan önce):** "GM'den 600.000 adım verince puanın artmaması" ve "cihazlar arasında utanç (shame) listesinin farklı görünmesi" hatası ayrı bir çalışmada düzeltiliyor. Düzeltme dosyası ([11_gm_steps_points_and_shame_fix.sql](../supabase/migrations/11_gm_steps_points_and_shame_fix.sql)) ve ön deneme dosyası ([preflight_gm_steps_and_shame_fix.sql](../supabase/preflight_gm_steps_and_shame_fix.sql)) depoda var. Ancak bu rehberi yazarken **canlı sunucuya uygulandığı ve iki telefonda sonucun düzeldiği doğrulanmadı**. "Çözüldü" demeyin; son sürümde (DURUM.md + iki telefon) kontrol edin. Bu rehberin yazıldığı sırada dosya henüz commitlenmemişti (commit listesinde yok).

---

## 1. Önce açık sözlük (jargon yok, hepsi günlük örnekle)

| Terim | Sade anlamı | Örnek |
|---|---|---|
| Sensör | Telefonun içindeki ölçüm parçası | Adım sayar, ivmeölçer (sallanma), GPS (konum) |
| Kotlin köprüsü | Telefonun işletim sistemiyle konuşan küçük Android kodu; Flutter sensöre doğrudan erişemez | Tercüman: Android "1000 adım" der, tercüman Dart'a iletir |
| Dart / Flutter | Uygulamanın asıl yazıldığı dil/araç | Ekranlar ve kurallar burada |
| Store (`AppStore`) | Uygulamanın "hafızası ve karar merkezi": puan, adım, altın hep burada tutulur | Defter tutan muhasebeci |
| Outbox (giden kutusu) | Sunucuya gidecek olayları önce telefonda bekleten kuyruk | Postaneye gidemeyince mektubu çekmeceye koymak |
| Supabase | Ortak sunucu (veritabanı + giriş sistemi). Tüm telefonlar aynı yeri okur | Herkesin baktığı ortak skor panosu |
| RPC | Sunucudaki hazır "işlem fonksiyonu". Telefon tabloyu elle değiştirmez, fonksiyonu çağırır | Banka gişesi: kasaya el sokamazsın, gişeye talep verirsin |
| RLS | Sunucuda "bu satırı kim görebilir/değiştirebilir" kuralı | Herkes ortak listeyi görür ama yalnız kendi defterini düzenler |
| Anonim giriş | E-posta/şifre yok; sunucu uygulamaya gizli bir kimlik verir | Kulüp giriş bileti: adın yok ama numaran var |
| Idempotency (tekrarın etkisiz olması) | Aynı isteğin iki kez gelmesi ikinci kez ödül vermez | Asansör düğmesine 5 kez basınca asansör 5 kez gelmez |
| Outbox "eventId" | Her olaya verilen tekil numara | Fiş numarası |
| GM paneli | Yönetici (jüri/geliştirici) panelinin bilgisayardaki web sayfası | Kumanda masası |
| Debug / demo | Gerçek sensör olmadan puan vermeyi simüle eden araçlar | Jüri için sahte yürüyüş düğmesi |

---

## 2. Proje: problem ve çözüm (1 dakikalık özet)

**Problem:** İnsanlar yürüyebilecekleri yolu araçla gidiyor; ama "çevre için yürü" demek tek başına motive etmiyor.

**Çözüm:** Telefonun adım sayarıyla yürüyüşü ölçüp **puan** veriyoruz. Puanlar haftalık yarışmaya girer (bireysel + klan), hafta sonu **altına** çevrilir, altınla avatar/çerçeve/evcil hayvan alınır. Araçla gereksiz gidenler "utanç tablosunda" görünür (şaka tadında rekabet). Bisiklet de otomatik algılanır.

**Dürüst sınır:** Telefon sensörü kişinin arabada mı yürüyüşte mi olduğunu *kesin* kanıtlayamaz. Bu yüzden sistem veri eksikse kimseyi cezalandırmaz.

---

## 3. Bugünkü gerçek durum (tek tablo)

| Konu | Durum |
|---|---|
| Gerçek adım sensörü → puan | Var (kodda); bağlı telefonda canlı doğrulama kullanıcıya ait |
| Adım: 1.000 adım = 5 puan | Var, testli |
| Otomatik bisiklet (kartta Bitir/İptal) | Var |
| Otomatik araba/taksi (utanç) | Kurallar kodda; tek başına kesin kanıt değildir |
| Otomatik **otobüs** | **Ana sürümde yok.** Taslak ayrı dalda (`wip/automatic-bus`), birleştirilmedi, canlı yolculukla doğrulanmadı |
| 500 m kısa otobüs cezası | **Etkin DEĞİL.** Kural ve birim testi taslak/hazır; canlı ceza altyapısı bilerek açılmadı |
| QR/NFC okutma ekranı | **Kaldırıldı.** Alt menü 3 sekme |
| Gerçek push bildirimi (FCM) | **Yok** |
| Uygulama kapalıyken bildirim | **Garanti yok** |
| Arka planda adım/konum takibi | **Garanti yok** (ön plan odaklı) |
| Ortak sunucu | Supabase, anonim giriş çalışıyor |
| Realtime (anında canlı akış) | İki oturumlu testte aynı veri okunuyor; 3 telefonda ekranın kendiliğinden güncellendiği **kanıtlanmadı** |
| GM 600k adım→puan, shame cihaz farkı | **Düzeltme hazırlanıyor, doğrulanmadı** (başa bkz.) |

Son güvenlik taraması kaydı: 0 hata, 14 uyarı (DURUM.md). "Tüm uyarılar giderildi" denmemeli.

---

## 4. Mimari ve veri akışı

```text
[Telefon sensörü: adım sayar / ivmeölçer / GPS]
        │
[Kotlin köprüsü]  MainActivity.kt  (kanal: com.yesiladim.ecoclan/hardware ve /events)
        │
[Dart: HardwareBridge → SensorController → AppStore]
        │   30 sn pencere + kural kontrolü (ActivityValidationService)
        │   puan yerelde hemen yazılır, telefona kaydedilir
        ▼
[Outbox kuyruğu]  telefonda bekler (internet yoksa)
        │   eventId ile
        ▼
[Supabase ortak sunucu]  RPC fonksiyonları + RLS + ortak görünümler
        │
        ├──► Başka telefonlar sıralamayı buradan okur
        └──► PC'deki GM paneli (127.0.0.1:8787) yönetici oturumuyla buraya komut yollar
```

### Ne nerede? (gerçek dosyalar)

| Görev | Dosya |
|---|---|
| Android sensör/izin köprüsü | [MainActivity.kt](../android/app/src/main/kotlin/com/yesiladim/ecoclan/green_project/MainActivity.kt) |
| Köprünün Dart yüzü | [hardware_bridge.dart](../lib/services/hardware_bridge.dart) |
| Sensör olaylarını store'a taşır | [sensor_controller.dart](../lib/services/sensor_controller.dart) |
| Servisleri bağlar (açılış) | [main.dart](../lib/main.dart), [hub.dart](../lib/services/hub.dart) |
| Karar merkezi (puan, gün, klan, mağaza) | [app_store.dart](../lib/services/app_store.dart) |
| Saf kurallar (adım, bisiklet, araba, 45 dk) | [activity_validation_service.dart](../lib/services/activity_validation_service.dart) |
| Otomatik bisiklet/yürüyüş motoru | [auto_motion_engine.dart](../lib/services/auto_motion_engine.dart) |
| Araç türü sınıflandırıcı (taslak mantık dahil) | [auto_transport_classifier.dart](../lib/services/auto_transport_classifier.dart) |
| Giden kutusu | [supabase_outbox.dart](../lib/services/supabase_outbox.dart) |
| Sunucu çağrıları | [supabase_service.dart](../lib/services/supabase_service.dart) |
| GM komutları (telefon tarafı) | [command_dispatcher.dart](../lib/services/command_dispatcher.dart), [gm_server.dart](../lib/services/gm_server.dart) |
| Sıralama penceresi (ilk 10 + sen) | [leaderboard_window.dart](../lib/core/utils/leaderboard_window.dart) |
| Klan, lig modeli | [clan.dart](../lib/models/clan.dart), [league_tier.dart](../lib/models/league_tier.dart) |
| Ekranlar | [home_screen.dart](../lib/screens/home/home_screen.dart), [leaderboard_screen.dart](../lib/screens/leaderboard/leaderboard_screen.dart), [shop_profile_screen.dart](../lib/screens/shop_profile/shop_profile_screen.dart), [main_shell.dart](../lib/screens/main_shell.dart), [welcome_screen.dart](../lib/screens/onboarding/welcome_screen.dart) |
| Jüri/Admin demo ekranı | [admin_panel_screen.dart](../lib/screens/admin/admin_panel_screen.dart) |
| Sunucu şeması, güvenlik, fonksiyonlar | [supabase/migrations/](../supabase/migrations/) (01 şema, 02 RLS, 03 fonksiyonlar, 05 realtime, 06 revizyon, 07–10 teslim düzeltmeleri) |
| PC GM paneli (web) | [tools/universal_gm/](../tools/universal_gm/) |
| İki oturumlu sunucu denemesi | [tools/test_two_sessions.dart](../tools/test_two_sessions.dart) |

**Gizli dosyalar:** `GM-Yonetici-Oturumu.private.json` ve `.gm-private/` yöneticiye özeldir. Sunumda **açılmaz, ekrana gösterilmez, repoya konmaz**. GM paneline giriş bu dosyanın panele içe aktarılmasıyla olur; içeriği anlatmaya gerek yok.

---

## 5. Adım, puan ve "bin adım = 5 puan"

**Kural:** Gün içinde tamamlanan her 1.000 adım için 5 puan. Puan yalnızca eşik geçilince artar.

| Günlük adım | O gün toplam puan |
|---|---|
| 999 | 0 |
| 1.000 | 5 |
| 1.999 | 5 |
| 2.000 | 10 |
| 6.666 → 7.000 (+334) | yalnız +5 (6→7. bin) |

- Kod: `stepPoints` ([activity_validation_service.dart](../lib/services/activity_validation_service.dart)) ve `_creditSteps` ([app_store.dart](../lib/services/app_store.dart)).
- **Aynı bini iki kez ödüllendirmez:** o güne ait "ödenen bin sayısı" (`dayRewardedThousands`) tutulur.
- **6.000 adım serisi:** Günde 6.000'e ulaşınca seri +1 (günde en fazla bir kez). Dün 6.000 yoksa seri 1'den başlar.
- **Sunucu da kendisi hesaplar:** `rpc_record_steps` ([03_functions_and_rpc.sql](../supabase/migrations/03_functions_and_rpc.sql)) puanı istemcinin söylediğine bakmadan kendi toplamından çıkarır.
- **Telefon yeniden başlarsa** sayaç sıfırlanır. Yeni değer eskisinden küçükse uygulama hata/puan üretmez, yalnız yeni başlangıç noktası alır.
- **Bilmediğimiz küçük nokta:** Sunucu gün sınırı `CURRENT_DATE` ile, uygulama Türkiye gününe göre tutuluyor. Gece yarısına yakın bir zaman dilimi farkı olabilir; ölçüp doğrulanmadı.

### Adım nasıl "geçerli" sayılır?
Adımlar 30 saniyelik pencerede toplanır, sonra `checkSteps` bakar:
- Dakikada **185 adımdan fazla** → ret (insan bu hızda yürümez; telefonu sallıyor olabilir).
- Telefon **3,5 Hz'den hızlı sallanıyor VE GPS konumu 3 m'den az değişmiş** → ret.
- GPS verisi yoksa (`null`) "hareket yok" **varsayılmaz**, ret verilmez.

*Örnek:* 30 sn'de 100 adım = dakikada 200 → reddedilir. 30 sn'de 50 adım = 100/dk → kabul.

---

## 6. Otomatik yürüyüş, bisiklet, araba — ve otobüsün durumu

Eşikler kodda, kesin kanıt değil. Önemli sayılar:

**Yürüyüş (otomatik motor):** 5+ adım artışı gelince "yürüyüş algılandı" durumuna geçer. Puan yine 1.000 adım = 5 puan kuralıyla.

**Bisiklet** ([auto_motion_engine.dart](../lib/services/auto_motion_engine.dart)):
- Başlamak için tek GPS ölçümüne güvenilmez: en az 10 sn ve art arda 3 geçerli konumda hız 9–45 km/sa, adım artışı az (≤8), titreşim yeterli (≥0,10).
- Kırmızı ışık: hız 3 km/sa altına düşse de 45 sn beklenir; sonra otomatik kaydedilir.
- GPS yoksa ya da doğruluğu 30 m'den kötüyse "sınırlı mod": **ceza yok**, yalnız güvenli adım modu.
- Sürüş sırasında adım sayacının verdiği adımlar yürüyüş puanına katılmaz (çift ödül olmasın).
- Puan: her tam 1 km = 1 puan (`distanceKm.floor()`). 0,999 km → 0, 2 km → 2.
- Reddedilen: anlık hız ≥ 50 veya ortalama ≥ 35 km/sa ("bisiklet bu hızda olmaz") → puan yok, ceza da yok.
- Kullanıcı sürüşü istediği an **İptal** (cezasız) veya **Bitir & Kaydet** yapar (kart: [home_screen.dart](../lib/screens/home/home_screen.dart)).

**Araba/taksi (utanç):** `checkVehicle`: ortalama hız 30 km/sa üstü ve adım artışı ≤10 → "araçla gidiliyor" sayılır; israf CO₂ = km × 0,192. Veri eksikse suçlama yok. Son 45 dakikada toplu taşıma kaydı varsa muafiyet var. Bu **kesin kanıt değil**; telefon cepte duran birini ya da otobüsü taksi sanabilir.
*Örnek:* Bisiklet modunda 28 km/sa ama titreşimsiz (<0,12) → bisiklet ödülü yok, araba sayacı +1.

**Otobüs — dürüst durum:**
- Ana sürümde kullanıcıya açık otobüs akışı **yok**. QR/NFC ekranı kaldırıldı (`bdbffba`).
- Otomatik otobüs motoru taslak: ayrı dal `wip/automatic-bus`, commit `bf89e78`, **birleştirilmedi**, 11 senaryolu test taslağı root tarafından çalıştırılmadı, gerçek otobüsle denenmedi.
- Sunucudaki `rpc_record_bus_trip` canlıda **geliştirme yanıtı verir, ödül veya ceza yazmaz** ([07_delivery.sql](../supabase/migrations/07_delivery.sql)).
- **500 m kısa otobüs cezası etkin değildir.** İstemcide kuralın kodu ve birim testi vardır ([auto_transport_classifier.dart](../lib/services/auto_transport_classifier.dart)) ama arkasında doğrulanmış otobüs akışı olmadığı için canlıda bilerek açılmadı. "500 m'de ceza kesiyoruz" **denmemeli**; "tasarlandı, güvenli olmadığı için kapalı" denmeli.
- Taslakta tasarlanan puanlama (otobüs skoru ≥60 vb.) [otomatik_otobus_ve_aktivite_algoritmasi.md](isterler/otomatik_otobus_ve_aktivite_algoritmasi.md) içindedir; çalışan özellik değil, plandır.

---

## 7. Sıralama: bireysel, klan, hibrit, utanç

**Bireysel:** Haftalık puan azalan; eşitlikte kullanıcı adı, sonra kimlik (kararlı sıra).

**Klan hibrit puanı** ([clan.dart](../lib/models/clan.dart)):
`toplam×0,6 + (toplam÷üye)×50×0,4`. Sıralamaya girmek için klanda **en az 5 üye**.
*Örnek:* A klanı 5 üye, 1.000 puan → ortalama 200; 600 + 200×50×0,4 = 600 + 4.000 = **4.600**. B klanı 10 üye, 1.000 puan → ort. 100 → 600 + 2.000 = **2.600**. Aynı toplamda küçük/etkin klan öne geçer; kalabalık tek başına yetmez. Formül ders amaçlı bir tasarım tercihidir, bilimsel bir ölçü değildir.

**Ekran penceresi:** İlk 10 + kullanıcının kendisi + bir üstü/altı; boşluklara `…` ([leaderboard_window.dart](../lib/core/utils/leaderboard_window.dart)). Kullanıcı kaydı yoksa uydurma satır eklenmez.

**Lig eşikleri** (bireysel puan): 0, 150, 350, 650, 1.100, 1.800 → CO, CO₂, N₂, O₂, O₃, BIO ([league_tier.dart](../lib/models/league_tier.dart)).

**Utanç tablosu:** İsrafa yazılan CO₂'ye göre sıralanır; cezası olmayanlar listede yoktur. İsimler maskelenir (`Ali***`, [name_masker.dart](../lib/core/utils/name_masker.dart)).

**Utanç mesajı (dürtme):** 10 altın, günde 1 mesaj, en çok 50 karakter. Altın telefonda hemen düşmez; sunucu kabul ederse düşer ([06_revizyon_03.sql](../supabase/migrations/06_revizyon_03.sql), `rpc_send_shame_message`; tekrar gönderimi `idempotency_key` ile engellenir, kota kilit altında kontrol edilir).
*Örnek:* Ayşe aynı gün 2. mesajı yazarsa kota dolduğu için reddedilir, altını eksilmez.

> Utanç listesinin cihazlar arası farkı için başa konan nota bakın: düzeltme doğrulanmadı.

---

## 8. Altın, pet ve kozmetik

- **Haftalık kapanış:** Haftalık puan, **1'e 1** altına çevrilir; haftalık alanlar sıfırlanır; şampiyon (kullanıcı ve klan) önce kaydedilir (`_settle`, [app_store.dart](../lib/services/app_store.dart)). Yönetici tetikleyebilir (`rpc_admin_trigger_weekly_reset`).
- **Mağaza:** Avatar, çerçeve ve evcil hayvan alınır; alınan eşya otomatik takılır. Örnekler ([demo_data.dart](../lib/data/demo_data.dart)): *Yaprak Savaşçısı Avatarı 500*, *Oksijen Neon Çerçevesi 650*, *Yürüyen Çam Fidanı (pet) 900*, *Orman Tilkisi (pet) 1.800*. Fiyat listesi sunucudaki `shop_items` ile aynı olmayabilir; kesin liste için sunucu verisine bakılmalı.
- **Yetersiz altın:** Alım reddedilir ve yerel durum bozulmaz (testli).
- Pet ve kozmetik yalnız görünüm; puan avantajı vermez (kodda böyle bir bonus yok).

---

## 9. Hesap ve güvenlik (sade örneklerle)

- **Anonim giriş:** Uygulama ilk açılışta sunucudan gizli bir kimlik alır. E-posta/şifre yok. Uygulamayı silip yüklemek yeni kimlik demektir; eski puan kendiliğinden gelmez.
- **RLS örneği:** Ali, Veli'nin puanını sıralamada görür; ama Veli'nin satırını güncelleyemez. Kural: "yalnız kendi kimliğine ait satırı değiştir" (`users_update_own`, [02_security_rls.sql](../supabase/migrations/02_security_rls.sql)). Altın/envanter kişiye özeldir (envanter yalnız sahibi tarafından okunur).
- **Admin yetkisi:** "Admin" olmak uygulamadaki bir düğme değil; sunucuda `server_admins` tablosundaki kayıttır. Telefon APK'sındaki herkese açık anahtar admin yetkisi vermez. GM paneli yetkiyi sunucuda doğrulatır; giriş yapılmadan işlem düğmeleri kapalıdır.
- **Idempotency örneği:** Ayşe'nin telefonu "1000 adım, olay numarası X" gönderdi, internet kesildi, cevap gelmedi. Telefon tekrar gönderir. Sunucu `processed_events` tablosunda X'i görür ve ilk sonucu geri verir; **puan ikinci kez yazılmaz**.
- **Neden "olay" yollanır, "toplam puanım 50" yollanmaz?** 3 gün çevrimdışı kalan telefon sunucudaki 80 puanı 50 ile ezmesin diye. Telefon "şu olay oldu" der, sunucu kendi toplamına ekler.
- **Atomik harcama:** Altın harcarken satır kilitlenir (`FOR UPDATE`); iki istek aynı anda gelse bile bakiye iki kez harcanmaz.

---

## 10. Debug gösterimi ile gerçek sensör kanıtı farkı

| | Debug/demo (Jüri/Admin ekranı, GM komutları) | Gerçek sensör |
|---|---|---|
| Kaynak | `demoAddSteps`, GM `add_steps`/`set_steps` | `TYPE_STEP_COUNTER` → Kotlin köprüsü |
| Kanıt değeri | Ekran/sunucu zincirinin çalıştığını gösterir | Telefonun gerçekten yürümeyi saydığını gösterir |
| Bekleme | Hemen | 30 sn pencere + kural kontrolü |
| Kural | Doğrulama atlanabilir | `checkSteps` uygulanır |

Sunumda **önce demoyla akışı göster, sonra "bu demo, gerçek yürüyüş kanıtı değil" de.** Adım ekranında ve Jüri/Admin ekranında "DEMO" etiketi vardır ([admin_panel_screen.dart](../lib/screens/admin/admin_panel_screen.dart)).

### Gerçek kanıt adımları (kullanıcı elle yapar; otomatik gezinti yok)
1. **Yürüyüş:** İzinleri ver (hareket/fiziksel aktivite, konum, bildirim). Uygulamayı açık tut, ekranı kilitleme. Telefonda ~1.000+ adım yürü. 30 sn pencereden sonra adımın arttığını, 1.000'i geçince +5 puan yazıldığını gör. GM panelindeki sensör ölçümü (telemetri) ham adım ve pencere durumunu gösterir.
2. **Bisiklet/araç:** Kontrollü, güvenli bir yolculukta hız 9+ km/sa olacak şekilde ~10 sn+ ilerle; bisiklet kartının çıkıp çıkmadığına bak. Çıkmazsa "bisiklet algılanmadı" bir hata değil, sınırdır; sonucu not et.
3. **Senkron:** İkinci telefonda (ya da ikinci oturumda) sıralama ekranını yenile; ilk telefondaki puan ortak listede görünmeli. "Kendiliğinden güncellenme" ayrı bir iddiadır; yalnız gerçekten gördüysen söyle.
4. **Çevrimdışı:** Uçak moduyla yürü, sonra interneti aç; giden kutusunun boşaldığını ve puanın sunucuya yazıldığını doğrula.

Not: Bu kanıtlar tamamlanmadıkça "gerçek cihazda her şey doğrulandı" denmez.

---

## 11. Hatalar ve sınır durumları

| Durum | Ne olur |
|---|---|
| İnternet kesilir | Olay giden kutusuna yazılır; geri gelince sırayla gider. Hata durumunda bekleme süresi katlanır (≈2, 4, 8 … en çok 60 sn) |
| 5 başarısız deneme | Olay karantinaya alınır (kuyruğu tıkamasın) |
| İzin verilmedi | Köprü "yok/reddedildi" döner; o sensörle ilgili özellik çalışmaz, uygulama çökmez. Ayarlara yönlendirme vardır |
| Telefon kilitli / uygulama arka planda | Takip ve bildirim **garanti edilmez**. Android sensörü kapatabilir. Sunumda bunu açıkça söyle |
| GPS belirsiz (doğruluk >30 m, metro, bina içi) | Ceza yok; GPS isteyen kontroller atlanır; bisiklet "sınırlı mod" |
| Telefon yeniden başladı | Sayaç küçülür, puan/ceza yok, yeni başlangıç noktası |
| Saat geriye alındı | 45 dk bekleme kuralında zaman geriye giderse reddedilir (kötüye kullanım koruması) |
| Kapalı uygulama bildirimi | **Yok** (FCM kurulu değil). Yalnız uygulama açıkken yerel bildirim |
| Bozuk yerel kayıt | Çökmez, temiz başlar (testli) |

---

## 12. Testler neyi kanıtlıyor, neyi kanıtlamıyor?

[DURUM.md](../DURUM.md) kaydına göre son çalıştırma: analiz temiz, **134/134 test geçti**, APK derlendi. Not: bu rehber yazılırken test çalıştırılmadı; bu sayı kayıttan alınmıştır, son sürümle yeniden kontrol edilmelidir.

| Test dosyası | Kanıtladığı |
|---|---|
| [rules_test.dart](../test/rules_test.dart) | Eşikler: 999/1000/2000, kadans 185/186, 45 dk 44:59 ret–45:00 kabul, bisiklet 50/35/0,12 sınırları, 4 üye hariç–5 üye dahil |
| [store_test.dart](../test/store_test.dart) | Puan zinciri, yeniden başlatma, gün değişimi, mağaza, sıralama, bozuk kayıt dayanıklılığı |
| [leaderboard_window_test.dart](../test/leaderboard_window_test.dart) | 120 satırda ilk 10 + komşular + tek `…` |
| [supabase_integration_test.dart](../test/supabase_integration_test.dart) | Sahte (taklit) sunucu ile outbox, aynı olayın tek işlenmesi, yetersiz altın, çevrimdışı yedek |
| [ui_flow_test.dart](../test/ui_flow_test.dart) | Ekran akışı, 3 sekmeli kabuk |
| [gm_panel_test.dart](../test/gm_panel_test.dart) | GM komutlarının uygulamada doğru işlenmesi |
| [tools/test_two_sessions.dart](../tools/test_two_sessions.dart) | İki gerçek anonim oturumun aynı sunucudan aynı sıralamayı okuduğu |

**Testler neyi kanıtlamaz:** Gerçek telefonun adım doğruluğunu, kişinin gerçekten arabada olup olmadığını, arka planda çalışmayı, 3 cihazda canlı akışı, otobüs doğruluğunu, **600k GM düzeltmesinin canlıda çalıştığını**. "Test geçti" ≠ "fiziksel doğruluk".

Sunucu SQL'i için ayrıca ön deneme dosyaları (BEGIN/ROLLBACK ile, kalıcı veri bırakmadan) ve doğrulama dosyaları vardır: [preflight_delivery.sql](../supabase/preflight_delivery.sql), [verification_rev08.sql](../supabase/verification_rev08.sql).

---

## 13. Ekran ekran demo sırası (8–10 dk)

Uygulama 3 sekmelidir: **Ana Sayfa → Sıralamalar → Profil** ([main_shell.dart](../lib/screens/main_shell.dart)).

1. **Karşılama/giriş** (ilk açılış): takma ad, avatar, klan seçimi; izinler istenir. *Söyle:* "E-posta yok, anonim kimlik."
2. **Ana Sayfa:** günlük adım, "Sonraki +5 puana … adım kaldı", streak, bisiklet kartı (varsa), utanç mini listesi, CO₂ kartı (ağaç eşdeğeri "demo eşdeğer" etiketli, bilimsel iddia değil).
3. **Adım ekleme (demo):** Profil → yönetici/jüri ekranı → "+334" gibi demo komutu; 6.666→7.000'de +5 puan. *Söyle:* "Bu demo."
4. **Sıralamalar:** bireysel/klan, hibrit–toplam, ilk 10 + sen, utanç sekmesi, utanç mesajı (10 altın, 50 karakter, günde 1).
5. **Profil/mağaza:** altın, avatar–çerçeve–pet satın alma, otomatik kuşanma, yetersiz altında ret.
6. **GM paneli (PC):** `127.0.0.1:8787`, yönetici oturumu ile giriş, bir komut yolla, telefonda sonucu göster. Gizli dosya içeriği gösterilmez.
7. **Kapanış:** "Ne gerçek, ne demo, ne yapılmadı" tablosu (bölüm 3).

---

## 14. Konuşma metni

### 14.1 Kısa sürüm (≈5 dk)

> "Çoğumuz yürüyebileceğimiz yolu araçla gidiyoruz. Yeşil Adım, telefondaki adım sayacıyla yürüyüşü ölçüp puana çeviren bir uygulama. Her bin adım beş puan. Puanlar haftalık bireysel ve klan yarışına girer, hafta bitince altına dönüşür; altınla avatar, çerçeve ve evcil hayvan alınır.
>
> Telefonun sensörü adımı sayar, uygulamanın Android kısmı bunu bize iletir, uygulamanın karar merkezi kuralları kontrol eder. Örneğin dakikada 185 adımdan hızlı sayım olursa telefon sallanıyor demektir, puan yazılmaz. Sonra olay ortak sunucuya gider; böylece herkes aynı sıralamayı görür. İnternet yoksa olay telefonda bekler, gelince gider; aynı olay iki kez gelse sunucu ikinci kez puan vermez.
>
> Bisiklet otomatik algılanıyor. Otobüs tarafı henüz bitmedi; ayrı bir taslakta ve canlıda kapalı. Gerçek bildirim servisi yok, uygulama kapalıyken takip garantisi vermiyoruz. Bunları bilerek açık söylüyoruz: telefon sensörü kimin arabada olduğunu kesin kanıtlayamaz, bu yüzden veri eksikse kimseyi cezalandırmıyoruz."

### 14.2 Uzatılabilir parçalar (10 dk'ya çıkarmak için)
- **Neden olay gönderiyoruz, puan değil?** (bölüm 9, 80→50 örneği)
- **Hile kuralı örneği:** 30 sn'de 100 adım → reddedilir.
- **Hibrit klan formülü:** 5 üye/1.000 puan = 4.600, 10 üye/1.000 puan = 2.600 (bölüm 7).
- **Telefon yeniden başlarsa:** sayaç sıfırlanır, ceza yok.
- **Test neyi kanıtlar:** 134 test kural ve akışı korur; fiziksel doğruluğu değil.
- **Canlı demo:** komut yolla, ikinci telefonda sıralamayı yenile.

---

## 15. Commitleri gösterme (git log / git show)

Bu rehberde Git komutu çalıştırılmadı. Sunumda şunları kullan:

```bash
git log --oneline -15
git show --stat bdbffba      # QR/NFC ekranı kaldırma, 3 sekme
git show --stat 761a58c      # profil yeniden deneme, klan etkileşimi, GM bildirim düğmesi
git show --stat 2336226      # GM bildirim migration 10
git show --stat bf89e78      # otobüs taslağı (ayrı dalda: wip/automatic-bus)
git branch -a
```

Somut commit konuları (kayıttan): "feat: add automatic walking and cycling sessions", "fix: verify shared scores and require an admin session in GM panel", "fix: remove QR NFC screen and keep three navigation tabs", "docs: simplify presentation into everyday examples and short answers". Push yapılmaz; geçmiş yereldir. Henüz commitlenmemiş çalışma varsa (örneğin migration 11) `git status` ile göster.

---

## 16. Olası hoca soruları ve dürüst cevaplar

1. **Sensör hile yapılabilir mi?** Kısmen. Çok hızlı sayım ve "sallıyor ama konum sabit" yakalanır; yavaş, sürekli sallamayı kesin ayıramayız. Kesin kanıt yok, yalnız olasılık eşikleri.
2. **Arabadaysam otobüsten nasıl ayırıyorsunuz?** Ayırmıyoruz; otobüs otomatik tespiti ana sürümde yok. Araba/taksi kuralı yalnız hız yüksek + adım yok durumuna bakar; toplu taşıma kaydı varsa muafiyet var.
3. **500 m cezası var mı?** Hayır, etkin değil. Kural ve test hazır; doğrulanmış otobüs akışı olmadan canlıya açılmadı.
4. **QR/NFC var mı?** Kullanıcı ekranından kaldırıldı. (Eski belgelerde QR anlatımı kalmış olabilir; güncel durum DURUM.md.)
5. **Bildirim geliyor mu?** Uygulama açıkken yerel bildirim. Gerçek push (FCM) yok, kapalıyken garanti yok.
6. **Arka planda sayar mı?** Garanti vermiyoruz; ön planda doğrulandı.
7. **Realtime çalışıyor mu?** İki oturumun aynı veriyi okuduğunu test ettik. Üç cihazda kendiliğinden güncelleme kanıtlamadık.
8. **İnternet yoksa?** Olaylar telefonda bekler, sonra gider, tekrar gelen olay ikinci kez puan vermez.
9. **Güvenlik tam mı?** Hayır. RLS ve admin tablosu var; güvenlik taraması 0 hata, 14 uyarı verdi. Hepsi giderildi diyemeyiz.
10. **Anonim hesap kaybolursa?** Evet, e-posta olmadığı için uygulama silinince hesap geri gelmez.
11. **GM'den 600.000 adım verince puan neden artmıyordu?** Hata bulundu; düzeltme hazırlanıyor, canlıda doğrulanması bekliyor (başa bkz.). "Çözüldü" demiyoruz.
12. **Shame listesi neden iki telefonda farklıydı?** Aynı hata paketinde düzeltiliyor; doğrulanmadı.
13. **CO₂ değerleri gerçek mi?** Hayır, model. Araç km başına 0,192 kg, yürüyüş/bisiklet 0,19 kg/km tasarruf katsayısı eğitim amaçlı sabittir; resmî ölçüm iddiası yok.
14. **Test geçmesi uygulamanın doğru olduğu demek mi?** Hayır; yalnız yazılan kuralların korunduğunu gösterir.
15. **Bilmediğimiz şeyler?** Gün sınırının sunucu/istemci saat dilimi uyumu, gerçek otobüs davranışı, farklı marka telefonlarda arka plan sensör davranışı.

---

## 17. Sunum öncesi kısa kontrol listesi

- [ ] [DURUM.md](../DURUM.md) son halini oku; GM 600k ve shame düzeltmesi uygulanmış mı, iki telefonda doğrulandı mı?
- [ ] Telefon bağlı mı, internet var mı, izinler verilmiş mi?
- [ ] GM paneli `127.0.0.1:8787` açık mı (8080 başka servise ait)?
- [ ] Gizli yönetici dosyası ekranda/paylaşımda yok mu?
- [ ] Demo anlatılırken "demo" ve "gerçek" ayrımı yapıldı mı?
- [ ] Otobüs, 500 m cezası, push ve arka plan için iddia yok mu?
