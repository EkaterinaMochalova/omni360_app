import 'app_notification_delegate.dart';
import 'app_notification_delegate_stub.dart'
    if (dart.library.io) 'app_notification_delegate_native.dart'
    if (dart.library.html) 'app_notification_delegate_web.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppNotificationsService {
  AppNotificationsService._();

  static final AppNotificationsService instance = AppNotificationsService._();
  final AppNotificationDelegate _delegate = createNotificationDelegate();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  bool _initialized = false;
  static const _enabledKey = 'campaign_notifications_enabled';

  Future<void> initialize() async {
    if (_initialized) return;
    await _delegate.initialize();
    _initialized = true;
  }

  Future<void> requestPermissions() async {
    await initialize();
    await _delegate.requestPermissions();
  }

  Future<bool> isEnabled() async {
    final stored = await _storage.read(key: _enabledKey);
    if (stored == null) return true;
    return stored == 'true';
  }

  Future<void> setEnabled(bool value) async {
    await _storage.write(key: _enabledKey, value: value.toString());
  }

  Future<void> show({
    required String dedupeKey,
    required String title,
    required String body,
  }) async {
    await initialize();
    if (!await isEnabled()) return;
    await _delegate.show(
      id: dedupeKey.hashCode & 0x7fffffff,
      title: title,
      body: body,
    );
  }
}
