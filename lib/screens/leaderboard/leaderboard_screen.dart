import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/leaderboard_window.dart';
import '../../core/utils/name_masker.dart';
import '../../models/app_user.dart';
import '../../models/clan.dart';
import '../../models/league_tier.dart';
import '../../widgets/individual_league_badge.dart';
import '../../services/hub.dart';

class LeaderboardScreen extends StatefulWidget {
  final String initialCategory; // 'individual' | 'clan'
  final bool initialShame;
  final bool highlightSelf;

  const LeaderboardScreen({
    super.key,
    this.initialCategory = 'individual',
    this.initialShame = false,
    this.highlightSelf = false,
  });

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  late bool _clanMode = widget.initialCategory == 'clan';
  late bool _shame = widget.initialShame;
  bool _allTime = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Hub.store,
      builder: (context, _) {
        final store = Hub.store;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.white,
            title: Text(
              _shame ? '🚨 Utanç Tablosu' : '🏆 Gurur Tablosu',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: _shame ? AppColors.fireRed : AppColors.textDark,
                fontSize: 18,
              ),
            ),
          ),
          body: Column(
            children: [
              // Sabit üst kontrol şeridi: Gurur/Utanç solda sabit, Haftalık/Tüm Zamanlar sağda sabit
              Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 360;
                    final shameBtn = SegmentedButton<bool>(
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('🏆 Gurur', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text('🚨 Utanç', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                      ],
                      selected: {_shame},
                      onSelectionChanged: (s) => setState(() => _shame = s.first),
                    );

                    final timeBtn = _shame
                        ? const SizedBox.shrink()
                        : SegmentedButton<bool>(
                            showSelectedIcon: false,
                            style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
                            segments: const [
                              ButtonSegment(
                                value: false,
                                label: Text('Haftalık', style: TextStyle(fontSize: 10)),
                              ),
                              ButtonSegment(
                                value: true,
                                label: Text('Tüm Zaman', style: TextStyle(fontSize: 10)),
                              ),
                            ],
                            selected: {_allTime},
                            onSelectionChanged: (s) => setState(() => _allTime = s.first),
                          );

                    if (isNarrow) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(child: shameBtn),
                          const SizedBox(width: 4),
                          Flexible(child: timeBtn),
                        ],
                      );
                    }
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        shameBtn,
                        SizedBox(width: 150, child: timeBtn),
                      ],
                    );
                  },
                ),
              ),
              const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
              Expanded(
                child: _shame
                    ? _shameList(store)
                    : (_clanMode ? _clanList(store) : _userList(store)),
              ),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('Bireysel', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text('Klan', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ],
                      selected: {_clanMode},
                      onSelectionChanged: (s) => setState(() => _clanMode = s.first),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _ellipsisRow() => Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(vertical: 6),
        alignment: Alignment.center,
        child: const Text('…', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.textMuted)),
      );

  Widget _row({
    required int rank,
    required Widget lead,
    required String title,
    required String sub,
    Widget? badge,
    required String trail,
    bool me = false,
    bool highlighted = false,
    Color? bg,
  }) {
    final isSpecial = me || highlighted;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: bg ?? (isSpecial ? const Color(0xFFF5F3FF) : Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: isSpecial
            ? Border.all(color: AppColors.primaryPurple, width: 2)
            : Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // #SIRA
          SizedBox(
            width: 22,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '#$rank',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  color: isSpecial ? AppColors.primaryPurple : AppColors.textDark,
                ),
              ),
            ),
          ),
          const SizedBox(width: 3),
          // PROFİL FOTOĞRAFI / AVATAR
          lead,
          const SizedBox(width: 5),
          // İSİM / NICK (altında klan)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: isSpecial ? AppColors.primaryPurple : AppColors.textDark,
                  ),
                ),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          // LİG LOGOSU
          if (badge != null) ...[
            const SizedBox(width: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: badge,
            ),
          ],
          const SizedBox(width: 4),
          // PUAN
          Flexible(
            flex: 0,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                trail,
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _userList(store) {
    final users = store.rankedUsers(allTime: _allTime);
    final myId = store.me?.id;
    final windowItems = LeaderboardWindow.build<AppUser>(
      items: users,
      isSelf: (u) => myId != null && u.id == myId,
    );

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Rakip/klan satırları DEMO verisidir; yalnızca "Sen" gerçek yerel veridir.',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ),
        ),
        if (windowItems.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('Henüz kayıt yok.')),
          )
        else
          for (final item in windowItems)
            if (item is LeaderboardEllipsisRow<AppUser>)
              _ellipsisRow()
            else if (item is LeaderboardDataRow<AppUser>) ...[
              _buildUserRow(item, store),
            ],
      ],
    );
  }

  Widget _buildUserRow(LeaderboardDataRow<AppUser> item, store) {
    final u = item.data;
    final isMe = item.isSelf;
    final tier = LeagueTier.fromPoints(u.weeklyPoints, category: LeagueCategory.individual);
    final pts = _allTime ? u.allTimePoints : u.weeklyPoints;

    Widget avatar;
    if (isMe && u.photoPath != null && u.photoPath!.isNotEmpty && File(u.photoPath!).existsSync()) {
      avatar = CircleAvatar(
        radius: 16,
        backgroundImage: FileImage(File(u.photoPath!)),
      );
    } else {
      final initial = u.username.trim().isEmpty ? '?' : u.username.trim().substring(0, 1).toUpperCase();
      avatar = CircleAvatar(
        radius: 16,
        backgroundColor: isMe ? AppColors.primaryPurple.withValues(alpha: 0.15) : const Color(0xFFE2E8F0),
        child: Text(
          initial,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12,
            color: isMe ? AppColors.primaryPurple : AppColors.textDark,
          ),
        ),
      );
    }

    final leagueBadge = IndividualLeagueBadge(
      tier: tier,
      size: 20,
    );

    return _row(
      rank: item.rank,
      me: isMe,
      highlighted: isMe && widget.highlightSelf,
      lead: avatar,
      title: '${u.username}${u.isDemo ? ' (demo)' : ' (Sen)'}',
      sub: u.clanName,
      badge: leagueBadge,
      trail: '$pts P',
    );
  }

  Widget _clanList(store) {
    final eligible = store.rankedClans(hybrid: true, allTime: _allTime);
    final myClanId = store.me?.clanId;
    final windowItems = LeaderboardWindow.build<Clan>(
      items: eligible,
      isSelf: (c) => myClanId != null && c.id == myClanId,
    );
    final out = store.clans.where((c) => !c.isEligibleForRanking).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Tüm klan sıralaması hibrit normalize: 0.6×toplam + 0.4×50×üye ortalaması.',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ),
        ),
        if (windowItems.isEmpty && out.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('Klan yok.')),
          )
        else ...[
          for (final item in windowItems)
            if (item is LeaderboardEllipsisRow<Clan>)
              _ellipsisRow()
            else if (item is LeaderboardDataRow<Clan>) ...[
              _buildClanRow(item, store),
            ],
          if (out.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Yetersiz üye (5\'ten az): sıralamaya alınmadı',
                style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textMuted, fontSize: 12),
              ),
            ),
            for (final c in out)
              Text('• ${c.name} (${c.memberCount} üye)', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
        ],
      ],
    );
  }

  Widget _buildClanRow(LeaderboardDataRow<Clan> item, store) {
    final c = item.data;
    final isMyClan = item.isSelf;
    final tier = LeagueTier.fromPoints(
      _allTime ? c.allTimePoints : c.weeklyPoints,
      category: LeagueCategory.clan,
    );
    final score = c.hybridScoreFor(allTime: _allTime).toStringAsFixed(0);

    final avatar = Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tier.color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.shield, color: Colors.white, size: 16),
    );

    final leagueBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: tier.color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        tier.symbol,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10),
      ),
    );

    return _row(
      rank: item.rank,
      me: isMyClan,
      highlighted: isMyClan && widget.highlightSelf,
      lead: avatar,
      title: '${c.name}${isMyClan ? ' (Klanın)' : ''}',
      sub: '${c.memberCount} üye',
      badge: leagueBadge,
      trail: '$score H',
    );
  }

  Widget _shameList(store) {
    final list = store.shameBoard();
    final myId = store.me?.id;
    final windowItems = LeaderboardWindow.build<AppUser>(
      items: list,
      isSelf: (u) => myId != null && u.id == myId,
    );

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Rakip satırları DEMO verisidir; yalnızca "Sen" gerçek yerel veridir.',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ),
        ),
        if (windowItems.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('Bu hafta kimse utanç tablosunda değil. 🎉')),
          )
        else
          for (final item in windowItems)
            if (item is LeaderboardEllipsisRow<AppUser>)
              _ellipsisRow()
            else if (item is LeaderboardDataRow<AppUser>) ...[
              _buildShameRow(item, store),
            ],
      ],
    );
  }

  Widget _buildShameRow(LeaderboardDataRow<AppUser> item, store) {
    final u = item.data;
    final isMe = item.isSelf;

    return _row(
      rank: item.rank,
      bg: const Color(0xFFFEF2F2),
      me: isMe,
      lead: const CircleAvatar(
        radius: 16,
        backgroundColor: Color(0xFFFCA5A5),
        child: Text('🚕', style: TextStyle(fontSize: 12)),
      ),
      title: '${NameMasker.maskShameName(u.username)}${isMe ? ' (Sen)' : ''}',
      sub: '${u.weeklyCarTaxiTrips} araba/taksi yolculuğu',
      trail: '${u.weeklyWastedCo2Kg.toStringAsFixed(1)} kg CO₂',
    );
  }
}
