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
      print("completing");
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
  Future<String> getLock(String lockType) {
    print("getlock");
    Completer completer = _sendRequest(lockType, "get");
    return completer.future;
  }

  Future releaseLock(String lockType) {
    print("rellock");
    Completer completer = _sendRequest(lockType, "release");
    return completer.future;
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
