import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../models/app_user.dart';
import '../../models/clan.dart';
import '../../models/league_tier.dart';
import '../../services/app_store.dart';
import '../../services/hub.dart';
import '../../widgets/clan_league_badge.dart';

class ClanDetailScreen extends StatefulWidget {
  final Clan clan;

  const ClanDetailScreen({super.key, required this.clan});

  @override
  State<ClanDetailScreen> createState() => _ClanDetailScreenState();
}

class _ClanDetailScreenState extends State<ClanDetailScreen> {
  bool _isRefreshing = false;

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    try {
      await Hub.supabase.fetchServerLeaderboard(Hub.store);
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  List<AppUser> _getClanMembers(AppStore store) {
    final clanId = widget.clan.id;
    final members = store.serverUsers.where((u) => u.clanId == clanId).toList();
    // Sıralama: Haftalık puan DESC, tüm zamanlar DESC, isim ASC
    members.sort((a, b) {
      final c = b.weeklyPoints.compareTo(a.weeklyPoints);
      if (c != 0) return c;
      final aTime = b.allTimePoints.compareTo(a.allTimePoints);
      if (aTime != 0) return aTime;
      return a.username.compareTo(b.username);
    });

    return members;
  }

  String _getMemberRole(AppUser member) {
    final role = member.clanRole.trim().toLowerCase();
    if (role == 'leader' || role == 'lider') return 'Lider';
    if (role == 'elder' || role == 'kıdemli') return 'Kıdemli';
    return 'Üye';
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'Lider':
        return const Color(0xFFD97706); // Amber
      case 'Kıdemli':
        return AppColors.primaryPurple;
      default:
        return const Color(0xFF64748B); // Slate
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Hub.store,
      builder: (context, _) {
        final store = Hub.store;
        // Güncel klan nesnesini store'dan bul (yoksa parametredeki klanı kullan)
        final clan = store.serverClans.firstWhere(
          (c) => c.id == widget.clan.id,
          orElse: () => widget.clan,
        );

        final tier = LeagueTier.fromPoints(clan.weeklyPoints, category: LeagueCategory.clan);
        final members = _getClanMembers(store);
        final myId = store.me?.serverUserId ?? store.me?.id;

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            title: Text(
              clan.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            actions: [
              IconButton(
                icon: _isRefreshing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
                onPressed: _isRefreshing ? null : _refresh,
                tooltip: 'Puanları Yenile',
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Klan Bilgi Kartı
                _buildClanHeaderCard(clan, tier, members.length),
                const SizedBox(height: 16),

                // Klan İçi Hiyerarşi & Sıralama Başlığı
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Klan İçi Sıralama & Hiyerarşi',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                    Text(
                      '${members.length} Üye',
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (members.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Text(
                      'Bu klanda henüz kayıtlı üye bulunmuyor.',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  )
                else
                  for (int i = 0; i < members.length; i++) ...[
                    _buildMemberRow(
                      rank: i + 1,
                      member: members[i],
                      role: _getMemberRole(members[i]),
                      isMe: (members[i].serverUserId ?? members[i].id) == myId,
                    ),
                    const SizedBox(height: 8),
                  ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildClanHeaderCard(Clan clan, LeagueTier tier, int actualMemberCount) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              ClanLeagueBadge(tier: tier, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clan.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: tier.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${tier.clanName} Ligi',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: tier.color),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          actualMemberCount >= 5 ? '$actualMemberCount Üye' : '$actualMemberCount Üye (Min 5 gerekli)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: actualMemberCount >= 5 ? AppColors.textMuted : AppColors.fireRed,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statColumn('HAFTALIK', '${clan.weeklyPoints} P'),
              _statColumn('HİBRİT SKOR', '${clan.hybridScore.toStringAsFixed(0)} H'),
              _statColumn('TÜM ZAMANLAR', '${clan.allTimePoints} P'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statColumn(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.textDark)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _buildMemberRow({
    required int rank,
    required AppUser member,
    required String role,
    required bool isMe,
  }) {
    final roleColor = _getRoleColor(role);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFFF5F3FF) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMe ? AppColors.primaryPurple : const Color(0xFFE2E8F0),
          width: isMe ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '#$rank',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12,
                color: isMe ? AppColors.primaryPurple : AppColors.textDark,
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 16,
            backgroundColor: isMe ? AppColors.primaryPurple.withValues(alpha: 0.15) : const Color(0xFFE2E8F0),
            child: Text(
              member.username.trim().isEmpty ? '?' : member.username.trim().substring(0, 1).toUpperCase(),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: isMe ? AppColors.primaryPurple : AppColors.textDark,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '${member.username}${isMe ? ' (Sen)' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: isMe ? AppColors.primaryPurple : AppColors.textDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: roleColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        role,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: roleColor,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  '${member.todaySteps} adım • ${member.streakDays} gün seri',
                  style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${member.weeklyPoints} P',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppColors.textDark),
          ),
        ],
      ),
    );
  }
}
