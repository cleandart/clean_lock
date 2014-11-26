library clean_lock.lock_requestor;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:useful/socket_jsonizer.dart';
import 'package:clean_logging/logger.dart';

Logger logger = new Logger("clean_lock.lock_requestor");

/**
 * All Exceptions thrown somewhere in LockRequestor's methods are of this type or extend it.
 */
class LockRequestorException implements Exception {

  final String message;

  const LockRequestorException([String this.message = ""]);

  String toString() => "LockRequestor exception: $message";
}

/**
 * Exception thrown when timeout is reached while getting lock
 */
class LockTimeoutException extends LockRequestorException {

  final String message;

  const LockTimeoutException([String this.message = ""]);

  String toString() => "Timeout exception: $message";

}

class _Bool {
  bool value;
  _Bool([bool this.value = false]);
}

class _Lock {
  String lockType;
  String callId;

  _Lock(this.lockType, this.callId);

}

/**
 * This class is for requesting various locks from a running Locker. When a specific
 * lock is acquired, no other instance can acquire a lock of the same type until it is
 * released.
 */
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

  /// Initialization - connecting to specified url & port, initializing listeners
  Future init() =>
      // Zone needed for catching broken pipe exceptions (e.g. server restarted) happening somewhere in future
      runZoned(() =>
        Socket.connect(url, port)
          .then((Socket socket) => _lockerSocket = socket)
          .then((_) => _initListeners()),
      onError: (e) => e is SocketException ? throw new LockRequestorException(e.toString()) : throw e);

  _initListeners() {
    ss = toJsonStream(_lockerSocket).listen((Map resp) {
      Completer completer = requestors.remove(resp["requestId"]);
      if (resp.containsKey("error")) {
        logger.warning("The response contains error.", data: {"response": resp});
        completer.completeError(resp["error"]);
      } else if (resp.containsKey("result")) {
        completer.complete();
      } else {
        throw new Exception("Unknown response from _lockerSocket");
      }
    }, onError: (e) => throw new LockRequestorException(e.toString())
    , onDone: () => throw new LockRequestorException("ServerSocket is done (probably crashed) this shouldn't happen"));
  }

  /**
   * Shortcut for construct & init.
   */
  static Future<LockRequestor> connect(url, port) =>
    runZoned(() =>
        Socket.connect(url, port).then((Socket socket) => new LockRequestor.fromSocket(socket))
          .catchError((e,s) => throw new LockRequestorException("LockRequestor was "
                "unable to connect to url: $url, port: $port, (is Locker running?)")),
    onError: (e) => e is SocketException ? throw new LockRequestorException(e.toString()) : throw e);

  /// Obtains and returns a unique lock of given type for the holder. Completes after the
  /// lock is aquired
  Future<_Lock> _getLock(String lockType, Duration timeout, String author) {
    _Lock lock = new _Lock(lockType, "${_callIdCounter++}");
    Completer completer = _sendRequest(lock, "get", author: author);

    if (timeout != null) {
      return completer.future.timeout(timeout,
          onTimeout: () => _cancelLock(lock)
              .then((_) => throw new LockTimeoutException("Timed out while waiting for lock '$lockType'")))
          .then((_) => lock);

    } else {
      return completer.future.then((_) => lock);
    }

  }

  Future _releaseLock(_Lock lock) {
    Completer completer = _sendRequest(lock, "release");
    return completer.future;
  }

  Future _cancelLock(_Lock lock) {
    Completer completer = _sendRequest(lock, "cancel");
    return completer.future;
  }

  /**
   * Used to access meta data passed to [withLock]. It returns the most inner available
   * meta data passed to nested [withLock]s. For example, this can be useful if the same instance
   * of some object should be accessed in nested calls of [withLock].
   */
  getZoneMetaData() => Zone.current[#meta];

  /**
   * Runs the [callback] after getting a lock of type [lockType]. Ensures, that [callback]
   * is not run before the lock is acquired. It runs in Zones. Nested calls of [withLock] remember all locks
   * the zone acquired (and has not yet released) in the meantime, so if the [callback] is to be run with some lock that some
   * outer [withLock] has already acquired, the lock is ignored and the [callback] is run.
   * [safe] - Ensures the release of lock after the [callback] is finished
   * ([Exception] is thrown if the callback has not finished before the lock is
   * returned).
   * [timeout] - if specified, [withLock] will wait for lock for only a given time.
   * When the [timeout] is reached, the future will complete with [LockTimeoutException]
   * and the lock will never be acquired in this call.
   * [metaData] - data accessible anywhere in [callback] by calling [getZoneMetaData]
   * (if used in nested [withLock], it returns the first available data traversing from the
   * most inner to the most outer call)
   * [author] - signature (not necessarily unique), used in Locker server
   */
  Future withLock(String lockType, callback(), {Duration timeout: null,
    dynamic metaData: null, bool safe: true, String author: null}) {
    runIfActive(Zone zone, f()) {
      if (safe && !zone[#active].value) {
        throw new Exception("Zone has already finished "
                            "(maybe a future was not waited for?)");
      }
      return f();
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
      return _getLock(lockType, timeout, author)
        .then((lock) {
          return runZoned(() {
            return new Future.sync(callback)
              .whenComplete(deactivateZone);
          }, zoneValues: {
            #locks: Zone.current[#locks] == null ? new Set.from([lockType]) : (new Set.from(Zone.current[#locks]))..add(lockType),
            #meta: metaData,
            #active: new _Bool(true)
          }, zoneSpecification: zoneSpec)
          .whenComplete(() => _releaseLock(lock));
          // TODO Should create tests for releasing locks after an exception
      });
    }
  }

  /// Sends a request for [lock] to the Locker server. Returns a completer, for this request.
  _sendRequest(_Lock lock, String action, {String author: null}) {
    var requestId = "$prefix--$_lockIdCounter";
    _lockIdCounter++;
    Completer completer = new Completer();
    requestors[requestId] = completer;
    var json = {"type": "lock",
                "data" : {"lockType": lock.lockType,
                          "action" : action,
                          "requestId" : requestId,
                          "callId": lock.callId,
                          "author": author
                         }
               };
    writeJSON(_lockerSocket, json);
    return completer;
  }

  /**
   * Disposes of the created resources
   */
  Future close() => _lockerSocket.close().then((_) => ss.cancel()).then((_) => _lockerSocket.destroy());

}
