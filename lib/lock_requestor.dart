library clean_lock.lock_requestor;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:useful/socket_jsonizer.dart';

class LockRequestorException implements Exception {

  final String message;

  const LockRequestorException([String this.message = ""]);

  String toString() => "LockRequestor exception: $message";
}

class LockRequestor {

  Map <String, Completer> requestors = {};
  Socket _lockerSocket;
  num _lockIdCounter = 0;
  String prefix = (new Random(new DateTime.now().millisecondsSinceEpoch % (1<<20))).nextDouble().toString();

  String url;
  int port;

  StreamSubscription ss;

  Future get done => _lockerSocket.done;

  LockRequestor.fromSocket(this._lockerSocket) {
    _initListeners();
  }

  LockRequestor(this.url, this.port);

  // Zone needed for catching broken pipe exceptions (e.g. server restarted) happening somewhere in future
  Future init() =>
      runZoned(() =>
        Socket.connect(url, port)
          .then((Socket socket) => _lockerSocket = socket)
          .then((_) => _initListeners()),
      onError: (e) => e is SocketException ? throw new LockRequestorException(e.toString()) : throw e);

  _initListeners() {
    ss = toJsonStream(_lockerSocket).listen((Map resp) {
      Completer completer = requestors.remove(resp["requestId"]);
      if (resp.containsKey("error")) {
        completer.completeError(resp["error"]);
      } else if (resp.containsKey("result")) {
        completer.complete();
      } else {
        throw new Exception("Unknown response from _lockerSocket");
      }
    }, onError: (e) => throw new LockRequestorException(e.toString())
    , onDone: () => throw new LockRequestorException("ServerSocket is done (probably crashed) this shouldn't happen"));
  }

  static Future<LockRequestor> connect(url, port) =>
    Socket.connect(url, port).then((Socket socket) => new LockRequestor.fromSocket(socket))
      .catchError((e,s) => throw new LockRequestorException("LockRequestor was "
                "unable to connect to url: $url, port: $port, (is Locker running?)"));

  // Obtains lock and returns unique ID for the holder
  Future<String> _getLock(String lockType, String author) {
    Completer completer = _sendRequest(lockType, "get", author);
    return completer.future;
  }

  Future _releaseLock(String lockType, String author) {
    Completer completer = _sendRequest(lockType, "release", author);
    return completer.future;
  }

  getZoneMetaData() => Zone.current[#meta];

  Future withLock(String lockType, callback(), {dynamic metaData: null,
    String author: null}) {
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
           return _getLock(lockType, author)
            .then((_) => new Future.sync(callback))
            .whenComplete(() => _releaseLock(lockType, author))
            .then((_) => Zone.current[#finished]['finished'] = true);
         }, zoneValues: {
           #locks: Zone.current[#locks] == null ? new Set.from([lockType]) : (new Set.from(Zone.current[#locks]))..add(lockType),
           #meta: metaData,
           #finished: {"finished" : false}
         });
       }
     }

  _sendRequest(String lockType, String action, String author) {
    var requestId = "$prefix--$_lockIdCounter";
    _lockIdCounter++;
    Completer completer = new Completer();
    requestors[requestId] = completer;
    writeJSON(_lockerSocket, {"type": "lock", "data" : {"lockType": lockType, "action" : action, "requestId" : requestId}});
    return completer;
  }

  Future close() => _lockerSocket.close().then((_) => ss.cancel()).then((_) => _lockerSocket.destroy());

}
