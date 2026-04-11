import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'app_notification_delegate.dart';

class NativeAppNotificationDelegate implements AppNotificationDelegate {
  NativeAppNotificationDelegate();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
        'campaign_alerts',
        'Campaign alerts',
        description: 'Notifications about campaign status and delivery issues',
        importance: Importance.max,
      );

  @override
  Future<void> initialize() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        defaultPresentAlert: true,
        defaultPresentBadge: true,
        defaultPresentSound: true,
        defaultPresentBanner: true,
        defaultPresentList: true,
      ),
      macOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        defaultPresentAlert: true,
        defaultPresentBadge: true,
        defaultPresentSound: true,
        defaultPresentBanner: true,
        defaultPresentList: true,
      ),
      linux: LinuxInitializationSettings(defaultActionName: 'Open'),
      windows: WindowsInitializationSettings(
        appName: 'Omni360 App',
        appUserModelId: 'io.omni360.omni360_app',
        guid: '3f245fd6-6d30-4f44-93d1-90f2e64fd1d9',
      ),
    );

    await _plugin.initialize(settings: settings);

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_androidChannel);
  }

  @override
  Future<void> requestPermissions() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    await _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'campaign_alerts',
        'Campaign alerts',
        channelDescription:
            'Notifications about campaign status and delivery issues',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        presentBanner: true,
        presentList: true,
      ),
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        presentBanner: true,
        presentList: true,
      ),
      linux: LinuxNotificationDetails(defaultActionName: 'Open'),
      windows: WindowsNotificationDetails(),
    );

    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }
}

AppNotificationDelegate createNotificationDelegate() =>
    NativeAppNotificationDelegate();
