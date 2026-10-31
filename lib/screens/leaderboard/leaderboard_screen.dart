import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/leaderboard_window.dart';
import '../../core/utils/name_masker.dart';
import '../../models/app_user.dart';
import '../../models/clan.dart';
import '../../models/league_tier.dart';
import '../../widgets/clan_league_badge.dart';
import '../../widgets/individual_league_badge.dart';
import '../../services/hub.dart';
import '../clan/clan_detail_screen.dart';

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
                    ? (_clanMode ? _clanShameList(store) : _shameList(store))
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
    VoidCallback? onTap,
  }) {
    final isSpecial = me || highlighted;
    Widget card = Container(
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

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: card,
      );
    }
    return card;
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

    final leagueBadge = ClanLeagueBadge(tier: tier, size: 22);

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
              'Bireysel Utanç Tablosu • Dokunarak 10 altın karşılığı dürtme mesajı gönderebilirsin (Günde 1 kez).',
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
      sub: '${u.weeklyCarTaxiTrips} araba/taksi yolculuğu • Dokun: Dürt',
      trail: '${u.weeklyWastedCo2Kg.toStringAsFixed(1)} kg CO₂',
      onTap: () => _openShamePokeDialog(context, u, store),
    );
  }

  /// Klan Utanç Tablosu: En çok israf yapan klanlar listelenir.
  Widget _clanShameList(store) {
    final worst = store.worstClans();
    final myClanId = store.me?.clanId;
    final windowItems = LeaderboardWindow.build<Clan>(
      items: worst,
      isSelf: (c) => myClanId != null && c.id == myClanId,
    );

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Klan Utanç Tablosu • En çok CO₂ israfı yapan klanlar listelenir. Dokunarak üyeyi dürtebilirsin.',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ),
        ),
        if (windowItems.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('Bu hafta hiçbir klan utanç tablosunda değil. 🎉')),
          )
        else
          for (final item in windowItems)
            if (item is LeaderboardEllipsisRow<Clan>)
              _ellipsisRow()
            else if (item is LeaderboardDataRow<Clan>) ...[
              _buildClanShameRow(item, store),
            ],
      ],
    );
  }

  Widget _buildClanShameRow(LeaderboardDataRow<Clan> item, store) {
    final c = item.data;
    final isMyClan = item.isSelf;
    final tier = LeagueTier.fromPoints(c.weeklyPoints, category: LeagueCategory.clan);

    return _row(
      rank: item.rank,
      bg: const Color(0xFFFEF2F2),
      me: isMyClan,
      lead: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFFCA5A5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text('🚕', style: TextStyle(fontSize: 14)),
      ),
      title: '${c.name}${isMyClan ? ' (Klanın)' : ''}',
      sub: '${c.memberCount} üye ${c.memberCount < 5 ? '(Yetersiz üye)' : ''} • Dokun: Dürt / Detay',
      badge: ClanLeagueBadge(tier: tier, size: 20),
      trail: '${c.weeklyWastedCo2Kg.toStringAsFixed(1)} kg CO₂',
      onTap: () => _openClanShamePokeDialog(context, c, store),
    );
  }

  void _openShamePokeDialog(BuildContext context, AppUser target, store) {
    final myUid = store.me?.serverUserId ?? store.me?.id;
    final targetUid = target.serverUserId ?? target.id;

    if (myUid == targetUid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kendine utanç mesajı gönderemezsin!')),
      );
      return;
    }

    if (target.isDemo) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Simülasyon Profili'),
          content: Text(
            '${target.username} bir simülasyon/demo kullanıcısıdır. Canlı utanç mesajları yalnızca gerçek sunucu kullanıcılarına iletilebilir ve altın harcanmaz.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tamam'),
            ),
          ],
        ),
      );
      return;
    }

    if (store.hasSentShameMessageToday) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Günlük Kota Doldu'),
          content: const Text(
            'Bugünlük utanç mesajı hakkınızı kullandınız (Europe/Istanbul gününde toplam en fazla 1 gönderim).',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tamam'),
            ),
          ],
        ),
      );
      return;
    }

    if ((store.me?.goldCoins ?? 0) < 10) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Yetersiz Altın'),
          content: Text(
            'Utanç mesajı göndermek için 10 altın gerekir. Mevcut bakiyeniz: ${store.me?.goldCoins ?? 0} altın.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tamam'),
            ),
          ],
        ),
      );
      return;
    }

    final msgCtrl = TextEditingController();
    bool isSending = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Text('🎯 Utanç Dürtmesi', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hedef: ${target.username} • Bedel: 10 Altın',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: msgCtrl,
                maxLength: 50,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Dalga geçen mesajını yaz (Maks 50 karakter)...',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSending ? null : () => Navigator.pop(dialogCtx),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryPurple),
              onPressed: isSending
                  ? null
                  : () async {
                      final text = msgCtrl.text.trim();
                      if (text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Mesaj metni boş olamaz.')),
                        );
                        return;
                      }
                      if (text.characters.length > 50) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Mesaj en fazla 50 karakter olabilir.')),
                        );
                        return;
                      }

                      setDialogState(() => isSending = true);

                      try {
                        final res = await Hub.supabase.sendShameMessage(
                          targetUserId: targetUid,
                          message: text,
                        );

                        if (res['ok'] == true) {
                          // Yalnızca sunucu onayladığında 10 altın düşülür ve günlük kota kaydedilir
                          store.me = store.me!.copyWith(goldCoins: store.me!.goldCoins - 10);
                          store.markShameMessageSent();
                        }

                        if (mounted) {
                          Navigator.pop(dialogCtx);
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: Text(res['message'] as String? ?? (res['ok'] == true ? 'Utanç mesajı başarıyla iletildi! (-10 Altın)' : 'Mesaj iletilemedi.')),
                              backgroundColor: res['ok'] == true ? AppColors.emeraldGreen : AppColors.fireRed,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          setDialogState(() => isSending = false);
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: Text('Bağlantı hatası: $e. Altın bakiyeniz korundu.'),
                              backgroundColor: AppColors.fireRed,
                            ),
                          );
                        }
                      }
                    },
              child: isSending
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Gönder (10 🪙)', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _openClanShamePokeDialog(BuildContext context, Clan clan, store) {
    final clanId = clan.id;
    final realMembers = store.serverUsers
        .where((u) => u.clanId == clanId && !u.isDemo && (u.serverUserId ?? u.id) != (store.me?.serverUserId ?? store.me?.id))
        .toList();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${clan.name} (Utanç Sırası)',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                'Toplam ${clan.weeklyWastedCo2Kg.toStringAsFixed(1)} kg CO₂ israfı • ${clan.memberCount} üye',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: AppColors.fireRed.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.send_rounded, color: AppColors.fireRed),
                ),
                title: const Text('Klan Üyesine Utanç Mesajı Gönder (10 🪙)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                subtitle: Text(realMembers.isEmpty
                    ? 'Bu klanda henüz çevrimiçi canlı üye yok.'
                    : 'Klandaki üyeye dalga geçen mesaj gönderir.'),
                enabled: realMembers.isNotEmpty,
                onTap: realMembers.isEmpty
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        if (realMembers.length == 1) {
                          _openShamePokeDialog(context, realMembers.first, store);
                        } else {
                          _chooseClanMemberToPoke(context, clan, realMembers, store);
                        }
                      },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: AppColors.primaryPurple.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.shield_outlined, color: AppColors.primaryPurple),
                ),
                title: const Text('Klan Detayları ve Hiyerarşi', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                subtitle: const Text('Üye listesi, sıralama ve klan lig durumunu incele.', style: TextStyle(fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ClanDetailScreen(clan: clan)));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _chooseClanMemberToPoke(BuildContext context, Clan clan, List<AppUser> realMembers, store) {
    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: Text('${clan.name} — Hedef Üye Seç'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: realMembers.length,
            itemBuilder: (context, i) {
              final m = realMembers[i];
              return ListTile(
                title: Text(m.username, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${m.weeklyPoints} P • ${m.todaySteps} adım'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 12),
                onTap: () {
                  Navigator.pop(dlgCtx);
                  _openShamePokeDialog(context, m, store);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('İptal')),
        ],
      ),
    );
  }
}
