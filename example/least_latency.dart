import 'dart:convert';
import 'dart:io';
import 'package:angel_compress/angel_compress.dart';
import 'package:angel_errors/angel_errors.dart';
import 'package:angel_framework/angel_framework.dart';
import 'package:angel_multiserver/angel_multiserver.dart';

final Uri cluster = Platform.script.resolve('clusters/least_latency.dart');

main() async {
  var loadBalancer = new LoadBalancer(algorithm: LEAST_LATENCY);
  await loadBalancer.spawnIsolates(cluster, count: 5);

  // Auto-spawn a new instance on crash
  loadBalancer.onCrash.listen((_) {
    loadBalancer.spawnIsolates(cluster);
  });

  // Fallback content is easy - just use normal Angel handlers!
  loadBalancer.after.add(serviceUnavailable());
  loadBalancer.responseFinalizers.add(deflate());

  var errorHandler = new ErrorHandler()
    ..fatalErrorHandler = (AngelFatalError e) async {
      print('Fatal error: ${e.error}');
      print(e.stack);

      if (e.request != null) {
        var error500 = GZIP.encode(UTF8.encode('''
        <!DOCTYPE html>
        <html>
          <head>
            <title>500 Internal Server Error</title>
          </head>
          <body>
            <h1>${e.error}</h1>
            <p>${e.stack}</p>
          </body>
        </html>
        '''));

        var rs = e.request.response;
        rs.add(error500);
        await rs.flush();
        await rs.close();
      }
    };

  await loadBalancer.configure(errorHandler);
  var server = await loadBalancer.startServer(InternetAddress.ANY_IP_V4, 3000);
  print('Server listening at http://${server.address.address}:${server.port}');
}
