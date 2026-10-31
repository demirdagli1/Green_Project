# Otomatik güvenlik incelemesi reddi — düzeltme görevi

Root apply_migration ile `fhaxxraibydsjikxacbb` projesine full_deployment.sql uygulamayı denedi. Otomatik onay incelemesi reddetti: "large persistent live-database mutation, including broad public policies and exposure of user fields such as gold_coins, without explicit authorization for that exact security configuration or evidence the target is empty". İşlem uygulanmadı. Aynı SQLi başka API/execute_sql üzerinden dolanarak çalıştırma; bu reddi bypass etmek yasak.

Root aynı projenin public tablolarını yeniden listeliyor; önceki incelemede de boştu. Yeni0$/ayGreen_Project projesini kullanıcı açıkça oluşturttu, sunucu entegrasyonunu istedi. Bu yetki geniş private veri paylaşımı anlamına gelmez.

AGY yalnız backend dosyalarında daha güvenli çözüm üretsin:
- users/device_id/gold_coins/envanter/private hesap alanlarına herkese SELECT veren GRANT/policy/viewları kaldır. Sıralama için yalnız gerekli ad/avatar/bio/klan/lig/puan ve maskeli utanç ölçümleri okunabilsin. device_id, altın ve özel durum sadece kendi oturumunun dar sahiplikliRPCsiyle veya özel tablodan okunur.
- En az değişiklikle dar public projection/kolon GRANTı + security_invoker view ya da ayrı public leaderboard tablosu tasarla; users SELECT* erişimi tümkullanıcılara açılamaz. İstemci ajanı SUPABASE_ISTEMCI_GOREVI.md üzerinde çalışıyor; yeni güvenli view/okuma sözleşmesini SUPABASE_HAZIRLIK.mdde netleştir, istemci dosyalarına dokunma.
- Tüm PUBLIC/anonGRANTlar ve definerfunctionlar için işlevsel en az yetki; globaladmin/reset ayrı yönetim yetkili. Doğrulama SQLi iki kullanıcı kimliğiyle gold/device_id gibi private alanı başka hesaptan okuyamama assertionını da içersin.
- Serveradımödülü olaybaşına FLOOR(delta/1000) olamaz: aynıgün500+500 adım toplamı tek+5, duplicateödülsüz, güngeçişidoğru; bunu verification SQLine assertionla ekle. Canonical QR/NFC45dk ve harcama/reset tekrarları da gerçek assertionlarla sınansın.
- SourceSQL DROP komutları yok; hiçbirkullanıcıverisi silinmez. full_deployment + parçalar tutarlı kalsın. Güvenli değişiklikleri SUPABASE_GUVENLI_DUZELTME.mdde <=20satır yaz. Sonra root güncel boş-hedef kanıtı ve değiştirilmiş SQL ile aynı apply_migration yolunu yeniden deneyecek; bypass yok.
- BüyükSQLi/planırootsohbete dökme. Kod/SQLAGYde, rootdeploy/commit yapar; son modelFlashHigh. Remoteişlem yapma, frontenddosyalarını diğerajan değiştirsin.
