import 'dart:async';
import 'dart:io';
import 'package:angel_framework/angel_framework.dart';
import 'package:angel_multiserver/angel_multiserver.dart';

main() async {
  var host = InternetAddress.LOOPBACK_IP_V4;
  var port = 3000;

  var multi = new MultiServer();
  await multi.spawn(3);

  await multi.startServer(host, port);

  print("Multi-server listening on ${host.address}:$port");
}

Future<Angel> createServer() async {
  var app = new Angel();
  app.get("/", app.hashCode);
  return app;
}