# Yeşil Adım — Kullanım ve Yönetim Kılavuzu

Bu belge, **Yeşil Adım** mobil uygulamasının ve **Evrensel GM Paneli**'nin kullanım adımlarını, mimarisini ve kurallarını içeren tekil referans kılavuzudur.

---

## 1. 📱 Mobil Uygulama Kullanım Kılavuzu

### 1.1. Adım Sayar ve Yürüyüş Takibi
* **Ödül Kuralı:** Her 1.000 geçerli adımda **+5 haftalık puan** kazanılır.
* **Hareket Kontrolleri:** Hız, adım ritmi ve sarsıntı gibi ölçümler değerlendirilir. Bunlar her hileyi veya araç türünü kesin yakalama garantisi vermez; gerçek yol denemeleri gerekir.
* **Senkronizasyon:** Çevrimdışı atılan adımlar yerel outbox'ta saklanır; internet bağlantısı kurulduğunda `rpc_record_steps` ile Supabase veritabanına aktarılır.

### 1.2. Toplu Taşıma (QR ve NFC) Doğrulama
* **Erişim:** Alt menüdeki ilk sekme (`[0] QR/NFC`).
* **Ödül:** Doğrulanan her durak binişi için **+3 puan** ve durak mesafesine göre **CO₂ tasarrufu** (ör. 1.15 kg) kazanılır.
* **Ortak Cooldown Kuralı:** 
  - Aynı durak veya otomatik biniş oturumu için **tam 45 dakika bekleme süresi** vardır.
  - Şartnameye uygun olarak: **44:59 RET**, **45:00 KABUL** sınırıyla çalışır.
* **Girdi Formatları:**
  - Tam QR URI: `YESILADIM://TRANSIT/TRB-KTU-01?hash=...`
  - Çıplak Kod: `TRB-KTU-01`, `TRB-MEY-01` vb.
  - NFC UID: `NFC_KTU_01`, `04:A2:3B:4C:5D:6E:7F` vb.

### 1.3. Bisiklet ve Otomatik Hareket Algılama
* **Manuel Sürüş:** Aktivite ekranındaki Bisiklet kartından başlatılıp bitirilebilir. Puan verilmeden önce hız ve hareket ölçümleri kontrol edilir.
* **Otomatik Algılama (Aşama D):**
  - **Başlama Histerezisi:** 10 saniye ve ardışık 3 GPS fix boyunca bisiklet örüntüsü doğrulanmadan sürüş başlatılmaz.
  - **Trafik Işığı Toleransı:** 45 saniyeye kadar kırmızı ışık duraklamalarında sürüş sonlandırılmaz.
  - **Kullanıcı Kontrolü:** Ana ekranda dinamik kart görünür; sürüş "Bitir & Kaydet" veya cezasız "İptal Et" ile yönetilebilir.
* **Otomatik Otobüs:** Bağımsız dalda (`.worktrees/automatic-bus`) geliştirilmekte olup ana teslimatta veri güvenliği için dormant moddadır.

### 1.4. Sıralamalar, Utanç Tablosu ve Dürtme Mesajı
* **Gurur Tablosu:** Bireysel ve klan bazında haftalık en çok yeşil puan toplayanları sıralar.
* **Klan Utanç Tablosu:** Bireyleri hedef göstermez; haftalık en çok CO₂ israfı yapan klanları sıralar (`v_worst_clans`).
* **Utanç Dürtme Mesajı:**
  - Utanç listesindeki bir kullanıcıya dokunarak en fazla 50 karakterlik dostane uyarı mesajı gönderilebilir.
  - **Ücret:** 10 Altın (yalnızca sunucu `res.ok == true` onayı verdiğinde düşülür; ağ hatasında bakiye korunur).
  - **Kota:** Europe/Istanbul takvim gününde kullanıcı başına **en fazla 1 gönderim** yapılabilir.

### 1.5. Profil, Kozmetik Mağazası ve Kuşanılan Pet
* **Profil Fotoğrafı:** Sistem dosya seçicisi ile fotoğraf seçilebilir.
* **Kuşanılan Pet (Yoldaş):**
  - Mağazadan satın alınan ve kuşanılan petler (`bit-bee.png` — Biyo-Mekanik Arı, `auro-fairy.png` — Ozon Perisi Aura) profil fotoğrafının hemen sağında görüntülenir.
* **Biyografi:** Maksimum 160 karakter (Türkçe ve emoji güvenli).

---

## 2. ⚡ Evrensel GM ve Yönetim Paneli (Port 8787)

Yerel PC tarayıcısından doğrudan Supabase veritabanını yönetmek için geliştirilmiş, harici ADB veya cihaz loopback'i gerektirmeyen web konsoludur.

### 2.1. Panele Erişim
Tarayıcınızda şu adresi açınız:
```
http://127.0.0.1:8787
```
Bilgisayar yeniden başlatıldıysa proje klasöründe şu komutla paneli aç:
```bash
python3 -m http.server 8787 --bind 127.0.0.1 --directory tools/universal_gm
```
*(Not: Port 8080 kullanıcının `llama-server` servisine ayrıldığı için panel 8787 portuna taşınmıştır).*

### 2.2. Oturum Açma ve `server_admins` Yetkilendirmesi
1. **Oturum Dosyası Seçme:**
   - Panel açıldığında "📁 Oturum Dosyası Seç (.json)" butonuna tıklayınız.
   - Proje dizininde güvenli tutulan `.gm-private/gm_admin_session.private.json` (veya `GM-Yonetici-Oturumu.private.json`) dosyasını seçiniz.
2. **Yetki Teyidi:**
   - Panel, bu oturumun yönetici yetkisini sunucudan kontrol eder.
   - Doğrulama başarılı olduğunda **"🛡️ Yetkili Sunucu Yöneticisi"** rozeti yeşil yanar ve tüm GM müdahale butonları aktif hale gelir.
   - Oturumu olmayan veya yetkisiz kullanıcılarda tüm işlem butonları güvenlik gereği kilitli tutulur (`disabled = true`).
3. **Kalıcı Oturum ve Token Yenileme:**
   - Tarayıcı `localStorage` üzerinde saklanan oturum, PostgREST JWT süresi dolduğunda `auth/v1/token?grant_type=refresh_token` ile arka planda otomatik olarak yenilenir.

### 2.3. Yapılabilecek GM İşlemleri
Sol panelden hedef kullanıcı seçildikten sonra sağ panelden şu işlemler yürütülebilir:
* **Adım Ekle / Ayarla:** Hedef kullanıcının bugünkü adım sayısına ekleme yapma veya doğrudan sabitleme.
* **Altın Ekle / Ayarla:** Altın bakiyesi yükleme veya düzeltme.
* **Haftalık Puan Ekle / Çıkar:** Bireysel ve klan puanına anında etki eden haftalık puan mutasyonu.
* **Seri (Streak) Gün Ayarla:** Günlük seri gününü düzenleme.
* **Utanç Mesaj Kotasını Sıfırla:** Kullanıcının günlük 1 mesaj hakkını sıfırlayarak anında yeni test mesajı atabilmesini sağlama.
* **Sunucu Denetim İzi (Audit Trail):** Yapılan tüm işlemler veritabanındaki `admin_audit_trail` tablosuna atomik olarak kaydedilir ve panel altındaki konsoldan anlık izlenir.

---

## 3. ☁️ Supabase Bulut Mimarisi ve Güvenlik

* **Hedef Proje:** `fhaxxraibydsjikxacbb` (`https://fhaxxraibydsjikxacbb.supabase.co`)
* **Bağlantı ayarı:** [supabase_config.dart](../lib/services/supabase_config.dart). Yönetici oturumu veya gizli sunucu anahtarı bu dosyaya konmaz.
* **Row Level Security (RLS):**
  - Standart kullanıcılar yalnızca kamuya açık projeksiyonları (`v_leaderboard_users`, `v_clan_members`, `v_worst_clans`) okuyabilir.
  - Altın sütunu ortak listeye açılmaz. Kullanıcı kendi özel profilini ve envanterini yetkili yollarla görür; yönetim kayıtları yalnız yetkililere açıktır. Sütun izinleri ve satır erişim kuralları birlikte uygulanır.
* **Realtime:**
  - Değişiklikleri dinleyen bağlantı vardır. İki bağımsız sunucu oturumunda birinin kazandığı 5 puanın diğerinin ortak listesinde göründüğü doğrulandı. Üç fiziksel telefonun ekranında anlık güncellenme ayrıca kullanıcı tarafından denenecek.
* **Outbox Kuyruğu:**
  - Gönderilecek kayıtlar telefonda SharedPreferences ile saklanır. Bağlantı gelince tekrar gönderilir; aynı kayıt ikinci kez puan üretmemelidir. İşlenemeyen kayıtların durumu ve yeniden deneme yolu vardır. Uygulamayı silmek yerel kayıtları kaybettirebilir.

---

## 4. 📦 Android Derlemesi ve Doğrulama

* **APK Konumu:** `releases/YeSilAdim-debug.apk`
* **Dosya Boyutu:** 173.965.301 bayt (~166 MB)
* **SHA-256 Özeti:** `1f09907ec13f3f31ba3ddc58721a7eb331546cef309e658c908290142827d19b`
* **Doğrulama Komutu:**
  ```bash
  sha256sum -c releases/YeSilAdim-debug.apk.sha256
  ```
