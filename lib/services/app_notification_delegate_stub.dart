import 'app_notification_delegate.dart';

class StubAppNotificationDelegate implements AppNotificationDelegate {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> requestPermissions() async {}

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {}
}

AppNotificationDelegate createNotificationDelegate() =>
    StubAppNotificationDelegate();
