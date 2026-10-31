-- ============================================================================
-- 04_seed_data.sql
-- İdempotent Referans ve Başlangıç Verileri (Ligler, 11 Klan, 20 Kullanıcı, Duraklar, Ürünler)
-- Proje: Green_Project (fhaxxraibydsjikxacbb)
-- ============================================================================

-- 1. Ligler (Bireysel ve Klan Ligleri)
INSERT INTO public.leagues (league_type, tier, name, min_points, badge_slug, color_hex, description)
VALUES
('individual', 1, 'Karbonmonoksit', 0,     'ind_tier_1_co',       '#8C8275', 'Başlangıç seviyesi. Egzoz dumanından yeni çıkıyoruz!'),
('individual', 2, 'Karbondioksit',  150,   'ind_tier_2_co2',      '#8B5A2B', 'Adımlar hızlandı, fabrika bacalarını geride bırakıyoruz.'),
('individual', 3, 'Azot',           350,   'ind_tier_3_n2',       '#4A6070', 'Atmosferin dengesini koruyan istikrarlı yürüyüşçüler.'),
('individual', 4, 'Oksijen',        650,   'ind_tier_4_o2',       '#2CE5B5', 'Şehre nefes aldıran, toplu taşıma ve bisiklet tutkunları.'),
('individual', 5, 'Ozon',           1100,  'ind_tier_5_o3',       '#5B6EE1', 'Gezegenin koruyucu kalkanı! Karbon ayak izi minimumda.'),
('individual', 6, 'Sönmez Biyosfer',1800,  'ind_tier_6_biosfer',  '#589A42', 'Efsanevi ekosistem liderleri. Sıfır emisyon şampiyonları!'),
('clan', 1, 'Kül Birliği',          0,     'clan_tier_1_kul',     '#8C8275', 'Henüz kıvılcım aşamasındaki topluluklar.'),
('clan', 2, 'Sis Loncası',          2500,  'clan_tier_2_sis',     '#8B5A2B', 'Sisi dağıtmaya başlayan organize ekipler.'),
('clan', 3, 'Akım Cephesi',        6000,  'clan_tier_3_nefes',   '#4A6070', 'Rüzgarı ve hareketi arkasına alan organize klanlar.'),
('clan', 4, 'Koruyucu İttifak',     12000, 'clan_tier_4_ittifak', '#2CE5B5', 'Yeşil dönüşümü sırtlayan güçlü topluluklar.'),
('clan', 5, 'Ozon Muhafızları',     25000, 'clan_tier_5_ozon',    '#5B6EE1', 'Atmosferi koruyan elit klanlar ligi.'),
('clan', 6, 'Biyosfer Konseyi',     50000, 'clan_tier_6_konsey',  '#589A42', 'Türkiye''nin en yeşil ve yenilmez zirve toplulukları!')
ON CONFLICT (league_type, tier) DO UPDATE SET
    name = EXCLUDED.name,
    min_points = EXCLUDED.min_points,
    badge_slug = EXCLUDED.badge_slug,
    color_hex = EXCLUDED.color_hex,
    description = EXCLUDED.description;

-- 2. Klanlar (11 Referans Klan - Puan Eşiklerine Göre Doğrulanmış Lig Kademeleri)
-- KTÜ Kanuni (125k), OF (98k), ODTÜ (87k), Koç (76k), Sabancı (69k), İTÜ (54k) >= 50k -> Tier 6
-- YTÜ (48k), Gazi (42k), KTÜDAK (38k), Sincan (29k) >= 25k -> Tier 5
-- Kırıkkale (18k) >= 12k -> Tier 4
INSERT INTO public.clans (id, name, tag, logo_url, league_tier, weekly_points, all_time_points, weekly_saved_co2_kg, weekly_wasted_co2_kg, member_count)
VALUES
(1,  'KTÜ Kanuni',          'KTÜ-K',  'assets/clans/ktu_kanuni.png', 6, 125430, 480200, 312.40, 14.20, 142),
(2,  'KTÜ OF',              'KTÜ-OF', 'assets/clans/ktu_of.png',     6, 98210,  365000, 245.80, 18.50, 98),
(3,  'ODTÜ',                'ODTU',   'assets/clans/odtu.png',       6, 87540,  410500, 218.00, 22.10, 115),
(4,  'Koç Üni',             'KOC',    'assets/clans/koc.png',        6, 76320,  290100, 184.50, 45.80, 84),
(5,  'Sabancı Üni',         'SU',     'assets/clans/sabanci.png',    6, 69430,  255400, 162.30, 39.40, 76),
(6,  'İTÜ',                 'ITU',    'assets/clans/itu.png',        6, 54210,  310000, 138.90, 25.00, 92),
(7,  'YTÜ',                 'YTU',    'assets/clans/ytu.png',        5, 48960,  198000, 119.20, 19.80, 68),
(8,  'Gazi Üni',            'GAZİ',   'assets/clans/gazi.png',       5, 42180,  175300, 104.60, 21.30, 61),
(9,  'KTÜ Dağcılık Kulübü', 'KTÜDAK', 'assets/clans/ktudak.png',     5, 38450,  142000, 98.40,  2.10,  34),
(10, 'Sincanlılar Derneği', '06SNC',  'assets/clans/sincan.png',     5, 29800,  112000, 74.20,  31.50, 45),
(11, 'Kırıkkale_45',        '71_45',  'assets/clans/kirikkale.png',  4, 18400,  64500,  42.10,  28.90, 29)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    tag = EXCLUDED.tag,
    logo_url = EXCLUDED.logo_url,
    league_tier = EXCLUDED.league_tier,
    weekly_points = EXCLUDED.weekly_points,
    all_time_points = EXCLUDED.all_time_points,
    weekly_saved_co2_kg = EXCLUDED.weekly_saved_co2_kg,
    weekly_wasted_co2_kg = EXCLUDED.weekly_wasted_co2_kg,
    member_count = EXCLUDED.member_count;

SELECT setval('public.clans_id_seq', (SELECT MAX(id) FROM public.clans));

-- 3. Toplu Taşıma Durakları (Trabzon ve Kampüs 6 Durak)
INSERT INTO public.transit_stops (id, stop_code, nfc_uid, qr_payload, route_name, stop_name, latitude, longitude, avg_trip_km, points_reward, co2_saved_per_trip_kg)
VALUES
(1, 'TRB-KTU-01',  '04:A1:2B:9C:11:80:01', 'YESILADIM://TRANSIT/TRB-KTU-01?sig=9f8a7b',  'Kampüs Ring - Hat 1', 'KTÜ Atatürk Kültür Merkezi Durağı',       40.994210, 39.771540, 3.20,  3, 0.58),
(2, 'TRB-KTU-02',  '04:A1:2B:9C:11:80:02', 'YESILADIM://TRANSIT/TRB-KTU-02?sig=3c4d5e',  'Kampüs Ring - Hat 2', 'KTÜ Mühendislik / Milli Teknoloji Atölyesi',40.991850, 39.775120, 3.50,  3, 0.63),
(3, 'TRB-BLD-101', '04:B2:4C:8D:22:90:10', 'YESILADIM://TRANSIT/TRB-BLD-101?sig=7e6f5a', 'Belediye Otobüsü 101','KTÜ A Kapısı - Meydan Ana Durak',           40.998120, 39.768400, 6.80,  3, 1.22),
(4, 'TRB-BLD-104', '04:B2:4C:8D:22:90:14', 'YESILADIM://TRANSIT/TRB-BLD-104?sig=1a2b3c', 'Belediye Otobüsü 104','Kalkınma - Beşirli - Ayasofya Hattı',      40.996500, 39.765200, 11.40, 3, 2.05),
(5, 'TRB-BLD-501', '04:C3:5D:7E:33:A0:50', 'YESILADIM://TRANSIT/TRB-BLD-501?sig=8d9e0f', 'Belediye Ekspres 501','KTÜ Kanuni Kampüsü - Of Teknoloji Fakültesi',40.997800, 39.769100, 52.00, 3, 9.36),
(6, 'ANK-EGO-411', '04:D4:6E:6F:44:B0:41', 'YESILADIM://TRANSIT/ANK-EGO-411?sig=4f5a6b', 'EGO 411 & Başkentray','ODTÜ Metro - Kızılay Aktarma',             39.891200, 32.784500, 9.20,  3, 1.65)
ON CONFLICT (stop_code) DO UPDATE SET
    nfc_uid = EXCLUDED.nfc_uid,
    qr_payload = EXCLUDED.qr_payload,
    route_name = EXCLUDED.route_name,
    stop_name = EXCLUDED.stop_name,
    latitude = EXCLUDED.latitude,
    longitude = EXCLUDED.longitude,
    avg_trip_km = EXCLUDED.avg_trip_km,
    points_reward = EXCLUDED.points_reward,
    co2_saved_per_trip_kg = EXCLUDED.co2_saved_per_trip_kg;

SELECT setval('public.transit_stops_id_seq', (SELECT MAX(id) FROM public.transit_stops));

-- 4. Mağaza Kozmetikleri (8 Ürün)
INSERT INTO public.shop_items (id, item_slug, category, name, price_gold, asset_preview, description)
VALUES
(1, 'frame_oxygen_glow',   'frame',  'Oksijen Neon Çerçevesi',     450,  'assets/shop/frame_oxygen.png',   'Profil fotoğrafının etrafında turkuaz yaprak efektleri döner.'),
(2, 'frame_ozone_purple',  'frame',  'Ozon Kalkanı Çerçevesi',     800,  'assets/shop/frame_ozone.png',    'Mor atmosferik kalkan parlaklığı.'),
(3, 'frame_biosfer_gold',  'frame',  'Sönmez Biyosfer Tacı',       1500, 'assets/shop/frame_biosfer.png',  'Sadece gerçek sıfır-atık efsanelerinin taşıyabileceği altın sarmaşık çerçeve.'),
(4, 'pet_pine_sprout',     'pet',    'Yürüyen Çam Fidanı (Pet)',   600,  'assets/shop/pet_pine.png',       'Sen adım attıkça büyüyen ve kozalak atan sevimli Karadeniz çamı.'),
(5, 'pet_robo_bee',        'pet',    'Biyo-Mekanik Arı (Pet)',     950,  'assets/shop/pet_bee.png',        'Profilinde uçuşarak polen ve oksijen puanı toplayan siber arı.'),
(6, 'pet_leaf_fox',        'pet',    'Orman Tilkisi (Pet)',        1200, 'assets/shop/pet_fox.png',        'Bisiklet sürdüğünde seninle birlikte koşan animasyonlu yoldaş.'),
(7, 'ava_cycling_pro',     'avatar', 'Aero Bisikletçi Avatarı',    350,  'assets/shop/ava_cyclist.png',    'Kasklı ve rüzgar gözlüklü özel bisikletçi karakteri.'),
(8, 'ava_ktu_mountaineer', 'avatar', 'Kaçkar Dağcısı Avatarı',     500,  'assets/shop/ava_climber.png',    'Kampüs yokuşlarını düz yol gibi çıkan efsanevi dağcı.')
ON CONFLICT (item_slug) DO UPDATE SET
    category = EXCLUDED.category,
    name = EXCLUDED.name,
    price_gold = EXCLUDED.price_gold,
    asset_preview = EXCLUDED.asset_preview,
    description = EXCLUDED.description;

SELECT setval('public.shop_items_id_seq', (SELECT MAX(id) FROM public.shop_items));

-- 5. Bildirim Şablonları (6 Şablon)
INSERT INTO public.notification_templates (id, trigger_code, title, body_template, action_button_text, severity)
VALUES
(1, 'RIVAL_PASSED_YOU', '🚨 Koltuğun Sallanıyor!', '{rival_name} az önce seni geçti ve sıralamada üstüne çıktı! Sen de anca yat... Kalk bir 500 adım at da yerini geri al!', 'Sıralamayı Gör', 'savage'),
(2, 'STEP_NUDGE_900',   '👟 5 Puan Çöpe mi Gitsin?', 'Şu an {current_mods} adımdasın! Sadece {remaining_steps} adım daha atarsan tam +5 puan kapacaksın. Koridorda iki tur atsan bitti bu iş!', 'Adımlarımı Tamamla', 'nudge'),
(3, 'INACTIVE_WALK',    '🕸️ Ayakların Örümcek Bağladı!', 'Tam {inactive_days} gündür doğru düzgün yürümüyorsun. Biraz yürü de ayağın açılsın, kasların paslandı be!', 'Yürüyüşe Başla', 'savage'),
(4, 'NO_TRANSIT_LATELY','🚌 Hayırdır, Araba mı Aldın???', 'Bu ara hiç otobüse binmiyorsun, hayırdır? Özel şoför mü tuttun yoksa gizli gizli taksiye mi biniyorsun? Utanç tablosu seni bekliyor!', 'QR/NFC Okut', 'savage'),
(5, 'CAR_DETECTED_LIVE','🚕 Yakalandın! Taksi mi O?', 'Hızın {speed_kmh} km/s ve otobüs kaydın yok! Bu yolu toplu taşımayla gitseydin {potential_co2_kg} kg CO2 tasarruf yapabilirdin aslında!!!', 'Utanç Tablosuna Bak', 'critical'),
(6, 'STREAK_DANGER',    '🔥 {streak_days} Günlük Serin Yanıyor!', 'Saat 21:00 oldu ve 6.000 adıma ulaşmana sadece {remaining_to_6k} adım kaldı! Seriyi bozarsan klanın yüzüne nasıl bakacaksın?', 'Seriyi Kurtar', 'urgent')
ON CONFLICT (trigger_code) DO UPDATE SET
    title = EXCLUDED.title,
    body_template = EXCLUDED.body_template,
    action_button_text = EXCLUDED.action_button_text,
    severity = EXCLUDED.severity;

SELECT setval('public.notification_templates_id_seq', (SELECT MAX(id) FROM public.notification_templates));

-- 6. Kullanıcılar (20 Referans Demo Kullanıcısı - Tümü is_demo = true ve Puan Eşiklerine Göre Doğrulanmış Tier)
INSERT INTO public.users (
    id, device_id, nickname, avatar_url, frame_slug, pet_slug, clan_id, league_tier,
    today_steps, weekly_points, all_time_points, gold_coins, streak_days, last_streak_date,
    weekly_saved_co2_kg, weekly_wasted_co2_kg, weekly_car_taxi_trips, weekly_car_taxi_km, is_demo, last_active_at
) VALUES
-- 1. Demo Kullanıcı: Sen (Efe) - 8.960 puan -> Tier 6 (Sönmez Biyosfer, min 1800)
('11111111-1111-1111-1111-111111111104', 'DEV-KTU-DEMO-USER-01', 'Sen (Efe)', 'assets/avatars/user_sen.png', 'frame_oxygen_glow', 'pet_pine_sprout', 1, 6,
 6666, 8960, 34500, 1450, 12, '2026-10-30', 12.40, 0.80, 1, 4.20, true, NOW() - INTERVAL '15 minutes'),

-- 2-4: Zirve Kullanıcılar (>=1800 -> Tier 6)
('11111111-1111-1111-1111-111111111101', 'DEV-KTU-USER-001', 'Zeynep Kaya', 'assets/avatars/ava_01.png', 'frame_biosfer_gold', 'pet_robo_bee', 1, 6,
 14250, 12480, 58900, 3200, 28, '2026-10-30', 21.80, 0.00, 0, 0.00, true, NOW() - INTERVAL '5 minutes'),
('11111111-1111-1111-1111-111111111102', 'DEV-KTU-USER-002', 'Burak Demir', 'assets/avatars/ava_02.png', 'frame_ozone_purple', 'pet_leaf_fox', 9, 6,
 11800, 11230, 49200, 2150, 19, '2026-10-30', 18.90, 0.00, 0, 0.00, true, NOW() - INTERVAL '1 hour'),
('11111111-1111-1111-1111-111111111103', 'DEV-KTU-USER-003', 'Elif Yılmaz', 'assets/avatars/ava_03.png', 'frame_ozone_purple', 'none', 2, 6,
 9420, 10540, 41800, 1890, 15, '2026-10-30', 16.50, 1.10, 1, 5.50, true, NOW() - INTERVAL '30 minutes'),

-- 5-9: Orta-Üst Sıralar (>=1800 -> Tier 6)
('11111111-1111-1111-1111-111111111105', 'DEV-KTU-USER-005', 'Mert Çelik', 'assets/avatars/ava_05.png', 'frame_oxygen_glow', 'none', 1, 6,
 7120, 7430, 28400, 980, 8, '2026-10-30', 10.20, 2.40, 2, 12.00, true, NOW() - INTERVAL '2 hours'),
('11111111-1111-1111-1111-111111111106', 'DEV-KTU-USER-006', 'Selin Şahin', 'assets/avatars/ava_06.png', 'none', 'none', 3, 6,
 6340, 6980, 24100, 820, 6, '2026-10-30', 9.80, 0.00, 0, 0.00, true, NOW() - INTERVAL '3 hours'),
('11111111-1111-1111-1111-111111111107', 'DEV-KTU-USER-007', 'Kerem Arslan', 'assets/avatars/ava_07.png', 'none', 'none', 1, 6,
 5890, 6320, 19500, 640, 4, '2026-10-29', 8.40, 3.80, 3, 19.00, true, NOW() - INTERVAL '4 hours'),
('11111111-1111-1111-1111-111111111108', 'DEV-KTU-USER-008', 'Ayşe Koç', 'assets/avatars/ava_08.png', 'none', 'none', 6, 6,
 6100, 5860, 17200, 510, 5, '2026-10-30', 7.90, 1.50, 1, 7.50, true, NOW() - INTERVAL '6 hours'),
('11111111-1111-1111-1111-111111111109', 'DEV-KTU-USER-009', 'Caner Aydın', 'assets/avatars/ava_09.png', 'none', 'none', 10, 6,
 4300, 5420, 15800, 430, 0, '2026-10-27', 6.50, 4.20, 4, 21.00, true, NOW() - INTERVAL '2 days'),

-- 10-15: Utanç Tablosu Kullanıcıları (Puan eşiklerine göre doğru tierler)
('11111111-1111-1111-1111-111111111110', 'DEV-SHAME-USER-010', 'Berkecan Taksi', 'assets/avatars/ava_shame_1.png', 'none', 'none', 1, 1,
 850, 120, 1450, 45, 0, NULL, 0.40, 38.60, 18, 193.00, true, NOW() - INTERVAL '1 day'),
('11111111-1111-1111-1111-111111111111', 'DEV-SHAME-USER-011', 'Pelinsu Yılmaz', 'assets/avatars/ava_shame_2.png', 'none', 'none', 4, 2,
 1120, 185, 2100, 90, 0, NULL, 0.90, 44.20, 22, 221.00, true, NOW() - INTERVAL '12 hours'),
('11111111-1111-1111-1111-111111111112', 'DEV-SHAME-USER-012', 'Taha Özkan', 'assets/avatars/ava_shame_3.png', 'none', 'none', 1, 2,
 1450, 240, 3200, 120, 0, '2026-10-20', 1.10, 29.80, 14, 149.00, true, NOW() - INTERVAL '3 days'),
('11111111-1111-1111-1111-111111111113', 'DEV-SHAME-USER-013', 'Cansu Erdem', 'assets/avatars/ava_shame_4.png', 'none', 'none', 1, 3,
 2300, 410, 4800, 210, 0, '2026-10-25', 2.00, 21.40, 11, 107.00, true, NOW() - INTERVAL '5 hours'),
('11111111-1111-1111-1111-111111111114', 'DEV-SHAME-USER-014', 'Oğuzhan Kılıç', 'assets/avatars/ava_shame_5.png', 'none', 'none', 11, 1,
 620, 95, 980, 30, 0, NULL, 0.20, 34.00, 16, 170.00, true, NOW() - INTERVAL '4 days'),
('11111111-1111-1111-1111-111111111115', 'DEV-SHAME-USER-015', 'Hakan Doğan', 'assets/avatars/ava_shame_6.png', 'none', 'none', 2, 3,
 3100, 620, 6400, 310, 1, '2026-10-29', 3.10, 18.20, 9, 91.00, true, NOW() - INTERVAL '1 day'),

-- 16-20: Farklı Lig ve Durumlarda 5 Ek Kullanıcı (Toplam 20 Kullanıcıyı Tamamlayan İdempotent Kayıtlar)
('11111111-1111-1111-1111-111111111116', 'DEV-KTU-USER-016', 'Deniz Yıldız', 'assets/avatars/ava_01.png', 'none', 'none', 7, 5,
 8200, 1420, 18200, 720, 7, '2026-10-30', 11.20, 0.00, 0, 0.00, true, NOW() - INTERVAL '40 minutes'),
('11111111-1111-1111-1111-111111111117', 'DEV-KTU-USER-017', 'Barış Aksoy', 'assets/avatars/ava_02.png', 'none', 'none', 8, 4,
 6500, 950, 12400, 480, 3, '2026-10-30', 8.60, 2.10, 1, 10.50, true, NOW() - INTERVAL '3 hours'),
('11111111-1111-1111-1111-111111111118', 'DEV-KTU-USER-018', 'Gizem Vural', 'assets/avatars/ava_03.png', 'none', 'none', 5, 3,
 4100, 520, 8900, 300, 2, '2026-10-29', 5.10, 0.00, 0, 0.00, true, NOW() - INTERVAL '1 day'),
('11111111-1111-1111-1111-111111111119', 'DEV-KTU-USER-019', 'Emre Bulut', 'assets/avatars/ava_05.png', 'none', 'none', 9, 2,
 2800, 290, 5100, 190, 1, '2026-10-28', 3.20, 4.80, 2, 24.00, true, NOW() - INTERVAL '2 days'),
('11111111-1111-1111-1111-111111111120', 'DEV-SHAME-USER-020', 'Sarp Kaya', 'assets/avatars/ava_shame_1.png', 'none', 'none', 3, 1,
 900, 80, 1100, 40, 0, NULL, 0.30, 24.50, 12, 122.50, true, NOW() - INTERVAL '1 day')
ON CONFLICT (id) DO UPDATE SET
    nickname = EXCLUDED.nickname,
    avatar_url = EXCLUDED.avatar_url,
    frame_slug = EXCLUDED.frame_slug,
    pet_slug = EXCLUDED.pet_slug,
    clan_id = EXCLUDED.clan_id,
    league_tier = EXCLUDED.league_tier,
    today_steps = EXCLUDED.today_steps,
    weekly_points = EXCLUDED.weekly_points,
    all_time_points = EXCLUDED.all_time_points,
    gold_coins = EXCLUDED.gold_coins,
    streak_days = EXCLUDED.streak_days,
    weekly_saved_co2_kg = EXCLUDED.weekly_saved_co2_kg,
    weekly_wasted_co2_kg = EXCLUDED.weekly_wasted_co2_kg,
    weekly_car_taxi_trips = EXCLUDED.weekly_car_taxi_trips,
    weekly_car_taxi_km = EXCLUDED.weekly_car_taxi_km,
    is_demo = EXCLUDED.is_demo;

-- 7. Demo Kullanıcıların Kuşandığı Eşyaları Envanterlerine Ekle
INSERT INTO public.user_inventory (user_id, item_slug)
VALUES
('11111111-1111-1111-1111-111111111104', 'frame_oxygen_glow'),
('11111111-1111-1111-1111-111111111104', 'pet_pine_sprout'),
('11111111-1111-1111-1111-111111111101', 'frame_biosfer_gold'),
('11111111-1111-1111-1111-111111111101', 'pet_robo_bee'),
('11111111-1111-1111-1111-111111111102', 'frame_ozone_purple'),
('11111111-1111-1111-1111-111111111102', 'pet_leaf_fox'),
('11111111-1111-1111-1111-111111111103', 'frame_ozone_purple'),
('11111111-1111-1111-1111-111111111105', 'frame_oxygen_glow')
ON CONFLICT (user_id, item_slug) DO NOTHING;

-- 8. Geçen Haftanın Şampiyonları (1 Kayıt - 2026-W43)
INSERT INTO public.weekly_champions (id, week_id, week_label, champion_user_id, champion_user_points, champion_clan_id, champion_clan_points, total_community_saved_co2_kg, announced_at)
VALUES
(1, '2026-W43', '19 - 25 Ekim 2026 Haftası', '11111111-1111-1111-1111-111111111101', 14850, 1, 138900, 1420.50, NOW() - INTERVAL '5 days')
ON CONFLICT (id) DO UPDATE SET
    week_id = EXCLUDED.week_id,
    week_label = EXCLUDED.week_label,
    champion_user_id = EXCLUDED.champion_user_id,
    champion_user_points = EXCLUDED.champion_user_points,
    champion_clan_id = EXCLUDED.champion_clan_id,
    champion_clan_points = EXCLUDED.champion_clan_points,
    total_community_saved_co2_kg = EXCLUDED.total_community_saved_co2_kg;

SELECT setval('public.weekly_champions_id_seq', (SELECT MAX(id) FROM public.weekly_champions));

-- 9. Örnek Aktivite Logları
INSERT INTO public.activities (
    user_id, activity_type, steps_count, distance_km, avg_speed_kmh, max_speed_kmh,
    accel_variance, transit_stop_id, points_earned, co2_delta_kg, verification_status, feedback_message, created_at
) VALUES
('11111111-1111-1111-1111-111111111104', 'walk', 6666, 5.12, 4.80, 6.20, 1.420, NULL, 30, 0.98, 'verified',
 'Harika gidiyorsun! Günlük adım barajını aştın ve streakini korudun.', NOW() - INTERVAL '25 minutes'),
('11111111-1111-1111-1111-111111111104', 'public_transit', 0, 6.80, 28.50, 54.00, 0.310, 3, 3, 1.22, 'verified',
 'Belediye Otobüsü 101 NFC doğrulandı! 1.22 kg CO2 salımını önledin.', NOW() - INTERVAL '4 hours'),
('11111111-1111-1111-1111-111111111104', 'bike', 0, 9.40, 18.20, 26.50, 0.890, NULL, 9, 1.80, 'verified',
 'Beşirli Sahil bisiklet sürüşün doğrulandı! +9 puan kazandın.', NOW() - INTERVAL '1 day'),
('11111111-1111-1111-1111-111111111110', 'bike', 0, 12.50, 58.40, 74.20, 0.080, NULL, 0, 0.00, 'rejected_speed_spoof',
 'HİLE TESPİT EDİLDİ! 74.2 km/s bisiklet hızı reddedildi.', NOW() - INTERVAL '6 hours'),
('11111111-1111-1111-1111-111111111110', 'car_taxi_penalty', 45, 8.50, 46.00, 82.00, 0.095, NULL, 0, -1.63, 'shame_logged',
 'Taksi kullanımı tespit edildi. Utanç tablosuna işlendi.', NOW() - INTERVAL '2 hours'),
('11111111-1111-1111-1111-111111111111', 'car_taxi_penalty', 20, 14.20, 52.00, 95.00, 0.070, NULL, 0, -2.72, 'shame_logged',
 'Özel araç kullanımı tespit edildi. 2.72 kg CO2 israfı kaydedildi.', NOW() - INTERVAL '3 hours')
ON CONFLICT DO NOTHING;

-- 10. Admin Canlı Bildirim Örnekleri
INSERT INTO public.admin_notifications_log (id, target_type, target_user_id, target_clan_id, template_code, title, message_body, severity, is_delivered, created_at)
VALUES
(1, 'user', '11111111-1111-1111-1111-111111111104', NULL, 'RIVAL_PASSED_YOU', '🚨 Koltuğun Sallanıyor!', 'Elif Yılmaz az önce seni geçti! Sen de anca yat... Kalk bir adım at da yerini geri al!', 'savage', true, NOW() - INTERVAL '12 minutes'),
(2, 'user', '11111111-1111-1111-1111-111111111110', 1, 'CAR_DETECTED_LIVE', '🚕 Yakalandın! Taksi mi O?', 'Hızın 64 km/s ve otobüs QR kaydın yok! Bu 8.5 km yolu 101 otobüsüyle gitseydin 1.63 kg CO2 tasarruf yapabilirdin!', 'critical', true, NOW() - INTERVAL '45 minutes'),
(3, 'clan', NULL, 2, 'CLAN_RIVAL_ALERT', '⚔️ KTÜ Kanuni Farkı Açıyor!', 'KTÜ OF Klanı uyuyor mu? KTÜ Kanuni bu hafta 125.430 puana ulaştı, acil yürüyüşe çıkın!', 'urgent', true, NOW() - INTERVAL '2 hours')
ON CONFLICT (id) DO UPDATE SET
    title = EXCLUDED.title,
    message_body = EXCLUDED.message_body,
    severity = EXCLUDED.severity;

SELECT setval('public.admin_notifications_log_id_seq', (SELECT MAX(id) FROM public.admin_notifications_log));
