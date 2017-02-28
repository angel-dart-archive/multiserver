import 'dart:async';
import 'package:angel_websocket/server.dart';

abstract class PollingWebSocketSynchronizer extends WebSocketSynchronizer {
  final StreamController<WebSocketEvent> _stream = new StreamController<WebSocketEvent>();
  final Duration pollInterval;

  PollingWebSocketSynchronizer({this.pollInterval}) {
    new Timer.periodic(pollInterval, (_) async {
      var events = await getOutstandingEvents();

      for (var event in events) {
        _stream.add(event);
      }
    });
  }

  Future<List<WebSocketEvent>> getOutstandingEvents();

  @override
  Stream<WebSocketEvent> get stream => _stream.stream;
}