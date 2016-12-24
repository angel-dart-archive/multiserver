import 'dart:async';
import 'dart:io';
import 'package:angel_framework/angel_framework.dart';
import 'package:angel_multiserver/angel_multiserver.dart';

Future<Angel> spawnChildServer() async {
  // Return a new instance of your
  // main application here.
  var app = new Angel();
  return app..get('/', 'Hello from instance #${app.hashCode}!');
}

main() async {
  var masterApp = new Angel();
  var loadBalancer = new LoadBalancer();

  loadBalancer
    ..spawn(spawnChildServer, count: 3)
    ..onCrash.listen((endpoint) async {
      // When a server fails to respond, it is removed
      // from the list, and an event is fired.
      // Use this to automatically re-spawn your application.
      await loadBalancer.spawn(spawnChildServer);
    });

  masterApp
    ..before.add(loadBalancer)
    ..all('*', (req, res) async {
      res
        ..statusCode = HttpStatus.SERVICE_UNAVAILABLE
        ..write('There is no server available to service the request.')
        ..end();
    });

  var server =
      await masterApp.startServer(InternetAddress.LOOPBACK_IP_V4, 3000);
  print('Load balancer listening at ${server.address.address}:${server.port}');
}
