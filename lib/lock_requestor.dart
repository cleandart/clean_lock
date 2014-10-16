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

class _Bool {
  bool value;
  _Bool([bool this.value = false]);
}

class LockRequestor {

  Map <String, Completer> requestors = {};
  Socket _lockerSocket;
  num _lockIdCounter = 0;
  int _callIdCounter = 0;
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
  Future<String> _getLock(String lockType, String callId, Duration timeout, String author) {
    Completer completer = _sendRequest(lockType, "get", callId: callId, author: author);
    Future future = completer.future;

    if (timeout != null) {
      future = future.timeout(timeout)
        .catchError((_) =>
            _cancelLock(lockType, callId)
              .then((_) => throw new LockRequestorException("Timed out while waiting for lock '$lockType'")),
          test: (e) => e is TimeoutException);
    }

    return future;
  }

  Future _releaseLock(String lockType, String callId) {
    Completer completer = _sendRequest(lockType, "release", callId: callId);
    return completer.future;
  }

  Future _cancelLock(String lockType, String callId) {
    Completer completer = _sendRequest(lockType, "cancel", callId: callId);
    return completer.future;
  }

  getZoneMetaData() => Zone.current[#meta];

  Future withLock(String lockType, callback(), {Duration timeout: null,
    dynamic metaData: null, String author: null}) {
    runIfActive(Zone zone, f()) {
      if (zone[#active].value) {
        return f();
      } else {
        throw new Exception("Zone has already finished (maybe a future was not waited for?)");
      }
    }

    deactivateZone() => Zone.current[#active].value = false;

    var zoneSpec = new ZoneSpecification(
      run: (self, parent, zone, f) {
        return runIfActive(self, () => parent.run(zone, f));
      },
      runUnary: (self, parent, zone, f, arg) {
        return runIfActive(self, () => parent.runUnary(zone, f, arg));
      },
      runBinary: (self, parent, zone, f, arg1, arg2) {
        return runIfActive(self, () => parent.runBinary(zone, f, arg1, arg2));
      }
    );

    if ((Zone.current[#locks] != null) && Zone.current[#locks].contains(lockType)) {
      return new Future.sync(callback);
    } else {
      var callId = "${_callIdCounter++}";
      Future lock = _getLock(lockType, callId, timeout, author);

      Future result =
          runZoned(() {
            return lock.then((_) => new Future.sync(callback))
              .whenComplete(deactivateZone);
          }, zoneValues: {
            #locks: Zone.current[#locks] == null ? new Set.from([lockType]) : (new Set.from(Zone.current[#locks]))..add(lockType),
            #meta: metaData,
            #active: new _Bool(true)
          }, zoneSpecification: zoneSpec);

      return result.then((_) => _releaseLock(lockType, callId));
    }
  }

  _sendRequest(String lockType, String action, {String callId, String author: null}) {
    var requestId = "$prefix--$_lockIdCounter";
    _lockIdCounter++;
    Completer completer = new Completer();
    requestors[requestId] = completer;
    var json = {"type": "lock",
                "data" : {"lockType": lockType,
                          "action" : action,
                          "requestId" : requestId,
                          "callId": callId,
                          "author": author
                         }
               };
    writeJSON(_lockerSocket, json);
    return completer;
  }

  Future close() => _lockerSocket.close().then((_) => ss.cancel()).then((_) => _lockerSocket.destroy());

}
