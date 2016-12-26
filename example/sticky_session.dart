/// This entire example will also work with Round Robin, etc.

import 'dart:convert';
import 'dart:io';
import 'package:angel_compress/angel_compress.dart';
import 'package:angel_diagnostics/angel_diagnostics.dart';
import 'package:angel_framework/angel_framework.dart';
import 'package:angel_multiserver/angel_multiserver.dart';

final Uri cluster = Platform.script.resolve('cluster.dart');

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

  loadBalancer
    ..onCrash.listen((_) {
      // Auto-spawn a new instance on crash
      loadBalancer.spawnIsolates(cluster);
    })
    ..onDistributionError.listen((e) {
      stderr..writeln('This error caused a crash:')..writeln(e);
    })
    ..onErrored.listen((request) async {
      var rs = request.response
        ..headers.contentType = ContentType.HTML
        ..statusCode = HttpStatus.BAD_GATEWAY
        ..headers.set(HttpHeaders.CONTENT_ENCODING, 'gzip')
        ..add(error502);
      await rs.close();
    });

  // Fallback content
  loadBalancer
    ..all('*', (req, ResponseContext res) async {
      res
        ..contentType = ContentType.HTML
        ..statusCode = HttpStatus.SERVICE_UNAVAILABLE
        ..write(error503);
    })
    ..responseFinalizers.add(gzip());

  await new DiagnosticsServer(loadBalancer, new File('log.txt'))
      .startServer(InternetAddress.ANY_IP_V4, 3000);
}
