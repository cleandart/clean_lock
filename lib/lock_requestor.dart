library clean_lock.lock_requestor;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:useful/socket_jsonizer.dart';

class LockRequestor {

  Map <String, Completer> requestors = {};
  Socket _lockerSocket;
  num _lockIdCounter = 0;
  String prefix = (new Random(new DateTime.now().millisecondsSinceEpoch % (1<<20))).nextDouble().toString();

  String url;
  int port;


  Future get done => _lockerSocket.done;

  LockRequestor.fromSocket(this._lockerSocket) {
    _initListeners();
  }

  LockRequestor(this.url, this.port);

  Future init() =>
      Socket.connect(url, port)
        .then((Socket socket) => _lockerSocket = socket)
        .then((_) => _initListeners());

  _initListeners() {
    toJsonStream(_lockerSocket).listen((Map resp) {
      Completer completer = requestors.remove(resp["requestId"]);
      if (resp.containsKey("error")) {
        completer.completeError(resp["error"]);
      } else if (resp.containsKey("result")) {
        completer.complete();
      }
    });
  }

  static Future<LockRequestor> connect(url, port) =>
    Socket.connect(url, port).then((Socket socket) => new LockRequestor.fromSocket(socket))
      .catchError((e,s) => throw new Exception("LockRequestor was unable to connect to url: $url, port: $port, (is Locker running?)"));

  // Obtains lock and returns unique ID for the holder
  Future<String> _getLock(String lockType) {
    Completer completer = _sendRequest(lockType, "get");
    return completer.future;
  }

  Future _releaseLock(String lockType) {
    Completer completer = _sendRequest(lockType, "release");
    return completer.future;
  }

  getZoneMetaData() => Zone.current[#meta];

  Future withLock(String lockType, callback(), {dynamic metaData: null}) {
       // Check if the zone it was running in was already finished
       if ((Zone.current[#finished] != null) && (Zone.current[#finished]['finished'])) {
         throw new Exception("Zone finished but withLock was called (maybe some future not waited for?)");
       }
       // Check if the lock is already acquired
       if ((Zone.current[#locks] != null) && Zone.current[#locks].contains(lockType)) {
         return new Future.sync(callback);
       } else {
         // It's not running in any Zone yet or lock is not acquired
         return runZoned(() {
           return _getLock(lockType)
            .then((_) => new Future.sync(callback))
            .whenComplete(() => _releaseLock(lockType))
            .catchError((e,s) => print("error: $e"))
            .then((_) => (Zone.current[#locks] as Set).remove(lockType))
            .then((_) => Zone.current[#finished]['finished'] = true);
         }, zoneValues: {
           #locks: Zone.current[#locks] == null ? new Set.from([lockType]) : (new Set.from(Zone.current[#locks]))..add(lockType),
           #meta: metaData,
           #finished: {"finished" : false}
         });
       }
     }

  _sendRequest(String lockType, String action) {
    var requestId = "$prefix--$_lockIdCounter";
    _lockIdCounter++;
    Completer completer = new Completer();
    requestors[requestId] = completer;
    writeJSON(_lockerSocket, {"type": "lock", "data" : {"lockType": lockType, "action" : action, "requestId" : requestId}});
    return completer;
  }

  Future close() => _lockerSocket.close();

}
