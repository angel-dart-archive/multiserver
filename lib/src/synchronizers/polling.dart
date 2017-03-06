import 'dart:async';
import 'package:angel_websocket/server.dart';

abstract class PollingWebSocketSynchronizer extends WebSocketSynchronizer {
  final StreamController<WebSocketEvent> _stream =
      new StreamController<WebSocketEvent>();
  final int maxAge;
  final Duration pollInterval;

  PollingWebSocketSynchronizer({this.maxAge: 30000, this.pollInterval}) {
    new Timer.periodic(pollInterval, (_) async {
      await deleteOldEvents();
      var events = await getOutstandingEvents();

      for (var event in events) {
        _stream.add(event);
      }
    });
  }

  Future deleteOldEvents();

  Future<List<WebSocketEvent>> getOutstandingEvents();

  @override
  Stream<WebSocketEvent> get stream => _stream.stream;
}
