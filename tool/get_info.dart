import 'dart:io';
import 'package:args/args.dart';
import 'package:useful/socket_jsonizer.dart';

main(List<String> args) {
  ArgParser parser = new ArgParser();
  parser.addOption('host', abbr: 'h', defaultsTo: '127.0.0.1');
  parser.addOption('port', abbr: 'p', defaultsTo: '27002');
  ArgResults res = parser.parse(args);

  var host = res['host'];
  var port = num.parse(res['port']);

  Socket.connect(host, port).then((Socket socket) {
    writeJSON(socket, {"type": "info"});
    toJsonStream(socket).listen(prettyPrint,
        onDone: () => socket.close().then((_) => socket.destroy()));
  });
}

void prettyPrint(Map<String, Map> answer) {
  answer.forEach((key, vals) {
    if (vals.isEmpty) print("$key:\tNone");
    else {
      print("$key:");
      vals.forEach((lock, list) {
        print("\tLock type = $lock:");
        list.forEach((v) => print("\t\t$v"));
      });
    }
  });
}
