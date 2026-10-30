import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/hub.dart';

/// Jüri/Admin DEMO paneli: yerel veriyi etkiler, sensör sonucu DEĞİLDİR; cihazlar arası/sunucu etkisi yoktur.
class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  int _seq = 0;
  static const _nudges = [
    'Zeynep seni geçti, sen de anca yat!',
    'Biraz yürü ayağın açılsın, bir süredir yürümüyosun',
    'Bu ara hiç otobüse binmiyosun, hayırdır? Araba mı aldın???',
  ];

  String _id(String p) => '${p}_${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Widget _btn(String label, String sub, VoidCallback onTap) => Card(
        child: ListTile(title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)), subtitle: Text(sub, style: const TextStyle(fontSize: 11)), trailing: const Icon(Icons.play_arrow), onTap: onTap),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Hub.store,
      builder: (context, _) {
        final s = Hub.store;
        return Scaffold(
          appBar: AppBar(title: const Text('Jüri / Admin (DEMO)', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18))),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(12)),
              child: const Text('DEMO: Bu işlemler gerçek sensör/backend sonucu değildir; yalnız bu cihazın yerel verisini değiştirir. Cihazlar arası Realtime/bildirim yok.',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 12),
            _btn('[DEMO] +334 adım ekle', 'Günlük adım +334; 1.000 sınırı geçilirse +5 puan.', () {
              final r = s.demoAddSteps(334);
              _snack(r.message);
            }),
            _btn('[DEMO] Adımı 6.666\'ya tamamla', 'Mevcut adım 6.666\'dan azsa aradaki farkı ekler.', () {
              final need = 6666 - (s.me?.todaySteps ?? 0);
              _snack(need > 0 ? s.demoAddSteps(need).message : 'Zaten 6.666 veya üstü');
            }),
            _btn('[DEMO] 101 otobüs doğrula', 'TRB-BLD-101 kodu: normal cooldown kuralıyla +3 puan.', () {
              _snack(s.scanTransit('YESILADIM://TRANSIT/TRB-BLD-101', source: 'DEMO').message);
            }),
            _btn('[DEMO] 68 km/sa araba/taksi yakala', '8,5 km, adım yok, 45 dk içinde biniş yoksa.', () {
              final r = s.evaluateVehicle(tripId: _id('demo_taxi'), avgSpeedKmh: 68, distanceKm: 8.5, stepDelta: 0, demo: true);
              _snack(r.message);
            }),
            _btn('[DEMO] 72 km/sa bisiklet hilesi', '72 km/sa ≥ 50 sınırı: reddedilir.', () {
              final r = s.evaluateBike(tripId: _id('demo_bike'), distanceKm: 5, maxSpeedKmh: 72, avgSpeedKmh: 40, demo: true);
              _snack(r.message);
            }),
            _btn('[DEMO] Titreşimsiz 28 km/sa bisiklet', 'Ort. 28 km/sa, varyans 0,05 < 0,12: ceza (kesin kanıt değil).', () {
              final r = s.evaluateBike(tripId: _id('demo_bike2'), distanceKm: 4, maxSpeedKmh: 30, avgSpeedKmh: 28, fastAccelVariance: 0.05, demo: true);
              _snack(r.message);
            }),
            _btn('[DEMO] +1000 altın', 'Mağazayı denemek için.', () => _snack(s.demoGrantGold(1000).message)),
            const SizedBox(height: 8),
            Card(
              color: const Color(0xFFFEF3C7),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Hafta: ${s.weekId} (Pzt 00:00 Europe/Istanbul)', style: const TextStyle(fontWeight: FontWeight.w800)),
                  const Text('Bu haftanın puanları bir kez altına çevrilir; aynı hafta için tekrar çağrı etkisizdir. Sonraki basış, demo olarak bir sonraki haftayı kapatır.',
                      style: TextStyle(fontSize: 11)),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () {
                      final ok = s.settleWeek(s.weekId);
                      _snack(ok ? 'Hafta kapandı; puanlar altına çevrildi.' : 'Bu hafta zaten kapatıldı.');
                    },
                    child: const Text('Haftayı Bitir & Puanları Altına Çevir'),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Darlama bildirimi (yalnız bu cihaz)', style: TextStyle(fontWeight: FontWeight.w900)),
            for (final n in _nudges)
              ListTile(
                dense: true,
                title: Text(n, style: const TextStyle(fontSize: 12)),
                trailing: IconButton(
                  icon: const Icon(Icons.send, color: AppColors.emeraldGreen),
                  onPressed: () {
                    s.demoNotify('🦉 Yeşil Adım', n);
                    _snack('Bildirim gönderildi (yerel).');
                  },
                ),
              ),
            const SizedBox(height: 8),
            const Text('Günlük', style: TextStyle(fontWeight: FontWeight.w900)),
            if (s.log.isEmpty) const Text('Kayıt yok.'),
            for (final e in s.log.take(15))
              ListTile(
                dense: true,
                title: Text('${e.demo ? '[DEMO] ' : ''}${e.title}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                subtitle: Text(e.body, style: const TextStyle(fontSize: 11)),
              ),
          ]),
        );
      },
    );
  }
}
