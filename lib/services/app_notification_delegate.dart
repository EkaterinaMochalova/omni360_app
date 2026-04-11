abstract class AppNotificationDelegate {
  Future<void> initialize();
  Future<void> requestPermissions();
  Future<void> show({
    required int id,
    required String title,
    required String body,
  });
}
