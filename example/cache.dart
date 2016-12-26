import 'dart:io';
import 'package:angel_diagnostics/angel_diagnostics.dart';
import 'package:angel_framework/angel_framework.dart';
import 'package:angel_multiserver/angel_multiserver.dart';

final Uri cluster = Uri.parse('clusters/static.dart');

main() async {
  var loadBalancer = new LoadBalancer();

  await loadBalancer.configure(new RequestCache());

  loadBalancer.all(
      '*',
      () => throw new AngelHttpException(null,
          statusCode: HttpStatus.SERVICE_UNAVAILABLE,
          message: '503 Service Unavailable'));

  await loadBalancer.spawnIsolates(cluster, count: 3);
  await new DiagnosticsServer(loadBalancer, new File('log.txt'))
      .startServer(InternetAddress.ANY_IP_V4, 3000);
}
