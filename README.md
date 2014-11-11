# Utility for sharing unique resources

## What does it provide ?
There's one server (*Locker*) that handles requests for locks and distributes them in a way,
so that there is always at most one requestor holding a lock of some type at a time.
Then there's a *LockRequestor* that sends requests for those locks and provides
a functionality which ensures that a given callback is ran if and only if the requested
lock is acquired.

## How does it help ?
Imagine you have many dart programs sharing one resource, and you only want one at a time to access it. 
Well, now you only start the Locker server and wrap the part, which accesses the resource, into one method 
with the same lock for all the programs and you're done !

Another example - you may have a non-transactional database (e.g. mongo) and wish to make all operations transactional.
You can just use the same lock for every operation on database, which ensures there's only 
one operation at a time using the database and therefore it is transactional.  

## How to use this ?

### At first, there comes a quick installation for Linux systems with upstart
Requirements: 

* Availability of port 27002. If it's not available, change the port in tool/upstart_template to some available one.
* Your root must be capable of running *dart* without a path.

Clone this project (& get dependencies) and run *sudo tool/installLocker.sh*. 
This will create locker.conf file in /etc/init and start a *locker* service. There you go ! Locker server is now running !

If you don't have Linux with upstart, you can just run *dart bin/mongo_locker.dart -h [host url] -p [port]*

### Run a callback with lock
Create the LockRequestor, connect it to proper url and port (the ones specified in Locker)
and wrap your desired callback in LockRequestor's *withLock* method ! It's just as easy as this:

     //initialized with start of application
     LockRequestor lockRequestor = new LockRequestor(lockerUrl, lockerPort);
     Future waitForMe = lockRequestor.init(); // wait for this operation to complete before using the lockRequestor
     ...
     //somewhere in code
     myCallback() => print("This is printed while having 'my_lock' !");
     lockRequestor.withLock('my_lock', myCallback));

Of course, the Locker has to be running before any requests by LockRequestor are made.

### Check, who has locks
Cannot acquire a lock for a very long time and you are not sure where's the problem?
Run *dart tool/get_info.dart -h [host url] -p [port]* and it will list down all the lock holders and requestors for you!
Host and port defaults to 127.0.0.1 and 27002 if not specified. It does not show types of locks,
which were acquired somewhere in the past, but are not now requested. To show them, use flag *-e*.
For easier reading, you may add *author* to *withLock* call, which will be here displayed with prepending @.
The line prepending with \* currently has the lock. The duration signalizes, how long is the request in its status (requesting for lock / holding it).
Request id is prepended with #.

Example output:

     test-lock-1:
     * @create_user, #0.9235510017307383--0, duration: 0:00:14.379000
       @update_something, #0.9235510017307383--2, duration: 0:00:05.375000
     
     test-lock-2:
     * @check_other_resource, #0.9235510017307383--1, duration: 0:00:00.378000
