import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

abstract class GeoQueue {
  Future<void> add(String userId, Map<String, dynamic> point);
  Future<List<Map<String, dynamic>>> read(String userId, {int limit = 100});
  Future<void> acknowledge(String userId, Set<String> ids);
  Future<void> reject(String userId, Set<String> ids);
}

class GeoDeliveryResult {
  final bool delivered;
  final bool? shiftActive;
  final bool unauthorized;
  final bool attempted;
  final bool contacted;
  final int acceptedCount;
  final int rejectedCount;
  final DateTime? latestAcceptedAt;
  const GeoDeliveryResult(this.delivered,
      {this.shiftActive,
      this.unauthorized = false,
      this.attempted = false,
      this.contacted = false,
      this.acceptedCount = 0,
      this.rejectedCount = 0,
      this.latestAcceptedAt});
}

/// One sender per runtime; SQLite and server point IDs protect concurrent runtimes.
class GeoDelivery {
  final GeoQueue queue;
  http.Client client;
  final http.Client Function()? clientFactory;
  final Uri url;
  final Future<String?> Function() readToken;
  final Future<String?> Function() refreshToken;
  bool _sending = false;
  bool _closed = false;

  GeoDelivery(
      {required this.queue,
      required this.client,
      required this.url,
      required this.readToken,
      required this.refreshToken,
      this.clientFactory});

  void close() {
    _closed = true;
    client.close();
  }

  static String? userFromToken(String? token) {
    try {
      final data = jsonDecode(utf8
          .decode(base64Url.decode(base64Url.normalize(token!.split('.')[1]))));
      final user = data['user_id']?.toString();
      return user == null || user.isEmpty ? null : user;
    } catch (_) {
      return null;
    }
  }

  Future<GeoDeliveryResult> send({Map<String, dynamic>? tracking}) async {
    if (_sending || _closed) return const GeoDeliveryResult(false);
    _sending = true;
    try {
      var token = await readToken().timeout(const Duration(seconds: 5));
      final user = userFromToken(token);
      if (user == null)
        return const GeoDeliveryResult(false, unauthorized: true);
      final points = await queue.read(user).timeout(const Duration(seconds: 5));
      if (points.isEmpty && tracking == null)
        return const GeoDeliveryResult(false);
      final body = jsonEncode(
          {'data': points, if (tracking != null) 'tracking': tracking});
      Future<http.Response> post(String jwt) async {
        try {
          return await client
              .post(url,
                  headers: {
                    'Authorization': 'Bearer $jwt',
                    'Content-Type': 'application/json'
                  },
                  body: body)
              .timeout(const Duration(seconds: 15));
        } on TimeoutException {
          // Future.timeout alone does not close a stalled socket.
          if (clientFactory != null && !_closed) {
            client.close();
            client = clientFactory!();
          }
          rethrow;
        }
      }

      var response = await post(token!);
      if (response.statusCode == 401) {
        token = await refreshToken().timeout(const Duration(seconds: 20));
        if (token == null || userFromToken(token) != user) {
          return const GeoDeliveryResult(false,
              unauthorized: true, attempted: true);
        }
        if (_closed) return const GeoDeliveryResult(false);
        response = await post(token);
      }
      if (response.statusCode != 200 && response.statusCode != 503) {
        return GeoDeliveryResult(false,
            attempted: true, unauthorized: response.statusCode == 401);
      }
      final reply = jsonDecode(response.body) as Map<String, dynamic>;
      final sentIDs = points.map((p) => p['point_id'] as String).toSet();
      final accepted = <String>{};
      final rejected = <String>{};
      if (reply['accepted_ids'] is List && reply['rejected_ids'] is List) {
        accepted.addAll((reply['accepted_ids'] as List)
            .whereType<String>()
            .where(sentIDs.contains));
        rejected.addAll((reply['rejected_ids'] as List)
            .whereType<String>()
            .where(sentIDs.contains));
        rejected.removeAll(accepted);
      } else if (response.statusCode == 200 &&
          reply['points_saved'] == points.length) {
        // Older backend: never discard a partially accepted packet.
        accepted.addAll(sentIDs);
      }
      // Only acknowledged points leave the queue. A legacy partial response has
      // no point IDs, so retaining the packet is safer than guessing which saved.
      if (accepted.isNotEmpty) await queue.acknowledge(user, accepted);
      if (rejected.isNotEmpty) await queue.reject(user, rejected);
      // Preserve rejected payloads locally; the server does not provide reasons.
      // They must not disappear silently or be mistaken for a successful upload.
      DateTime? latest;
      for (final point
          in points.where((p) => accepted.contains(p['point_id']))) {
        final at = DateTime.tryParse(point['timestamp']?.toString() ?? '');
        if (at != null && (latest == null || at.isAfter(latest))) latest = at;
      }
      final statusAccepted = points.isEmpty &&
          response.statusCode == 200 &&
          (reply['status'] == 'ok' || reply['shift_active'] is bool);
      return GeoDeliveryResult(
          accepted.length == points.length &&
              (points.isNotEmpty || statusAccepted),
          attempted: true,
          contacted: true,
          acceptedCount: accepted.length,
          rejectedCount: rejected.length,
          latestAcceptedAt: latest,
          shiftActive: reply['shift_active'] as bool?);
    } catch (_) {
      // Network failures must neither delete a queue nor log the user out.
      return const GeoDeliveryResult(false, attempted: true);
    } finally {
      _sending = false;
    }
  }
}

bool isFreshGeoPoint(DateTime measuredAt, DateTime now) =>
    !measuredAt.isAfter(now.add(const Duration(seconds: 30))) &&
    now.difference(measuredAt) <= const Duration(seconds: 60);
