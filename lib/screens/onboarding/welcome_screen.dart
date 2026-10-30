import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_colors.dart';
import '../../services/hub.dart';

class WelcomeScreen extends StatefulWidget {
  final Future<String> Function() deviceIdProvider;
  const WelcomeScreen({super.key, required this.deviceIdProvider});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _name = TextEditingController();
  String? _clan;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final clan = _clan;
    if (_name.text.trim().isEmpty || clan == null) {
      setState(() => _error = 'İsmini yaz ve bir klan seç.');
      return;
    }
    setState(() => _busy = true);

    try {
      final p = await SharedPreferences.getInstance();
      final alreadyAsked = p.getBool('perm_asked_once') ?? false;
      if (!alreadyAsked) {
        // İlk açılışta izinleri bir kez iste (kabul zorunlu değil)
        await Hub.sensors.requestAll();
        await p.setBool('perm_asked_once', true);
      }
    } catch (_) {}

    final id = await widget.deviceIdProvider();
    final r = Hub.store.register(deviceId: id, name: _name.text, clanName: clan);
    if (!r.ok && mounted) {
      setState(() {
        _error = r.message;
        _busy = false;
      });
    } else if (r.ok) {
      await Hub.sensors.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final clans = Hub.store.clans.map((c) => c.name).toList();
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              const Icon(Icons.eco, color: AppColors.emeraldGreen, size: 48),
              const SizedBox(height: 16),
              const Text('Hoş Geldin!\nİsmin ne?',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: AppColors.textDark)),
              const SizedBox(height: 8),
              const Text(
                'Üyelik yok: bu cihazda yerel bir profil oluşturulur. Adım, konum ve bildirim izinleri ilk açılışta istenir (kabul zorunlu değildir).',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                maxLength: 24,
                decoration: InputDecoration(
                  labelText: 'Kullanıcı adı',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Klanını seç', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _clan,
                hint: const Text('Klan seç'),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
                items: [
                  for (final c in clans) DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _clan = v),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: const TextStyle(color: AppColors.fireRed, fontWeight: FontWeight.w700)),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  onPressed: _submit,
                  child: const Text('Klanıma Katıl ve Başla',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
