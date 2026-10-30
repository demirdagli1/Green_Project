-- ============================================================================
-- YEŞİL GELECEK HACKATHONU (KTÜ) - SUPABASE POSTGRESQL ŞEMASI VE MOCK-UP VERİLERİ
-- Tarih: 30-31 Ekim 2026 | Alt Tema 2.3: Dijital Karbon Ayak İzi ve Sürdürülebilirlik
-- ============================================================================
-- KULLANIM: Bu dosyanın tamamını kopyalayıp Supabase Dashboard -> SQL Editor
-- ekranına yapıştırarak "Run" tuşuna basmanız yeterlidir. Tüm tablolar,
-- ligler, klanlar, 20 kullanıcı, otobüs/QR durakları, aktiviteler, utanç tablosu
-- verileri, bildirim şablonları ve mağaza kozmetikleri otomatik oluşacaktır.
-- ============================================================================

-- Temiz kurulum için mevcut tabloları kaldır (isteğe bağlı)
DROP TABLE IF EXISTS user_inventory CASCADE;
DROP TABLE IF EXISTS shop_items CASCADE;
DROP TABLE IF EXISTS notification_templates CASCADE;
DROP TABLE IF EXISTS activities CASCADE;
DROP TABLE IF EXISTS transit_stops CASCADE;
DROP TABLE IF EXISTS weekly_champions CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS clans CASCADE;
DROP TABLE IF EXISTS leagues CASCADE;

-- ============================================================================
-- 1. LİGLER TABLOSU (Bireysel ve Klan Ligleri Ayrı)
-- ============================================================================
CREATE TABLE leagues (
    id SERIAL PRIMARY KEY,
    league_type VARCHAR(20) NOT NULL CHECK (league_type IN ('individual', 'clan')),
    tier INT NOT NULL CHECK (tier BETWEEN 1 AND 6),
    name VARCHAR(50) NOT NULL,
    min_points INT NOT NULL,
    badge_slug VARCHAR(50) NOT NULL,
    color_hex VARCHAR(10) NOT NULL,
    description TEXT
);

INSERT INTO leagues (league_type, tier, name, min_points, badge_slug, color_hex, description) VALUES
-- Bireysel Ligler (Görsel 2'deki Tasarımına Birebir Uygun)
('individual', 1, 'Karbonmonoksit', 0,     'ind_tier_1_co',       '#8C8275', 'Başlangıç seviyesi. Egzoz dumanından yeni çıkıyoruz!'),
('individual', 2, 'Karbondioksit',  150,   'ind_tier_2_co2',      '#8B5A2B', 'Adımlar hızlandı, fabrika bacalarını geride bırakıyoruz.'),
('individual', 3, 'Azot',           350,   'ind_tier_3_n2',       '#4A6070', 'Atmosferin dengesini koruyan istikrarlı yürüyüşçüler.'),
('individual', 4, 'Oksijen',        650,   'ind_tier_4_o2',       '#2CE5B5', 'Şehre nefes aldıran, toplu taşıma ve bisiklet tutkunları.'),
('individual', 5, 'Ozon',           1100,  'ind_tier_5_o3',       '#5B6EE1', 'Gezegenin koruyucu kalkanı! Karbon ayak izi minimumda.'),
('individual', 6, 'Sönmez Biyosfer',1800,  'ind_tier_6_biosfer',  '#589A42', 'Efsanevi ekosistem liderleri. Sıfır emisyon şampiyonları!'),

-- Klan Ligleri (Eskizdeki Tasarımına Birebir Uygun)
('clan', 1, 'Kül Birliği',          0,     'clan_tier_1_kul',     '#8C8275', 'Henüz kıvılcım aşamasındaki topluluklar.'),
('clan', 2, 'Sis Loncası',          2500,  'clan_tier_2_sis',     '#8B5A2B', 'Sisi dağıtmaya başlayan organize ekipler.'),
('clan', 3, 'Akım Cephesi',        6000,  'clan_tier_3_nefes',   '#4A6070', 'Rüzgarı ve hareketi arkasına alan organize klanlar.'),
('clan', 4, 'Koruyucu İttifak',     12000, 'clan_tier_4_ittifak', '#2CE5B5', 'Yeşil dönüşümü sırtlayan güçlü topluluklar.'),
('clan', 5, 'Ozon Muhafızları',     25000, 'clan_tier_5_ozon',    '#5B6EE1', 'Atmosferi koruyan elit klanlar ligi.'),
('clan', 6, 'Biyosfer Konseyi',     50000, 'clan_tier_6_konsey',  '#589A42', 'Türkiye''nin en yeşil ve yenilmez zirve toplulukları!');

-- ============================================================================
-- 2. KLANLAR TABLOSU
-- ============================================================================
CREATE TABLE clans (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    tag VARCHAR(15) NOT NULL,
    logo_url VARCHAR(255),
    league_tier INT NOT NULL DEFAULT 1,
    weekly_points INT NOT NULL DEFAULT 0,
    all_time_points INT NOT NULL DEFAULT 0,
    weekly_saved_co2_kg NUMERIC(8,2) NOT NULL DEFAULT 0.00,
    weekly_wasted_co2_kg NUMERIC(8,2) NOT NULL DEFAULT 0.00,
    member_count INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO clans (id, name, tag, logo_url, league_tier, weekly_points, all_time_points, weekly_saved_co2_kg, weekly_wasted_co2_kg, member_count) VALUES
(1, 'KTÜ Kanuni',             'KTÜ-K',  'assets/clans/ktu_kanuni.png', 5, 125430, 480200, 312.40, 14.20, 142),
(2, 'KTÜ OF',                 'KTÜ-OF', 'assets/clans/ktu_of.png',     5, 98210,  365000, 245.80, 18.50, 98),
(3, 'ODTÜ',                   'ODTU',   'assets/clans/odtu.png',       5, 87540,  410500, 218.00, 22.10, 115),
(4, 'Koç Üni',                'KOC',    'assets/clans/koc.png',        4, 76320,  290100, 184.50, 45.80, 84),
(5, 'Sabancı Üni',            'SU',     'assets/clans/sabanci.png',    4, 69430,  255400, 162.30, 39.40, 76),
(6, 'İTÜ',                    'ITU',    'assets/clans/itu.png',        4, 54210,  310000, 138.90, 25.00, 92),
(7, 'YTÜ',                    'YTU',    'assets/clans/ytu.png',        3, 48960,  198000, 119.20, 19.80, 68),
(8, 'Gazi Üni',               'GAZİ',   'assets/clans/gazi.png',       3, 42180,  175300, 104.60, 21.30, 61),
(9, 'KTÜ Dağcılık Kulübü',    'KTÜDAK', 'assets/clans/ktudak.png',     4, 38450,  142000, 98.40,  2.10,  34),
(10,'Sincanlılar Derneği',    '06SNC',  'assets/clans/sincan.png',     3, 29800,  112000, 74.20,  31.50, 45),
(11,'Kırıkkale_45',           '71_45',  'assets/clans/kirikkale.png',  2, 18400,  64500,  42.10,  28.90, 29);

SELECT setval('clans_id_seq', (SELECT MAX(id) FROM clans));

-- ============================================================================
-- 3. KULLANICILAR TABLOSU (Üyeliksiz Device-ID + İsim Sistemi)
-- ============================================================================
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id VARCHAR(100) NOT NULL UNIQUE,
    nickname VARCHAR(50) NOT NULL,
    avatar_url VARCHAR(255) NOT NULL,
    frame_slug VARCHAR(50) DEFAULT 'frame_default',
    pet_slug VARCHAR(50) DEFAULT NULL,
    clan_id INT REFERENCES clans(id) ON DELETE SET NULL,
    league_tier INT NOT NULL DEFAULT 1,
    today_steps INT NOT NULL DEFAULT 0,
    weekly_points INT NOT NULL DEFAULT 0,
    all_time_points INT NOT NULL DEFAULT 0,
    gold_coins INT NOT NULL DEFAULT 100,
    streak_days INT NOT NULL DEFAULT 0,
    last_streak_date DATE,
    weekly_saved_co2_kg NUMERIC(6,2) NOT NULL DEFAULT 0.00,
    weekly_wasted_co2_kg NUMERIC(6,2) NOT NULL DEFAULT 0.00,
    weekly_car_taxi_trips INT NOT NULL DEFAULT 0,
    weekly_car_taxi_km NUMERIC(6,2) NOT NULL DEFAULT 0.00,
    last_active_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Not: Utanç tablosu (Shame Board) sorgusunda maskeli isim ("Ahmet" -> "Ahm***")
-- doğrudan SQL View veya Frontend'de `LEFT(nickname, 3) || '***'` ile çekilir.

INSERT INTO users (
    id, device_id, nickname, avatar_url, frame_slug, pet_slug, clan_id, league_tier,
    today_steps, weekly_points, all_time_points, gold_coins, streak_days, last_streak_date,
    weekly_saved_co2_kg, weekly_wasted_co2_kg, weekly_car_taxi_trips, weekly_car_taxi_km, last_active_at
) VALUES
-- 1. Ana Demo Kullanıcısı ("Sen" - UI Tasarımındaki 6.666 adım, 8.960 puan, 12.4 kg CO2, Oksijen Ligi)
('11111111-1111-1111-1111-111111111104', 'DEV-KTU-DEMO-USER-01', 'Sen (Efe)', 'assets/avatars/user_sen.png', 'frame_oxygen_glow', 'pet_pine_sprout', 1, 4,
 6666, 8960, 34500, 1450, 12, '2026-10-30', 12.40, 0.80, 1, 4.20, NOW() - INTERVAL '15 minutes'),

-- İlk 3 Sıradaki Rakipler
('11111111-1111-1111-1111-111111111101', 'DEV-KTU-USER-001', 'Zeynep Kaya', 'assets/avatars/ava_01.png', 'frame_biosfer_gold', 'pet_robo_bee', 1, 6,
 14250, 12480, 58900, 3200, 28, '2026-10-30', 21.80, 0.00, 0, 0.00, NOW() - INTERVAL '5 minutes'),
('11111111-1111-1111-1111-111111111102', 'DEV-KTU-USER-002', 'Burak Demir', 'assets/avatars/ava_02.png', 'frame_ozone_purple', 'pet_leaf_fox', 9, 5,
 11800, 11230, 49200, 2150, 19, '2026-10-30', 18.90, 0.00, 0, 0.00, NOW() - INTERVAL '1 hour'),
('11111111-1111-1111-1111-111111111103', 'DEV-KTU-USER-003', 'Elif Yılmaz', 'assets/avatars/ava_03.png', 'frame_ozone_purple', 'pet_turtle', 2, 5,
 9420, 10540, 41800, 1890, 15, '2026-10-30', 16.50, 1.10, 1, 5.50, NOW() - INTERVAL '30 minutes'),

-- 5. - 9. Sıradaki Rakipler (UI Tasarımındaki Puanlarla Birebir)
('11111111-1111-1111-1111-111111111105', 'DEV-KTU-USER-005', 'Mert Çelik', 'assets/avatars/ava_05.png', 'frame_oxygen_glow', NULL, 1, 4,
 7120, 7430, 28400, 980, 8, '2026-10-30', 10.20, 2.40, 2, 12.00, NOW() - INTERVAL '2 hours'),
('11111111-1111-1111-1111-111111111106', 'DEV-KTU-USER-006', 'Selin Şahin', 'assets/avatars/ava_06.png', 'frame_nitrogen_steel', 'pet_cactus', 3, 4,
 6340, 6980, 24100, 820, 6, '2026-10-30', 9.80, 0.00, 0, 0.00, NOW() - INTERVAL '3 hours'),
('11111111-1111-1111-1111-111111111107', 'DEV-KTU-USER-007', 'Kerem Arslan', 'assets/avatars/ava_07.png', 'frame_nitrogen_steel', NULL, 1, 3,
 5890, 6320, 19500, 640, 4, '2026-10-29', 8.40, 3.80, 3, 19.00, NOW() - INTERVAL '4 hours'),
('11111111-1111-1111-1111-111111111108', 'DEV-KTU-USER-008', 'Ayşe Koç', 'assets/avatars/ava_08.png', 'frame_default', 'pet_mushroom', 6, 3,
 6100, 5860, 17200, 510, 5, '2026-10-30', 7.90, 1.50, 1, 7.50, NOW() - INTERVAL '6 hours'),
('11111111-1111-1111-1111-111111111109', 'DEV-KTU-USER-009', 'Caner Aydın', 'assets/avatars/ava_09.png', 'frame_default', NULL, 10, 3,
 4300, 5420, 15800, 430, 0, '2026-10-27', 6.50, 4.20, 4, 21.00, NOW() - INTERVAL '2 days'),

-- UTANÇ TABLOSU (SHAME BOARD) ŞAMPİYONLARI (Sürekli Taksiye/Arabaya Binenler!)
('11111111-1111-1111-1111-111111111110', 'DEV-SHAME-USER-010', 'Berkecan Taksi', 'assets/avatars/ava_shame_1.png', 'frame_smog_warning', NULL, 1, 1,
 850, 120, 1450, 45, 0, NULL, 0.40, 38.60, 18, 193.00, NOW() - INTERVAL '1 day'),
('11111111-1111-1111-1111-111111111111', 'DEV-SHAME-USER-011', 'Pelinsu Yılmaz', 'assets/avatars/ava_shame_2.png', 'frame_default', NULL, 4, 1,
 1120, 185, 2100, 90, 0, NULL, 0.90, 44.20, 22, 221.00, NOW() - INTERVAL '12 hours'),
('11111111-1111-1111-1111-111111111112', 'DEV-SHAME-USER-012', 'Taha Özkan', 'assets/avatars/ava_shame_3.png', 'frame_default', NULL, 1, 1,
 1450, 240, 3200, 120, 0, '2026-10-20', 1.10, 29.80, 14, 149.00, NOW() - INTERVAL '3 days'),
('11111111-1111-1111-1111-111111111113', 'DEV-SHAME-USER-013', 'Cansu Erdem', 'assets/avatars/ava_shame_4.png', 'frame_default', NULL, 1, 2,
 2300, 410, 4800, 210, 0, '2026-10-25', 2.00, 21.40, 11, 107.00, NOW() - INTERVAL '5 hours'),
('11111111-1111-1111-1111-111111111114', 'DEV-SHAME-USER-014', 'Oğuzhan Kılıç', 'assets/avatars/ava_shame_5.png', 'frame_default', NULL, 11, 1,
 620, 95, 980, 30, 0, NULL, 0.20, 34.00, 16, 170.00, NOW() - INTERVAL '4 days'),
('11111111-1111-1111-1111-111111111115', 'DEV-SHAME-USER-015', 'Hakan Doğan', 'assets/avatars/ava_shame_6.png', 'frame_default', NULL, 2, 2,
 3100, 620, 6400, 310, 1, '2026-10-29', 3.10, 18.20, 9, 91.00, NOW() - INTERVAL '1 day');

-- ============================================================================
-- 4. GEÇEN HAFTANIN ŞAMPİYONLARI TABLOSU (Ana Sayfa Vitrin Kartı İçin)
-- ============================================================================
CREATE TABLE weekly_champions (
    id SERIAL PRIMARY KEY,
    week_label VARCHAR(50) NOT NULL,
    champion_user_id UUID REFERENCES users(id),
    champion_user_points INT NOT NULL,
    champion_clan_id INT REFERENCES clans(id),
    champion_clan_points INT NOT NULL,
    total_community_saved_co2_kg NUMERIC(10,2) NOT NULL,
    announced_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO weekly_champions (week_label, champion_user_id, champion_user_points, champion_clan_id, champion_clan_points, total_community_saved_co2_kg) VALUES
('19 - 25 Ekim 2026 Haftası', '11111111-1111-1111-1111-111111111101', 14850, 1, 138900, 1420.50);

-- ============================================================================
-- 5. TOPLU TAŞIMA NFC / QR DURAK VE HAT MOCK-UP TABLOSU (Trabzon & Kampüs Odaklı)
-- ============================================================================
CREATE TABLE transit_stops (
    id SERIAL PRIMARY KEY,
    stop_code VARCHAR(30) NOT NULL UNIQUE,
    nfc_uid VARCHAR(50) NOT NULL UNIQUE,
    qr_payload VARCHAR(100) NOT NULL UNIQUE,
    route_name VARCHAR(100) NOT NULL,
    stop_name VARCHAR(100) NOT NULL,
    latitude NUMERIC(9,6) NOT NULL,
    longitude NUMERIC(9,6) NOT NULL,
    avg_trip_km NUMERIC(5,2) NOT NULL DEFAULT 6.50,
    points_reward INT NOT NULL DEFAULT 3,
    co2_saved_per_trip_kg NUMERIC(5,2) NOT NULL DEFAULT 1.15
);

INSERT INTO transit_stops (stop_code, nfc_uid, qr_payload, route_name, stop_name, latitude, longitude, avg_trip_km, points_reward, co2_saved_per_trip_kg) VALUES
('TRB-KTU-01', '04:A1:2B:9C:11:80:01', 'YESILADIM://TRANSIT/TRB-KTU-01?sig=9f8a7b', 'Kampüs Ring - Hat 1', 'KTÜ Atatürk Kültür Merkezi Durağı', 40.994210, 39.771540, 3.20, 3, 0.58),
('TRB-KTU-02', '04:A1:2B:9C:11:80:02', 'YESILADIM://TRANSIT/TRB-KTU-02?sig=3c4d5e', 'Kampüs Ring - Hat 2', 'KTÜ Mühendislik / Milli Teknoloji Atölyesi', 40.991850, 39.775120, 3.50, 3, 0.63),
('TRB-BLD-101','04:B2:4C:8D:22:90:10', 'YESILADIM://TRANSIT/TRB-BLD-101?sig=7e6f5a','Belediye Otobüsü 101','KTÜ A Kapısı - Meydan Ana Durak', 40.998120, 39.768400, 6.80, 3, 1.22),
('TRB-BLD-104','04:B2:4C:8D:22:90:14', 'YESILADIM://TRANSIT/TRB-BLD-104?sig=1a2b3c','Belediye Otobüsü 104','Kalkınma - Beşirli - Ayasofya Hattı', 40.996500, 39.765200, 11.40, 3, 2.05),
('TRB-BLD-501','04:C3:5D:7E:33:A0:50', 'YESILADIM://TRANSIT/TRB-BLD-501?sig=8d9e0f','Belediye Ekspres 501','KTÜ Kanuni Kampüsü - Of Teknoloji Fakültesi', 40.997800, 39.769100, 52.00, 3, 9.36),
('ANK-EGO-411','04:D4:6E:6F:44:B0:41', 'YESILADIM://TRANSIT/ANK-EGO-411?sig=4f5a6b','EGO 411 & Başkentray', 'ODTÜ Metro - Kızılay Aktarma', 39.891200, 32.784500, 9.20, 3, 1.65);

-- ============================================================================
-- 6. AKTİVİTE LOGLARI TABLOSU (Yürüme, Bisiklet, Otobüs ve Taksi/Araba Tespiti)
-- ============================================================================
CREATE TABLE activities (
    id SERIAL PRIMARY KEY,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    activity_type VARCHAR(25) NOT NULL CHECK (activity_type IN ('walk', 'bike', 'public_transit', 'car_taxi_penalty')),
    steps_count INT DEFAULT 0,
    distance_km NUMERIC(6,2) DEFAULT 0.00,
    avg_speed_kmh NUMERIC(5,2) DEFAULT 0.00,
    max_speed_kmh NUMERIC(5,2) DEFAULT 0.00,
    accel_variance NUMERIC(5,3) DEFAULT 0.000, -- İvmeölçer titreşim/pedal varyansı
    transit_stop_id INT REFERENCES transit_stops(id),
    points_earned INT NOT NULL DEFAULT 0,
    co2_delta_kg NUMERIC(6,2) NOT NULL DEFAULT 0.00, -- Pozitif: Tasarruf, Negatif: İsraf
    verification_status VARCHAR(30) NOT NULL DEFAULT 'verified' CHECK (verification_status IN ('verified', 'rejected_speed_spoof', 'rejected_duplicate_qr', 'shame_logged')),
    feedback_message TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO activities (
    user_id, activity_type, steps_count, distance_km, avg_speed_kmh, max_speed_kmh,
    accel_variance, transit_stop_id, points_earned, co2_delta_kg, verification_status, feedback_message, created_at
) VALUES
-- Ana kullanıcının ("Sen") bugünkü yürüyüşü (6.666 adım -> 6x5 = 30 puan, 666 adım cepte, 1000'e 334 adım kaldı!)
('11111111-1111-1111-1111-111111111104', 'walk', 6666, 5.12, 4.80, 6.20, 1.420, NULL, 30, 0.98, 'verified',
 'Harika gidiyorsun! Sadece 334 adım daha atarsan +5 puan daha cebinde. Günlük 6.000 adım barajını aştın ve 12 günlük Streak alevini korudun!', NOW() - INTERVAL '25 minutes'),

-- Ana kullanıcının NFC ile Belediye Otobüsü binişi
('11111111-1111-1111-1111-111111111104', 'public_transit', 0, 6.80, 28.50, 54.00, 0.310, 3, 3, 1.22, 'verified',
 'Belediye Otobüsü 101 (KTÜ A Kapısı - Meydan) NFC doğrulandı! Taksi yerine otobüs seçerek 1.22 kg CO2 salımını önledin ve +3 puan kazandın.', NOW() - INTERVAL '4 hours'),

-- Ana kullanıcının Sahil Bisiklet Yolu sürüşü
('11111111-1111-1111-1111-111111111104', 'bike', 0, 9.40, 18.20, 26.50, 0.890, NULL, 9, 1.80, 'verified',
 'Beşirli Sahil bisiklet sürüşün doğrulandı! 9.4 km pedal çevirerek +9 puan kazandın ve 1.80 kg CO2 tasarrufu sağladın.', NOW() - INTERVAL '1 day'),

-- HİLE YAKALAMA ÖRNEĞİ (Bisiklet modunu açıp arabayla 64 km/s hız yapan kullanıcı!)
('11111111-1111-1111-1111-111111111110', 'bike', 0, 12.50, 58.40, 74.20, 0.080, NULL, 0, -2.40, 'rejected_speed_spoof',
 'HİLE TESPİT EDİLDİ! Saatte 74.2 km hızla bisiklet mi sürüyorsun yoksa Tour de France motorlu etabında mısın? İvme sensörün pedal çevirmediğini söylüyor. Puan iptal edildi ve Utanç Tablosuna yazıldın!', NOW() - INTERVAL '6 hours'),

-- ARABA / TAKSİ YAKALAMA VE KARBON UYARISI ÖRNEĞİ (Utanç Tablosu + Bildirim Tetikleyici)
('11111111-1111-1111-1111-111111111110', 'car_taxi_penalty', 45, 8.50, 46.00, 82.00, 0.095, NULL, 0, -1.63, 'shame_logged',
 'Şu an taksi veya özel araçla gidiyorsun! Bu 8.5 km yolu 101 numaralı otobüsle gitseydin 1.63 kg CO2 tasarruf edecek ve klanına +3 puan kazandıracaktın. KTÜ Kanuni Utanç Tablosunda 1. sıraya yükseldin!', NOW() - INTERVAL '2 hours'),

('11111111-1111-1111-1111-111111111111', 'car_taxi_penalty', 20, 14.20, 52.00, 95.00, 0.070, NULL, 0, -2.72, 'shame_logged',
 'Yine mi araba? Bu 14.2 km mesafede atmosfere 2.72 kg CO2 bıraktın. Toplu taşıma kullansaydın bir ağacın 1.5 aylık emeğini kurtarabilirdin!', NOW() - INTERVAL '3 hours');

-- ============================================================================
-- 7. DUOLINGO TARZI "RAHATSIZ EDİCİ / DÜRTÜCÜ" BİLDİRİM ŞABLONLARI
-- ============================================================================
CREATE TABLE notification_templates (
    id SERIAL PRIMARY KEY,
    trigger_code VARCHAR(40) NOT NULL UNIQUE,
    title VARCHAR(100) NOT NULL,
    body_template TEXT NOT NULL,
    action_button_text VARCHAR(50) NOT NULL,
    severity VARCHAR(20) DEFAULT 'savage'
);

INSERT INTO notification_templates (trigger_code, title, body_template, action_button_text, severity) VALUES
('RIVAL_PASSED_YOU', '🚨 Koltuğun Sallanıyor!', '{rival_name} az önce seni geçti ve sıralamada üstüne çıktı! Sen de anca yat... Kalk bir 500 adım at da yerini geri al!', 'Sıralamayı Gör', 'savage'),
('STEP_NUDGE_900',   '👟 5 Puan Çöpe mi Gitsin?', 'Şu an {current_mods} adımdasın! Sadece {remaining_steps} adım daha atarsan tam +5 puan kapacaksın. Koridorda iki tur atsan bitti bu iş!', 'Adımlarımı Tamamla', 'nudge'),
('INACTIVE_WALK',    '🕸️ Ayakların Örümcek Bağladı!', 'Tam {inactive_days} gündür doğru düzgün yürümüyorsun. Biraz yürü de ayağın açılsın, kasların paslandı be!', 'Yürüyüşe Başla', 'savage'),
('NO_TRANSIT_LATELY','🚌 Hayırdır, Araba mı Aldın???', 'Bu ara hiç otobüse binmiyorsun, hayırdır? Özel şoför mü tuttun yoksa gizli gizli taksiye mi biniyorsun? Utanç tablosu seni bekliyor!', 'QR/NFC Okut', 'savage'),
('CAR_DETECTED_LIVE','🚕 Yakalandın! Taksi mi O?', 'Hızın {speed_kmh} km/s ve otobüs kaydın yok! Bu yolu toplu taşımayla gitseydin {potential_co2_kg} kg CO2 tasarruf yapabilirdin aslında!!!', 'Utanç Tablosuna Bak', 'critical'),
('STREAK_DANGER',    '🔥 {streak_days} Günlük Serin Yanıyor!', 'Saat 21:00 oldu ve 6.000 adıma ulaşmana sadece {remaining_to_6k} adım kaldı! Seriyi bozarsan klanın yüzüne nasıl bakacaksın?', 'Seriyi Kurtar', 'urgent');

-- ============================================================================
-- 8. KOZMETİK, AVATAR, ÇERÇEVE VE PET MAĞAZASI (Altın Harcama Ekranı)
-- ============================================================================
CREATE TABLE shop_items (
    id SERIAL PRIMARY KEY,
    item_slug VARCHAR(50) NOT NULL UNIQUE,
    category VARCHAR(20) NOT NULL CHECK (category IN ('avatar', 'frame', 'pet', 'title')),
    name VARCHAR(80) NOT NULL,
    price_gold INT NOT NULL,
    asset_preview VARCHAR(255) NOT NULL,
    description TEXT
);

INSERT INTO shop_items (item_slug, category, name, price_gold, asset_preview, description) VALUES
('frame_oxygen_glow',   'frame',  'Oksijen Neon Çerçevesi',     450,  'assets/shop/frame_oxygen.png',   'Profil fotoğrafının etrafında turkuaz yaprak efektleri döner.'),
('frame_ozone_purple',  'frame',  'Ozon Kalkanı Çerçevesi',     800,  'assets/shop/frame_ozone.png',    'Mor atmosferik kalkan parlaklığı.'),
('frame_biosfer_gold',  'frame',  'Sönmez Biyosfer Tacı',       1500, 'assets/shop/frame_biosfer.png',  'Sadece gerçek sıfır-atık efsanelerinin taşıyabileceği altın sarmaşık çerçeve.'),
('pet_pine_sprout',     'pet',    'Yürüyen Çam Fidanı (Pet)',   600,  'assets/shop/pet_pine.png',       'Sen adım attıkça büyüyen ve kozalak atan sevimli Karadeniz çamı.'),
('pet_robo_bee',        'pet',    'Biyo-Mekanik Arı (Pet)',     950,  'assets/shop/pet_bee.png',        'Profilinde uçuşarak polen ve oksijen puanı toplayan siber arı.'),
('pet_leaf_fox',        'pet',    'Orman Tilkisi (Pet)',        1200, 'assets/shop/pet_fox.png',        'Bisiklet sürdüğünde seninle birlikte koşan animasyonlu yoldaş.'),
('ava_cycling_pro',     'avatar', 'Aero Bisikletçi Avatarı',    350,  'assets/shop/ava_cyclist.png',    'Kasklı ve rüzgar gözlüklü özel bisikletçi karakteri.'),
('ava_ktu_mountaineer', 'avatar', 'Kaçkar Dağcısı Avatarı',     500,  'assets/shop/ava_climber.png',    'Kampüs yokuşlarını düz yol gibi çıkan efsanevi dağcı.');

-- ============================================================================
-- 9. HAZIR GÖRÜNÜMLER (VIEWS) - FRONTEND'DEN TEK SATIRLA ÇEKMEK İÇİN
-- ============================================================================

-- 9.1. Klan İçi Utanç Tablosu (İlk 3 harf + *** maskeli, en çok arabaya binenler)
CREATE OR REPLACE VIEW v_clan_shame_board AS
SELECT
    u.clan_id,
    c.name AS clan_name,
    u.id AS user_id,
    CONCAT(LEFT(u.nickname, 3), '***') AS masked_name,
    u.avatar_url,
    u.weekly_car_taxi_trips,
    u.weekly_car_taxi_km,
    u.weekly_wasted_co2_kg,
    RANK() OVER (PARTITION BY u.clan_id ORDER BY u.weekly_wasted_co2_kg DESC) AS shame_rank
FROM users u
JOIN clans c ON u.clan_id = c.id
WHERE u.weekly_car_taxi_trips > 0;

-- 9.2. Bireysel Genel Utanç Tablosu (Herkesin İçinde En Kötüler)
CREATE OR REPLACE VIEW v_global_shame_board AS
SELECT
    u.id AS user_id,
    CONCAT(LEFT(u.nickname, 3), '***') AS masked_name,
    u.avatar_url,
    c.name AS clan_name,
    u.weekly_car_taxi_trips,
    u.weekly_car_taxi_km,
    u.weekly_wasted_co2_kg,
    RANK() OVER (ORDER BY u.weekly_wasted_co2_kg DESC) AS global_shame_rank
FROM users u
LEFT JOIN clans c ON u.clan_id = c.id
WHERE u.weekly_car_taxi_trips > 0;


-- ============================================================================
-- 10. ADMİN PANELİ TABLOLARI VE FONKSİYONLARI (CANLI BİLDİRİM & SİMÜLASYON)
-- ============================================================================

-- 10.1. Admin Tarafından Gönderilen Canlı Bildirim Kuyruğu (Supabase Realtime İle Dinlenir)
CREATE TABLE IF NOT EXISTS admin_notifications_log (
    id SERIAL PRIMARY KEY,
    target_type VARCHAR(20) NOT NULL CHECK (target_type IN ('user', 'clan', 'all')),
    target_user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    target_clan_id INT REFERENCES clans(id) ON DELETE CASCADE,
    template_code VARCHAR(40),
    title VARCHAR(120) NOT NULL,
    message_body TEXT NOT NULL,
    severity VARCHAR(20) DEFAULT 'savage' CHECK (severity IN ('nudge', 'savage', 'urgent', 'critical', 'reward')),
    is_delivered BOOLEAN DEFAULT FALSE,
    sent_by VARCHAR(50) DEFAULT 'Hackathon_Admin',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO admin_notifications_log (target_type, target_user_id, target_clan_id, template_code, title, message_body, severity, is_delivered, created_at) VALUES
('user', '11111111-1111-1111-1111-111111111104', NULL, 'RIVAL_PASSED_YOU', '🚨 Koltuğun Sallanıyor!', 'Elif Yılmaz az önce seni geçti! Sen de anca yat... Kalk bir 334 adım at da +5 puanı kap!', 'savage', TRUE, NOW() - INTERVAL '12 minutes'),
('user', '11111111-1111-1111-1111-111111111110', 1, 'CAR_DETECTED_LIVE', '🚕 Yakalandın! Taksi mi O?', 'Hızın 64 km/s ve otobüs QR kaydın yok! Bu 8.5 km yolu 101 otobüsüyle gitseydin 1.63 kg CO2 tasarruf yapabilirdin aslında!!!', 'critical', TRUE, NOW() - INTERVAL '45 minutes'),
('clan', NULL, 2, 'CLAN_RIVAL_ALERT', '⚔️ KTÜ Kanuni Farkı Açıyor!', 'KTÜ OF Klanı uyuyor mu? KTÜ Kanuni bu hafta 125.430 puana ulaştı, acil yürüyüşe çıkın!', 'urgent', TRUE, NOW() - INTERVAL '2 hours');

-- 10.2. Haftalık Sıfırlama & Puanları Altına Dönüştürme Fonksiyonu (Admin Tek Tuşla Tetikler)
CREATE OR REPLACE FUNCTION admin_trigger_weekly_reset()
RETURNS void AS $$
DECLARE
    top_user RECORD;
    top_clan RECORD;
    total_co2 NUMERIC(10,2);
BEGIN
    -- 1. En yüksek puanlı bireysel şampiyonu ve klanı bul
    SELECT id, weekly_points INTO top_user FROM users ORDER BY weekly_points DESC LIMIT 1;
    SELECT id, weekly_points INTO top_clan FROM clans ORDER BY weekly_points DESC LIMIT 1;
    SELECT COALESCE(SUM(weekly_saved_co2_kg), 0) INTO total_co2 FROM clans;

    -- 2. Geçen haftanın şampiyonlar tablosuna kaydet
    INSERT INTO weekly_champions (week_label, champion_user_id, champion_user_points, champion_clan_id, champion_clan_points, total_community_saved_co2_kg)
    VALUES ('Yeni Tamamlanan Hafta', top_user.id, top_user.weekly_points, top_clan.id, top_clan.weekly_points, total_co2);

    -- 3. Kullanıcıların haftalık puanlarını Altına (Gold) ekle ve haftalık sayaçları sıfırla
    UPDATE users
    SET gold_coins = gold_coins + weekly_points,
        weekly_points = 0,
        weekly_saved_co2_kg = 0,
        weekly_wasted_co2_kg = 0,
        weekly_car_taxi_trips = 0,
        weekly_car_taxi_km = 0;

    -- 4. Klanların haftalık puanlarını sıfırla
    UPDATE clans
    SET weekly_points = 0,
        weekly_saved_co2_kg = 0,
        weekly_wasted_co2_kg = 0;
END;
$$ LANGUAGE plpgsql;