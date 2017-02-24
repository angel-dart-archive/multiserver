import 'dart:io';
import 'package:angel_diagnostics/angel_diagnostics.dart';
import 'package:angel_framework/angel_framework.dart';
import 'package:angel_multiserver/angel_multiserver.dart';

final Uri cluster = Uri.parse('clusters/cache.dart');

// The profiler is enabled on this server, so you can see the
// drop in request-handling time on repeat requests.
main() async {
  var loadBalancer = new LoadBalancer()
    ..get('/', (_, ResponseContext res) {
      res.contentType = ContentType.TEXT;
      return 'Hello! This response was originally sent at ${new DateTime.now()}';
    })
    ..all('*', serviceUnavailable());
  await loadBalancer.configure(cacheResponses(varyHeaders: [])); // If not empty, defaults to [content-encoding]
  await loadBalancer.configure(profileRequests());
  await loadBalancer.configure(logRequests(new File('log.txt')));
  await loadBalancer.spawnIsolates(cluster, count: 3);
  var server = await loadBalancer.startServer(InternetAddress.ANY_IP_V4, 3000);
  print('Server listening at http://${server.address.address}:${server.port}');
}
