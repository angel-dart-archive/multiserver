import 'dart:io';
import 'dart:isolate';
import 'package:angel_compress/angel_compress.dart';
import 'package:angel_diagnostics/angel_diagnostics.dart';
import 'package:angel_framework/angel_framework.dart';
import 'package:angel_multiserver/angel_multiserver.dart';
import 'package:memcached_client/memcached_client.dart';

main(args, SendPort sendPort) async {
  var app = new Angel();

  var client =
      await MemcachedClient.connect([new SocketAddress('127.0.0.1', 11211)]);
  await app.configure(new MemcachedSessionSynchronizer(client));

  app.before.add((req, res) async {
    print('Incoming headers: ${req.headers}');
    print('Incoming body: ${req.body}');
    return true;
  });

  app.get('/', (req, res) async {
    res
      ..contentType = ContentType.HTML
      ..write('''
    <!DOCTYPE html>
    <html>
      <head>
        <title>Cluster</title>
      </head>
      <body>
        <h1>Instance: #${app.hashCode}</h1>
        <i>Session: ${req.session}</i>
        <br>
        <a href="/clear">Clear session data</a>
        <br>
        <b>Set session data:</b>
        <br>
        <form action="/session" method="post">
          <input name="key" placeholder="Key to set" type="text">
          <br>
          <input name="value" placeholder="Value" type="text">
          <br>
          <input type="submit" value="Ok">
        </form>
      </body>
    </html>
    ''');
    return false;
  });

  app.post('/session', (RequestContext req, res) async {
    if (!req.body.containsKey('key') || !req.body.containsKey('value')) {
      throw new AngelHttpException.BadRequest();
    }

    req.session[req.body['key']] = req.body['value'];
    return res.redirect('/');
  });

  app.get('/clear', (req, res) async {
    req.session.clear();
    return res.redirect('/');
  });

  app.all('*', () => throw new AngelHttpException.NotFound());

  app.responseFinalizers
    ..add((req, res) async {
      print('Outgoing cookies: ${res.cookies}');
      print('Outgoing headers: ${res.headers}');
    })
    ..add(gzip());

  var server =
      await new DiagnosticsServer(app, new File('log.txt')).startServer();
  sendPort?.send([server.address.address, server.port]);
}
