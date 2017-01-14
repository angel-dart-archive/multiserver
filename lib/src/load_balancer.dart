import 'dart:async';
import 'dart:isolate';
import 'dart:io';
import 'package:angel_framework/angel_framework.dart';
import 'package:random_string/random_string.dart' as rs;
import 'algorithm.dart';
import 'defs.dart';

final RegExp _decl = new RegExp(r'([^\s]+) ([^\s]+) HTTP/([^\n]+)');
final RegExp _header = new RegExp(r'([^:]+):\s*([\n]+)');

/// Distributes requests to different servers.
///
/// The default implementation uses a simple round-robin.
class LoadBalancer extends Angel {
  LoadBalancingAlgorithm _algorithm;
  String _certificateChainPath, _serverKeyPath;
  final HttpClient _client = new HttpClient();
  bool _secure = false;
  HttpServer _server;

  /// Distributes requests between servers.
  LoadBalancingAlgorithm get algorithm => _algorithm;

  @override
  HttpServer get httpServer => _server ?? super.httpServer;

  /// If set to `true`, the load balancer will manage
  /// synchronized sessions.
  final bool sessionAware;

  LoadBalancer(
      {LoadBalancingAlgorithm algorithm,
      bool debug: false,
      this.sessionAware: true})
      : super(debug: debug == true) {
    _algorithm = algorithm ?? ROUND_ROBIN;
    storeOriginalBuffer = true;
  }

  LoadBalancer.secure(this._certificateChainPath, this._serverKeyPath,
      {LoadBalancingAlgorithm algorithm,
      bool debug: false,
      this.sessionAware: true})
      : super(debug: debug == true) {
    _secure = true;
    _algorithm = algorithm ?? ROUND_ROBIN;
    storeOriginalBuffer = true;
  }

  final StreamController<Endpoint> _onBoot = new StreamController<Endpoint>();
  final StreamController<Endpoint> _onCrash = new StreamController<Endpoint>();

  /// Fired whenever a new server is started.
  Stream<Endpoint> get onBoot => _onBoot.stream;

  /// Fired whenever a server fails to respond, and is assumed to have crashed.
  ///
  /// This can easily be hooked to spawn a new instance automatically.
  Stream<Endpoint> get onCrash => _onCrash.stream;

  /// Forwards a request to the [endpoint].
  Future<HttpClientResponse> dispatchRequest(
      RequestContext req, Endpoint endpoint) async {
    var rq = await _client.open(req.method, endpoint.address.address,
        endpoint.port, req.uri.toString());

    if (req.headers.contentType != null)
      rq.headers.contentType = req.headers.contentType;

    rq.cookies.addAll(req.cookies);
    copyHeaders(req.headers, rq.headers);

    if (req.headers[HttpHeaders.ACCEPT] == null) {
      req.headers.set(HttpHeaders.ACCEPT, '*/*');
    }

    rq.headers
      ..add('X-Forwarded-For', req.ip)
      ..add('X-Forwarded-Port', req.io.connectionInfo.remotePort.toString())
      ..add('X-Forwarded-Host',
          req.headers.host ?? req.headers.value(HttpHeaders.HOST) ?? 'none')
      ..add('X-Forwarded-Proto', _secure ? 'https' : 'http');

    if (req.originalBuffer.isNotEmpty) rq.add(req.originalBuffer);
    return await rq.close();
  }

  /// Angel middleware to distribute requests.
  RequestHandler handler() {
    return (RequestContext req, ResponseContext res) async {
      var endpoint = await algorithm.nextEndpoint(this, req);
      if (endpoint == null) return true;

      try {
        var rs = await dispatchRequest(req, endpoint);
        /*res
          ..willCloseItself = true
          ..end();*/
        await algorithm.pipeResponse(rs, res);
        return false;
      } catch (e) {
        triggerCrash(endpoint);
        rethrow;
      }
    };
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

      onEndpoint.listen((msg) async {
        if (msg is List && msg.length >= 2) {
          var lookup = await InternetAddress.lookup(msg[0]);

          if (lookup.isEmpty) return;

          var address = lookup.first;
          int port = msg[1];
          var endpoint = new Endpoint(address, port, isolate: isolate);
          _onBoot.add(endpoint);
          algorithm.onEndpoint(this, endpoint);
        }
      });

      void mayday(_) => algorithm.onCrashed(this, isolate);
      onError.listen(mayday);
      onExit.listen(mayday);
    }

    return spawned;
  }

  @override
  Future<HttpServer> startServer([InternetAddress address, int port]) async {
    after.insert(0, handler());

    if (_secure) {
      var certificateChain =
          Platform.script.resolve(_certificateChainPath).toFilePath();
      var serverKey = Platform.script.resolve(_serverKeyPath).toFilePath();
      var serverContext = new SecurityContext();
      serverContext.useCertificateChain(certificateChain);
      serverContext.usePrivateKey(serverKey,
          password: password ?? rs.randomAlphaNumeric(8));

      _server = await HttpServer.bindSecure(
          address ?? InternetAddress.LOOPBACK_IP_V4, port ?? 0, serverContext);
      _server.listen(handleRequest);
    } else
      _server = await super.startServer(address, port);

    print("Load balancer using '${algorithm.name}' algorithm");
    return _server;
  }

  void triggerCrash(Endpoint endpoint) => _onCrash.add(endpoint);
}
