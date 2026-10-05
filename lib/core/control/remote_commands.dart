import 'dart:async';

/// Handles control-channel requests that target a phone acting as a remote host
/// (the device being controlled). Implemented on Android by
/// [AndroidRemoteHostAgent]; tests use fakes.
abstract class RemoteCommandHandler {
  Future<Map<String, Object?>> handle(String type, Map<String, Object?> msg);
}

/// Snapshot the remote host returns for `host.status` / `host.ping`.
class RemoteHostStatus {
  const RemoteHostStatus({
    required this.deviceName,
    required this.keepAwake,
    required this.screenShare,
    this.unlockedHint,
    this.message,
    this.extras = const {},
  });

  final String deviceName;
  final bool keepAwake;

  /// `unavailable` | `scaffolded` | `active` — MediaProjection not shipped in MVP.
  final String screenShare;
  final bool? unlockedHint;
  final String? message;
  final Map<String, Object?> extras;

  Map<String, Object?> toJson() => {
        'deviceName': deviceName,
        'keepAwake': keepAwake,
        'screenShare': screenShare,
        'unlockedHint': ?unlockedHint,
        'message': ?message,
        ...extras,
      };

  factory RemoteHostStatus.fromJson(Map<String, Object?> j) => RemoteHostStatus(
        deviceName: '${j['deviceName'] ?? 'Telefon'}',
        keepAwake: j['keepAwake'] == true,
        screenShare: '${j['screenShare'] ?? 'unavailable'}',
        unlockedHint: j['unlockedHint'] as bool?,
        message: j['message'] as String?,
        extras: {
          for (final e in j.entries)
            if (!const {
              'deviceName',
              'keepAwake',
              'screenShare',
              'unlockedHint',
              'message',
            }.contains(e.key))
              e.key: e.value,
        },
      );
}
