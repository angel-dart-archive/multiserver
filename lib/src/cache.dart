import 'dart:async';
import 'dart:io';

import 'package:angel_framework/angel_framework.dart';

/// Determines if a response should be cached.
typedef Future<bool> CacheFilter(
    RequestContext request, ResponseContext response);

/// Caches static content to improve response time.
///
/// [filters] must be of the following:
/// * [CacheFilter]
/// * [RegExp]
/// * [String]
///
/// You can add [varyHeaders] as well. If present, then different cached responses
/// will be present for different values of each header. This works well with `Accept-Encoding`
/// or `User-Agent`.
///
/// Default: `HttpHeaders.ACCEPT_ENCODING`
AngelConfigurer cacheResponses(
        {Iterable filters: const [],
        Iterable<String> varyHeaders: const [HttpHeaders.CONTENT_ENCODING],
        bool debug: false}) =>
    new _ResponseCache(
        filters: filters ?? [], varyHeaders: varyHeaders, debug: debug == true);

class _ResponseCache extends AngelPlugin {
  final Map<String, CacheMapping> _cache = {};
  final List<CacheFilter> _filters = [];
  final List<String> _varyHeaders = [];
  final bool debug;

  _ResponseCache(
      {Iterable filters: const [],
      Iterable<String> varyHeaders: const [HttpHeaders.CONTENT_ENCODING],
      this.debug: false}) {
    _varyHeaders.addAll(varyHeaders ?? [HttpHeaders.CONTENT_ENCODING]);

    for (var filter in filters) {
      if (filter is CacheFilter)
        _filters.add(filter);
      else if (filter is RegExp)
        _filters.add((req, res) async => filter.hasMatch(req.path));
      else if (filter is String)
        _filters.add((req, res) async => req.path == filter);
      else
        throw new ArgumentError('$filter is not a valid cache filter.');
    }

    printDebug('Cache filters: $_filters');
  }

  void printDebug(Object object) {
    if (debug) print(object);
  }

  CachedResponse resolveCached(RequestContext req) {
    if (_cache.containsKey(req.path)) {
      var mapping = _cache[req.path];

      if (mapping.responses.isNotEmpty) {
        if (_varyHeaders.isEmpty)
          return mapping.responses.first;
        else
          return mapping.responses.firstWhere((response) {
            for (var key in _varyHeaders) {
              String client = key;

              if (key == HttpHeaders.CONTENT_ENCODING)
                client = HttpHeaders.ACCEPT_ENCODING;
              else if (key == HttpHeaders.CONTENT_TYPE)
                client = HttpHeaders.ACCEPT;
              else if (key.startsWith('accept-'))
                client = key.replaceFirst('accept-', 'content-');

              /*print(
                  'key: $key, client: $client, req: ${req.headers.value(client)} res: ${response.headers[key]}');*/
              if (!response.headers.containsKey(key) ||
                  req.headers[client]?.contains(response.headers[key]) != true)
                return false;
            }

            return true;
          }, orElse: () => null);
      }
    }

    return null;
  }

  Future call(Angel app) async {
    app.before.add((RequestContext req, ResponseContext res) async {
      printDebug(
          'Request path: ${req.path}; In cache? ${_cache.containsKey(req.path)}');

      var response = resolveCached(req);

      if (response != null) {
        try {
          res
            ..buffer.add(response.buffer)
            ..cookies.addAll(response.cookies)
            ..headers.addAll(response.headers)
            ..end();
        } catch (e, st) {
          printDebug('Response caching exception: $e');
          printDebug(st);
          rethrow;
        }
      }

      return true;
    });

    app.responseFinalizers.add((req, res) async {
      bool shouldCache = _filters.isEmpty;

      if (!shouldCache) {
        for (var filter in _filters) {
          if (await filter(req, res) == true) {
            shouldCache = true;
            break;
          }
        }
      }

      if (shouldCache) {
        printDebug('Caching response to ${req.path}');

        CacheMapping mapping;

        if (_cache.containsKey(req.path))
          mapping = _cache[req.path];
        else
          mapping = _cache[req.path] = new CacheMapping();

        mapping.responses.add(new CachedResponse(
            res.statusCode, res.buffer.toBytes(), res.cookies, res.headers));
      }
    });
  }
}

class CacheMapping {
  final List<CachedResponse> responses = [];
}

/// Represents a cached response.
class CachedResponse {
  final List<int> buffer;
  final List<Cookie> cookies;
  final Map<String, String> headers;
  final int statusCode;

  CachedResponse(this.statusCode, this.buffer, this.cookies, this.headers);
}
