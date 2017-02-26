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
  HttpServer _server;

  ServerGenerator _serverGenerator = HttpServer.bind;

  /// Distributes requests between servers.
  LoadBalancingAlgorithm get algorithm => _algorithm;

  @override
  HttpServer get httpServer => _server ?? super.httpServer;

  /// If set to `true`, the load balancer will manage
  /// synchronized sessions.
  final bool sessionAware;

  /// The maximum amount of time to wait for a client server to respond before
  /// throwing a `504 Gateway Timeout` error.
  final int timeoutThreshold;

  LoadBalancer(
      {LoadBalancingAlgorithm algorithm,
      bool debug: false,
      this.sessionAware: true,
      this.timeoutThreshold: 5000})
      : super(debug: debug == true) {
    _algorithm = algorithm ?? ROUND_ROBIN;
    storeOriginalBuffer = true;
  }

  factory LoadBalancer.custom(ServerGenerator serverGenerator,
      {LoadBalancingAlgorithm algorithm,
      bool debug: false,
      bool sessionAware: true,
      int timeoutThreshold: 5000}) {
    return new LoadBalancer(
        algorithm: algorithm,
        debug: debug == true,
        sessionAware: sessionAware == true,
        timeoutThreshold: timeoutThreshold ?? 5000)
      .._serverGenerator = serverGenerator;
  }

  factory LoadBalancer.fromSecurityContext(SecurityContext context,
      {LoadBalancingAlgorithm algorithm,
      bool debug: false,
      bool sessionAware: true,
      int timeoutThreshold: 5000}) {
    return new LoadBalancer.custom(
        (InternetAddress address, int port) async =>
            HttpServer.bindSecure(address, port, context),
        algorithm: algorithm,
        debug: debug == true,
        sessionAware: sessionAware == true,
        timeoutThreshold: timeoutThreshold ?? 5000);
  }

  factory LoadBalancer.secure(String certificateChainPath, String serverKeyPath,
      {LoadBalancingAlgorithm algorithm,
      bool debug: false,
      String password,
      bool sessionAware: true,
      int timeoutThreshold: 5000}) {
    var context = new SecurityContext()
      ..useCertificateChain(
          Platform.script.resolve(certificateChainPath).toFilePath(),
          password: password)
      ..usePrivateKey(Platform.script.resolve(serverKeyPath).toFilePath(),
          password: password);
    return new LoadBalancer.fromSecurityContext(context,
        algorithm: algorithm,
        debug: debug == true,
        sessionAware: sessionAware == true,
        timeoutThreshold: timeoutThreshold ?? 5000);
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
    return (RequestContext req, ResponseContext res) {
      return algorithm.nextEndpoint(this, req).then((endpoint) {
        if (endpoint == null) return true;
        var c = new Completer();

        Timer timer;

        timer =
            new Timer(new Duration(milliseconds: timeoutThreshold ?? 5000), () {
          if (timer.isActive) {
            timer.cancel();
            c.completeError(new AngelHttpException(null,
                message: '504 Gateway Timeout', statusCode: 504));
          }
        });

        dispatchRequest(req, endpoint).then((rs) async {
          if (timer.isActive) {
            timer.cancel();
            await algorithm.pipeResponse(rs, res);
            c.complete(false);
          }
        }).catchError((e) {
          if (timer.isActive) timer.cancel();

          if (e is! AngelHttpException) triggerCrash(endpoint);
          throw e;
        });

        return c.future;
      });
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
    if (_serverGenerator != null) {
      app.after.insert(0, handler());
      _server = (await _serverGenerator(
          address ?? InternetAddress.LOOPBACK_IP_V4, port ?? 0))
        ..listen(handleRequest);
    } else {
      justBeforeStart.add((Angel app) {
        app.after.insert(0, handler());
      });
      _server = await super.startServer(address, port);
    }

    print("Load balancer using '${algorithm.name}' algorithm");
    return _server;
  }

  void triggerCrash(Endpoint endpoint) => _onCrash.add(endpoint);
}
