import 'dart:io';
import 'dart:isolate';
import 'package:angel_diagnostics/angel_diagnostics.dart';
import 'package:angel_framework/angel_framework.dart';
import 'package:angel_websocket/server.dart';

main(args, [SendPort sendPort]) async {
  var ws = new AngelWebSocket()
    ..onConnection.listen((socket) {
      socket
        ..send('foo', {'hello': 'world'})
        ..onData.listen((data) {
          print('WS data from client: $data');
        });
    });

  var app = new Angel();
  await app.configure(ws);
  app.all('*', () => throw new AngelHttpException.notFound());

  await app.configure(logRequests(new File('log.txt')));
  var server = await app.startServer();
  sendPort?.send([server.address.address, server.port]);
  print(
      'WS cluster listening at http://${server.address.address}:${server.port}');
}
