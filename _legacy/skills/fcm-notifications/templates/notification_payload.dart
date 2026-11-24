// Dart 3 native sealed-class payload hierarchy. Default for new projects.
//
// CRITICAL — every concrete subclass overrides == and hashCode. NavigationIntent
// flows through ValueNotifier<NavigationIntent?>, which uses != for dedup;
// default reference equality silently breaks the deferred-dispatch contract
// in PendingIntentStore.
//
// Distinct UnknownPayload (type missing or unknown to this app version) vs
// MalformedPayload (type known, required field missing/invalid) — separate
// telemetry so dashboards can tell "we shipped a payload our installed
// base can't handle" from "the sender bug rendered a known type wrong."
//
// 4 KB defensive size guard. FCM enforces 4096 bytes total at the sender
// (`MessageTooBig` error); this is defence-in-depth for misbehaving local
// test injection.
//
// PROJECT SUBSTITUTIONS:
//   <your_app>          package name (imports below).
//   Replace the OrderShippedPayload / ChatMessagePayload variants with the
//   project's own payload types. Keep the UnknownPayload + MalformedPayload
//   variants verbatim.

import 'dart:convert';

import 'package:<your_app>/core/notifications/fcm_message.dart';

const int _kMaxPayloadBytes = 4 * 1024;

sealed class NotificationPayload {
  // The raw `data['type']` discriminator, if present. Lets the router emit
  // telemetry that includes the variant name even for unknown types.
  String? get variant;

  static NotificationPayload fromMessage(FcmMessage message) {
    // Defensive size guard. Telemetry on this is interesting — it means
    // either the sender bypassed FCM's 4 KB cap (impossible via HTTP v1)
    // or a local-test injection misbehaved.
    final raw = jsonEncode(message.data);
    if (raw.length > _kMaxPayloadBytes) {
      return MalformedPayload(
        rawData: message.data,
        reason: 'payload_over_4kb',
      );
    }

    final type = message.data['type'];
    if (type is! String || type.isEmpty) {
      return const UnknownPayload(reason: 'missing_or_invalid_type');
    }

    try {
      return switch (type) {
        'order_shipped' => OrderShippedPayload._parse(message.data),
        'chat_message' => ChatMessagePayload._parse(message.data),
        _ => UnknownPayload(reason: 'unknown_type', variantHint: type),
      };
    } on _MalformedField catch (e) {
      return MalformedPayload(
        rawData: message.data,
        reason: e.reason,
        variantHint: type,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Example variant — replace with project payloads.
// ---------------------------------------------------------------------------

final class OrderShippedPayload extends NotificationPayload {
  final String orderId;
  final DateTime? shippedAt;

  OrderShippedPayload({required this.orderId, this.shippedAt});

  factory OrderShippedPayload._parse(Map<String, dynamic> data) {
    final orderId = data['order_id'];
    if (orderId is! String || orderId.isEmpty) {
      throw const _MalformedField('order_id missing or not String');
    }
    return OrderShippedPayload(
      orderId: orderId,
      shippedAt: _tryParseDate(data['shipped_at']),
    );
  }

  @override
  String get variant => 'order_shipped';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderShippedPayload &&
          other.orderId == orderId &&
          other.shippedAt == shippedAt;

  @override
  int get hashCode => Object.hash(orderId, shippedAt);
}

final class ChatMessagePayload extends NotificationPayload {
  final String threadId;
  final String? preview;

  ChatMessagePayload({required this.threadId, this.preview});

  factory ChatMessagePayload._parse(Map<String, dynamic> data) {
    final threadId = data['thread_id'];
    if (threadId is! String || threadId.isEmpty) {
      throw const _MalformedField('thread_id missing or not String');
    }
    final preview = data['preview'];
    return ChatMessagePayload(
      threadId: threadId,
      preview: preview is String ? preview : null,
    );
  }

  @override
  String get variant => 'chat_message';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessagePayload &&
          other.threadId == threadId &&
          other.preview == preview;

  @override
  int get hashCode => Object.hash(threadId, preview);
}

// ---------------------------------------------------------------------------
// Unknown vs malformed — KEEP both; telemetry differentiates them.
// ---------------------------------------------------------------------------

final class UnknownPayload extends NotificationPayload {
  // 'missing_or_invalid_type' | 'unknown_type'
  final String reason;
  final String? variantHint;

  const UnknownPayload({required this.reason, this.variantHint});

  @override
  String? get variant => variantHint;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnknownPayload &&
          other.reason == reason &&
          other.variantHint == variantHint;

  @override
  int get hashCode => Object.hash(reason, variantHint);
}

final class MalformedPayload extends NotificationPayload {
  final Map<String, dynamic> rawData;
  final String reason;
  final String? variantHint;

  MalformedPayload({
    required this.rawData,
    required this.reason,
    this.variantHint,
  });

  @override
  String? get variant => variantHint;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MalformedPayload &&
          other.reason == reason &&
          other.variantHint == variantHint;

  @override
  int get hashCode => Object.hash(reason, variantHint);
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

class _MalformedField implements Exception {
  final String reason;
  const _MalformedField(this.reason);
}

DateTime? _tryParseDate(Object? raw) {
  if (raw is String) return DateTime.tryParse(raw);
  if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
  return null;
}
