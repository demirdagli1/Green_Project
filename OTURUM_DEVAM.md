# Güncel devam noktası — 30 Ekim 2026, 23:52

Bu dosya DEVAM_RAPORU.md ve önceki ara anlık görüntülerinin önüne geçer.

**23:52 Mock-up ve Bireysel Lig Logoları Paketi Tamamlandı:**
- **Bireysel Lig Logoları (1-6 PNG):** `lig-bireysel-1.png` ... `6.png` kod-native asset olarak eklendi, `BoxFit.contain` ve ortak `IndividualLeagueBadge` bileşeniyle ana sayfa bireysel kartı ve Gurur Tablosu satırlarına bağlandı. Klanlara bireysel logo atanmadı (klan görselleri henüz yoktur). Toplu `erasebg-transformed.png` kullanılmadı.
- **Yerel Seed Verisi (SQL Kaynağı):** `supabase_schema_ve_mockup_veriler.sql` şeması/seed kaynağı baz alındı (canlı DB yok, veritabanında çalıştırılmadı).
  - 15 demo kullanıcı (Zeynep Kaya 1., Berkecan Taksi ve Pelinsu Yılmaz utanç tablosu vb.) yüklendi; 100'e tamamlamak için kullanıcı uydurulmadı.
  - 11 klan deterministik tamsayı → kalıcı string ID (`clan_ktu_kanuni`, vb.) ile eşlendi; SQL dışı mevcut klan `clan_micro` (Yalnız Gezginler) ve kullanıcı klanları korundu.
  - 6 transit durağı (`TRB-KTU-01` ... `ANK-EGO-411`) ve legacy `TRB-OF-204` aliası bağlandı.
  - 8 aktif mağaza ürünü ve legacy ürün aliasları eşlendi.
- **Sürümlü Veri Yükseltmesi (Seed v3) & İdempotentlik:** Gerçek kullanıcı profili (`me`), adı, biyografisi, fotoğraf yolu, adımları, streak'i, altınları ve klan katkıları korundu. `Sen (Efe)` kaydı `isDemo: true` olan demo kullanıcısıdır; gerçek profilin yerine geçmez. İkinci load ve restart işlemleri tamamen idempotenttir; veriler tekrar ezilmez.
- **Transit QR ve NFC Normalizasyonu:** `?sig=...` parametresi ayıklanarak durak koduna indirgenir (sahte imza iddiası yok). Kolonlu ve kolonsuz NFC UID hex dizgileri durak koduna normalize edilir. QR ve NFC binişleri arasında aynı durak için ortak 45 dk cooldown kuralı korunur.
- **Statik Kod Analizi:** `dart analyze` ➔ **0 issue (Hatasız ve Uyarısız)**.
- **Otomasyonlu Testler:** `flutter test --no-pub --concurrency=1` ➔ **107 / 107 test BAŞARILI** (103 mevcut test korundu + 4 yeni regresyon testi eklendi: `test/mockup_migration_test.dart`).
- **Offline APK Teslimatı:** Tek worker / 2 GB JVM Heap ile Gradle derlemesi **22 saniyede başarılı**.
  - Dosya: `releases/YeSilAdim-debug.apk` (169.049.571 bayt)
  - SHA-256: `59553921b3f9bc2ef427d3ea41697ac22669f539c513a652fd80d5d61b2f124b`
  - Sürüm Notu: `releases/SURUM_NOTLARI.md`
  - Sözleşme & Eşleme Raporu: [MOCKUP_ESLEME.md](MOCKUP_ESLEME.md)
- **Kullanıcı Elle Testleri:** Talimat gereği telefona otomatik dokunma/kurulum yapılmamış, telefon mevcut ekranında bırakılmıştır; elle testler kullanıcıya aittir.

## Kesin kullanıcı kuralları
- Codex yönetir/inceleme ve Git yapar; ürün ve test kodunu yalnız AGY yazar. Model Gemini 3.8 Flash High; Argon/Claude başlatma.
- Yerel ara commitlere devam; push kesinlikle yok. Kullanıcının Düzenlemeler.txt değişikliklerini geri alma veya sessizce uygulama.
- Yeni SDK/paket indirme yok. Diğer projeler salt okunur. Aynı anda bir test/derleme; Gradle offline/no-daemon/max-workers=1, 2 GB heap.
- Telefon kullanıcı tarafından elle test edilecek; telefona otomatik tıklama/kurulum yapılmaz.
