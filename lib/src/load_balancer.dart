import 'dart:async';
import 'dart:isolate';
import 'dart:io';
import 'package:angel_framework/angel_framework.dart';
import 'package:random_string/random_string.dart' as rs;
import 'algorithm.dart';
import 'defs.dart';
import 'interceptor.dart';

final RegExp _decl = new RegExp(r'([^\s]+) ([^\s]+) HTTP/([^\n]+)');
final RegExp _header = new RegExp(r'([^:]+):\s*([\n]+)');

/// Distributes requests to different servers.
///
/// The default implementation uses a simple round-robin.
class LoadBalancer extends Angel {
  String _certificateChainPath, _serverKeyPath;
  final HttpClient _client = new HttpClient();
  bool _secure = false;
  ServerSocket _socket;

  /// Distributes requests between servers.
  final LoadBalancingAlgorithm algorithm;

  int index = -1;

  /// A dynamic list of endpoints registered with the load balancer.
  ///
  /// Do not modify, please. :)
  final List<Endpoint> endpoints = [];

  /// Middleware to run before requests.
  final List<RequestInterceptor> requestInterceptors = [];

  /// Middleware to run after dispatched responses are received.
  final List<RequestInterceptor> responseInterceptors = [];

  /// Used for [STICKY_SESSION].
  final Map<InternetAddress, Endpoint> sticky = {};

  /// If set to `true`, the load balancer will manage
  /// synchronized sessions.
  final bool sessionAware;

  LoadBalancer({this.algorithm: ROUND_ROBIN, this.sessionAware: true});

  LoadBalancer.secure(this._certificateChainPath, this._serverKeyPath,
      {this.algorithm: ROUND_ROBIN, this.sessionAware: true}) {
    _secure = true;
  }

  final StreamController<Endpoint> _onBoot = new StreamController<Endpoint>();
  final StreamController<Endpoint> _onCrash = new StreamController<Endpoint>();
  final StreamController<HttpRequest> _onErrored =
      new StreamController<HttpRequest>();
  final StreamController _fatalErrorStream = new StreamController();
  final StreamController<HttpRequest> _onHandled =
      new StreamController<HttpRequest>();

  /// Fired whenever a new server is started.
  Stream<Endpoint> get onBoot => _onBoot.stream;

  /// Fired whenever a server fails to respond, and is assumed to have crashed.
  ///
  /// This can easily be hooked to spawn a new instance automatically.
  Stream<Endpoint> get onCrash => _onCrash.stream;

  /// Fired whenever a failure to respond occurs. Use this to deliver an error message.
  Stream<HttpRequest> get onErrored => _onErrored.stream;

  /// Fired when a fatal error occurs while trying to dispatch a request.
  Stream get onDistributionError => _fatalErrorStream.stream;

  /// Fired whenever a client is responded to successfully.
  Stream<HttpRequest> get onHandled => _onHandled.stream;

  /// The socket we are listening on.
  ServerSocket get socket => _socket;

  /// Forwards a request to the [endpoint].
  Future<HttpClientResponse> dispatchRequest(HttpRequest request, Endpoint endpoint) async {
    var rq = await _client.open(request.method, endpoint.address.address,
        endpoint.port, request.uri.toString());

    if (request.headers.contentType != null)
      rq.headers.contentType = request.headers.contentType;

    rq.cookies.addAll(request.cookies);
    copyHeaders(request.headers, rq.headers);

    if (request.headers[HttpHeaders.ACCEPT] == null) {
      request.headers.set(HttpHeaders.ACCEPT, '*/*');
    }

    rq.headers
      ..add('X-Forwarded-For', request.connectionInfo.remoteAddress.address)
      ..add('X-Forwarded-Port', request.connectionInfo.remotePort.toString())
      ..add(
          'X-Forwarded-Host',
          request.headers.host ??
              request.headers.value(HttpHeaders.HOST) ??
              'none')
      ..add('X-Forwarded-Proto', _secure ? 'https' : 'http');
    await rq.addStream(request);
    return await rq.close();
  }

  @override
  Future handleRequest(HttpRequest request) async {
    try {
      for (var interceptor in requestInterceptors) {
        if (await interceptor(request) != true) return;
      }

      var endpoint = await algorithm.nextEndpoint(this, request);

      if (endpoint == null) {
        await super.handleRequest(request);
        return;
      }

      try {
        var rs = await dispatchRequest(request, endpoint);

        for (var interceptor in responseInterceptors) {
          if (await interceptor(response) != true) return;
        }

        final HttpResponse r = request.response;
        await algorithm.pipeResponse(rs, r);
        return;
      } catch (e) {
        triggerCrash(endpoint);
        rethrow;
      }
    } catch (e) {
      _fatalErrorStream.add(e);
      _onErrored.add(request);
    }
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

      onError.listen(_fatalErrorStream.add);

      onExit.listen((_) {
        algorithm.onCrashed(this, isolate);
      });
    }

    return spawned;
  }

  @override
  Future<HttpServer> startServer([InternetAddress address, int port]) {
    if (_secure) {
      var certificateChain =
          Platform.script.resolve(_certificateChainPath).toFilePath();
      var serverKey = Platform.script.resolve(_serverKeyPath).toFilePath();
      var serverContext = new SecurityContext();
      serverContext.useCertificateChain(certificateChain);
      serverContext.usePrivateKey(serverKey,
          password: password ?? rs.randomAlphaNumeric(8));

      return HttpServer.bindSecure(
          address ?? InternetAddress.LOOPBACK_IP_V4, port ?? 0, serverContext);
    }

    return super.startServer(address, port);
  }

  void triggerCrash(Endpoint endpoint) {
    _onCrash.add(endpoint);
  }
}
