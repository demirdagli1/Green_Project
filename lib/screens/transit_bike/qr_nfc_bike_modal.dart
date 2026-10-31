import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/hub.dart';

class QrNfcBikeModal extends StatefulWidget {
  final bool isTab;
  const QrNfcBikeModal({super.key, this.isTab = false});

  @override
  State<QrNfcBikeModal> createState() => _QrNfcBikeModalState();
}

class _QrNfcBikeModalState extends State<QrNfcBikeModal> {
  final _code = TextEditingController();
  String? _msg;
  bool _msgOk = false;

  @override
  void dispose() {
    _code.dispose();
    Hub.sensors.stopNfc();
    super.dispose();
  }

  void _show(String m, bool ok) => setState(() {
        _msg = m;
        _msgOk = ok;
      });

  @override
  Widget build(BuildContext context) {
    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _transitSection(),
        const SizedBox(height: 16),
        _bikeSection(),
      ],
    );

    if (widget.isTab) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          title: const Text(
            'Ulaşım Doğrulama & Bisiklet',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
        ),
        body: content,
      );
    }

    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ulaşım Doğrulama & Bisiklet',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }

  Widget _transitSection() {
    final store = Hub.store;
    final sensors = Hub.sensors;
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ListenableBuilder(
          listenable: sensors,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryPurple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.directions_bus, color: AppColors.primaryPurple, size: 22),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Toplu Taşıma Doğrula (+3 Puan)',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                        ),
                        Text(
                          'Aynı durak QR/NFC: 45 dk içinde 1 kez geçerlidir.',
                          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Kamera ile QR tarama bu sürümde YOK (kamera/QR paketi yerelde bulunmadı). QR içeriğini aşağıya elle yazabilirsin.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _code,
                      decoration: const InputDecoration(
                        labelText: 'Durak Kodu (YESILADIM://... veya kod)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final r = store.scanTransit(_code.text, source: 'Manuel');
                      _show(r.message, r.ok);
                    },
                    child: const Text('Doğrula'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (!sensors.nfcAvailable)
                const Text('Bu cihazda NFC donanımı yok.', style: TextStyle(color: AppColors.fireRed, fontSize: 12))
              else if (!sensors.nfcEnabled)
                const Text('NFC kapalı: Android ayarlarından aç.', style: TextStyle(color: AppColors.fireRed, fontSize: 12))
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.nfc),
                    label: Text(sensors.nfcListening ? 'NFC dinleniyor… (etiketi yaklaştır)' : 'NFC okumayı başlat'),
                    onPressed: () async {
                      final ok = await sensors.startNfc();
                      if (!ok) _show('NFC başlatılamadı.', false);
                    },
                  ),
                ),
              if (sensors.lastEventNote != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('NFC Durumu: ${sensors.lastEventNote}', style: const TextStyle(fontSize: 12)),
                ),
              const SizedBox(height: 12),
              const Text('Hızlı Test Durakları (Demo)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final s in store.stops)
                    ActionChip(
                      label: Text(s.code, style: const TextStyle(fontSize: 11)),
                      onPressed: () {
                        final r = store.scanTransit(s.code, source: 'DEMO');
                        _show(r.message, r.ok);
                      },
                    ),
                ],
              ),
              if (_msg != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _msg!,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: _msgOk ? AppColors.emeraldGreen : AppColors.fireRed,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bikeSection() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ListenableBuilder(
          listenable: Listenable.merge([Hub.store, Hub.sensors]),
          builder: (context, _) {
            final s = Hub.store;
            final b = s.bike;
            final sensors = Hub.sensors;
            final gpsReady = sensors.started['gps'] == true;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.emeraldGreen.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.pedal_bike, color: AppColors.emeraldGreen, size: 22),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Bisiklet Sürüş Modu', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                          Text('Tamamlanan her 1 km = +1 Puan (Tam km esası)', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _stat('HIZ (GPS)', '${(b?.currentKmh ?? 0).toStringAsFixed(1)} km/sa'),
                    _stat('MESAFE', '${(b?.distanceKm ?? 0).toStringAsFixed(3)} km'),
                    _stat('GEÇERLİ FİX', '${b?.validFixes ?? 0}'),
                  ],
                ),
                const SizedBox(height: 12),
                if (!gpsReady)
                  const Text(
                    'GPS kullanılamıyor (izin verilmemiş veya konum kapalı). Sürüş başlatılamaz.',
                    style: TextStyle(color: AppColors.fireRed, fontSize: 12),
                  ),
                if (b != null && b.jumps + b.lowAccuracy > 0)
                  Text(
                    'Atlanan GPS örneği: ${b.jumps} sıçrama, ${b.lowAccuracy} düşük doğruluk',
                    style: const TextStyle(fontSize: 11),
                  ),
                const SizedBox(height: 12),
                if (b == null)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      onPressed: gpsReady ? () => s.startBike() : null,
                      label: const Text('Bisiklet Modunu Başlat'),
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => b.paused ? s.resumeBike() : s.pauseBike(),
                          child: Text(b.paused ? 'Devam Et' : 'Durdur'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            final r = s.finishBike();
                            _show(r.message, r.ok);
                          },
                          child: const Text('Bitir ve Değerlendir'),
                        ),
                      ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _stat(String l, String v) => Column(
        children: [
          Text(l, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
          Text(v, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
        ],
      );
}
