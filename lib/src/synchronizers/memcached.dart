import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:json_god/json_god.dart' as god;
import 'package:memcached_client/memcached_client.dart';
import '../session_synchronizer.dart';

/// Synchronizes sessions via Memcached.
class MemcachedSessionSynchronizer extends SessionSynchronizer {
  int _cas;

  /// The Memcached store to save sessions in.
  final MemcachedClient store;

  MemcachedSessionSynchronizer(this.store);

  @override
  Future<Map> loadSession(String id) async {
    var result = await store.gets(id);

    if (result == null || result.data?.isNotEmpty != true) {
      return {};
    } else {
      _cas = result.cas;
      var json = JSON.decode(UTF8.decode(result.data));

      if (json is Map) return json;
    }

    return {};
  }

  @override
  Future saveSession(HttpSession session) async {
    var data = {};

    for (var key in session.keys.where((key) => key is String)) {
      data[key] = god.serializeObject(session[key]);
    }

    var result = await store.set(session.id, UTF8.encode(god.serialize(data)),
        cas: _cas);

    if (!result)
      throw new SessionSynchronizerException(
          'Could not save session #${session.id}.');
  }
}
