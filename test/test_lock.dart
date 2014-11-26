import 'dart:async';
import 'dart:math';
import "package:unittest/unittest.dart";
import 'package:clean_lock/lock_requestor.dart';

main() {
  run();
}

run() {
  LockRequestor lockRequestor;

  var random = new Random();
  randomLock() => "test-lock-${random.nextInt(1000)}";

  setUp(() {
    return LockRequestor.connect("127.0.0.1", 27002)
        .then((LockRequestor lockR) => lockRequestor = lockR);
  });

  tearDown(() {
    return lockRequestor.close();
  });

  group("withLock behavior for when callback is not waiting for futures", () {
    bool caughtError, callbackFinished;

    run(safe) {
      caughtError = false;
      callbackFinished = false;

      runZoned(() {
        lockRequestor.withLock(randomLock(), () {
          // a future that is not waited for
          new Future.delayed(new Duration(milliseconds: 300),
              () => callbackFinished = true);

          return new Future.delayed(new Duration(milliseconds: 100), () => null);
        }, safe: safe);
      }, onError: (e, s) {
        caughtError = true;
      });
    }

    runChecks(check()) {
      return new Future.delayed(new Duration(milliseconds: 500), check);
    }

    test("should throw when safe=true", () {
      run(true);
      return runChecks(() {
        expect(callbackFinished, isFalse);
        expect(caughtError, isTrue);
      });
    });

    test("should not throw when safe=false", () {
      run(false);
      return runChecks(() {
        expect(callbackFinished, isTrue);
        expect(caughtError, isFalse);
      });
    });
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

  test("withLock should not timeout when lock is available", () {
    var acquiredLock = false;

    var lock = lockRequestor.withLock(randomLock(), () => acquiredLock = true, timeout: new Duration(milliseconds: 500));

    new Future.delayed(new Duration(milliseconds: 100))
      .then((_) {
        expect(acquiredLock, isTrue, reason: "Failed to acquire lock");
      });

    return lock;
  });

  test("withLock should timeout when lock is not available", () {
    var lockType = randomLock();

    var lock1 = lockRequestor.withLock(lockType, () => new Future.delayed(new Duration(seconds: 2)), author: '1');
    var lock2 = lockRequestor.withLock(lockType, () => null, timeout: new Duration(milliseconds: 500));

    expect(lock2 , throwsA(new isInstanceOf<LockTimeoutException>()));

    return lock1;
  });

  test("nested withLock should be able to timeout", () {
    var lockType1 = randomLock();
    var lockType2 = randomLock();

    var lock1 = lockRequestor.withLock(lockType2, () => new Future.delayed(new Duration(seconds: 1)));
    var lock2 = lockRequestor.withLock(lockType1, () => lockRequestor.withLock(lockType2, (){}, timeout: new Duration(milliseconds: 500)));

    expect(lock2, throwsA(new isInstanceOf<LockTimeoutException>()));

    return lock1;

  });

}
