/// Represents an IP endpoint.

import 'dart:io';

class Endpoint {
  final InternetAddress address;
  final int port;

  Endpoint(this.address, this.port);
}