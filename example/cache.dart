import 'dart:io';
import 'package:angel_diagnostics/angel_diagnostics.dart';
import 'package:angel_multiserver/angel_multiserver.dart';

final Uri cluster = Uri.parse('clusters/static.dart');

// The profiler is enabled on this server, so you can see the
// drop in request-handling time on repeat requests.
main() async {
  var loadBalancer = new LoadBalancer()
    ..get(
        '/',
        () =>
            'Hello! This response was originally sent at ${new DateTime.now()}')
    ..all('*', serviceUnavailable());
  await loadBalancer.configure(cacheResponses());
  await loadBalancer.configure(profileRequests());
  await loadBalancer.configure(logRequests(new File('log.txt')));
  await loadBalancer.spawnIsolates(cluster, count: 3);
  var server = await loadBalancer.startServer(InternetAddress.ANY_IP_V4, 3000);
  print('Server listening at http://${server.address.address}:${server.port}');
}
