import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/constants/app_colors.dart';
import 'screens/main_shell.dart';
import 'screens/onboarding/welcome_screen.dart';
import 'services/app_store.dart';
import 'services/command_dispatcher.dart';
import 'services/gm_server.dart';
import 'services/hardware_bridge.dart';
import 'services/hub.dart';
import 'services/sensor_controller.dart';
import 'services/storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bridge = AndroidHardwareBridge();
  final store = AppStore(
    backend: PrefsStore(),
    systemNotify: (t, b) => bridge.showNotification(t, b),
  );
  await store.load();
  AppStore.instance = store;
  final sensors = SensorController(bridge: bridge, store: store);
  Hub.sensors = sensors;
  final dispatcher = CommandDispatcher(store);
  Hub.dispatcher = dispatcher;
  final gmServer = GmServer(dispatcher: dispatcher, sensors: sensors);
  Hub.gmServer = gmServer;

  final token = await loadOrCreateGmToken();
  await gmServer.start(initialToken: token);

  runApp(const GreenProjectApp());
}

Future<String> loadOrCreateGmToken() async {
  try {
    final p = await SharedPreferences.getInstance();
    var t = p.getString('gm_token');
    if (t == null || t.isEmpty) {
      t = 'gm_${const Uuid().v4().replaceAll('-', '').substring(0, 16)}';
      await p.setString('gm_token', t);
    }
    return t;
  } catch (_) {
    return 'gm_${const Uuid().v4().replaceAll('-', '').substring(0, 16)}';
  }
}

/// Cihaza özgü kimlik (güvenli sunucu kimliği DEĞİLDİR).
Future<String> loadOrCreateDeviceId() async {
  try {
    final p = await SharedPreferences.getInstance();
    var id = p.getString('device_id');
    if (id == null) {
      id = const Uuid().v4();
      await p.setString('device_id', id);
    }
    return id;
  } catch (_) {
    return const Uuid().v4(); // depolama yoksa oturumluk kimlik
  }
}

class GreenProjectApp extends StatelessWidget {
  const GreenProjectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yeşil Adım',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primaryPurple,
          primary: AppColors.primaryPurple,
          secondary: AppColors.emeraldGreen,
        ),
      ),
      home: const RootGate(),
    );
  }
}


class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  @override
  void initState() {
    super.initState();
    Hub.store.addListener(_onStore);
  }

  @override
  void dispose() {
    Hub.store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Hub.store.hasProfile
        ? const MainShell()
        : WelcomeScreen(deviceIdProvider: loadOrCreateDeviceId);
  }
}
