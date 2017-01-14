/// Represents an IP endpoint.

import 'dart:io';
import 'dart:isolate';

final RegExp _endpoint =
    new RegExp(r'(([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)):([0-9]+)');

class Endpoint {
  final InternetAddress address;
  final int port;
  Isolate isolate;

  Endpoint(this.address, this.port, {this.isolate});

  /// Parses an endpoint from an `IP:port` string.
  factory Endpoint.parse(String endpoint, {Isolate isolate}) {
    var match = _endpoint.firstMatch(endpoint);

    if (match == null)
      throw new ArgumentError(
          'Invalid endpoint string. Expected IP:port format.');

    return new Endpoint(new InternetAddress(match[1]), int.parse(match[2]));
  }

  @override
  String toString() => '${address.address}:$port';
}

/// Copies HTTP headers ;)
void copyHeaders(HttpHeaders from, HttpHeaders to) {
  to
    ..chunkedTransferEncoding = from.chunkedTransferEncoding
    ..contentLength = from.contentLength
    ..contentType = from.contentType
    ..host = from.host
    ..persistentConnection = from.persistentConnection
    ..port = from.port;

  if (from.date != null)
    to.date = from.date;
  else
    to.date = new DateTime.now();

  if (from.expires != null)
    to.expires = from.expires;
  else
    to.expires = new DateTime.now();

  if (from.ifModifiedSince != null)
    to.ifModifiedSince = from.ifModifiedSince;
  else
    to.ifModifiedSince = new DateTime.now();

  from.forEach((header, values) {
    to.set(header, values);
  });
}
