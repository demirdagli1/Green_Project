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
                const SizedBox(height: 4),
                SelectableText('Cihaz ID: ${u.deviceId}', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                const Text('(yerel kimlik; güvenli sunucu kimliği değildir)', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
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
