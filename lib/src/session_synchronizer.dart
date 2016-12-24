import 'dart:async';
import 'dart:io';
import 'package:angel_framework/angel_framework.dart';

/// Used to auto-share sessions between instances by loading
/// data from an external source.
///
/// As you can imagine, typed session data will not be preserved.
abstract class SessionSynchronizer extends AngelPlugin {
  @override
  Future call(Angel app) async {
    app
      ..before.add((RequestContext req, res) async {
        req.session.addAll(await loadSession(req.session.id));
      })
      ..responseFinalizers.add((RequestContext req, res) async {
        await saveSession(req.session);
      });
  }

  /// Loads session data based on an ID.
  Future<Map> loadSession(String id);

  /// Saves existing session data.
  Future saveSession(HttpSession session);
}

/// Thrown when session data fails to be synchronized.
class SessionSynchronizerException implements Exception {
  final String message;

  SessionSynchronizerException(this.message);

  @override
  String toString() => 'Session synchronizer exception: $message';
}
