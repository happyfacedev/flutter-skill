// State for NotificationsCubit. Two leaves (TokenRegistrationState +
// PermissionState) aggregated into NotificationsState. Manual copyWith,
// plain Dart — NO Freezed (per cubit-creation Rule 4).
//
// What's intentionally NOT here: the in-flight Completer, the
// _recentTaps dedup map, _currentUserId, the in-flight token snapshot.
// Those are private fields on the cubit — they MUST NOT enter state or
// toJson, or HydratedCubit will persist transient runtime state across
// restarts.
//
// PROJECT SUBSTITUTIONS: none.

enum TokenRegistrationStatus { idle, registering, registered, failed }

enum NotificationPermissionStatus {
  notDetermined,
  denied,
  deniedTerminal,
  provisional,
  authorized,
  ephemeral,
}

class TokenRegistrationState {
  final TokenRegistrationStatus status;
  final String? persistedToken;
  final DateTime? lastRegisteredAt;
  final Object? lastError;

  const TokenRegistrationState({
    this.status = TokenRegistrationStatus.idle,
    this.persistedToken,
    this.lastRegisteredAt,
    this.lastError,
  });

  TokenRegistrationState copyWith({
    TokenRegistrationStatus? status,
    String? persistedToken,
    DateTime? lastRegisteredAt,
    Object? lastError,
  }) =>
      TokenRegistrationState(
        status: status ?? this.status,
        persistedToken: persistedToken ?? this.persistedToken,
        lastRegisteredAt: lastRegisteredAt ?? this.lastRegisteredAt,
        lastError: lastError,
      );

  Map<String, dynamic> toJson() => {
        'status': status.name,
        'persistedToken': persistedToken,
        'lastRegisteredAt': lastRegisteredAt?.toIso8601String(),
      };

  static TokenRegistrationState fromJson(Map<String, dynamic> json) =>
      TokenRegistrationState(
        status: TokenRegistrationStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => TokenRegistrationStatus.idle,
        ),
        persistedToken: json['persistedToken'] as String?,
        lastRegisteredAt:
            DateTime.tryParse(json['lastRegisteredAt'] as String? ?? ''),
      );
}

class PermissionState {
  final NotificationPermissionStatus status;

  const PermissionState({
    this.status = NotificationPermissionStatus.notDetermined,
  });

  PermissionState copyWith({NotificationPermissionStatus? status}) =>
      PermissionState(status: status ?? this.status);

  Map<String, dynamic> toJson() => {'status': status.name};

  static PermissionState fromJson(Map<String, dynamic> json) => PermissionState(
        status: NotificationPermissionStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => NotificationPermissionStatus.notDetermined,
        ),
      );
}

class NotificationsState {
  final TokenRegistrationState token;
  final PermissionState permission;

  const NotificationsState({
    this.token = const TokenRegistrationState(),
    this.permission = const PermissionState(),
  });

  NotificationsState copyWith({
    TokenRegistrationState? token,
    PermissionState? permission,
  }) =>
      NotificationsState(
        token: token ?? this.token,
        permission: permission ?? this.permission,
      );

  Map<String, dynamic> toJson() => {
        'token': token.toJson(),
        'permission': permission.toJson(),
      };

  static NotificationsState fromJson(Map<String, dynamic> json) =>
      NotificationsState(
        token: TokenRegistrationState.fromJson(
          (json['token'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        permission: PermissionState.fromJson(
          (json['permission'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
      );
}
