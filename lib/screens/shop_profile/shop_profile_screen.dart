import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../models/shop_item.dart';
import '../../services/hub.dart';
import '../admin/admin_panel_screen.dart';

class ShopProfileScreen extends StatelessWidget {
  const ShopProfileScreen({super.key});

  static String _emoji(String c) => switch (c) {
        'leaf' => '🍃',
        'sun' => '☀️',
        'frame' => '💫',
        'crown' => '👑',
        'tree' => '🌲',
        'bug' => '🐝',
        'paw' => '🦊',
        _ => '✨',
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Hub.store,
      builder: (context, _) {
        final store = Hub.store;
        final u = store.me;
        if (u == null) return const SizedBox.shrink();
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.white,
            title: const Text('Profil ve Mağaza', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            actions: [
              TextButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPanelScreen())),
                icon: const Icon(Icons.admin_panel_settings, size: 18),
                label: const Text('Jüri/Admin'),
              ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
              child: Column(children: [
                CircleAvatar(radius: 34, child: Text(u.username.trim().isEmpty ? '?' : u.username.trim().substring(0, 1), style: const TextStyle(fontSize: 26))),
                const SizedBox(height: 8),
                Text(u.username, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                Text('${u.clanName}', style: const TextStyle(color: AppColors.textMuted)),
                const SizedBox(height: 10),
                Text('🪙 ${u.goldCoins} Altın', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text('Avatar: ${u.equippedAvatar} • Çerçeve: ${u.equippedFrame} • Pet: ${u.equippedPet}',
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
              ]),
            ),
            const SizedBox(height: 16),
            const Text('🛍️ Kozmetik Mağazası', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            const Text('Altın, haftalık puanların haftayı kapatınca altına dönüşmesiyle kazanılır.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 10),
            for (final item in store.shopItems) _item(context, item),
            const SizedBox(height: 20),
            const SensorStatusCard(),
          ]),
        );
      },
    );
  }

  Widget _item(BuildContext context, ShopItem item) {
    final store = Hub.store;
    final u = store.me!;
    final has = store.owned.contains(item.id);
    final eq = u.equippedAvatar == item.id || u.equippedFrame == item.id || u.equippedPet == item.id;
    final canAfford = u.goldCoins >= item.price;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: eq ? Border.all(color: AppColors.emeraldGreen, width: 2) : null,
      ),
      child: Row(children: [
        Text(_emoji(item.iconCode), style: const TextStyle(fontSize: 26)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.title, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(item.description, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ]),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            visualDensity: VisualDensity.compact,
          ),
          onPressed: eq
              ? null
              : () {
                  final r = has ? store.equip(item.id) : store.buy(item.id);
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text(r.message)));
                },
          child: Text(
            eq ? 'Kuşanıldı' : (has ? 'Kuşan' : (canAfford ? '${item.price} 🪙' : '${item.price} (yetersiz)')),
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ]),
    );
  }
}

/// Gerçek donanım yeteneği ve izin durumu (Profil sekmesinde kullanıcı kontrolü).
class SensorStatusCard extends StatelessWidget {
  const SensorStatusCard({super.key});

  String _perm(String? s) => switch (s) {
        'granted' => 'verildi',
        'permanentlyDenied' => 'kalıcı reddedildi',
        'denied' => 'verilmedi',
        _ => 'bilinmiyor',
      };

  @override
  Widget build(BuildContext context) {
    final s = Hub.sensors;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final problems = <String>[];
        if (s.capsKnown) {
          if (!s.stepCounterAvailable) problems.add('Cihazda adım sayacı sensörü yok.');
          if (s.perms['activity'] != 'granted') {
            problems.add('Fiziksel aktivite izni ${_perm(s.perms['activity'])}: adımlar sayılmaz.');
          }
          if (!s.gpsAvailable) {
            problems.add('GPS yok.');
          } else if (!s.locationEnabled) {
            problems.add('Konum kapalı: bisiklet/hız ölçümü yapılamaz.');
          }
          if (s.perms['location'] != 'granted') problems.add('Konum izni ${_perm(s.perms['location'])}.');
          if (!s.nfcAvailable) problems.add('NFC donanımı yok.');
        }
        final allGranted = s.capsKnown &&
            s.perms['activity'] == 'granted' &&
            s.perms['location'] == 'granted' &&
            s.perms['notifications'] == 'granted';
        final permanent = s.perms.values.contains('permanentlyDenied');
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 14,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              s.sensorsRunning ? '📡 Sensörler açık (yalnız uygulama ön plandayken)' : '📡 Sensörler kapalı',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
            const SizedBox(height: 4),
            if (!s.capsKnown)
              Text('Donanım bilgisi alınamadı (${s.bridgeError ?? 'Android köprüsü yok'}).',
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted))
            else ...[
              Text(
                'Donanım: Adımsayar ${s.stepCounterAvailable ? 'var' : 'yok'} • '
                'GPS ${s.gpsAvailable ? (s.locationEnabled ? 'açık' : 'kapalı') : 'yok'} • '
                'NFC ${s.nfcAvailable ? (s.nfcEnabled ? 'açık' : 'kapalı') : 'yok'}'
                '${s.caps['sdk'] != null ? ' (API ${s.caps['sdk']})' : ''}',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              Text(
                'İzinler: Aktivite ${_perm(s.perms['activity'])} • '
                'Konum ${_perm(s.perms['location'])} • '
                'Bildirim ${_perm(s.perms['notifications'])}',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
            for (final p in problems) Text('• $p', style: const TextStyle(fontSize: 12, color: AppColors.fireRed)),
            if (permanent) ...[
              const SizedBox(height: 4),
              const Text('Kalıcı ret: İzinleri sistem ayarlarından açmalısın.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                icon: const Icon(Icons.settings, size: 16),
                label: const Text('Sistem Ayarlarını Aç', style: TextStyle(fontSize: 12)),
                onPressed: () => s.bridge.openAppSettings(),
              ),
            ],
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              OutlinedButton(
                onPressed: () async {
                  final wasAllGranted = s.perms['activity'] == 'granted' &&
                      s.perms['location'] == 'granted' &&
                      s.perms['notifications'] == 'granted';
                  await s.requestAll();
                  await s.start();
                  if (context.mounted && wasAllGranted) {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        const SnackBar(
                          content: Text('İzinler zaten verilmiş; donanım ve sensör durumu yenilendi.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                  }
                },
                child: Text(allGranted ? 'Durumu yenile (İzinler verildi)' : 'İzinleri iste'),
              ),
            ]),
          ]),
        );
      },
    );
  }
}
