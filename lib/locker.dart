library clean_lock.locker;

import 'dart:io';
import 'dart:async';
import 'package:useful/socket_jsonizer.dart';
import 'package:clean_logging/logger.dart';

Logger _logger = new Logger('clean_lock.locker');

/**
 * Locker server. Responsible for assigning locks to given requestors. Responsible
 * for that for every type of lock there is at most one requestor holding it at a time.
 * Listens to requests and informs the requestors when it assigns the lock to them.
 * It also responds to an info request, listing all the requestors and lock holders.
 */
class Locker {

  ServerSocket serverSocket;
  List<Socket> clientSockets = [];
  // lockName: [{socket : Socket, requestId: String, callId: String, author: String, timestamp: DateTime}]
  Map<String, List<Map> > requestors = {};
  // lockName: {socket : Socket, requestId: String, callId: String, author: String, timestamp: DateTime}
  Map<String, Map> currentLock = {};

  Locker.config(this.serverSocket);

  /**
   * Start the [Locker] server on given [url] and [port].
   */
  static Future<Locker> bind(url, port) =>
      ServerSocket.bind(url, port)
        .then((ServerSocket sSocket) {
          _logger.info('Locker running on $url, $port');
          Locker locker = new Locker.config(sSocket);
          locker.serverSocket.listen(locker.handleClient);
          return locker;
        });

  /// Removes given [socket] from requestors and releases its locks
  /// (used when the [socket] suddenly disconnects)
  _disposeOfSocket(Socket socket) {
    _logger.fine("disposeOfSocket ${_getInfoAboutSocket(socket)}");
    socket.close();
    requestors.forEach((lock, reqList) {
      reqList.removeWhere((e) => e["socket"] == socket);
    });
    _removeSocketLocks(socket);
    clientSockets.remove(socket);
    checkLockRequestors();
  }

  /// Releases all locks the [socket] holds
  _removeSocketLocks(Socket socket) {
    List toRemove = [];
    currentLock.forEach((lock, sct) {
      if (sct["socket"] == socket) toRemove.add(lock);
    });
    if (toRemove.isNotEmpty) _logger.warning('Socket disconnected - it '
        'held locks $toRemove, now they are released');
    toRemove.forEach(currentLock.remove);
  }

  /// New [socket] connects - take notion of it and set up listeners to requests
  handleClient(Socket socket) {
    _logger.fine("New socket come: ${_getInfoAboutSocket(socket)}");
    socket.done.catchError((e,s) => _logger.info("Soccet ${_getInfoAboutSocket(socket)} done error $e $s "));
    clientSockets.add(socket);
    toJsonStream(socket).listen((Map data) {
      if (data["type"] == "lock") handleLockRequest(data["data"], socket);
      if (data["type"] == "info") handleInfoRequest(socket);
    }, onDone: () => _disposeOfSocket(socket)
     , onError: (e,s) => _logger.warning("Error on listening on stream ${_getInfoAboutSocket(socket)} $e $s"));
  }

  String _getInfoAboutSocket(Socket s) {
    if (s == null) {
      return "Socket(null)";
    } else if (s is! Socket) {
        return "Socket(not a socket ${s.runtimeType} ${s.hashCode})";
    } else {
      var result = "";
      try {
        result = "Socket(Address:${s.address} ${s.port} "
                 "Remote:${s.remoteAddress} ${s.remotePort} "
                 "HashCode: ${s.hashCode})";
      } catch (e, s) { result = "Socket(Error getting info ${s.hashCode})";}
      return result;
    }
  }


  _writeJsonWithErrors(Socket socket, dynamic object, {toEncodable}) =>
    new Future.sync(() => writeJSON(socket, object, toEncodable: toEncodable))
    //not shure why its crashing when i flush it
    //.then((_) => socket.flush())
    .catchError((e, s) => _logger.warning("error when writeJSON in socket "
        "${_getInfoAboutSocket(socket)} $e $s"));


  /// [socket] requested for info, it returns a Map with all the requestors and
  /// all locks with their holders.
  handleInfoRequest(Socket socket) {
    getProperInfo(Map map) =>
      {
        "requestId" : map["requestId"],
        "author" : map["author"],
        "duration" : new DateTime.now().difference(map['timestamp']).toString(),
      };

    var requestorsWithoutSockets = {};
    requestors.forEach((lock, reqList) {
      requestorsWithoutSockets[lock] = reqList.map(getProperInfo).toList();
    });

    var ownersWithoutSockets = {};
    currentLock.forEach((lock, owner) {
      ownersWithoutSockets[lock] = getProperInfo(owner);
    });

    writeJSON(socket, {
      "requestors": requestorsWithoutSockets,
      "currentLock": ownersWithoutSockets
    });
  }

  /// [socket]'s request is concerning a lock - it may be: get, release or cancel.
  handleLockRequest(Map req, Socket socket) {
    var rid = req["requestId"];
    var cid = req["callId"];
    var lt = req["lockType"];
    var author = req["author"];
    var timestamp = new DateTime.now();
    if (req["action"] == "get") {
      return _addRequestor(rid, cid, author, timestamp, lt, socket);
    } else if (req["action"] == "cancel") {
      return _cancelRequestor(rid, cid, lt, socket);
    } else {
      return _releaseLock(rid, cid, lt, socket);
    }
  }

  /// Adds the socket with additional data to queue for given lockType
  _addRequestor(String requestId, String callId, String author,
      DateTime timestamp, String lockType, Socket socket) {
    if (requestors[lockType] == null) requestors[lockType] = [];
    requestors[lockType].add({
      "socket" : socket,
      "socketInfo" : _getInfoAboutSocket(socket),
      "requestId": requestId,
      "callId": callId,
      "author": author,
      "timestamp": timestamp
    });
    checkLockRequestors();
  }

  /// Tries to release [lockType] by [socket] - releases it only if the [socket]
  /// does really own it
  bool _tryReleaseLock(String requestId, String callId, String lockType,
                       Socket socket) {
    if (currentLock[lockType]["socket"] == socket &&
        currentLock[lockType]["callId"] == callId) {
      currentLock.remove(lockType);
      _logger.fine('Lock type $lockType released.');
      return true;
    } else {
      return false;
    }
  }

  /// Releases [lockType] iff the [socket] owns it.
  /// Lock is uniquely identified by [callId] & [socket].
  _releaseLock(String requestId, String callId, String lockType, Socket socket) {
    if (_tryReleaseLock(requestId, callId, lockType, socket)) {
      _writeJsonWithErrors(socket,
          {"result": "ok", "action": "release", "requestId": requestId});
      checkLockRequestors();
    } else {
      var message = "Cannot release lock when the socket does not own it.";
      var data = {"error": message,
                  "action": "release",
                  "requestId": requestId,
                  "callId": callId,
                  "lockType": lockType,};
      var serverData = {"socketInfo" : _getInfoAboutSocket(socket),
                        "currentLock": currentLock,
                        "requestors": requestors};
      _logger.shout(message, data: data..addAll(serverData));
      _writeJsonWithErrors(socket, data, toEncodable: (d) => d.toString());
    }
  }

  /// Removes the requestor from queue.
  bool _tryCancelRequestor(String requestId, String callId, String lockType,
                           Socket socket) {
    if (requestors[lockType] != null) {
      var length = requestors[lockType].length;
      requestors[lockType].removeWhere(
          (requestor) => requestor["socket"] == socket &&
                         requestor["callId"] == callId);
      return length != requestors[lockType].length;
    }
    return false;
  }

  /// Cancels all lock requests of given requestor ([socket] & [callId]).
  /// If it was not in the queue nor holding locks, this request should've
  /// probably never been sent and it's an error.
  _cancelRequestor(String requestId, String callId, String lockType,
                   Socket socket) {
    if (_tryReleaseLock(requestId, callId, lockType, socket) ||
        _tryCancelRequestor(requestId, callId, lockType, socket)) {
      _writeJsonWithErrors(socket,
          {"result": "ok", "action": "cancel", "requestId": requestId});
    } else {
      var message = "Cannot cancel requestor. "
                    "The socket does not own it nor waits for it.";
      var data = {"error": message,
                  "action": "cancel",
                  "requestId": requestId,
                  "callId": callId,
                  "lockType": lockType,};
      var serverData = {"socketInfo" : _getInfoAboutSocket(socket),
                        "currentLock": currentLock,
                        "requestors": requestors};
      _logger.shout(message, data: data..addAll(serverData));
      _writeJsonWithErrors(socket, data, toEncodable: (d) => d.toString());
    }
  }

  /// Checks if someone can be given their requested lockType
  checkLockRequestors() {
    _logger.finest('Current locks held: $currentLock');
    _logger.finest('Current requestors: $requestors');
    requestors.forEach((lockType, socketList) {
      if (socketList.isNotEmpty && (!currentLock.containsKey(lockType))) {
        currentLock[lockType] = requestors[lockType].removeAt(0);
        currentLock[lockType]['timestamp'] = new DateTime.now();
        _logger.fine('Lock type $lockType acquired');
        _writeJsonWithErrors(currentLock[lockType]["socket"],
            {"result": "ok", "action": "get", "requestId": currentLock[lockType]["requestId"]});
      }
    });

  }

  /// Disposes of created resources
  Future close() =>
     Future.wait([
       Future.wait(clientSockets.map((s) => s.close())),
       serverSocket.close()
     ]);

}
