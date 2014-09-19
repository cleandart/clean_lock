import 'dart:async';
import 'package:clean_lock/locker.dart';
import 'package:clean_logging/logger.dart';

String defaultLogMessage(Map rec) {
  var error = rec['error'] == null ? '' : '\n${rec['error']}';
  var stackTrace = rec['stackTrace'] == null ? '' : '\n${rec['stackTrace']}';
  return ('${rec['fullSource']}\t[${rec['level']}]\t${new DateTime.fromMillisecondsSinceEpoch(rec['timestamp'])}\t'
          '${rec['event']}\t${error}\t${stackTrace}\t');
}

defaultLoggingHandler(Map rec) => print(defaultLogMessage(rec));

main(List<String> args) {
  if (args.length != 2) {
    print("You have to specify url and port");
    return new Future.value(null);
  }
  Logger.onRecord.listen(defaultLoggingHandler);
  Logger.ROOT.logLevel = Level.FINEST;
  var url = args[0];
  var port = num.parse(args[1]);
  return Locker.bind(url, port)
      .then((_) => print("Locker running on ${args}"));
}