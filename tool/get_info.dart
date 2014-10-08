import 'dart:io';
import 'package:args/args.dart';
import 'package:useful/socket_jsonizer.dart';

main(List<String> args) {
  ArgParser parser = new ArgParser();
  parser.addOption('host', abbr: 'h');
  parser.addOption('port', abbr: 'p');
  ArgResults res = parser.parse(args);

  if (res['host'] == null || res['port'] == null) {
    print("You have to specify url and port");
  }

  var host = res['host'];
  var port = num.parse(res['port']);

  Socket.connect(host, port).then((Socket socket) {
    writeJSON(socket, {"type": "info"});
    toJsonStream(socket).listen(print,
        onDone: () => socket.close().then((_) => socket.destroy()));
  });
}
