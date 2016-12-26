import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'defs.dart';
import 'load_balancer.dart' show LoadBalancer;

const RoundRobinAlgorithm ROUND_ROBIN = const RoundRobinAlgorithm();
const StickySessionAlgorithm STICKY_SESSION = const StickySessionAlgorithm();

/// Drop-in functionality to route requests to different servers.
abstract class LoadBalancingAlgorithm {
  /// The name of this algorithm.
  final String name;

  const LoadBalancingAlgorithm(this.name);

  /// Chooses the next endpoint to forward a request to.
  Future<Endpoint> nextEndpoint(LoadBalancer loadBalancer, HttpRequest request);

  /// Handles a crashed instance.
  void onCrashed(LoadBalancer loadBalancer, Isolate isolate);

  /// Handles a newly discovered [Endpoint].
  void onEndpoint(LoadBalancer loadBalancer, Endpoint endpoint);

  /// Forwards [rs] to [r].
  ///
  /// Override this to compress the response, etc.
  Future pipeResponse(HttpClientResponse rs, HttpResponse r) async {
    r.statusCode = rs.statusCode;
    r.headers.contentType = rs.headers.contentType;
    await r.addStream(rs);
    await r.flush();
    await r.close();
  }
}

/// A simple next-in-loop algorithm.
class RoundRobinAlgorithm extends LoadBalancingAlgorithm {
  const RoundRobinAlgorithm() : super('round-robin');

  @override
  Future<Endpoint> nextEndpoint(
      LoadBalancer loadBalancer, HttpRequest request) async {
    var endpoints = loadBalancer.endpoints;
    if (endpoints.isEmpty) return null;

    if (loadBalancer.index++ < endpoints.length - 1)
      return endpoints[loadBalancer.index];
    else
      return endpoints[loadBalancer.index = 0];
  }

  @override
  void onCrashed(LoadBalancer loadBalancer, Isolate isolate) {
    var endpoints = loadBalancer.endpoints;
    var crashed = endpoints.where((endpoint) => endpoint.isolate == isolate);

    for (var endpoint in crashed) {
      endpoints.remove(endpoint);
      loadBalancer.triggerCrash(endpoint);
    }
  }

  @override
  void onEndpoint(LoadBalancer loadBalancer, Endpoint endpoint) {
    var endpoints = loadBalancer.endpoints;
    endpoints.add(endpoint);
  }
}

/// Sends specific clients to an assigned server each time.
class StickySessionAlgorithm extends LoadBalancingAlgorithm {
  const StickySessionAlgorithm() : super('sticky-session');

  @override
  Future<Endpoint> nextEndpoint(
      LoadBalancer loadBalancer, HttpRequest request) async {
    var endpoints = loadBalancer.endpoints;
    if (loadBalancer.sticky.containsKey(request.connectionInfo.remoteAddress)) {
      return loadBalancer.sticky[request.connectionInfo.remoteAddress];
    }

    var endpoint = endpoints.isNotEmpty ? endpoints.first : null;

    if (endpoint != null) {
      endpoints.remove(endpoint);
      loadBalancer.sticky[request.connectionInfo.remoteAddress] = endpoint;
    }

    return endpoint;
  }

  @override
  void onCrashed(LoadBalancer loadBalancer, Isolate isolate) {
    var endpoints = loadBalancer.endpoints;
    var crashed = endpoints.where((endpoint) => endpoint.isolate == isolate);

    List<Endpoint> remove = [];

    for (var endpoint in crashed) {
      var keys = loadBalancer.sticky.keys
          .map((k) => loadBalancer.sticky[k] == endpoint);
      keys.forEach(loadBalancer.sticky.remove);

      remove.add(endpoint);
      loadBalancer.triggerCrash(endpoint);
    }

    remove.forEach(endpoints.remove);
  }

  @override
  void onEndpoint(LoadBalancer loadBalancer, Endpoint endpoint) {
    loadBalancer.endpoints.add(endpoint);
  }
}
