import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'defs.dart';
import 'load_balancer.dart' show LoadBalancer;

import 'package:angel_framework/angel_framework.dart';

/// An algorithm that simply loops through servers, turn-by-turn.
final LoadBalancingAlgorithm ROUND_ROBIN = new _RoundRobinAlgorithm();

/// An algorithm that chooses the fastest-responding server on each request.
final LoadBalancingAlgorithm LEAST_LATENCY = new _LeastLatency();

/// An algorithm that matches the same clients to the same servers on each request.
final LoadBalancingAlgorithm STICKY_SESSION = new _StickySessionAlgorithm();

/// Drop-in functionality to route requests to different servers.
abstract class LoadBalancingAlgorithm {
  /// The name of this algorithm.
  final String name;

  const LoadBalancingAlgorithm(this.name);

  /// Chooses the next endpoint to forward a request to.
  Future<Endpoint> nextEndpoint(
      LoadBalancer loadBalancer, RequestContext request);

  /// Handles a crashed instance.
  void onCrashed(LoadBalancer loadBalancer, Isolate isolate);

  /// Handles a newly discovered [Endpoint].
  void onEndpoint(LoadBalancer loadBalancer, Endpoint endpoint);

  /// Forwards [rs] to [r].
  ///
  /// Override this to compress the response, etc.
  Future pipeResponse(HttpClientResponse rs, ResponseContext res) async {
    res.statusCode = rs.statusCode;
    res.headers.forEach(res.io.headers.set);
    rs.headers.forEach(res.io.headers.set);
    res.headers[HttpHeaders.SERVER] = 'angel_multiserver';
    //await rs.pipe(res.io);
    await rs.forEach(res.buffer.add);
  }
}

/// A simple next-in-loop algorithm.
class _RoundRobinAlgorithm extends LoadBalancingAlgorithm {
  final HttpClient _client = new HttpClient();
  final List<Endpoint> _endpoints = [];
  int _index = -1;

  _RoundRobinAlgorithm() : super('round-robin');

  _RoundRobinAlgorithm.named(String name) : super(name);

  Future<Endpoint> nextInLine(LoadBalancer loadBalancer) async {
    if (_endpoints.isEmpty) return null;
    Endpoint server;

    if (_index++ < _endpoints.length - 1)
      server = _endpoints[_index];
    else
      server = _endpoints[_index = 0];

    try {
      var rq = await _client.open(
          'OPTIONS', server.address.address, server.port, '/');
      await rq.close();
      return server;
    } catch (e) {
      // Error requesting - remove this guy from the list, and try again!
      _endpoints.remove(server);
      loadBalancer.triggerCrash(server);
      return await nextInLine(loadBalancer);
    }
  }

  @override
  Future<Endpoint> nextEndpoint(
      LoadBalancer loadBalancer, RequestContext request) async {
    return await nextInLine(loadBalancer);
  }

  @override
  void onCrashed(LoadBalancer loadBalancer, Isolate isolate) {
    var crashed = _endpoints.where((endpoint) => endpoint.isolate == isolate);

    for (var endpoint in crashed) {
      _endpoints.remove(endpoint);
      loadBalancer.triggerCrash(endpoint);
    }
  }

  @override
  void onEndpoint(LoadBalancer loadBalancer, Endpoint endpoint) =>
      _endpoints.add(endpoint);
}

class _LeastLatency extends _RoundRobinAlgorithm {
  _LeastLatency():super.named('least-latency');

  @override
  Future<Endpoint> nextInLine(LoadBalancer loadBalancer) async {
    if (_endpoints.isEmpty) return null;
    Endpoint fastest;
    int fastestTime = -1;
    List<Endpoint> remove = [];

    for (var server in _endpoints) {
      try {
        var sw = new Stopwatch()..start();
        var rq = await _client.open(
            'OPTIONS', server.address.address, server.port, '/');
        await rq.close();
        sw.stop();

        if (fastestTime == -1 || sw.elapsedMilliseconds < fastestTime) {
          fastestTime = sw.elapsedMilliseconds;
          fastest = server;
        }
      } catch (e) {
        // Error requesting - remove this guy from the list, and try again!
        remove.add(server);
      }
    }

    for (var server in remove) {
      _endpoints.remove(server);
      loadBalancer.triggerCrash(server);
    }

    return fastest;
  }
}

/// Sends specific clients to an assigned server each time.
class _StickySessionAlgorithm extends LoadBalancingAlgorithm {
  final List<Endpoint> _endpoints = [];
  final Map<String, Endpoint> _table = {};

  _StickySessionAlgorithm() : super('sticky-session');

  @override
  Future<Endpoint> nextEndpoint(
      LoadBalancer loadBalancer, RequestContext request) async {
    if (_table.containsKey(request.ip)) {
      return _table[request.ip];
    }

    var endpoint = _endpoints.isNotEmpty ? _endpoints.first : null;

    if (endpoint != null) {
      _endpoints.remove(endpoint);
      _table[request.ip] = endpoint;
    }

    return endpoint;
  }

  @override
  void onCrashed(LoadBalancer loadBalancer, Isolate isolate) {
    var crashed = _endpoints.where((endpoint) => endpoint.isolate == isolate);

    List<Endpoint> remove = [];

    for (var endpoint in crashed) {
      var keys = _table.keys.map((k) => _table[k] == endpoint);
      keys.forEach(_table.remove);
      remove.add(endpoint);
      loadBalancer.triggerCrash(endpoint);
    }

    remove.forEach(_endpoints.remove);
  }

  @override
  void onEndpoint(LoadBalancer loadBalancer, Endpoint endpoint) =>
      _endpoints.add(endpoint);
}
