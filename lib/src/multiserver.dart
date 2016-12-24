import 'dart:async';
import 'dart:io';
import 'package:angel_framework/angel_framework.dart';
import 'package:http_multi_server/http_multi_server.dart';

/// An [Angel] instance that listens on multiple network interfaces.
class MultiServer extends Angel {
  HttpServer _server;

  @override
  HttpServer get httpServer => _server;

  MultiServer() : super() {}

  /// A [MultiServer] that listens for HTTPS.
  factory MultiServer.secure(SecurityContext context,
          {int backlog,
          bool v6Only: false,
          bool requestClientCertificate: false,
          bool shared: false}) =>
      new _SecureMultiServer(context,
          backlog: backlog,
          v6Only: v6Only,
          requestClientCertificate: requestClientCertificate,
          shared: shared);

  @override
  Future<HttpServer> startServer([InternetAddress address, int port]) async {
    var server = await HttpMultiServer.loopback(port ?? 0);
    return _server = server..listen(handleRequest);
  }
}

class _SecureMultiServer extends MultiServer {
  final SecurityContext context;
  final int backlog;
  final bool v6Only, requestClientCertificate, shared;

  _SecureMultiServer(this.context,
      {this.backlog, this.v6Only, this.requestClientCertificate, this.shared});

  @override
  Future<HttpServer> startServer([InternetAddress address, int port]) async {
    var server = await HttpMultiServer.loopback(port ?? 0);
    return _server = server..listen(handleRequest);
  }
}
