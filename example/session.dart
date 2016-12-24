import 'dart:async';
import 'dart:io';
import 'package:angel_framework/angel_framework.dart';
import 'package:angel_multiserver/angel_multiserver.dart';
import 'package:mongo_dart/mongo_dart.dart';

Future<Angel> spawnChildServer() async {
  var app = new Angel();
  var db = new Db('mongodb://localhost:27017/angel_multiserver_example');
  await db.open();

  await app.configure(new MongoSessionSynchronizer(db.collection('sessions')));

  app
    ..get('/', (req, res) async {
      res
        ..contentType = ContentType.HTML
        ..write('''
        <!DOCTYPE html>
        <html>
          <head>
            <title>Session Example</title>
          </head>
          <body>
            <h1>Session Example</h1>
            <i>Session data: ${req.session}</i>
            <form action="/session" method="post">
              <input type="text" name="key" placeholder="Key to set">
              <br>
              <input type="text" name="value" placeholder="Value of key">
              <br>
              <input type="submit" value="Ok">
            </form>
          </body>
        </html>
        ''')
        ..end();
    });

  app.post('/session', (req, res) async {
    req.session[req.body['key']] = req.body['value'];
    return res.redirect('/');
  });

  return app;
}

main() async {
  var masterApp = new MultiServer();
  var loadBalancer = new LoadBalancer();

  loadBalancer
    ..spawn(spawnChildServer, count: 3)
    ..onCrash.listen((endpoint) async {
      // When a server fails to respond, it is removed
      // from the list, and an event is fired.
      // Use this to automatically re-spawn your application.
      await loadBalancer.spawn(spawnChildServer);
    });

  masterApp.chain(loadBalancer).all('*', (req, res) async {
    res
      ..statusCode = HttpStatus.SERVICE_UNAVAILABLE
      ..write('There is no server available to service the request.')
      ..end();
  });

  var server =
      await masterApp.startServer(InternetAddress.LOOPBACK_IP_V4, 3000);
  print('Load balancer listening at ${server.address.address}:${server.port}');
}
