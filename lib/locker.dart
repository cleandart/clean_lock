library clean_lock.locker;

import 'dart:io';
import 'dart:async';
import 'package:useful/socket_jsonizer.dart';

class Locker {

  ServerSocket serverSocket;
  List<Socket> clientSockets = [];
  // lockName: [{socket: Socket, requestId: String}]
  Map<String, List<Map> > requestors = {};
  // lockName: {socket: Socket, requestId: String}
  Map<String, Map> currentLock = {};

  Locker.config(this.serverSocket);

  static Future<Locker> bind(url, port) =>
      ServerSocket.bind(url, port)
        .then((ServerSocket sSocket) {
          Locker locker = new Locker.config(sSocket);
          locker.serverSocket.listen(locker.handleClient);
          return locker;
        });

  // Removes given socket from requestors and releases its locks
  _disposeOfSocket(Socket socket) {
    socket.close();
    requestors.forEach((lock, reqList) {
      while (reqList.removeWhere((e) => e["socket"] == socket));
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
    toRemove.forEach(currentLock.remove);
  }

  handleClient(Socket socket) {
    clientSockets.add(socket);
    toJsonStream(socket).listen((Map data) {
      if (data["type"] == "lock") handleLockRequest(data["data"], socket);
    }, onDone: () => _disposeOfSocket(socket));
  }

  handleLockRequest(Map req, Socket socket) =>
    (req["action"] == "get" ? _addRequestor : _releaseLock)(req["requestId"], req["lockType"], socket);

  // Adds the socket with additional data to queue for given lockType
  _addRequestor(String requestId, String lockType, Socket socket) {
    if (requestors[lockType] == null) requestors[lockType] = [];
    requestors[lockType].add({"socket" : socket, "requestId": requestId});
    checkLockRequestors();
  }

  _releaseLock(String requestId, String lockType, Socket socket) {
    if (currentLock[lockType]["socket"] == socket) {
      currentLock.remove(lockType);
      writeJSON(socket, {"result":"ok", "action":"release", "requestId":requestId});
      checkLockRequestors();
    } else {
      writeJSON(socket, {"error": "Cannot release lock when the socket does not own it", "action":"release", "requestId":requestId});
    }
  }

  // Checks if someone can be given their requested lockType
  checkLockRequestors() {
    requestors.forEach((lockType, socketList) {
      if (socketList.isNotEmpty && (!currentLock.containsKey(lockType))) {
        currentLock[lockType] = requestors[lockType].removeAt(0);
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
