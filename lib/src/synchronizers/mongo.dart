import 'dart:async';
import 'dart:io';
import 'package:angel_websocket/angel_websocket.dart';
import 'package:json_god/json_god.dart' as god;
import 'package:mongo_dart/mongo_dart.dart';
import '../session_synchronizer.dart';
import 'polling.dart';

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
  Future saveSession(String id, HttpSession session) async {
    var data = {};

    for (var key in session.keys.where((key) => key is String)) {
      data[key] = god.serializeObject(session[key]);
    }

    var existing = await collection.findOne(where.eq('sessionId', id));

    if (existing == null) {
      await collection.insert(data..['sessionId'] = id);
    } else {
      ObjectId id = existing['_id'];
      await collection.update(where.id(id), data);
    }
  }
}

/// Synchronizes WebSocket events via MongoDB.
class MongoWebSocketSynchronizer extends PollingWebSocketSynchronizer {
  DateTime _lastTime;
  /// The collection to query for events.
  final DbCollection collection;

  MongoWebSocketSynchronizer(this.collection, {Duration pollInterval})
      : super(pollInterval: pollInterval);

  @override
  Future<List<WebSocketEvent>> getOutstandingEvents() async {
    var timestamp = (_lastTime ?? (_lastTime = new DateTime.now())).toUtc();
    var msAfterEpoch = timestamp.millisecondsSinceEpoch;
    var events = await collection
        .find(where.gt('timestamp', msAfterEpoch))
        .map<WebSocketEvent>((m) => new WebSocketEvent.fromJson(m['event']));
    return await events.toList();
  }

  @override
  void notifyOthers(WebSocketEvent e) {
    collection.insert({
      'timestamp':
          (_lastTime = new DateTime.now()).toUtc().millisecondsSinceEpoch,
      'event': e.toJson()
    });
  }
}
