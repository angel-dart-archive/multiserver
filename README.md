# multiserver
Support for running Angel applications across multiple servers.

The idea is that you have one master server running the load balancer,
and the child applications call a session synchronizer.

Dedicated WebSocket support will come eventually.

See the [examples](example);

# Response Caching
This plug-in works on any `Angel` server, not just a `LoadBalancer`.
It caches responses, to lower future response times.

# Load Balancing

This package exposes a `LoadBalancer` class, which extends `Angel`,
and can be used like a normal server.

The default algorithm is a simple round-robin, but
it can be extended for your own purposes.

Three load-balancing algorithms are included:
* `ROUND_ROBIN` (default)
* `LEAST_LATENCY`
* `STICKY_SESSION`

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
