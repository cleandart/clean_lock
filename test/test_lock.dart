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

  tearDown(() {
    return lockRequestor.close();
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
    var lockedValue = 0;
    lockRequestor.withLock("lock1", () {
      return lockRequestor.withLock("lock2", () {
        return lockRequestor.withLock("lock1", (){
          return lockRequestor.withLock("lock3", () {
            return new Future.delayed(new Duration(milliseconds: 700), () => lockedValue = 1);
          });
        });
      });
    });

    new Future.delayed(new Duration(milliseconds: 200), () => lockRequestor.withLock("lock1", () => expect(lockedValue, equals(1))));
    new Future.delayed(new Duration(milliseconds: 200), () => lockRequestor.withLock("lock2", () => expect(lockedValue, equals(1))));
    new Future.delayed(new Duration(milliseconds: 200), () => lockRequestor.withLock("lock3", () => expect(lockedValue, equals(1))));

    return new Future.delayed(new Duration(seconds:1));
  });

  test('should provide mutual exclusion, (5 sec test)', () {
    infiniteRWL(callback()) {
      return lockRequestor.withLock("lock", callback).then((_) => infiniteRWL(callback));
    };

    var lockValue = 0;
    readWait() {
      var _lockValue = lockValue;
      return new Future.delayed(new Duration(milliseconds: 100)).then((_) => expect(lockValue, equals(_lockValue)));
    }

    increase() {
      lockValue++;
    }

    infiniteRWL(readWait);
    infiniteRWL(increase);

    return new Future.delayed(new Duration(seconds:5));
  });

  skip_test("withLock should not timeout when lock is available", () {
    var acquiredLock = false;

    var lock = lockRequestor.withLock("lock", () => acquiredLock = true, timeout: new Duration(milliseconds: 500));

    new Future.delayed(new Duration(milliseconds: 100))
      .then((_) {
        expect(acquiredLock, isTrue, reason: "Failed to acquire lock");
      });

    return lock;
  });

  test("withLock should timeout when lock is not available", () {
    var lock1 = lockRequestor.withLock("lock", () => new Future.delayed(new Duration(seconds: 2)), author: '1');

    var acquiredLock = false;

    var lock2 = lockRequestor.withLock("lock", () => acquiredLock = true, timeout: new Duration(milliseconds: 500));

    expect(lock2 , throws);

    return lock1;
  });

}