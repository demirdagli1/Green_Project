# Backend deployment öncesi AGY incelemesi

Yalnız supabase/ ve SUPABASE_HAZIRLIK.md/SUPABASE_INCELEME.md üzerinde çalış; lib/test/pubspec diğer ajanda. Model FlashHigh. Root tokenını koru; kodu/SQLi sohbete dökme, kısa rapor ver.

Hazırlanan 1525satırlık full_deployment.sql henüz canlıya uygulanmadı; proje publicboş. Kodu bağımsız incele, gerekli düzeltmeleri migration parçaları ve full_deployment içinde tutarlı yap. Orijinal kullanıcı SQLini değiştirme. Root deploy edecektir.

Zorunlu kapılar:
- Sözleşmede cooldown yanlışlıkla15dk yazılmış: **45dk** olmalı, QR/NFC canonicaldurak ortak. Aynı event tekrarı/eşzamanlı çağrı iki kez ödül/ceza/harcama yazamaz; eventowner ayrımı korunur. Kullanıcıya tekrar ayar sorulmasın.
- Puan/CO₂ gibi istemciden gelen p_points_earned/p_co2_saved/p_wasted parametreleri doğrulanmadan güvenilir sayılamaz; server eşik/mesafe ve mevcut baseline üzerinden hesaplar/sınırlar. NaN/negatif/aşırıgirdi ret; adım1000sınırı/bike50ve35/25variance0.12/vehicle30/0.192/0.19 ve6kstreak/haftaaltın kuralları REVIZYON_02/asıl yönergelerle tutarlı.
- PublicRLS açık; başkasının profili/altını/envanteri veya globalreset adminolmayan kullanıcıdan değiştirilemez. Admin yetkisi clientmetadata'dan gelmez. Sıralama okunurken private device_id/session/secret alanları sızmaz; views security_invoker kullanır veya eşdeğer dar güvenli okuma. SECURITY DEFINER sınırı, sabitsearch_path, PUBLIC/anonEXECUTErevoke ve auth.uid checklerini gerçekten incele. RLS sadece authenticated demek sahiplik değildir.
- Şampiyon/haftalıkreset bir kez, envanterharcama atomik, foto/bio sahiplikli, klan join ve toplam/member_count tutarlı. SQLdeki mock baseline sayıları ile gerçek yeni kullanıcı katkısı iki kez sayılmasın. Mevcut telefondaki SQLde bulunmayan klanı/legacyveriyi taşımaya istemci sözleşmesi imkân versin.
- EdgeFunctionlar JWT/admin kontrolünü gerçekten yapmalı; send-push yalnızRealtimekuyruğu ise FCM/backgroundpush yapılmış gibi yazma.
- Profil fotoğrafı farklı cihazlarda da görünecekse Storage bucket/policy sözleşmesini hazırla: auth.uid klasöründe sınırlı boyut/türde upload, başkasının dosyasını overwrite/delete yok, paylaşılabilir avatar URLsi; istemci yerel filesystem yolunu sunucuya/başka telefona fotoğraf adresi diye gönderemez.
- Kullanıcı authanonymous ayarını açtı ve root canlıPOST ile HTTP200/is_anonymous=true doğruladı; tekrar isteme. Serverprojectfhaxxraibydsjikxacbb var, URL/publicconfig.env.supabase.jsonda; gerçekcloudda şu tur işlem yapma, rootMCPde.
- verification.sql sadece başarıyazan göstermelikDOolmasın; iki authkimliği ile ownershipret/aynıeventduplicate/işlemrollback gibi gerçek assertion kontrollerini rollbackli dosyada hazırla. Root cloud execute_sql ile koşturacak. Testdemo veri profillerine zarar verme.

Teslim: güncel full_deployment.sql + migrationparçaları + verification.sql, istemcinin kullanacağı son RPC/event/alan sözleşmesi ve <=30satır SUPABASE_INCELEME.md. Statikinanılan ile canlıdoğrulanmış ayrımını koru. Yeniindirme/diğerprojelereyazma/Gitpush yok.
