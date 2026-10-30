import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../models/app_user.dart';
import '../../models/shop_item.dart';
import '../../services/app_store.dart';
import '../../services/hub.dart';
import '../admin/admin_panel_screen.dart';

class ShopProfileScreen extends StatelessWidget {
  const ShopProfileScreen({super.key});

  static String emojiFor(String c) => switch (c) {
        'leaf' => '🍃',
        'sun' => '☀️',
        'frame' => '💫',
        'crown' => '👑',
        'tree' => '🌲',
        'bug' => '🐝',
        'paw' => '🦊',
        _ => '✨',
      };

  static String readableEquipped(AppStore store, String id, ShopCategory cat) {
    if (id == 'none' || id.isEmpty) {
      return switch (cat) {
        ShopCategory.frame => 'Çerçeve Yok',
        ShopCategory.pet => 'Yoldaş Yok',
        ShopCategory.avatar => 'Avatar Yok',
      };
    }
    if (id == 'default_avatar') return 'Varsayılan Yaprak';
    final found = store.shopItems.where((i) => i.id == id).firstOrNull;
    return found?.title ?? id;
  }

  void _editBio(BuildContext context, AppStore store, String currentBio) {
    final controller = TextEditingController(text: currentBio);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Biyografiyi Düzenle', style: TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: controller,
          maxLength: 160,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Kendini ve yeşil hedeflerini anlat… (maks 160 karakter)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              store.updateBio(controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickPhoto(BuildContext context, AppStore store) async {
    try {
      final path = await Hub.sensors.pickProfileImage();
      if (path != null && path.isNotEmpty) {
        store.updateProfilePhoto(path);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fotoğraf seçilemedi: $e')),
        );
      }
    }
  }

  void _showPhotoOptions(BuildContext context, AppStore store, AppUser u) {
    final hasPhoto = u.photoPath != null && u.photoPath!.isNotEmpty && File(u.photoPath!).existsSync();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Fotoğraf Seç (Galeri / Dosyalar)'),
              subtitle: const Text('Android Photo Picker / Open Document'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(context, store);
              },
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.fireRed),
                title: const Text('Fotoğrafı Kaldır', style: TextStyle(color: AppColors.fireRed)),
                onTap: () {
                  store.updateProfilePhoto(null);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Hub.store,
      builder: (context, _) {
        final store = Hub.store;
        final u = store.me;
        if (u == null) return const SizedBox.shrink();

        final hasPhoto = u.photoPath != null && u.photoPath!.isNotEmpty && File(u.photoPath!).existsSync();

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
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        CircleAvatar(
                          radius: 38,
                          backgroundImage: (hasPhoto ? FileImage(File(u.photoPath!)) : null) as ImageProvider?,
                          child: !hasPhoto
                              ? Text(
                                  u.username.trim().isEmpty ? '?' : u.username.trim().substring(0, 1).toUpperCase(),
                                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                                )
                              : null,
                        ),
                        InkWell(
                          onTap: () => _showPhotoOptions(context, store, u),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: AppColors.primaryPurple,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(u.username, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    Text(u.clanName, style: const TextStyle(color: AppColors.textMuted)),
                    // Bio Düzenleme Alanı (Maks 160 Karakter, Türkçe/Emoji Güvenli)
                    InkWell(
                      onTap: () => _editBio(context, store, u.bio),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                u.bio.isNotEmpty ? u.bio : 'Biyografi eklemek için dokunun…',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontStyle: u.bio.isEmpty ? FontStyle.italic : FontStyle.normal,
                                  color: u.bio.isEmpty ? AppColors.textMuted : AppColors.textDark,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.edit, size: 14, color: AppColors.primaryPurple),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('🪙 ${u.goldCoins} Altın', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    // İnsan Okunur Kozmetik Fallback (Ham UUID veya text ID değil)
                    Text(
                      'Avatar: ${readableEquipped(store, u.equippedAvatar, ShopCategory.avatar)} • '
                      'Çerçeve: ${readableEquipped(store, u.equippedFrame, ShopCategory.frame)} • '
                      'Yoldaş: ${readableEquipped(store, u.equippedPet, ShopCategory.pet)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('🛍️ Kozmetik Mağazası', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              const Text(
                'Altın, haftalık puanların haftayı kapatınca altına dönüşmesiyle kazanılır.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 10),
              for (final item in store.shopItems) _item(context, item),
              const SizedBox(height: 20),
              const SensorStatusCard(),
            ],
          ),
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
      child: Row(
        children: [
          // Kozmetik asset slot (görsel henüz yoksa insan okunur emoji rozetiyle fallback)
          CosmeticAssetSlot(item: item),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(item.description, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
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
        ],
      ),
    );
  }
}

/// Kozmetik Asset Slotu: Kullanıcı görselleri verince doğrudan entegre edilebilir;
/// görsel henüz yoksa temiz ve insan okunur fallback ile görüntülenir.
class CosmeticAssetSlot extends StatelessWidget {
  final ShopItem item;
  final double size;

  const CosmeticAssetSlot({
    super.key,
    required this.item,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        ShopProfileScreen.emojiFor(item.iconCode),
        style: TextStyle(fontSize: size * 0.6),
      ),
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
