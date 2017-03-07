import 'dart:io';
import 'package:angel_diagnostics/angel_diagnostics.dart';
import 'package:angel_framework/angel_framework.dart';
import 'package:angel_multiserver/angel_multiserver.dart';

final Uri cluster = Uri.parse('clusters/cache.dart');

// Play around with `maxConcurrentConnections` to handle high load; try it out
// using ApacheBench or wrk!
//
// You might consider limiting the pool size to the number of nodes you've spawned!
main() async {
  var loadBalancer = new LoadBalancer(maxConcurrentConnections: 20);
  loadBalancer
    ..onCrash.listen((_) {
      print('Child node crashed, spawning a new one...!');
      return loadBalancer.spawnIsolates(cluster);
    })
    ..fatalErrorStream.listen((e) {
      print('Fatal error caught: ${e.error}');
      print(e.stack);
    })
    ..get('/', (_, ResponseContext res) {
      res.contentType = ContentType.TEXT;
      return 'Hello! This response was originally sent at ${new DateTime.now()}';
    })
    ..all('*', serviceUnavailable());
  await loadBalancer.configure(cacheResponses(
      varyHeaders: [])); // If not empty, defaults to [content-encoding]
  // await loadBalancer.configure(profileRequests());
  // await loadBalancer.configure(logRequests(new File('log.txt')));
  await loadBalancer.spawnIsolates(cluster, count: 20);
  var server = await loadBalancer.startServer(InternetAddress.ANY_IP_V4, 3000);
  print('Server listening at http://${server.address.address}:${server.port}');
}
