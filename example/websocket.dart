import 'dart:convert';
import 'dart:io';
import 'package:angel_diagnostics/angel_diagnostics.dart';
import 'package:angel_multiserver/angel_multiserver.dart';
import 'package:angel_websocket/io.dart';

final Uri cluster = Uri.parse('clusters/websocket.dart');

main() async {
  var loadBalancer = new LoadBalancer()..after.add(serviceUnavailable());
  await loadBalancer.configure(logRequests(new File('log.txt')));
  await loadBalancer.spawnIsolates(cluster, count: 3);
  var server = await loadBalancer.startServer(InternetAddress.ANY_IP_V4, 3000);
  print('Server listening at http://${server.address.address}:${server.port}');

  var client =
      new WebSockets('ws://${server.address.address}:${server.port}/ws');
  await client.connect();

  client.socket.sink.add(JSON.encode({
    'hello': {'foo': 'bar'}
  }));

  await client.close();

  var data = await client.onData.first;
  print('Got WS data from proxy: $data');
}
