import 'package:angel_framework/angel_framework.dart';

final RegExp _leadingSlashes = new RegExp(r'^\/+');

/// Redirects HTTP requests to an equivalent HTTPS URL.
RequestHandler forceHttps({String mapTo}) {
  return (RequestContext req, ResponseContext res) async {
    var host = req.hostname;
    var path = req.uri.path.replaceAll(_leadingSlashes, '');

    if (mapTo?.isNotEmpty == true) {
      path = mapTo.replaceAll(_leadingSlashes, '') + '/' + path;
    }

    res.redirect('https://$host/$path');
  };
}
