import 'dart:async';
import 'dart:io';
import 'package:json_god/json_god.dart' as god;
import 'package:mongo_dart/mongo_dart.dart';
import '../session_synchronizer.dart';

/// Synchronizes sessions via MongoDB.
class MongoSessionSynchronizer extends SessionSynchronizer {
  /// The collection to query for sessions.
  final DbCollection collection;

  MongoSessionSynchronizer(this.collection);

  @override
  Future<Map> loadSession(String id) async {
    var session = await collection.findOne(where.eq('sessionId', id));
    return session ?? {};
  }

  @override
  Future saveSession(HttpSession session) async {
    var data = {};

    for (var key in session.keys.where((key) => key is String)) {
      data[key] = god.serializeObject(session[key]);
    }

    var existing = await collection.findOne(where.eq('sessionId', session.id));

    if (existing == null) {
      await collection.insert(data..['sessionId'] = session.id);
    } else {
      ObjectId id = existing['_id'];
      await collection.update(where.id(id), data);
    }
  }
}
