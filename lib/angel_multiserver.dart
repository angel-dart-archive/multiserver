library angel_multiserver;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:angel_framework/angel_framework.dart';
import 'package:mongo_dart/mongo_dart.dart';

typedef void AngelSpawner(SendPort sendPort);

typedef AngelIsolateStarter(HttpRequest request);

class MultiServer extends Angel {
  static String dbUri = "mongodb://localhost:27017/multiserver_test_db";
  HttpClient client = new HttpClient();
  num currentInstanceIndex = 0;

  List<Map<String, dynamic>> availableHosts = [];
  List<Angel> instances = [];

  MultiServer() : super();

  MultiServer.secure(String certificateChainPath, String serverKeyPath,
      {String password})
      : super.secure(certificateChainPath, serverKeyPath, password: password);

  static defaultAngelIsolateStarter(SendPort sendPort) {
    var host = InternetAddress.LOOPBACK_IP_V4;
    var port = 0;

    var app = new Angel();

    app.get("/", (req, res) async {
      return "Accessed via instance #${app.hashCode}, listening on ${host
              .address}:$port ${req.session}";
    });

    app.get("/err", (req, res) async => throw new Exception("Hey"));

    app.startServer(host, port).then((HttpServer server) {
      sendPort.send({"address": server.address.address, "port": server.port});
    });
  }

  static AngelConfigurer sessionSynchronizer(Db db) {
    return (Angel app) async {
      var collection = db.collection("angel_multiserver.sessions");

      app.before.insert(0, (HttpRequest request) async {
        var session =
            await collection.findOne(where.eq("sessionId", request.session.id));

        if (session != null) {
          request.session.addAll(session['data']);
        }
      });

      app.afterProcessed.asBroadcastStream(
          onListen: (StreamSubscription<HttpRequest> sub) {
        sub.onData((HttpRequest request) {
          if (request.session.isNew) {
            collection.insert({
              "sessionId": request.session.id,
              "data": new Map.from(request.session)
            }).then((_) {});
          }
        });
      });
    };
  }

  Future spawn(int nInstances) async {
    for (int i = 0; i <= nInstances; i++) {
      await createAsyncWorker();
    }
  }

  Future<Isolate> createAsyncWorker() async {
    var recv = new ReceivePort()
      ..listen((Map host) {
        availableHosts.add(host);
      })
      ..handleError((e, st) {
        // When an isolate fails, start a new one
        spawn(1);
      });

    var exit = new ReceivePort()
      ..listen((_) {
        spawn(1);
      });

    return await Isolate.spawn(defaultAngelIsolateStarter, recv.sendPort,
        onExit: exit.sendPort, onError: exit.sendPort);
  }

  @override
  Future handleRequest(HttpRequest request) async {
    // Advance to next instance
    if (++currentInstanceIndex >= availableHosts.length)
      currentInstanceIndex = 0;

    // Find an available instance
    var host = availableHosts[currentInstanceIndex];

    // Forward the request to instance
    var clientRequest = await client.open(
        request.method, host['address'], host['port'], request.uri.toString());
    await clientRequest.addStream(request);

    // Return response to client
    var response = await clientRequest.close();
    await response.pipe(request.response);
  }
}
