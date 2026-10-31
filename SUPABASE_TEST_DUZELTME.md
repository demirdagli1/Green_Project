# Canlı test scriptini güvenli yap

Şema `fhaxxraibydsjikxacbb` projesine `green_project_initial_schema_safe` migrationıyla root tarafından başarıyla uygulandı. Kullanıcı bu publicprofil/privatehesap erişimmodelini açıkça onayladı. Securityadvisors boş döndü. **Şema dosyalarını bu tur değiştirme, deployment tekrar etme.**

Root verification.sql çağrısı otomatik güvenlik incelemesinde reddedildi: globalweeklyreset seededuser/klan puan-altın-sayaçlarını kalıcıdeğiştiriyor; cleanup eski değerleri geri getirmiyor. Test çalışmadı. Aynıscripti başkayoldan çalıştırıp reddi bypass etme.

Yalnız `supabase/verification.sql` dosyasını ve <=10satır testnotunu düzelt: tüm fixture/data/RPC/reset işlemleri açık tek transaction **BEGIN ... ROLLBACK** içinde, COMMIT yok. Kalıcı temizlik/değişiklik yok. Globalreset mutlaka test edilecekse onun tüm etkileri aynı rollbackli transaction içinde kalır; client/userdata bozulmaz. İki kimlikownership/privatekolonret, partial500+500steps+duplicate,45dk QR/NFC, atomikstore ve haftareset idempotency assertionları gerçekfonksiyonları sınasın. Sahte başarı SELECT'i yazma.

Tokenları/cihazverileriniçıktıyaatma; lib/test/pubspec başkaAGYde, dokunma. Root düzeltilmişscripti aynı execute_sql yolunda yeniden kontrol ettirip koşturacak, kendiSQLkodu yazmaz. Kısa somut dosyateslimi ver, SQLi sohbete dökme. ModelFlashHigh.
