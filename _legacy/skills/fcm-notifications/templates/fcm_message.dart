// Firebase-free DTO emitted on every FcmTransport stream and consumed by
// payload.fromMessage(...). Keeps the abstract layer (FcmTransport) and
// every consumer (NotificationsCubit, payload sealed classes, tests) free
// of `firebase_messaging` imports — only FcmTransportImpl knows about
// RemoteMessage.
//
// PROJECT SUBSTITUTIONS: none.

import 'dart:collection';
import 'package:meta/meta.dart';

@immutable
class FcmMessage {
  final String? messageId;
  final Map<String, dynamic> data;
  final FcmNotificationBlock? notification;
  final DateTime? sentTime;

  FcmMessage({
    required this.messageId,
    required Map<String, dynamic> data,
    this.notification,
    this.sentTime,
  }) : data = UnmodifiableMapView(data);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FcmMessage &&
          other.messageId == messageId &&
          _mapEquals(other.data, data) &&
          other.notification == notification &&
          other.sentTime == sentTime;

  @override
  int get hashCode => Object.hash(
        messageId,
        Object.hashAllUnordered(data.entries.map((e) => Object.hash(e.key, e.value))),
        notification,
        sentTime,
      );

  @override
  String toString() =>
      'FcmMessage(messageId: $messageId, data: $data, notification: $notification)';
}

@immutable
class FcmNotificationBlock {
  final String? title;
  final String? body;
  final String? androidChannelId;

  const FcmNotificationBlock({this.title, this.body, this.androidChannelId});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FcmNotificationBlock &&
          other.title == title &&
          other.body == body &&
          other.androidChannelId == androidChannelId;

  @override
  int get hashCode => Object.hash(title, body, androidChannelId);

  @override
  String toString() => 'FcmNotificationBlock(title: $title, body: $body)';
}

bool _mapEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (!b.containsKey(key) || a[key] != b[key]) return false;
  }
  return true;
}
