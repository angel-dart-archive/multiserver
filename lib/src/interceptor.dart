import 'dart:async';
import 'dart:io';
import 'load_balancer.dart' show LoadBalancer;

import 'package:angel_framework/angel_framework.dart';

/// Runs before trying to dispatch a [request].
typedef Future RequestInterceptor(HttpRequest request);

/// Runs after dispatching a request, and receiving a [response].
typedef Future ResponseInterceptor(HttpClientResponse response);

/// Determines if a response should be cached.
typedef bool CacheFilter(HttpRequest request);

/// Caches static content to improve response time.
class RequestCache extends AngelPlugin {
  /// Contains static, pre-fetched data that will automatically be sent on future requests.
  final Map<String, List<int>> cache = {};

  /// Contains static, pre-fetched headers that will automatically be sent on future requests.
  final Map<String, HttpHeaders> headers = {};

  Future call(LoadBalancer loadBalancer) async {
    loadBalancer.requestInterceptors.add((request) async {
      var uri = request.uri.toString();

      if (cache.containsKey(uri)) {
        if (headers.containsKey(uri)) {
          headers[uri].forEach((header, values) {
            request.response.headers.set(header, values);
          });
        }

        request.response.add(cache[uri]);
        await request.response.close();
        return false;
      }

      /*
      var rs = await loadBalancer.dispatchRequest(request,
          await loadBalancer.algorithm.nextEndpoint(loadBalancer, request));
      await rs.pipe(stdout);
      */

      return true;
    });
  }
}
