import 'dart:async';
import 'dart:io';
import 'defs.dart';

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
AngelConfigurer cacheResponses(
        {Iterable filters: const [], bool debug: false}) =>
    new _ResponseCache(filters: filters ?? [], debug: debug == true);

class _ResponseCache extends AngelPlugin {
  final Map<String, CachedResponse> _cache = {};
  final List<CacheFilter> _filters = [];
  final bool debug;

  _ResponseCache({Iterable filters: const [], this.debug: false}) {
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

  Future call(Angel app) async {
    app.before.add((RequestContext req, ResponseContext res) async {
      printDebug(
          'Request path: ${req.path}; In cache? ${_cache.containsKey(req.path)}');
      if (_cache.containsKey(req.path)) {
        try {
          var response = _cache[req.path];
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
        _cache[req.path] = new CachedResponse(
            res.statusCode, res.buffer.toBytes(), res.cookies, res.headers);
      }
    });
  }
}

/// Represents a cached request.
class CachedResponse {
  final List<int> buffer;
  final List<Cookie> cookies;
  final HttpHeaders headers;
  final int statusCode;

  CachedResponse(this.statusCode, this.buffer, this.cookies, this.headers);
}
