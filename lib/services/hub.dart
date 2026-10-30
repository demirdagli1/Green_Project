import 'app_store.dart';
import 'command_dispatcher.dart';
import 'gm_server.dart';
import 'hardware_bridge.dart';
import 'sensor_controller.dart';

/// Basit servis konumlandırıcı (main ve testler ayarlar).
class Hub {
  static AppStore get store => AppStore.instance;

  static SensorController? _sensors;
  static SensorController get sensors =>
      _sensors ??= SensorController(bridge: NoHardwareBridge(), store: AppStore.instance);
  static set sensors(SensorController s) => _sensors = s;

  static CommandDispatcher? _dispatcher;
  static CommandDispatcher get dispatcher =>
      _dispatcher ??= CommandDispatcher(AppStore.instance);
  static set dispatcher(CommandDispatcher d) => _dispatcher = d;

  static GmServer? _gmServer;
  static GmServer get gmServer =>
      _gmServer ??= GmServer(dispatcher: dispatcher, sensors: sensors);
  static set gmServer(GmServer s) => _gmServer = s;
}
