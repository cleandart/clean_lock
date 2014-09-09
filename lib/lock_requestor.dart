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

  Future get done => _lockerSocket.done;

  LockRequestor(this._lockerSocket) {
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
    Socket.connect(url, port).then((Socket socket) => new LockRequestor(socket))
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

  Future withLock(String lockType, callback()) {
       // Check if it's already running in zone
       if (Zone.current[#lock] != null) {
         // It is, check for lock and run
         if (Zone.current[#lock]["lock"]) {
           return new Future.sync(callback);
         } else {
           // Lock was already released, this shouldn't happen
           throw new Exception("withLock: Lock was released, but callback is still trying to run in this zone, (maybe there is some Future not waited for?)");
         }
       } else {
         // It's not running in any Zone yet
         return runZoned(() {
           return _getLock(lockType)
            .then((_) => new Future.sync(callback))
            .whenComplete(() => _releaseLock(lockType))
            .then((_) => Zone.current[#lock]["lock"] = false);
         }, zoneValues: {#lock: {"lock" : true}});
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
