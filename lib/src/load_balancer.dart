import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'package:angel_framework/angel_framework.dart';
import 'package:string_scanner/string_scanner.dart';
import 'defs.dart';

final RegExp _decl = new RegExp(r'([^\s]+) ([^\s]+) HTTP/([^\n]+)');
final RegExp _header = new RegExp(r'([^:]+):\s*([\n]+)');

/// Distributes requests to different servers.
///
/// The default implementation uses a simple round-robin.
class LoadBalancer {
  final HttpClient _client = new HttpClient();
  int _it = -1;
  ServerSocket _socket;
  final List<Endpoint> endpoints = [];

  final StreamController<Endpoint> _onBoot = new StreamController<Endpoint>();
  final StreamController<Endpoint> _onCrash = new StreamController<Endpoint>();
  final StreamController _onError = new StreamController();
  final StreamController<Socket> _onErrored = new StreamController<Socket>();
  final StreamController<Socket> _onHandled = new StreamController<Socket>();
  final StreamController<Socket> _onUnavailable =
      new StreamController<Socket>();

  /// Fired whenever a new server is started.
  Stream<Endpoint> get onBoot => _onBoot.stream;

  /// Fired whenever a server fails to respond, and is assumed to have crashed.
  ///
  /// This can easily be hooked to spawn a new instance automatically.
  Stream<Endpoint> get onCrash => _onCrash.stream;

  /// Fired whenever a failure to respond occurs. Use this to log errors.
  Stream get onError => _onError.stream;

  /// Fired whenever a failure to respond occurs. Use this to deliver an error message.
  Stream<Socket> get onErrored => _onErrored.stream;

  /// Fired whenever a client is responded to successfully.
  Stream<Socket> get onHandled => _onHandled.stream;

  /// Fired when there is no available server to service a request.
  Stream<Socket> get onUnavailable => _onUnavailable.stream;

  /// The socket we are listening on.
  ServerSocket get socket => _socket;

  /// Interacts with an incoming client.
  Future handleClient(Socket client) async {
    client.listen(
        (buf) async {
          try {
            var endpoint = await nextEndpoint();

            if (endpoint == null) {
              _onUnavailable.add(client);
              return;
            }

            try {
              var sock = await Socket.connect(endpoint.address, endpoint.port);
              sock.add(buf);
              await sock.flush();
              var rs = await sock.close();
              await client.addStream(rs);
              await client.flush();
              _onHandled.add(client);
            } catch (e) {
              endpoints.remove(endpoint);
              _onCrash.add(endpoint);
              rethrow;
            }
          } catch (e) {
            _onError.add(e);
            _onErrored.add(client);
          }
        },
        onDone: () => client.close(),
        onError: (e) {
          _onError.add(e);
          _onErrored.add(client);
        },
        cancelOnError: true);
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
      var endpoint = new Endpoint(server.address, server.port);
      endpoints.add(endpoint);
      _onBoot.add(endpoint);
      spawned.add(app);
    }

    return spawned;
  }

  /// Spawns a number of instances via isolates. This is the preferred method.
  ///
  /// Usually this will be a `bin/cluster.dart` file.
  Future<List<Isolate>> spawnIsolates(Uri uri,
      {int count: 1, List<String> args: const []}) async {
    List<Isolate> spawned = [];

    for (int i = 0; i < count; i++) {
      var onEndpoint = new ReceivePort(), onError = new ReceivePort();

      var isolate = await Isolate.spawnUri(uri, args, onEndpoint.sendPort,
          onError: onError.sendPort, errorsAreFatal: true, paused: true);
      spawned.add(isolate);

      var onExit = new ReceivePort();
      isolate.addOnExitListener(onExit.sendPort, response: 'FAILURE');
      isolate.resume(isolate.pauseCapability);

      onEndpoint.first.then((msg) async {
        if (msg is List && msg.length >= 2) {
          var lookup = await InternetAddress.lookup(msg[0]);

          if (lookup.isEmpty) return;

          var address = lookup.first;
          int port = msg[1];
          var endpoint = new Endpoint(address, port, isolate: isolate);
          endpoints.add(endpoint);
          _onBoot.add(endpoint);
        }
      });

      onError.listen(_onError.add);

      onExit.listen((_) {
        var crashed =
            endpoints.where((endpoint) => endpoint.isolate == isolate);

        for (var endpoint in crashed) {
          endpoints.remove(endpoint);
          _onCrash.add(endpoint);
        }
      });
    }

    return spawned;
  }

  /// Starts listening at the given host and port.
  ///
  /// This defaults to `0.0.0.0:3000`.
  Future<ServerSocket> startServer([address, int port = 3000]) async {
    var socket = await ServerSocket.bind(
        address ?? InternetAddress.ANY_IP_V4, port ?? 3000);
    return _socket = socket..listen(handleClient);
  }
}
