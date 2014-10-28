import 'dart:io';
import 'package:args/args.dart';
import 'package:useful/socket_jsonizer.dart';

main(List<String> args) {
  ArgParser parser = new ArgParser();
  parser.addOption('host', abbr: 'h', defaultsTo: '127.0.0.1');
  parser.addOption('port', abbr: 'p', defaultsTo: '27002');
  parser.addFlag('show-empty', abbr: 'e', defaultsTo: false);
  ArgResults res = parser.parse(args);

  var host = res['host'];
  var port = num.parse(res['port']);

  Socket.connect(host, port).then((Socket socket) {
    writeJSON(socket, {"type": "info"});
    toJsonStream(socket).listen((response) {
      prettyPrint(response, res["show-empty"]);
      socket.close()
        .then((_) => socket.destroy());
    });
  });
}

String getRequestorInfo(Map requestor) {
  var author = requestor["author"];
  var requestId = requestor["requestId"];
  var duration = requestor['duration'];

  return "${author == null ? "" : "@$author, "}#$requestId, duration: $duration";
}

void prettyPrint(Map<String, Map> response, bool showEmpty) {
  Map requestors = response["requestors"];
  Map lockOwners = response["currentLock"];

  Set locks = new Set.from(requestors.keys)..addAll(lockOwners.keys);

  locks.forEach((lock) {
    var lockOwner = lockOwners[lock];
    var ownerId = lockOwner != null ? lockOwner["requestId"] : null;

    List reqList = requestors[lock];

    if (lockOwner != null ||
        reqList != null && reqList.isNotEmpty ||
        showEmpty) {

      print("$lock:");

      if (lockOwner != null) {
        print("* " + getRequestorInfo(lockOwner));
      }

      if (reqList != null) {
        reqList.forEach((requestor) {
          print("  " + getRequestorInfo(requestor));
        });
      }

      print("");
    }
  });
}
