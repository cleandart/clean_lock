library clean_lock.locker;

import 'dart:io';
import 'dart:async';
import 'package:useful/socket_jsonizer.dart';
import 'package:clean_logging/logger.dart';

Logger _logger = new Logger('clean_lock.locker');

class Locker {

  ServerSocket serverSocket;
  List<Socket> clientSockets = [];
  // lockName: [{socket : socket, requestId: requestId, author: author}]
  Map<String, List<Map> > requestors = {};
  // lockName: {socket : socket, requestId: requestId, author: author}
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
    removeSocket(map) {
      return new Map.from(map)..remove("socket");
    }

    var requestorsWithoutSockets = {};
    requestors.forEach((lock, reqList) {
      requestorsWithoutSockets[lock] = reqList.map(removeSocket).toList();
    });

    var ownersWithoutSockets = {};
    currentLock.forEach((lock, owner) {
      ownersWithoutSockets[lock] = removeSocket(owner);
    });

    writeJSON(socket, {
      "requestors": requestorsWithoutSockets,
      "currentLock": ownersWithoutSockets
    });
  }

  handleLockRequest(Map req, Socket socket) {
    var rid = req["requestId"];
    var lt = req["lockType"];
    if (req["action"] == "get") {
      return _addRequestor(rid, req["author"], lt, socket);
    }
    else {
      return _releaseLock(rid, lt, socket);
    }
  }

  // Adds the socket with additional data to queue for given lockType
  _addRequestor(String requestId, String author, String lockType, Socket socket)
  {
    if (requestors[lockType] == null) requestors[lockType] = [];
    requestors[lockType].add({"socket" : socket, "requestId": requestId, "author": author});
    checkLockRequestors();
  }

  _releaseLock(String requestId, String lockType, Socket socket) {
    if (currentLock[lockType]["socket"] == socket) {
      currentLock.remove(lockType);
      _logger.fine('Lock type $lockType released');
      writeJSON(socket, {"result":"ok", "action":"release", "requestId":requestId});
      checkLockRequestors();
    } else {
      writeJSON(socket, {"error": "Cannot release lock when the socket does not own it", "action":"release", "requestId":requestId});
    }
  }

  // Checks if someone can be given their requested lockType
  checkLockRequestors() {
    _logger.finest('Current locks held: $currentLock');
    _logger.finest('Current requestors: $requestors');
    requestors.forEach((lockType, socketList) {
      if (socketList.isNotEmpty && (!currentLock.containsKey(lockType))) {
        currentLock[lockType] = requestors[lockType].removeAt(0);
        _logger.fine('Lock type $lockType acquired');
        writeJSON(currentLock[lockType]["socket"], {"result":"ok", "action":"get", "requestId": currentLock[lockType]["requestId"]});
      }
    });

  }

  Future close() =>
     Future.wait([
       Future.wait(clientSockets.map((s) => s.close())),
       serverSocket.close()
     ]);

}
