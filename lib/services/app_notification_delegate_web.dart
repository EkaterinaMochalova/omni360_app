// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

import 'app_notification_delegate.dart';

class WebAppNotificationDelegate implements AppNotificationDelegate {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> requestPermissions() async {
    if (!html.Notification.supported) return;
    if (html.Notification.permission == 'default') {
      await html.Notification.requestPermission();
    }
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!html.Notification.supported) return;
    if (html.Notification.permission != 'granted') return;

    html.Notification(title, body: body, icon: '/icons/Icon-192.png');
  }
}

AppNotificationDelegate createNotificationDelegate() =>
    WebAppNotificationDelegate();
