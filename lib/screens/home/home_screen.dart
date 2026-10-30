import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../models/league_tier.dart';
import '../../services/app_store.dart';
import '../../services/hub.dart';

class HomeScreen extends StatelessWidget {
  final VoidCallback? onOpenLeaderboardClan;
  final VoidCallback? onOpenLeaderboardIndividual;

  const HomeScreen({super.key, this.onOpenLeaderboardClan, this.onOpenLeaderboardIndividual});

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
                            Text('${user.username} • ${user.clanName}',
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
                  const _SensorStatusCard(),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 300;
                      if (isNarrow) {
                        return Column(
                          children: [
                            _leagueCard('Lig klan', clanTier.clanName, clanTier.symbol, clanTier.color),
                            const SizedBox(height: 8),
                            _leagueCard('Lig birey', indTier.individualName, indTier.symbol, indTier.color),
                            const SizedBox(height: 8),
                            _rankCard('Klan sırası', clanRank > 0 ? 'Bu hafta $clanRank.' : 'Sıralama dışı',
                                '${clan?.weeklyPoints ?? 0} P', Icons.shield_outlined, onOpenLeaderboardClan),
                            const SizedBox(height: 8),
                            _rankCard('Birey sırası', 'Bu hafta $userRank.', '${user.weeklyPoints} P',
                                Icons.person_outline, onOpenLeaderboardIndividual),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          Row(children: [
                            Expanded(child: _leagueCard('Lig klan', clanTier.clanName, clanTier.symbol, clanTier.color)),
                            const SizedBox(width: 12),
                            Expanded(child: _leagueCard('Lig birey', indTier.individualName, indTier.symbol, indTier.color)),
                          ]),
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(
                              child: _rankCard('Klan sırası', clanRank > 0 ? 'Bu hafta $clanRank.' : 'Sıralama dışı',
                                  '${clan?.weeklyPoints ?? 0} P', Icons.shield_outlined, onOpenLeaderboardClan),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _rankCard('Birey sırası', 'Bu hafta $userRank.', '${user.weeklyPoints} P',
                                  Icons.person_outline, onOpenLeaderboardIndividual),
                            ),
                          ]),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _co2Card(user.preventedCo2Kg, trees),
                  const SizedBox(height: 8),
                  const Text(
                    'Not: Klan/rakip puanları DEMO verisidir; yerel çevrimdışı sürüm, canlı sunucu yok.',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _championBanner(AppStore store) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFFEF3C7), Color(0xFFD1FAE5)]),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text('👑 Geçen Haftanın Şampiyonları: ${store.championUser} & ${store.championClan}',
            style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF065F46))),
      );

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

  static Widget _leagueCard(String title, String name, String symbol, Color color) => Container(
        padding: const EdgeInsets.all(14),
        decoration: _card(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          const SizedBox(height: 8),
          Row(children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
              child: Text(symbol, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            ),
          ]),
        ]),
      );

  static Widget _rankCard(String title, String rank, String sub, IconData icon, VoidCallback? onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: _card(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Flexible(child: Text(title, style: const TextStyle(fontSize: 11, color: AppColors.textMuted))),
              Icon(icon, size: 16, color: AppColors.primaryPurple),
            ]),
            const SizedBox(height: 6),
            Text(rank, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            Text(sub, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ]),
        ),
      );
}

/// Gerçek donanım yeteneği ve izin durumu (uydurma yok).
class _SensorStatusCard extends StatelessWidget {
  const _SensorStatusCard();

  String _perm(String? s) => switch (s) {
        'granted' => 'verildi',
        'permanentlyDenied' => 'kalıcı reddedildi',
        'denied' => 'verilmedi',
        _ => 'bilinmiyor',
      };

  @override
  Widget build(BuildContext context) {
    final s = Hub.sensors;
    final problems = <String>[];
    if (s.capsKnown) {
      if (!s.stepCounterAvailable) problems.add('Cihazda adım sayacı sensörü yok.');
      if (s.perms['activity'] != 'granted') problems.add('Fiziksel aktivite izni ${_perm(s.perms['activity'])}: adımlar sayılmaz.');
      if (!s.gpsAvailable) {
        problems.add('GPS yok.');
      } else if (!s.locationEnabled) {
        problems.add('Konum kapalı: bisiklet/hız ölçümü yapılamaz.');
      }
      if (s.perms['location'] != 'granted') problems.add('Konum izni ${_perm(s.perms['location'])}.');
      if (!s.nfcAvailable) problems.add('NFC donanımı yok.');
    }
    final permanent = s.perms.values.contains('permanentlyDenied');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: HomeScreen._card(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.sensorsRunning ? '📡 Sensörler açık (yalnız uygulama ön plandayken)' : '📡 Sensörler kapalı',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        const SizedBox(height: 4),
        if (!s.capsKnown)
          const Text('Donanım bilgisi alınamadı (Android köprüsü yok).',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        for (final p in problems) Text('• $p', style: const TextStyle(fontSize: 12, color: AppColors.fireRed)),
        if (permanent)
          const Text('Kalıcı ret: izinleri Android Ayarlar > Uygulamalar bölümünden açmalısın.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          OutlinedButton(
            onPressed: () async {
              await s.requestAll();
              await s.start();
            },
            child: const Text('İzinleri iste'),
          ),
        ]),
      ]),
    );
  }
}
