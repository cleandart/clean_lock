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
      Completer completer = requestors.remove(resp["id"]);
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

  Future getLock() {
    Completer completer = _sendRequest("get");
    return completer.future;
  }

  Future releaseLock() {
    Completer completer = _sendRequest("release");
    return completer.future;
  }

  _sendRequest(String action) {
    var id = "$prefix--$_lockIdCounter";
    _lockIdCounter++;
    Completer completer = new Completer();
    requestors[id] = completer;
    writeJSON(_lockerSocket, {"type": "lock", "data" : {"action" : action, "id": id}});
    return completer;
  }

  Future close() => _lockerSocket.close();

}
