// Otomatik üretilmiş ve derleme zamanı güvenli Supabase yapılandırması.
// Gizli service_role anahtarı APK içinde ASLA yer almaz.

class SupabaseConfig {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://fhaxxraibydsjikxacbb.supabase.co',
  );

  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_7TEibMmt8wbJtKTYb_vjlA_xZoCnN5J',
  );

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty &&
      supabasePublishableKey.isNotEmpty &&
      supabaseUrl.startsWith('https://');
}
