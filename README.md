# multiserver
Support for running Angel applications across multiple servers.

The idea is that you have one master server running the load balancer,
and the child applications call a session synchronizer.

Dedicated WebSocket support will come eventually.

See the [examples](example);

# Load Balancing

This package exposes a `LoadBalancer` class. 
The default implementation is a simple round-robin, but
it can be extended for your own purposes.


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
