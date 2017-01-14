import 'dart:io';
import 'dart:isolate';
import 'package:angel_diagnostics/angel_diagnostics.dart';
import 'package:angel_framework/angel_framework.dart';

main(args, [SendPort sendPort]) async {
  var app = new Angel();
  app.get('/', () => 'Hello from instance #${app.hashCode}!');
  await app.configure(logRequests(new File('log.txt')));
  var server = await app.startServer();
  sendPort?.send([server.address.address, server.port]);
}
