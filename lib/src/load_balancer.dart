import 'dart:async';
import 'dart:io';
import 'package:angel_framework/angel_framework.dart';
import 'defs.dart';

/// Distributes requests to different servers.
///
/// The default implementation uses a simple round-robin.
class LoadBalancer extends AngelMiddleware {
  final HttpClient _client = new HttpClient();
  int _it = -1;
  final List<Endpoint> endpoints = [];

  final StreamController<Endpoint> _onCrash = new StreamController<Endpoint>();

  /// Fired whenever a server fails to respond, and is assumed to have crashed.
  ///
  /// This can easily be hooked to spawn a new instance automatically.
  Stream<Endpoint> get onCrash => _onCrash.stream;

  @override
  Future<bool> call(RequestContext req, ResponseContext res) async {
    Endpoint endpoint;
    int tried = 0;

    while (tried < endpoints.length) {
      try {
        tried++;
        endpoint = await nextEndpoint();

        if (endpoint == null) {
          // If there is no server available, don't bother
          // waiting any longer.
          return true;
        }

        res
          ..willCloseItself = true
          ..end();

        final rq = await _client.open(req.method, endpoint.address.address,
            endpoint.port, req.uri.toString());
        await rq.addStream(req.io);
        final HttpClientResponse rs = await rq.close();
        final HttpResponse r = res.io;
        await pipeResponse(rs, r, res);
        return false;
      } catch (e, st) {
        // Oops, that's a dead server!
        endpoints.remove(endpoint);
        _onCrash.add(endpoint);
      }
    }

    // If we couldn't forward the request, go on to the next handler
    // ... Which may throw an error, who knows...
    return true;
  }

  /// Chooses the next endpoint to forward a request to.
  Future<Endpoint> nextEndpoint() async {
    if (endpoints.isEmpty) return null;

    if (_it++ < endpoints.length - 1)
      return endpoints[_it];
    else
      return endpoints[_it = 0];
  }

  /// Forwards [rs] to [r].
  ///
  /// Override this to compress the response, etc.
  Future pipeResponse(
      HttpClientResponse rs, HttpResponse r, ResponseContext res) async {
    r.statusCode = rs.statusCode;
    r.headers.contentType = rs.headers.contentType;
    await r.addStream(rs);
    await r.flush();
    await r.close();
  }

  /// Spawns a number of Angel instances.
  ///
  /// `spawner` should return an [Angel] instance, or [Future]<[Angel]>.
  Future<List<Angel>> spawn(spawner(), {int count: 1}) async {
    List<Angel> spawned = [];

    for (int i = 0; i < count; i++) {
      Angel app = await spawner();
      var server = await app.startServer();
      endpoints.add(new Endpoint(server.address, server.port));
      spawned.add(app);
    }

    return spawned;
  }
}
