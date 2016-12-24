import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:json_god/json_god.dart' as god;
import 'package:redis_client/redis_client.dart';
import '../session_synchronizer.dart';

/// Synchronizes sessions via Redis.
class RedisSessionSynchronizer extends SessionSynchronizer {
  /// The client to access Redis with.
  final RedisClient client;

  RedisSessionSynchronizer(this.client);

  @override
  Future<Map> loadSession(String id) async {
    var session = await client.get(id);

    if (session != null) {
      var json = JSON.decode(session);

      if (json is Map) return json;
    }

    return {};
  }

  @override
  Future saveSession(String id, HttpSession session) {
    var data = {};

    for (var key in session.keys.where((key) => key is String)) {
      data[key] = god.serializeObject(session[key]);
    }

    return client.set(id, god.serialize(data));
  }
}
