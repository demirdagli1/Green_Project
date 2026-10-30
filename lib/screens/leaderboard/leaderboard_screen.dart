import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/name_masker.dart';
import '../../models/league_tier.dart';
import '../../services/hub.dart';

class LeaderboardScreen extends StatefulWidget {
  final String initialCategory; // 'individual' | 'clan'
  const LeaderboardScreen({super.key, this.initialCategory = 'individual'});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  late bool _clanMode = widget.initialCategory == 'clan';
  bool _shame = false;
  bool _hybrid = false;
  bool _allTime = false;
  int _tier = 0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Hub.store,
      builder: (context, _) {
        final store = Hub.store;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.white,
            title: Text(_shame ? '🚨 Utanç Tablosu' : '🏆 Gurur Tablosu',
                style: TextStyle(fontWeight: FontWeight.w900, color: _shame ? AppColors.fireRed : AppColors.textDark, fontSize: 18)),
          ),
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: false, label: Text('🏆 Gurur', style: TextStyle(fontSize: 11))),
                      ButtonSegment(value: true, label: Text('🚨 Utanç', style: TextStyle(fontSize: 11))),
                    ],
                    selected: {_shame},
                    onSelectionChanged: (s) => setState(() => _shame = s.first),
                  ),
                  if (!_shame)
                    TextButton(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                      onPressed: () => setState(() => _allTime = !_allTime),
                      child: Text(_allTime ? 'Haftalık >' : 'Tüm Zamanlar >', style: const TextStyle(fontSize: 11)),
                    ),
                ],
              ),
            ),
            _tiers(),
            if (_clanMode && !_shame)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(alignment: WrapAlignment.end, spacing: 6, children: [
                  ChoiceChip(label: const Text('Toplam Puan', style: TextStyle(fontSize: 11)), selected: !_hybrid, onSelected: (_) => setState(() => _hybrid = false)),
                  ChoiceChip(label: const Text('Hibrit Normalize', style: TextStyle(fontSize: 11)), selected: _hybrid, onSelected: (_) => setState(() => _hybrid = true)),
                ]),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Rakip/klan satırları DEMO verisidir; yalnızca "Sen" gerçek yerel veridir.',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ),
            ),
            Expanded(child: _shame ? _shameList(store) : (_clanMode ? _clanList(store) : _userList(store))),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Bireysel')),
                      ButtonSegment(value: true, label: Text('Klan')),
                    ],
                    selected: {_clanMode},
                    onSelectionChanged: (s) => setState(() => _clanMode = s.first),
                  ),
                ),
              ),
            ),
          ]),
        );
      },
    );
  }

  Widget _tiers() => SizedBox(
        height: 64,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          children: [
            for (var i = 0; i < LeagueTier.allTiers.length; i++)
              GestureDetector(
                onTap: () => setState(() => _tier = i),
                child: Container(
                  margin: const EdgeInsets.all(6),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: LeagueTier.allTiers[i].color.withValues(alpha: _tier == i ? 0.25 : 0.08),
                    border: Border.all(color: _tier == i ? LeagueTier.allTiers[i].color : Colors.transparent, width: 2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(children: [
                    Text(LeagueTier.allTiers[i].symbol,
                        style: TextStyle(fontWeight: FontWeight.w900, color: LeagueTier.allTiers[i].color)),
                    const SizedBox(width: 6),
                    Text(_clanMode ? LeagueTier.allTiers[i].clanName : LeagueTier.allTiers[i].individualName,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
          ],
        ),
      );

  Widget _row({required int rank, required Widget lead, required String title, required String sub, required String trail, bool me = false, Color? bg}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg ?? (me ? const Color(0xFFF5F3FF) : Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: me ? Border.all(color: AppColors.primaryPurple) : null,
      ),
      child: Row(children: [
        SizedBox(width: 34, child: Text('#$rank', style: const TextStyle(fontWeight: FontWeight.w900))),
        lead,
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ]),
        ),
        const SizedBox(width: 8),
        Flexible(
          flex: 0,
          child: Text(trail, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
        ),
      ]),
    );
  }

  Widget _userList(store) {
    final users = store.rankedUsers(allTime: _allTime);
    if (users.isEmpty) return const Center(child: Text('Henüz kayıt yok.'));
    return ListView(padding: const EdgeInsets.all(16), children: [
      for (var i = 0; i < users.length; i++)
        _row(
          rank: i + 1,
          me: users[i].id == store.me?.id,
          lead: CircleAvatar(
            radius: 18,
            child: Text(users[i].username.trim().isEmpty ? '?' : users[i].username.trim().substring(0, 1)),
          ),
          title: '${users[i].username}${users[i].isDemo ? ' (demo)' : ' (Sen)'}',
          sub: '${users[i].clanName} • ${LeagueTier.fromPoints(users[i].weeklyPoints, category: LeagueCategory.individual).individualName}',
          trail: '🍃 ${_allTime ? users[i].allTimePoints : users[i].weeklyPoints} P',
        ),
    ]);
  }

  Widget _clanList(store) {
    final eligible = store.rankedClans(hybrid: _hybrid, allTime: _allTime);
    final out = store.clans.where((c) => !c.isEligibleForRanking).toList();
    if (eligible.isEmpty && out.isEmpty) return const Center(child: Text('Klan yok.'));
    return ListView(padding: const EdgeInsets.all(16), children: [
      for (var i = 0; i < eligible.length; i++)
        _row(
          rank: i + 1,
          me: eligible[i].id == store.me?.clanId,
          lead: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: LeagueTier.fromPoints(eligible[i].weeklyPoints, category: LeagueCategory.clan).color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.shield, color: Colors.white, size: 18),
          ),
          title: eligible[i].name,
          sub: '${eligible[i].memberCount} üye • ${LeagueTier.fromPoints(eligible[i].weeklyPoints, category: LeagueCategory.clan).clanName}',
          trail: _hybrid
              ? '${eligible[i].hybridScore.toStringAsFixed(0)} H'
              : '${_allTime ? eligible[i].allTimePoints : eligible[i].weeklyPoints} P',
        ),
      if (out.isNotEmpty) ...[
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Yetersiz üye (5\'ten az): sıralamaya alınmadı', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textMuted)),
        ),
        for (final c in out) Text('• ${c.name} (${c.memberCount} üye)', style: const TextStyle(color: AppColors.textMuted)),
      ],
    ]);
  }

  Widget _shameList(store) {
    final list = store.shameBoard();
    if (list.isEmpty) return const Center(child: Text('Bu hafta kimse utanç tablosunda değil. 🎉'));
    return ListView(padding: const EdgeInsets.all(16), children: [
      for (var i = 0; i < list.length; i++)
        _row(
          rank: i + 1,
          bg: const Color(0xFFFEF2F2),
          lead: const CircleAvatar(radius: 18, backgroundColor: Color(0xFFFCA5A5), child: Text('🚕')),
          title: NameMasker.maskShameName(list[i].username),
          sub: '${list[i].weeklyCarTaxiTrips} araba/taksi yolculuğu',
          trail: '${list[i].weeklyWastedCo2Kg.toStringAsFixed(1)} kg CO₂',
        ),
    ]);
  }
}
