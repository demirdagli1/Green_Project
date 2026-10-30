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
  int _index = 0;
  String _lbCategory = 'individual';
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
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resume();
    } else if (state == AppLifecycleState.paused) {
      Hub.sensors.stop();
    }
  }

  void _openSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const QrNfcBikeModal(),
    );
  }

  void _openLeaderboard(String cat) => setState(() {
        _lbCategory = cat;
        _lbNonce++;
        _index = 1;
      });

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomeScreen(
        onOpenLeaderboardClan: () => _openLeaderboard('clan'),
        onOpenLeaderboardIndividual: () => _openLeaderboard('individual'),
      ),
      LeaderboardScreen(key: ValueKey('lb$_lbNonce'), initialCategory: _lbCategory),
      const ShopProfileScreen(),
    ];
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _index = 0);
      },
      child: Scaffold(
        body: IndexedStack(index: _index, children: pages),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: AppColors.primaryPurple,
          onPressed: _openSheet,
          icon: const Icon(Icons.directions_bus, color: Colors.white),
          label: const Text('QR / NFC', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        ),
        bottomNavigationBar: BottomAppBar(
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                tooltip: 'Ana sayfa',
                icon: Icon(Icons.home_filled, color: _index == 0 ? AppColors.primaryPurple : AppColors.textMuted),
                onPressed: () => setState(() => _index = 0),
              ),
              const SizedBox(width: 96),
              IconButton(
                tooltip: 'Sıralama',
                icon: Icon(Icons.leaderboard_rounded, color: _index == 1 ? AppColors.primaryPurple : AppColors.textMuted),
                onPressed: () => _openLeaderboard('individual'),
              ),
              IconButton(
                tooltip: 'Mağaza ve profil',
                icon: Icon(Icons.storefront_rounded, color: _index == 2 ? AppColors.primaryPurple : AppColors.textMuted),
                onPressed: () => setState(() => _index = 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
