import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/hub.dart';

class QrNfcBikeModal extends StatefulWidget {
  final bool isTab;
  const QrNfcBikeModal({super.key, this.isTab = false});

  @override
  State<QrNfcBikeModal> createState() => _QrNfcBikeModalState();
}

class _QrNfcBikeModalState extends State<QrNfcBikeModal> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _code = TextEditingController();
  String? _msg;
  bool _msgOk = false;

  @override
  void dispose() {
    _tabs.dispose();
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
    if (widget.isTab) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          title: const Text('Toplu Taşıma & Bisiklet', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          bottom: TabBar(
            controller: _tabs,
            tabs: const [Tab(text: 'Otobüs QR / NFC'), Tab(text: 'Bisiklet Modu')],
          ),
        ),
        body: TabBarView(controller: _tabs, children: [_transit(), _bike()]),
      );
    }

    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.78,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(children: [
          const SizedBox(height: 8),
          TabBar(
            controller: _tabs,
            tabs: const [Tab(text: 'Otobüs QR / NFC'), Tab(text: 'Bisiklet Modu')],
          ),
          Expanded(child: TabBarView(controller: _tabs, children: [_transit(), _bike()])),
        ]),
      ),
    );
  }

  Widget _transit() {
    final store = Hub.store;
    final sensors = Hub.sensors;
    return ListenableBuilder(
      listenable: sensors,
      builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Toplu taşıma doğrula (+3 puan)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        const Text('Aynı durak QR/NFC: 45 dk içinde yalnız 1 kez.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(12)),
          child: const Text('Kamera ile QR tarama bu sürümde YOK (kamera/QR paketi yerelde bulunmadı). QR içeriğini aşağıya elle yazabilirsin.',
              style: TextStyle(fontSize: 12)),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _code,
              decoration: const InputDecoration(
                labelText: 'Manuel kod (YESILADIM://TRANSIT/... veya durak kodu)',
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
        ]),
        if (_msg != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_msg!, style: TextStyle(fontWeight: FontWeight.w800, color: _msgOk ? AppColors.emeraldGreen : AppColors.fireRed)),
          ),
        const SizedBox(height: 12),
        if (!sensors.nfcAvailable)
          const Text('Bu cihazda NFC donanımı yok.', style: TextStyle(color: AppColors.fireRed, fontSize: 12))
        else if (!sensors.nfcEnabled)
          const Text('NFC kapalı: Android ayarlarından aç.', style: TextStyle(color: AppColors.fireRed, fontSize: 12))
        else
          ElevatedButton.icon(
            icon: const Icon(Icons.nfc),
            label: Text(sensors.nfcListening ? 'NFC dinleniyor… (etiketi yaklaştır)' : 'NFC okumayı başlat'),
            onPressed: () async {
              final ok = await sensors.startNfc();
              if (!ok) _show('NFC başlatılamadı.', false);
            },
          ),
        if (sensors.lastEventNote != null) Text('NFC: ${sensors.lastEventNote}', style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 12),
        const Text('Hızlı test (DEMO — gerçek okuma değil)', style: TextStyle(fontWeight: FontWeight.w800)),
        Wrap(spacing: 8, children: [
          for (final s in store.stops)
            ActionChip(
              label: Text('[DEMO] ${s.code}'),
              onPressed: () {
                final r = store.scanTransit(s.code, source: 'DEMO');
                _show(r.message, r.ok);
              },
            ),
        ]),
        if (_msg != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_msg!, style: TextStyle(fontWeight: FontWeight.w800, color: _msgOk ? AppColors.emeraldGreen : AppColors.fireRed)),
          ),
      ]),
    );
  }

  Widget _bike() {
    return ListenableBuilder(
      listenable: Listenable.merge([Hub.store, Hub.sensors]),
      builder: (context, _) {
        final s = Hub.store;
        final b = s.bike;
        final sensors = Hub.sensors;
        final gpsReady = sensors.started['gps'] == true;
        return ListView(padding: const EdgeInsets.all(16), children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _stat('HIZ (GPS)', '${(b?.currentKmh ?? 0).toStringAsFixed(1)} km/sa'),
            _stat('MESAFE', '${(b?.distanceKm ?? 0).toStringAsFixed(3)} km'),
            _stat('GEÇERLİ FİX', '${b?.validFixes ?? 0}'),
          ]),
          const SizedBox(height: 12),
          if (!gpsReady)
            const Text('GPS kullanılamıyor (izin verilmemiş, konum kapalı veya donanım yok). Sürüş ölçülemez; puan/ceza yazılmaz.',
                style: TextStyle(color: AppColors.fireRed, fontSize: 12)),
          if (b != null && b.jumps + b.lowAccuracy > 0)
            Text('Atlanan GPS örneği: ${b.jumps} sıçrama, ${b.lowAccuracy} düşük doğruluk', style: const TextStyle(fontSize: 11)),
          const Text('Puan yalnız sürüş bitince yazılır (1 km = 1 puan, tam km).', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(height: 12),
          if (b == null)
            ElevatedButton(
              onPressed: gpsReady ? () => s.startBike() : null,
              child: const Text('Bisiklet modunu başlat'),
            )
          else ...[
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => b.paused ? s.resumeBike() : s.pauseBike(),
                  child: Text(b.paused ? 'Devam et' : 'Durdur'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    final r = s.finishBike();
                    _show(r.message, r.ok);
                  },
                  child: const Text('Bitir ve değerlendir'),
                ),
              ),
            ]),
          ],
          if (_msg != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_msg!, style: TextStyle(fontWeight: FontWeight.w800, color: _msgOk ? AppColors.emeraldGreen : AppColors.fireRed)),
            ),
        ]);
      },
    );
  }

  Widget _stat(String l, String v) => Column(children: [
        Text(l, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
        Text(v, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
      ]);
}
