/// Represents an IP endpoint.

import 'dart:io';
import 'dart:isolate';

class Endpoint {
  final InternetAddress address;
  final int port;
  Isolate isolate;

  Endpoint(this.address, this.port, {this.isolate});

  @override
  String toString() => '${address.address}:$port';
}