// Freezed alternative — use ONLY if the host project is already on Freezed
// for other models. Greenfield projects should prefer the native Dart 3
// sealed-class version in notification_payload.dart.
//
// If the host project already has a Freezed-based payload sealed union,
// this template is the migration target shape — adopt the unknown +
// malformed variants and the defensive fromMessage factory.
//
// CRITICAL — Freezed auto-generates == and hashCode; this version is safe
// for the ValueNotifier dedup in PendingIntentStore by construction.
// But: you still MUST add the UnknownPayload + MalformedPayload variants
// (Freezed unions don't enforce them) and you still MUST defensively
// parse `data['type']` because Freezed's `fromJson` will throw on missing
// fields rather than route to `unknown`.
//
// PROJECT SUBSTITUTIONS:
//   <your_app>          package name (imports below).
//   Replace OrderShippedPayload / ChatMessagePayload with the project's
//   own variants; keep `unknown` and `malformed`.

import 'dart:convert';

import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:<your_app>/core/notifications/fcm_message.dart';

part 'notification_payload_freezed_alt.freezed.dart';

const int _kMaxPayloadBytes = 4 * 1024;

@freezed
sealed class NotificationPayload with _$NotificationPayload {
  const NotificationPayload._();

  const factory NotificationPayload.orderShipped({
    required String orderId,
    DateTime? shippedAt,
  }) = OrderShippedPayload;

  const factory NotificationPayload.chatMessage({
    required String threadId,
    String? preview,
  }) = ChatMessagePayload;

  const factory NotificationPayload.unknown({
    required String reason,
    String? variantHint,
  }) = UnknownPayload;

  const factory NotificationPayload.malformed({
    required Map<String, dynamic> rawData,
    required String reason,
    String? variantHint,
  }) = MalformedPayload;

  static NotificationPayload fromMessage(FcmMessage message) {
    final raw = jsonEncode(message.data);
    if (raw.length > _kMaxPayloadBytes) {
      return NotificationPayload.malformed(
        rawData: message.data,
        reason: 'payload_over_4kb',
      );
    }

    final type = message.data['type'];
    if (type is! String || type.isEmpty) {
      return const NotificationPayload.unknown(reason: 'missing_or_invalid_type');
    }

    try {
      return switch (type) {
        'order_shipped' => _parseOrderShipped(message.data),
        'chat_message' => _parseChatMessage(message.data),
        _ => NotificationPayload.unknown(
            reason: 'unknown_type',
            variantHint: type,
          ),
      };
    } on _MalformedField catch (e) {
      return NotificationPayload.malformed(
        rawData: message.data,
        reason: e.reason,
        variantHint: type,
      );
    }
  }
}

NotificationPayload _parseOrderShipped(Map<String, dynamic> data) {
  final orderId = data['order_id'];
  if (orderId is! String || orderId.isEmpty) {
    throw const _MalformedField('order_id missing or not String');
  }
  return NotificationPayload.orderShipped(
    orderId: orderId,
    shippedAt: _tryParseDate(data['shipped_at']),
  );
}

NotificationPayload _parseChatMessage(Map<String, dynamic> data) {
  final threadId = data['thread_id'];
  if (threadId is! String || threadId.isEmpty) {
    throw const _MalformedField('thread_id missing or not String');
  }
  final preview = data['preview'];
  return NotificationPayload.chatMessage(
    threadId: threadId,
    preview: preview is String ? preview : null,
  );
}

DateTime? _tryParseDate(Object? raw) {
  if (raw is String) return DateTime.tryParse(raw);
  if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
  return null;
}

class _MalformedField implements Exception {
  final String reason;
  const _MalformedField(this.reason);
}
