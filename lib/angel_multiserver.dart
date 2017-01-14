library angel_multiserver;

import 'dart:io';
import 'package:angel_framework/angel_framework.dart';

export 'src/synchronizers/synchronizers.dart';
export 'src/algorithm.dart';
export 'src/defs.dart';
export 'src/load_balancer.dart';
export 'src/cache.dart';
export 'src/session_synchronizer.dart';

/// Throws a `503 Service Unavailable` error.
RequestHandler serviceUnavailable() {
  return (RequestContext req, ResponseContext res) =>
      throw new AngelHttpException(null,
          statusCode: HttpStatus.SERVICE_UNAVAILABLE,
          message: '503 Service Unavailable');
}
