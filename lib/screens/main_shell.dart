import 'dart:async';

import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../services/hub.dart';
import 'home/home_screen.dart';
import 'leaderboard/leaderboard_screen.dart';
import 'shop_profile/shop_profile_screen.dart';
import 'transit_bike/qr_nfc_bike_modal.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  // Varsayılan: Ana Menü (index 1)
  int _index = 1;
  String _lbCategory = 'individual';
  bool _lbShame = false;
  bool _lbHighlightSelf = false;
  int _lbNonce = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resume();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _resume() async {
    Hub.store.tick();
    await Hub.sensors.refresh();
    await Hub.sensors.start();
    unawaited(Hub.supabase.onAppResume(Hub.store));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resume();
    } else if (state == AppLifecycleState.paused) {
      Hub.sensors.stop();
    }
  }

  void _openLeaderboard(String cat, {bool highlightSelf = false}) {
    setState(() {
      _lbCategory = cat;
      _lbShame = false;
      _lbHighlightSelf = highlightSelf;
      _lbNonce++;
      _index = 2; // Sıralamalar sekmesi
    });
  }

  void _openLeaderboardShame() {
    setState(() {
      _lbCategory = 'individual';
      _lbShame = true;
      _lbHighlightSelf = false;
      _lbNonce++;
      _index = 2; // Sıralamalar sekmesi
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const QrNfcBikeModal(isTab: true),
      HomeScreen(
        onOpenLeaderboardClan: () => _openLeaderboard('clan', highlightSelf: true),
        onOpenLeaderboardIndividual: () => _openLeaderboard('individual', highlightSelf: true),
        onOpenLeaderboardShame: _openLeaderboardShame,
      ),
      LeaderboardScreen(
        key: ValueKey('lb$_lbNonce'),
        initialCategory: _lbCategory,
        initialShame: _lbShame,
        highlightSelf: _lbHighlightSelf,
      ),
      const ShopProfileScreen(),
    ];

    return PopScope(
      canPop: _index == 1,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          setState(() => _index = 1);
        }
      },
      child: Scaffold(
        body: IndexedStack(index: _index, children: pages),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _index,
          onTap: (i) {
            if (i == 2) {
              _lbHighlightSelf = false;
            }
            setState(() => _index = i);
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: AppColors.primaryPurple,
          unselectedItemColor: AppColors.textMuted,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.qr_code_scanner),
              label: 'QR / NFC',
              tooltip: 'QR / NFC',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.home_filled),
              label: 'Ana Menü',
              tooltip: 'Ana sayfa',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.leaderboard_rounded),
              label: 'Sıralamalar',
              tooltip: 'Sıralama',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_rounded),
              label: 'Profil',
              tooltip: 'Mağaza ve profil',
            ),
          ],
        ),
      ),
    );
  }
}
