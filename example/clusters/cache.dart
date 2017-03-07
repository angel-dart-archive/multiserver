import 'dart:io';
import 'dart:isolate';
import 'package:angel_diagnostics/angel_diagnostics.dart';
import 'package:angel_framework/angel_framework.dart';
import 'package:angel_static/angel_static.dart';

main(args, [SendPort sendPort]) async {
  var app = new Angel();

  await app.configure(new CachingVirtualDirectory(
      source: new Directory('static'),
      onlyInProduction: false,
      publicPath: '/static'));
  app.all('*', () => throw new AngelHttpException.notFound());

  await app.configure(logRequests(new File('log.txt')));
  var server = await app.startServer();
  print('Spawned cache node at http://${server.address.address}:${server.port}');
  sendPort?.send([server.address.address, server.port]);
}
