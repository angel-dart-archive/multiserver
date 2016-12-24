import 'dart:async';
import 'dart:io';
import 'package:angel_framework/angel_framework.dart';

const String _MULTI_SESS = 'sync_sess';

String _getSessId(RequestContext req) {
  var cookie = req.cookies
      .firstWhere((cookie) => cookie.name == _MULTI_SESS, orElse: () => null);

  return cookie?.value ?? req.session.id;
}

/// Used to auto-share sessions between instances by loading
/// data from an external source.
///
/// As you can imagine, typed session data will not be preserved.
abstract class SessionSynchronizer extends AngelPlugin {
  @override
  Future call(Angel app) async {
    app
      ..before.add((RequestContext req, ResponseContext res) async {
        req.session.addAll(normalize(await loadSession(_getSessId(req))));
      })
      ..responseFinalizers.add((RequestContext req, res) async {
        var sessionId = _getSessId(req);
        await saveSession(sessionId, req.session);
        res.cookies.add(new Cookie(_MULTI_SESS, sessionId));
      });
  }

  Map normalize(Map other) {
    var map = {};

    other.forEach((k, v) {
      map[Uri.decodeFull(k)] = normalizeValue(v);
    });

    return map;
  }

  normalizeValue(v) {
    if (v is String)
      return Uri.decodeFull(v);//.replaceAll('+', ' ');
    else if (v is Map)
      return normalize(v);
    else if (v is List)
      return v.map(normalizeValue).toList();
    else
      return v;
  }

  /// Loads session data based on an ID.
  Future<Map> loadSession(String id);

  /// Saves existing session data.
  Future saveSession(String id, HttpSession session);
}

/// Thrown when session data fails to be synchronized.
class SessionSynchronizerException implements Exception {
  final String message;

  SessionSynchronizerException(this.message);

  @override
  String toString() => 'Session synchronizer exception: $message';
}
