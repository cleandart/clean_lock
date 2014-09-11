import "package:unittest/unittest.dart";
import 'dart:async';
import 'package:clean_lock/lock_requestor.dart';

main() {
  run();
}

run() {

  LockRequestor lockRequestor;

  setUp(() {
    return LockRequestor.connect("127.0.0.1", 27002)
        .then((LockRequestor lockR) => lockRequestor = lockR);
  });

  test("withLock should throw if callback is not waiting for futures", () {
    var callback = () {
      Future lateFuture = new Future.delayed(new Duration(milliseconds:300),
          () => lockRequestor.withLock("random lock",() {}));
      return new Future.value(null);
    };
    bool caughtError = false;
    runZoned(() {
        lockRequestor.withLock("random lock",callback);
    }, onError: (e) => caughtError = true);
    return new Future.delayed(new Duration(milliseconds:800), () => expect(caughtError,isTrue));
  });

  test("should handle nested locking", () {
    Future requests = lockRequestor.withLock("lock1", () {
      return lockRequestor.withLock("lock2", () {
        return lockRequestor.withLock("lock1", (){
          return lockRequestor.withLock("lock3", () {
            return new Future.value(null);
          });
        });
      });
    });

    return expect(requests,completes);
  });
}