# multiserver
Support for running Angel applications across multiple servers.

The idea is that you have one master server running the load balancer,
and the child applications call a session synchronizer.

Dedicated WebSocket support will come eventually.

# Load Balancing

This package exposes a `LoadBalancer` class, which can be called as a
middleware. The default implementation is a simple round-robin, but
it can be extended for your own purposes.

```dart
import 'dart:async';
import 'dart:io';
import 'package:angel_framework/angel_framework.dart';
import 'package:angel_multiserver/angel_multiserver.dart';

Future<Angel> spawnChildServer() async {
    // Return a new instance of your
    // main application here.
}

main() async {
    var masterApp = new Angel();
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

    var server = await masterApp
        .startServer(InternetAddress.LOOPBACK_IP_V4, 3000);
    print('Load balancer listening at ${server.address.address}:${server.port}');
}
```

# Session Synchronization

This package also includes three `SessionSynchronizer` classes:
* MongoDB
* Memcached
* Redis

These are simply plugins that serialize and deserialize session data
to external data stores. Try to call them as early as possible in your
application, so that session data is loaded before any business logic.

```dart
import 'package:angel_framework/angel_framework.dart';
import 'package:angel_multiserver/angel_multiserver.dart';
import 'package:mongo_dart/mongo_dart.dart';

main() async {
    var app = new Angel();
    var db = new Db('<connection-string>');
    await db.open();
    await app.configure(
        new MongoSessionSynchronizer(db.collection('sessions')));
}
```
