import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

/// LiveKit access tokens (HS256 JWT with a `video` grant), see
/// https://docs.livekit.io/home/get-started/authentication/.
class LiveKitTokenIssuer {
  LiveKitTokenIssuer({
    required this.apiKey,
    required String apiSecret,
    this.lifetime = const Duration(hours: 6),
  }) : _secret = SecretKey(apiSecret);

  final String apiKey;
  final SecretKey _secret;
  final Duration lifetime;

  String issue({
    required String identity,
    required String displayName,
    required String room,
  }) {
    return JWT(
      {
        'name': displayName,
        'video': {
          'room': room,
          'roomJoin': true,
          'canPublish': true,
          'canSubscribe': true,
          'canPublishData': true,
          // Voice only: no camera or screen share.
          'canPublishSources': ['microphone'],
        },
      },
      issuer: apiKey,
      subject: identity,
    ).sign(_secret, expiresIn: lifetime, notBefore: Duration.zero);
  }
}
