import 'dart:async';
import 'dart:math';
import 'package:clean_lock/lock_requestor.dart';

Random _random = new Random();

void acquireLock(LockRequestor lockRequestor, String id, Duration duration) {
  var i = _random.nextInt(4);
  var authorId = i != 0 ? "example-author$i" : null;
  lockRequestor.withLock("example-lock$id", () => new Future.delayed(duration), author: authorId);
}

Duration seconds(int seconds) {
  return new Duration(seconds: seconds);
}

Duration minutes(int minutes) {
  return new Duration(minutes: minutes);
}

void main() {
  LockRequestor.connect("127.0.0.1", 27002)
    .then((LockRequestor lockRequestor) {
      acquireLock(lockRequestor, "example-lock1", seconds(5));
      acquireLock(lockRequestor, "example-lock1", minutes(5));
      acquireLock(lockRequestor, "example-lock1", minutes(5));

      acquireLock(lockRequestor, "example-lock2", minutes(5));
      acquireLock(lockRequestor, "example-lock2", seconds(0));
      acquireLock(lockRequestor, "example-lock2", minutes(5));

      acquireLock(lockRequestor, "example-lock3", seconds(0));

      acquireLock(lockRequestor, "example-lock4", minutes(5));
      acquireLock(lockRequestor, "example-lock4", minutes(5));
      acquireLock(lockRequestor, "example-lock4", minutes(5));
    });
}
