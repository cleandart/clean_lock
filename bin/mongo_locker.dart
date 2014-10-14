import 'package:clean_lock/locker.dart';
import 'package:clean_logging/logger.dart';
import 'package:args/args.dart';

String defaultLogMessage(Map rec) {
  var error = rec['error'] == null ? '' : '\n${rec['error']}';
  var stackTrace = rec['stackTrace'] == null ? '' : '\n${rec['stackTrace']}';
  return ('${rec['fullSource']}\t[${rec['level']}]\t'
          '${new DateTime.fromMillisecondsSinceEpoch(rec['timestamp'])}\t'
          '${rec['event']}\t${error}\t${stackTrace}\t');
}

defaultLoggingHandler(Map rec) => print(defaultLogMessage(rec));

Logger _logger = new Logger('clean_lock.locker');

main(List<String> args) {
  ArgParser parser = new ArgParser();
  parser.addFlag('debug', abbr: 'd', defaultsTo: false);
  parser.addOption('host', abbr: 'h', defaultsTo: '127.0.0.1');
  parser.addOption('port', abbr: 'p', defaultsTo: '27002');
  ArgResults res = parser.parse(args);

  var host = res['host'];
  var port = num.parse(res['port']);
  bool debug = res['debug'];

  Logger.onRecord.listen(defaultLoggingHandler);
  Logger.ROOT.logLevel = debug ? Level.ALL : Level.INFO;

  return Locker.bind(host, port)
      .then((_) => _logger.info("Locker started - running on $host, $port"));
}
