import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/name_masker.dart';
import '../../models/app_user.dart';
import '../../models/clan.dart';
import '../../models/league_tier.dart';
import '../../services/app_store.dart';
import '../../widgets/clan_league_badge.dart';
import '../../widgets/individual_league_badge.dart';
import '../../services/auto_motion_engine.dart';
import '../../services/hub.dart';
import '../clan/clan_detail_screen.dart';

class HomeScreen extends StatelessWidget {
  final VoidCallback? onOpenLeaderboardClan;
  final VoidCallback? onOpenLeaderboardIndividual;
  final VoidCallback? onOpenLeaderboardShame;

  const HomeScreen({
    super.key,
    this.onOpenLeaderboardClan,
    this.onOpenLeaderboardIndividual,
    this.onOpenLeaderboardShame,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Hub.store, Hub.sensors]),
      builder: (context, _) {
        final store = Hub.store;
        final user = store.me;
        if (user == null) return const SizedBox.shrink();
        final clan = store.myClan;
        final indTier = LeagueTier.fromPoints(user.weeklyPoints, category: LeagueCategory.individual);
        final clanTier = LeagueTier.fromPoints(clan?.weeklyPoints ?? 0, category: LeagueCategory.clan);
        final steps = user.todaySteps;
        final remaining = 1000 - (steps % 1000);
        final clanRank = clan == null ? 0 : store.rankedClans().indexWhere((c) => c.id == clan.id) + 1;
        final userRank = store.rankedUsers().indexWhere((u) => u.id == user.id) + 1;
        final trees = (user.preventedCo2Kg / AppStore.demoTreeCo2Kg).floor();

        return Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.start,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 160),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Daha yeşil bir gelecek için adım at!',
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1E1B4B))),
                            const SizedBox(height: 4),
                            Text('${user.username} • ${user.clanName.isEmpty ? 'Klansız' : user.clanName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _badge('🔥 ${user.streakDays} Gün', Colors.orange.shade50, Colors.orange.shade800),
                          _badge('🪙 ${user.goldCoins} Altın', Colors.amber.shade50, Colors.amber.shade900),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _championBanner(store),
                  const SizedBox(height: 16),
                  _stepsCard(steps, remaining),
                  const SizedBox(height: 12),
                  // Otomatik Hareket Durum Kartı (Aşama D)
                  _autoMotionCard(store),
                  const SizedBox(height: 12),
                  // Birleşik Lig + Sıra Kartları (Klan ve Birey tek kartlarda)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 450;
                      if (isNarrow) {
                        return Column(
                          children: [
                            _unifiedClanCard(context, clan, clanTier, clanRank, onOpenLeaderboardClan),
                            const SizedBox(height: 10),
                            _unifiedIndividualCard(user, indTier, userRank, onOpenLeaderboardIndividual),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: _unifiedClanCard(context, clan, clanTier, clanRank, onOpenLeaderboardClan)),
                          const SizedBox(width: 12),
                          Expanded(child: _unifiedIndividualCard(user, indTier, userRank, onOpenLeaderboardIndividual)),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  // Maskeli Ana Sayfa Utanç Tablosu Özeti + Tam Tabloya Geçiş
                  _shameSummaryCard(store, onOpenLeaderboardShame),
                  const SizedBox(height: 12),
                  _co2Card(user.preventedCo2Kg, trees),
                  const SizedBox(height: 8),
                  Text(
                    Hub.supabase.isAvailable
                        ? '🌱 Canlı Supabase bulut senkronizasyonu aktif • Otomatik veri eşitleme devrede'
                        : '🌱 Çevrimdışı mod: Adım ve aktiviteleriniz yerelde güvenle saklanır',
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _autoMotionCard(AppStore store) {
    final auto = store.autoMotion;
    final isCycling = auto.isAutoSessionActive;
    final isPotential = auto.mode == AutoMotionMode.potentialBike;

    if (!isCycling && !isPotential && auto.mode != AutoMotionMode.walking) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            const Icon(Icons.sensors, size: 16, color: AppColors.primaryPurple),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Hareket Modu: ${auto.statusExplanation}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted),
              ),
            ),
          ],
        ),
      );
    }

    if (isCycling) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFEDE9FE), Color(0xFFDCFCE7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primaryPurple, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(color: AppColors.primaryPurple, shape: BoxShape.circle),
                  child: const Icon(Icons.directions_bike, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '🚴 Otomatik Bisiklet Sürüşü Algılandı',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppColors.textDark),
                      ),
                      Text(
                        auto.statusExplanation,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF047857)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _miniMetric('Mesafe', '${(auto.tripDistanceM / 1000).toStringAsFixed(2)} km'),
                _miniMetric('Hız', '${auto.currentSpeedKmh.toStringAsFixed(1)} km/sa'),
                _miniMetric('Maks Hız', '${auto.maxSpeedKmh.toStringAsFixed(1)} km/sa'),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.emeraldGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Bitir & Kaydet', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                    onPressed: () => auto.finishAutoTrip(),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.fireRed,
                    side: const BorderSide(color: AppColors.fireRed),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => auto.cancelAutoTrip(),
                  child: const Text('İptal', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isPotential ? const Color(0xFFFEF3C7) : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isPotential ? const Color(0xFFF59E0B) : const Color(0xFF86EFAC)),
      ),
      child: Row(
        children: [
          Icon(
            isPotential ? Icons.hourglass_top : Icons.directions_walk,
            size: 18,
            color: isPotential ? const Color(0xFFD97706) : const Color(0xFF16A34A),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              auto.statusExplanation,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isPotential ? const Color(0xFFB45309) : const Color(0xFF15803D),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniMetric(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppColors.textDark)),
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
      ],
    );
  }

  Widget _championBanner(AppStore store) {
    final hasReal = store.championUser != '—' && store.championClan != '—' && store.championUser.isNotEmpty;
    final userChamp = hasReal ? store.championUser : 'Zeynep Kaya';
    final clanChamp = hasReal ? store.championClan : 'KTÜ Kanuni';
    final demoTag = hasReal ? '' : ' [DEMO]';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFFEF3C7), Color(0xFFD1FAE5)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        '👑 Geçen Haftanın Şampiyonları$demoTag: $userChamp & $clanChamp',
        style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF065F46)),
      ),
    );
  }

  Widget _stepsCard(int steps, int remaining) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: _card(24),
        child: Column(children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.emeraldGreen.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: const Icon(Icons.directions_walk, color: AppColors.emeraldGreen, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: Text('$steps adım',
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: AppColors.textDark)),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: (steps % 1000) / 1000.0,
              minHeight: 10,
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor: const AlwaysStoppedAnimation(AppColors.emeraldGreen),
            ),
          ),
          const SizedBox(height: 10),
          Text('🎯 Sonraki +5 puana sadece $remaining adım kaldı!',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF047857))),
        ]),
      );

  Widget _unifiedClanCard(BuildContext context, Clan? clan, LeagueTier tier, int clanRank, VoidCallback? fallbackOnTap) {
    return InkWell(
      onTap: fallbackOnTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: _card(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Klanım & Sıram',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted),
                  ),
                ),
                const Icon(Icons.shield_outlined, size: 16, color: AppColors.primaryPurple),
              ],
            ),
            const SizedBox(height: 8),
            InkWell(
              key: const ValueKey('clan_detail_button'),
              onTap: () {
                if (clan != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ClanDetailScreen(clan: clan)),
                  );
                } else if (fallbackOnTap != null) {
                  fallbackOnTap();
                }
              },
              borderRadius: BorderRadius.circular(10),
              child: Row(
                children: [
                  ClanLeagueBadge(tier: tier, size: 34),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          clan != null ? clan.name : 'Klansız',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                        ),
                        Text(
                          clan != null
                              ? '${tier.clanName} • ${clan.memberCount} üye (Detay)'
                              : 'Klan sıralamasını gör',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10, color: AppColors.primaryPurple, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, size: 11, color: AppColors.textMuted),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      clanRank > 0 ? '#$clanRank. Sırada' : 'Sıralama dışı',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.primaryPurple),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${clan?.hybridScore.toStringAsFixed(0) ?? 0} H',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textDark),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _unifiedIndividualCard(AppUser user, LeagueTier tier, int userRank, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: _card(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Bireysel Ligim & Sıram',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted),
                  ),
                ),
                const Icon(Icons.person_outline, size: 16, color: AppColors.primaryPurple),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IndividualLeagueBadge(tier: tier, size: 34),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                      ),
                      Text(
                        tier.individualName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      userRank > 0 ? '#$userRank. Sırada' : '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.primaryPurple),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${user.weeklyPoints} P',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textDark),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shameSummaryCard(AppStore store, VoidCallback? onOpenShame) {
    final list = store.shameBoard();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: _card(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              const Text(
                '🚨 Utanç Tablosu Özeti',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF991B1B)),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                ),
                onPressed: onOpenShame,
                child: const Text('Tam Tabloyu Gör >', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Bu hafta kimse utanç tablosunda değil. 🎉',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            )
          else ...[
            for (var i = 0; i < list.take(3).length; i++) ...[
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFECACA), width: 1),
                ),
                child: Row(
                  children: [
                    Text('#${i + 1}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: AppColors.fireRed)),
                    const SizedBox(width: 6),
                    const CircleAvatar(radius: 12, backgroundColor: Color(0xFFFCA5A5), child: Text('🚕', style: TextStyle(fontSize: 10))),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            NameMasker.maskShameName(list[i].username),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                          ),
                          Text(
                            '${list[i].weeklyCarTaxiTrips} yolculuk',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      flex: 0,
                      child: Text(
                        '${list[i].weeklyWastedCo2Kg.toStringAsFixed(1)} kg',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: Color(0xFF991B1B)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _co2Card(double kg, int trees) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: _card(24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 280;
            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.eco, color: Color(0xFF059669), size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Önlenen CO₂ Salımı: ${kg.toStringAsFixed(1)} kg',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF065F46))),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text('🌲 ≈$trees Ağaç (demo eşdeğer)',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF166534))),
                ],
              );
            }
            return Row(children: [
              const Icon(Icons.eco, color: Color(0xFF059669), size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Önlenen CO₂ Salımı: ${kg.toStringAsFixed(1)} kg',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF065F46))),
              ),
              const SizedBox(width: 8),
              Text('🌲 ≈$trees Ağaç\n(demo eşdeğer)',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF166534))),
            ]);
          },
        ),
      );

  static BoxDecoration _card(double r) => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(r),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 14, offset: const Offset(0, 4))],
      );

  static Widget _badge(String t, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg)),
      );
}
