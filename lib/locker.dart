library clean_lock.locker;

import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:useful/socket_jsonizer.dart';
import 'package:clean_logging/logger.dart';

Logger _logger = new Logger('clean_lock.locker');

class Locker {

  ServerSocket serverSocket;
  List<Socket> clientSockets = [];
  // lockName: [{socket : socket, requestId: requestId, author: author, timestamp: DateTime}]
  Map<String, List<Map> > requestors = {};
  // lockName: {socket : socket, requestId: requestId, author: author, timestamp: DateTime}
  Map<String, Map> currentLock = {};

  Locker.config(this.serverSocket);

  static Future<Locker> bind(url, port) =>
      ServerSocket.bind(url, port)
        .then((ServerSocket sSocket) {
          _logger.info('Locker running on $url, $port');
          Locker locker = new Locker.config(sSocket);
          locker.serverSocket.listen(locker.handleClient);
          return locker;
        });

  // Removes given socket from requestors and releases its locks
  _disposeOfSocket(Socket socket) {
    socket.close();
    requestors.forEach((lock, reqList) {
      reqList.removeWhere((e) => e["socket"] == socket);
    });
    _removeSocketLocks(socket);
    clientSockets.remove(socket);
    checkLockRequestors();
  }

  _removeSocketLocks(Socket socket) {
    List toRemove = [];
    currentLock.forEach((lock, sct) {
      if (sct["socket"] == socket) toRemove.add(lock);
    });
    if (toRemove.isNotEmpty) _logger.warning('Socket disconnected - it '
        'held locks $toRemove, now they are released');
    toRemove.forEach(currentLock.remove);
  }

  handleClient(Socket socket) {
    clientSockets.add(socket);
    toJsonStream(socket).listen((Map data) {
      if (data["type"] == "lock") handleLockRequest(data["data"], socket);
      if (data["type"] == "info") handleInfoRequest(socket);
    }, onDone: () => _disposeOfSocket(socket));
  }

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

  // Adds the socket with additional data to queue for given lockType
  _addRequestor(String requestId, String callId, String author,
      DateTime timestamp, String lockType, Socket socket) {
    if (requestors[lockType] == null) requestors[lockType] = [];
    requestors[lockType].add({
      "socket" : socket,
      "requestId": requestId,
      "callId": callId,
      "author": author,
      "timestamp": timestamp
    });
    checkLockRequestors();
  }

  /** Caution! This is not efficient; should be used rarely. */
  _prepareForSending(data) =>
      JSON.decode(JSON.encode(data, toEncodable: (d) => d.toString()));

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

  _releaseLock(String requestId, String callId, String lockType, Socket socket) {
    if (_tryReleaseLock(requestId, callId, lockType, socket)) {
      writeJSON(socket,
          {"result": "ok", "action": "release", "requestId": requestId});
      checkLockRequestors();
    } else {
      var message = "Cannot release lock when the socket does not own it.";
      var data = {
        "error": message,
        "action": "release",
        "requestId": requestId,
        "callId": callId,
        "lockType": lockType,
        "socket": socket,
        "currentLock": currentLock,
        "requestors": requestors
      };
      _logger.shout(message, data: data);
      writeJSON(socket, _prepareForSending(data));
    }
  }

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

  _cancelRequestor(String requestId, String callId, String lockType,
                   Socket socket) {
    if (_tryReleaseLock(requestId, callId, lockType, socket) ||
        _tryCancelRequestor(requestId, callId, lockType, socket)) {
      writeJSON(socket,
          {"result": "ok", "action": "cancel", "requestId": requestId});
    } else {
      var message = "Cannot cancel requestor. "
                    "The socket does not own it nor waits for it.";
      var data = {
        "error": message,
        "action": "cancel",
        "requestId": requestId,
        "callId": callId,
        "lockType": lockType,
        "socket": socket,
        "currentLock": currentLock,
        "requestors": requestors
      };
      _logger.shout(message, data: data);
      writeJSON(socket, _prepareForSending(data));
    }
  }

  // Checks if someone can be given their requested lockType
  checkLockRequestors() {
    _logger.finest('Current locks held: $currentLock');
    _logger.finest('Current requestors: $requestors');
    requestors.forEach((lockType, socketList) {
      if (socketList.isNotEmpty && (!currentLock.containsKey(lockType))) {
        currentLock[lockType] = requestors[lockType].removeAt(0);
        currentLock[lockType]['timestamp'] = new DateTime.now();
        _logger.fine('Lock type $lockType acquired');
        writeJSON(currentLock[lockType]["socket"],
            {"result": "ok", "action": "get", "requestId": currentLock[lockType]["requestId"]});
      }
    });

  }

  Future close() =>
     Future.wait([
       Future.wait(clientSockets.map((s) => s.close())),
       serverSocket.close()
     ]);

}
