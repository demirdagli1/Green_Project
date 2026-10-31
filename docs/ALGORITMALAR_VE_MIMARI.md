# Yeşil Adım: Algoritmalar, Karar Mantığı ve Sistem Mimarisi

Bu doküman, Yeşil Adım projesinin arka planında çalışan algoritmaları, sensör kontrollerini ve sunucu iletişimini kod bilmeyen birinin rahatlıkla anlayabileceği sade bir ders notu mantığıyla anlatır. 

Metin boyunca süslü pazarlama ifadeleri veya karmaşık formüller yerine; sistemde **ne** yaşandığı, bu kararın **nasıl** alındığı ve ilgili mantığın kaynak kodda **nereden** incelenebileceği gösterilmektedir.

---

## 1. Bir Olayın Anatomisi: Ayşe 1000 Adım Atınca Ne Olur?

Sistemin bütün parçalarının birbiriyle nasıl konuştuğunu anlamanın en kolay yolu, tek bir eylemi baştan sona izlemektir. Ayşe sabah yürüyüşe çıkıp tam 1.000 adım attığında sistemde şu adımlar sırasıyla gerçekleşir:

```text
[Telefon Sensörü] 
       │ (1000 adım sinyali)
       ▼
[Kotlin Donanım Köprüsü: MainActivity.kt]
       │ (MethodChannel üzerinden Flutter'a aktarım)
       ▼
[Başlangıç & Servis Yöneticisi: main.dart & hub.dart]
       │ (Merkezi durum yöneticisi AppStore.dart'a iletilir)
       ▼
[Merkezi Durum: AppStore.dart]
       │ (30 saniyelik bekleme penceresi başlatır)
       ▼
[Kural Motoru: ActivityValidationService.dart]
       │ (Kadans ≤ 185, telefon sallama yok, onaylandı)
       ▼
[Yerel Veritabanı & Arayüz] ───► Ekrana "+5 Puan" yansır
       │ (Çevrimdışı Olay Kuyruğu)
       ▼
[Outbox Servisi: SupabaseOutbox.dart]
       │ (İnternet varsa RPC isteği fırlatır)
       ▼
[Bulut Fonksiyonu: rpc_record_steps] ───► Idempotent kontrol (Tekrarlanan olay mı?)
       │ (Postgres FOR UPDATE satır kilidi)
       ▼
[Veritabanı Tablosu: public.users] ───► Haftalık puan +5 güncellenir
       │ (RLS Güvenlik Filtresi)
       ▼
[Ortak Liderlik Görünümü: v_leaderboard_users]
       │ (Mehmet kendi ekranını yenilediğinde)
       ▼
[Mehmet'in Telefonu: LeaderboardScreen.dart] ───► Ayşe'nin 5 puan yükseldiğini görür
```

1. **Sensör Tespiti:** Ayşe yürürken telefonun içindeki donanımsal adım sayacı çipi (`TYPE_STEP_COUNTER`) adım sayısını artırır.
2. **Donanım Köprüsü ([MainActivity.kt](../android/app/src/main/kotlin/com/yesiladim/ecoclan/green_project/MainActivity.kt)):** Android işletim sistemi bu donanım sinyalini yakalar ve Flutter uygulamasına iletir.
3. **Uygulama Girişi ve Servis Hub ([main.dart](../lib/main.dart) & [hub.dart](../lib/services/hub.dart)):** Uygulama açılışta servisleri başlatır ve sinyali merkezi mağazaya aktarır.
4. **Pencereleme ve Durum ([app_store.dart](../lib/services/app_store.dart)):** Uygulama gelen her adımı anında sunucuya fırlatmaz. 30 saniyelik bir kayan pencerede adımları biriktirir (`flushPendingStepsWindow`).
5. **Hile ve Kural Denetimi ([activity_validation_service.dart](../lib/services/activity_validation_service.dart)):** Kural motoru şu soruyu sorar: Ayşe dakikada 185 adımdan hızlı mı hareket etti? Telefon yerinde dururken sadece ivmeölçer mi sallandı? Şüpheli bir durum yoksa adımlar onaylanır.
6. **Puanlama ve Yerel Kayıt:** 1.000 tamamlanan adım karşılığı Ayşe'nin yerel profiline +5 puan eklenir ve telefon hafızasına kaydedilir ([storage.dart](../lib/services/storage.dart)).
7. **Olay Kuyruğuna Alma ([supabase_outbox.dart](../lib/services/supabase_outbox.dart)):** İnternet kopuk olsa bile puanın kaybolmaması için olay yerel bir bekleme kuyruğuna (`Outbox`) yazılır.
8. **Sunucuya İletim ([supabase_service.dart](../lib/services/supabase_service.dart)):** İnternet bağlantısı sağlandığında bu olay benzersiz bir işlem numarasıyla (`eventId`) sunucudaki `rpc_record_steps` fonksiyonuna gönderilir ([03_functions_and_rpc.sql](../supabase/migrations/03_functions_and_rpc.sql)).
9. **Güvenlik ve İzolasyon ([02_security_rls.sql](../supabase/migrations/02_security_rls.sql)):** Sunucu veritabanı satır düzeyinde güvenlik (RLS) kuralı uygulayarak Ayşe'nin sadece kendi puanını güncelleyebilmesini sağlar.
10. **Ortak Tablo ve Diğer Kullanıcı:** Ayşe'nin güncellenen puanı ortak görünüm tablosuna yansır. Başka bir şehirdeki Mehmet liderlik tablosunu açtığında Ayşe'nin yeni puanını görür.

---

## 2. Temel Kavramlar: Algoritma ve Durum (State) Nedir?

* **Algoritma:** Belirli bir girdiyi alıp kurallar dizisinden geçirerek kesin bir sonuca ulaştıran adım adım karar mantığıdır.  
  * *Somut Örnek:* "Eğer hız saatte 30 km'den büyükse VE adım sayısı 10'dan azsa, bu kişi yürümüyordur; otomobildedir." kararı bir algoritmadır.
* **Durum (State / Bellek):** Sistemin o anki hafızasıdır; geçmişte ne olduğunu hatırlama yeteneğidir.  
  * *Somut Örnek:* Ayşe şu an 999 adımda olsun. Uygulama "999" bilgisini aklında tutmazsa (durumsuz olursa), atılan 1 adımı tek başına değerlendirip 1.000 sınırına ulaşıldığını asla anlayamaz. Hafızadaki 999 sayısı "durum"dur.

---

## 3. Adım ve Puanlama Mantığı

Uygulamada adımlar ve puanlar keyfi artmaz; kesin tamsayı sınırlarına bağlıdır:

* **1.000 Adım Eşiği:** Sistem her **tamamlanan 1.000 adım** için tam **5 puan** verir.
  * 0 – 999 adım arası: **0 puan**
  * 1.000 adım: **+5 puan**
  * 1.001 – 1.999 adım arası: Puan değişmez, toplam **5 puan** kalır
  * 2.000 adım: **+5 puan daha eklenir (toplam 10 puan)**
  * *Hesap Kodu:* `((yeniAdim ~/ 1000) - (oncekiAdim ~/ 1000)) * 5` ([activity_validation_service.dart](../lib/services/activity_validation_service.dart#L36-L39))
* **Günlük 6.000 Adım Serisi (Streak):** Gün içinde toplam adım 6.000'e ulaştığında kullanıcının seri günü 1 artar. Aynı gün içinde 12.000 adım atılsa bile seri o gün ikinci kez artmaz.
* **Gün Değişimi:** Gece 00:00 (Türkiye saati) geçtiğinde `_sync()` fonksiyonu çalışır:
  * Günlük adım sayacı (`todaySteps`) sıfırlanır.
  * Eğer dün 6.000 adıma ulaşılmamışsa, kazanılan seri zinciri kırılır ve `streakDays = 0` yapılır.
* **Telefonun Kapanıp Açılması (Reboot):** Android'in donanımsal adım sayacı telefon kapandığında sıfırlanır. Uygulama hafızasındaki taban çizgiden (`stepBaseline`) daha küçük bir sensör verisi gelirse, aradaki farkı negatif sayıp hata vermez veya haksız puan dağıtmaz. Sayacı yeniden kalibre eder ve sıfırdan başlatır ([app_store.dart](../lib/services/app_store.dart#L453-L464)).
* **Çift Sensör ve Bisiklet Çakışması:** Bisiklet sürüşü açıkken pedal çevirme sarsıntısı donanımsal adım sayacını tetikleyebilir. Sistem bisiklet oturumu açıkken gelen adımları bastırır (`stepBaseline = total`), böylece aynı yolculukta hem bisiklet hem yürüyüş puanı alınarak çift ödül suistimali yapılması önlenir ([app_store.dart](../lib/services/app_store.dart#L443-L451)).
* **Eksik GPS Durumu:** GPS çekmiyorsa (örneğin metroda veya kapalı alanda), sistem kullanıcıyı otomatik olarak cezalandırmaz veya adımlarını silmez. Sadece GPS gerektiren hız denetimleri atlanır, adım frekansı üzerinden yürüyüş onaylanır.

---

## 4. Hareket Türü Nasıl Anlaşılır? Eşikler ve Sensörler

Telefon cebinizdeyken ne yaptığınızı anlamak için 3 sensör metriği çaprazlanır:

1. **Kadans (`spm`):** Dakikadaki adım frekansı.
2. **Hız (`km/sa`):** GPS uydularından alınan yer değiştirme hızı.
3. **İvme Varyansı (`σ²`):** Telefonun sarsıntı şiddeti. Pürüzsüz asfalt üzerindeki arabada çok düşüktür; koşan veya pedal çeviren insanda çok yüksektir.

| Hareket Türü | Ortalama Hız | Kadans (Adım/Dk) | İvme Titreşimi | Puan ve Sonuç |
| :--- | :--- | :--- | :--- | :--- |
| **Yürüyüş** | 1.5 – 7.2 km/sa | 60 – 135 | Normal | Tamamlanan her 1.000 adım = +5 Puan |
| **Koşu** | 7.2 – 18.5 km/sa | > 135 | Yüksek (> 2.0) | Adımlar geçerli, koşu antrenmanı sayılır |
| **Bisiklet** | 8.5 – 35.0 km/sa | < 35 | Titreşimli (≥ 0.30) | Her 1 km = +1 Puan (Maksimum hız < 48 km/sa olmalı) |
| **Özel Araç / Taksi** | > 30.0 km/sa | ≤ 10 | Hareketsiz | Puan yok! Utanç Tablosuna yazılır ve CO₂ israfı işlenir |

* **Doğru Örnek:** Saatte 12 km hızla ilerleyen, dakikada 160 adım atan ve dikey zıplama ivmesi üreten biri **koşucudur**.
* **Sınır / Hile Örneği:** Saatte 28 km hızla giden ama telefonunda hiç sarsıntı olmayan (ivme varyansı < 0.12) biri bisiklet modunu açmış olsa bile sistem bunu **araba** sayar ve puan vermez.
* **CO₂ Değerleri Hakkında:** Formüllerde yer alan CO₂ katsayıları (örneğin araç başına kilometreye 0.192 kg) mutlak bir ölçüm ya da resmi kurum verisi iddiası taşımaz; çevre farkındalığını somutlaştırmak için tasarlanmış bir **model yaklaşımıdır**.
* **Önemli Gerçek (Sensörler Kesin Kanıt Değildir):** Bir telefon sensörü araç plakası okuyamaz. GPS sapması veya telefonun yumuşak bir mont cebinde hareketsiz kalması taksi gibi algılanabilir. Bu nedenle kural motorunda veri eksikliği (`null`) asla otomatik ceza sebebi sayılmaz ([activity_validation_service.dart](../lib/services/activity_validation_service.dart#L105-L107)).

---

## 5. Toplu Taşıma, QR/NFC ve 45 Dakika Kuralı

Toplu taşıma binişleri karekod (QR) veya NFC etiketleri okutularak sisteme işlenir:

* **Durak Doğrulama:** Okutulan metin `YESILADIM://TRANSIT/<DURAK_KODU>` kalıbına uygun olmalıdır.
* **45 Dakika Kuralı:** Aynı durak veya aynı hat üzerinde 45 dakika içinde tekrar okutma yapılırsa sistem puan vermez:  
  * 44 dakika 59 saniye sonra okutulursa: **Reddedilir** ("Sonraki biniş için bekleyin").
  * 45 dakika 00 saniye sonra okutulursa: **Onaylanır (+3 Puan)**.
* **Aynı Olayın Tekrar Gelmesi (Retry):** İnternet gidip geldiğinde telefon aynı biniş isteğini iki kez sunucuya gönderirse ne olur? Her biniş isteğine benzersiz bir işlem kimliği (`eventId`) verilir. Sunucu bu kimliği `processed_events` tablosunda saklar. İkinci istek geldiğinde veritabanı "Ben bu işlemi zaten yaptım" der ve Ayşe'ye ikinci kez puan vermez.
* **Yerel Kural vs. Sunucu Kuralı:** Yerel kural ([app_store.dart](../lib/services/app_store.dart)) kullanıcının ekranında anında uyarı çıkması için çalışır. Asıl yetkili olan ise sunucudaki Postgres kilididir ([07_delivery.sql](../supabase/migrations/07_delivery.sql)); istemci hacklense bile sunucu kuralı aşamaz.

---

## 6. Otomatik Otobüs Tespiti: Yapılmakta Olan Bölüm

> [!WARNING]
> **Geliştirme Uyarısı:** Bu bölümdeki kurallar [otomatik_otobus_ve_aktivite_algoritmasi.md](isterler/otomatik_otobus_ve_aktivite_algoritmasi.md) belgesinde tasarlanmıştır. Ancak gerçek donanım sensör füzyonu ana kod tabanında değil, ayrı bir çalışma alanında (`.worktrees/automatic-bus`) geliştirilmektedir. Ana teslimatta veri bütünlüğünü bozmamak için sunucu tarafındaki `rpc_record_bus_trip` fonksiyonu geçici olarak devre dışı (dormant/uykuda) tutulmaktadır ([07_delivery.sql](../supabase/migrations/07_delivery.sql#L158-L185)). Bu özellik şimdiden canlıda çalışıyormuş gibi anlatılmamalıdır.

### Tasarlanan Karar Skoru (Otobüs mü, Taksi mi?)
Kullanıcı motorlu araca bindiğinde sistem 0 ile 100 arasında bir olasılık puanı hesaplar:
* Otobüs durağından biniş: **+35 puan**
* Güzergahtaki duraklarda yolcu indirme-bindirme beklemesi (8–60 sn): **Her durak için +25 puan** (Trafik ışığı olan durakta +15 puan)
* Dolmuş tarzı kısa dur-kalklar (en az 3 kez): **+30 puan**
* Durakta iniş: **+20 puan**
* **Karar Sınırı:** Toplam skor **≥ 60** ise otobüs kabul edilir (+3 Puan). Skor **< 60** ise özel araç/taksi kabul edilir (Utanç Tablosu).

### Kısa Mesafe Kuralı (≤ 500 Metre)
Otobüs doğrulansa bile gidilen mesafe 500 metreden azsa yürünebilecek bir mesafe araçla gidildiği için ceza uygulanır:
* Eğer kullanıcı binişte QR okutmamışsa: **-3 puan** ceza uygulanır.
* Eğer kullanıcı binişte QR okutup +3 puan almışsa: Verilen 3 puan geri alınır ve üstüne 3 puan ceza kesilir (kullanıcıdan net **-6 puan** düşülür ve kazanılan CO₂ tasarrufu iptal edilir) ([app_store.dart](../lib/services/app_store.dart#L681-L710)).
* **Sistem Riskleri:** Tünellerde GPS'in kesilmesi, kırmızı ışıkta bekleyen taksinin durak sanılması veya hiç durmadan giden ekspres otobüs hatları algoritmanın en hassas sınır noktalarıdır.

---

## 7. Ligler, Sıralama Tablosu ve Klanlar

### Bireysel ve Klan Lig Eşikleri
Kazanılan haftalık puanlara göre kullanıcılar ve klanlar 6 seviyeden birinde yer alır ([league_tier.dart](../lib/models/league_tier.dart)):

| Seviye | Bireysel Lig Adı | Bireysel Puan Eşiği | Klan Lig Adı | Klan Puan Eşiği |
| :---: | :--- | :---: | :--- | :---: |
| 1 | Karbonmonoksit (CO) | 0 | Kül Birliği | 0 |
| 2 | Karbondioksit (CO₂) | 150 | Sis Loncası | 2.500 |
| 3 | Azot (N₂) | 350 | Akım Cephesi | 6.000 |
| 4 | Oksijen (O₂) | 650 | Koruyucu İttifak | 12.000 |
| 5 | Ozon (O₃) | 1.100 | Ozon Muhafızları | 25.000 |
| 6 | Sönmez Biyosfer (BIO) | 1.800 | Biyosfer Konseyi | 50.000 |

### Klan Hibrit Puan Formülü
Büyük klanların sadece kalabalık oldukları için haksız avantaj kazanmasını önlemek üzere puanlar hibrit bir formülle hesaplanır ([clan.dart](../lib/models/clan.dart#L59-L66)):
$$\text{Klan Skoru} = (\text{Toplam Puan} \times 0.6) + (\text{Üye Başına Ortalama Puan} \times 50 \times 0.4)$$
* *Klan Boyutu Kuralı:* Sıralamaya girebilmek için bir klanın **en az 5 üyesi** olmalıdır (4 üye elenir, 5 üye kabul edilir).

### Sıralama Penceresi (Leaderboard Window)
Sıralama ekranında binlerce kişiyi tek tek listelemek telefonu kilitler. Bu yüzden özel bir pencereleme algoritması kullanılır ([leaderboard_window.dart](../lib/core/utils/leaderboard_window.dart)):
* İlk 10 kullanıcı her zaman gösterilir (Zirvedekiler).
* Kullanıcının kendi sırası, bir üstündeki rakibi ve bir altındaki rakibi listeye eklenir.
* Aradaki boşluklara tek bir üç nokta (`…`) satırı konur.
* **Puan Eşitliği Durumu:** İki kişinin puanı eşitse, kullanıcı adlarına alfabetik bakılır; o da eşitse kayıt kimlik numarasına (ID) göre kararlı sıralama yapılır.
* **Gurur vs. Utanç Tablosu:** Gurur tablosu kazanılan yeşil puanlara göre sıralanır; Utanç tablosu ise özel araç/taksiyle doğaya salınan israf CO₂ miktarına göre en çok kirleteni en başa yazar.

---

## 8. Sanal Ekonomi: Altın, Mağaza ve Utanç Dürtmesi

* **Altın Nasıl Kazanılır?** Haftalık sıfırlama (Pazartesi 00:00) anında haftalık yeşil puanlar **1'e 1 oranında altın paraya** dönüşür.
* **Satın Alma ve Kuşanma:** Mağazadan avatar, profil çerçevesi veya evcil hayvan alınabilir ([app_store.dart](../lib/services/app_store.dart#L991-L1034)). Yetersiz bakiye durumunda işlem reddedilir. Eşya alındığında otomatik kuşanılır.
* **Utanç Dürtmesi (Shame Poke):** Utanç tablosundaki bir arkadaşınıza takılmak için sistem üzerinden dürtme mesajı gönderebilirsiniz ([leaderboard_screen.dart](../lib/screens/leaderboard/leaderboard_screen.dart#L630-L725)):
  * **Bedel:** 10 Altın.
  * **Kısıt:** Günde en fazla 1 mesaj gönderilebilir.
  * **Metin Sınırı:** En fazla 50 karakter olabilir.
  * **Bakiye Güvenliği:** Mesaj yazıldığında altın hemen telefonda silinmez. İstek sunucuya gider, sunucu işlemi onaylarsa 10 altın düşülür. İnternet kesilirse bakiye eksilmez.

---

## 9. Kullanıcı Hesabı ve Güvenlik Sınırları

* **Anonim Kimlik vs. Cihaz ID:** Cihaz ID telefonun donanım numarasıdır. Anonim kimlik ise Supabase sunucusunun bu cihaza atadığı şifreli oturumdur. Kullanıcı uygulamayı silip yüklerse yeni bir anonim kimlik oluşur; eski puanlar yeni cihaza kendiliğinden aktarılmaz (çünkü e-posta/şifre sistemi yoktur).
* **Yönetici (Admin) vs. Standart Üye:** Normal kullanıcılar sadece kendi aktivitelerini yazabilir. Haftalık puan sıfırlama veya sistem duyurusu yapma yetkisi sadece sunucu tarafındaki `server_admins` tablosunda kayıtlı yöneticilere aittir ([03_functions_and_rpc.sql](../supabase/migrations/03_functions_and_rpc.sql#L1124-L1125)).
* **Mahremiyet ve RLS Koruması:** Diğer kullanıcılar sizin liderlik tablosundaki puanınızı görebilir (`v_leaderboard_users`). Ancak sahip olduğunuz altın miktarı, çantanızdaki eşyalar ve telefon kimliğiniz gizlidir; başka bir kullanıcı bunları veritabanından sorgulayamaz.

---

## 10. İnternet Kesilirse Ne Olur? (Outbox ve Veri Ezilmeme Garantisi)

Telefon dağda veya tüneldeyken internet koptuğunda uygulamanın çökmemesi ve verinin kaybolmaması için **Outbox** mekanizması çalışır:

1. Ayşe metroda 1.000 adım attığında olay hemen yerel hafızaya (`supabase_outbox_queue_v1`) yazılır.
2. İnternet geldiğinde bu kuyruk sırayla sunucuya gönderilir.
3. Sunucu hata verirse, telefon sunucuyu soru yağmuruna tutmaz; üstel geri çekilme (exponential backoff) uygulayarak 2, 4, 8 saniye aralıklarla yeniden dener ([supabase_outbox.dart](../lib/services/supabase_outbox.dart#L170)).
4. Bir olay 5 kez denenmesine rağmen yapısal bir hata alıyorsa, kuyruğu kilitlememesi için **karantinaya** alınır.
5. **Stale Snapshot (Eski Veri) Tehlikesinin Önlenmesi:** Telefon sunucuya asla *"Benim puanım 50 oldu, bunu veritabanına yaz"* demez. Eğer öyle deseydi, 3 gün internetsiz kalan telefon internete bağlandığında sunucudaki güncel 80 puanı ezip 50 yapardı. Bunun yerine telefon **olay** bildirir: *"Ben 1000 adım attım (İşlem No: XYZ-1)"*. Sunucu bu işlemi kendi mevcut puanının üzerine ekler.

---

## 11. Ortak Liste ile Canlı Değişiklik (Realtime) Arasındaki Fark

Geliştirme testlerinde iki oturum arasındaki veri geçişi sınanmıştır ([test_two_sessions.dart](../tools/test_two_sessions.dart)):
* Test ortamında A kullanıcısı 1.000 adım atıp 5 puan aldığında, B kullanıcısının ekranı HTTP ile yenilendiğinde puanın 0'dan 5'e çıktığı doğrulanmıştır.
* **Önemli Ayrım:** Bu test iki istemcinin aynı veritabanını doğru okuduğunu kanıtlar. Ancak bu durum, masada duran 3 farklı fiziksel telefonun ekranında hiçbir tuşa basmadan verilerin anında şakır şakır aktığı anlamına (canlı WebSocket Realtime veri akışı kanıtına) gelmez. Gerçek cihaz doğrulaması ile arka plan testleri birbirine karıştırılmamalıdır.

---

## 12. Hangi Algoritma Nerede? Kod ve Test Haritası

Projeyi incelerken hangi mantığın nerede olduğunu bulabileceğiniz hızlı rehber:

| Algoritma / Kural | Kaynak Kod Dosyası | Doğrulandığı Anlamlı Test |
| :--- | :--- | :--- |
| **Adım, Bisiklet, Taksi Eşikleri** | [activity_validation_service.dart](../lib/services/activity_validation_service.dart) | [rules_test.dart](../test/rules_test.dart) |
| **Otomatik Hareket Sınıflandırma** | [auto_transport_classifier.dart](../lib/services/auto_transport_classifier.dart) | [phase_d_test.dart](../test/phase_d_test.dart) |
| **Pencereleme ve Durum Yönetimi** | [app_store.dart](../lib/services/app_store.dart) | [store_test.dart](../test/store_test.dart) |
| **Sıralama Pencereleme (Top 10 + Komşular)** | [leaderboard_window.dart](../lib/core/utils/leaderboard_window.dart) | [leaderboard_window_test.dart](../test/leaderboard_window_test.dart) |
| **Çevrimdışı Kuyruk ve Karantina** | [supabase_outbox.dart](../lib/services/supabase_outbox.dart) | [supabase_integration_test.dart](../test/supabase_integration_test.dart) |
| **Lig Seviyeleri ve Formüller** | [league_tier.dart](../lib/models/league_tier.dart) & [clan.dart](../lib/models/clan.dart) | [rules_test.dart](../test/rules_test.dart) |
| **Sunucu Kilitleri ve İdempotency** | [03_functions_and_rpc.sql](../supabase/migrations/03_functions_and_rpc.sql) | [test_two_sessions.dart](../tools/test_two_sessions.dart) |

---

## 13. Kendini Sına: Küçük Sorular ve 30 Dakikalık İnceleme Sırası

### Hızlı Sorular ve Yanıtlar
1. **Telefonu koltukta sallarsam neden puan alamam?**  
   *Çünkü adım kadansı dakikada 185'in üzerine çıkar ve GPS konum değişimi 3 metrenin altında kalır. Kural motoru bunu hile sayar.*
2. **Sabah 999 adım attım, neden ekranda 0 puan yazıyor?**  
   *Puan ödülü her tamamlanan 1.000 adımda bir (+5) tetiklenir.*
3. **Aynı otobüse binerken arka arkaya iki kez QR okutursam ne olur?**  
   *45 dakikalık durak bekleme süresi devrededir; ikinci tarama reddedilir.*
4. **Bisikletle saatte 55 km hız yaparsam ne olur?**  
   *Maksimum bisiklet eşiği olan 48 km/sa aşıldığı için sürüş geçersiz sayılır ve puan verilmez.*
5. **Otobüsle sadece 300 metre gidersem ne kazanırım?**  
   *Kısa mesafe kuralı gereği hiçbir şey kazanamazsınız; aksine -3 puan ceza kesilir.*
6. **Telefonum kapandı açıldı, adımlarım sıfırlandı; hile cezası yer miyim?**  
   *Hayır, sayaç yeniden başlatması yakalanır ve taban çizgi sessizce güncellenir.*
7. **Klanımız 4 kişi ve 10.000 puan topladık; liderlikte neden görünmüyoruz?**  
   *Klan sıralamasına girebilmek için en az 5 üye barajı vardır.*
8. **İnternetim yokken yaptığım yürüyüş kaybolur mu?**  
   *Hayır, Outbox kuyruğunda saklanır ve internet bağlandığında sunucuya aktarılır.*

### 30–45 Dakikalık Çalışma Rotası
* **00–10. Dakika:** Bu dokümanın 1. ve 4. bölümlerini okuyarak bir sensör verisinin ekrana nasıl yansıdığını zihninizde canlandırın.
* **10–20. Dakika:** [activity_validation_service.dart](../lib/services/activity_validation_service.dart) dosyasını açıp hız ve adım eşiklerinin Dart dilinde nasıl yazıldığını görün.
* **20–30. Dakika:** [app_store.dart](../lib/services/app_store.dart) içindeki `_creditSteps` ve `scanTransit` fonksiyonlarını inceleyin.
* **30–40. Dakika:** [rules_test.dart](../test/rules_test.dart) dosyasını inceleyerek yazılan kuralların kod testleriyle nasıl korunduğunu öğrenin.
