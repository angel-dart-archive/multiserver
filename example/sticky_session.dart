/// This entire example will also work with Round Robin, etc.

import 'dart:convert';
import 'dart:io';
import 'package:angel_compress/angel_compress.dart';
import 'package:angel_diagnostics/angel_diagnostics.dart';
import 'package:angel_framework/angel_framework.dart';
import 'package:angel_multiserver/angel_multiserver.dart';

final Uri cluster = Platform.script.resolve('clusters/hello.dart');

final error502 = GZIP.encode(UTF8.encode('''
        <!DOCTYPE html>
        <html>
          <head>
            <title>502 Bad Gateway</title>
          </head>
          <body>
            <h1>502 Bad Gateway</h1>
          </body>
        </html>
        '''));

final error503 = '''
        <!DOCTYPE html>
        <html>
          <head>
            <title>503 Service Unavailable</title>
          </head>
          <body>
            <h1>503 Service Unavailable</h1>
            <i>There is no server available to service your request.</i>
          </body>
        </html>
        ''';

main() async {
  var loadBalancer = new LoadBalancer(algorithm: STICKY_SESSION);
  await loadBalancer.spawnIsolates(cluster, count: 5);

  // Auto-spawn a new instance on crash
  loadBalancer.onCrash.listen((_) {
    loadBalancer.spawnIsolates(cluster);
  });

  // Fallback content is easy - just use normal Angel handlers!
  loadBalancer.after.add((req, ResponseContext res) async {
    res
      ..contentType = ContentType.HTML
      ..statusCode = HttpStatus.SERVICE_UNAVAILABLE
      ..write(error503);
  });

  loadBalancer.responseFinalizers.add(gzip());
  await loadBalancer.configure(logRequests(new File('log.txt')));
  var server = await loadBalancer.startServer(InternetAddress.ANY_IP_V4, 3000);
  print('Server listening at http://${server.address.address}:${server.port}');
}
