library tracing.test;

import 'dart:async';

import 'package:unittest/unittest.dart';
import 'package:perf_api/perf_api.dart';

main() {
  group('Tracing', () {
    var system;
    var clock;
    var oldTest;
    setUp(() {
      clock = 0;
      system = new TraceSystem(clock: () => clock++);
    });
    wrap(fn()) => () => system.traceInSystem(fn);
    test('basic traced events', wrap(() {
      system.events.take(2).toList().then(expectAsync1((events) {
        expect(events[0].toString(), 'test(0, event1)');
        expect(events[1].toString(), 'test(0, event2)');
      }));
      system.events.skip(2).listen(neverCalled());
      system.current.record(new TestEvent('event1'));
      system.current.record(new TestEvent('event2'));
    }));
    test('nested traced events', wrap(() {
      system.events.take(5).toList().then(expectAsync1((events) {
        expect(events[0].toString(), 'test(0, event1)');
        expect(events[1].toString(), 'tracing.child.start(0, 1)');
        expect(events[2].toString(), 'test(1, child)');
        expect(events[3].toString(), 'tracing.child.fnEnd(0, 1)');
        expect(events[4].toString(), 'test(0, event2)');
      }));
      system.events.skip(5).listen(neverCalled());
      system.current.record(new TestEvent('event1'));
      system.current.child(() {
        system.current.record(new TestEvent('child'));
      });
      system.current.record(new TestEvent('event2'));
    }));
    test('Trace propagates into microtask', wrap(() {
      system.events.take(5).toList().then(expectAsync1((events) {
        expect(events[0].toString(), 'tracing.child.start(0, 1)');
        expect(events[1].toString(), 'tracing.child.fnEnd(0, 1)');
        expect(events[2].toString(), 'tracing.microtask.start(1)');
        expect(events[3].toString(), 'test(1, microtask)');
        expect(events[4].toString(), 'tracing.microtask.end(1)');
      }));
      system.events.skip(5).listen(neverCalled());
      system.current.child(() {
        scheduleMicrotask(() {
          system.current.record(new TestEvent('microtask'));
        });
      });
    }));
    test('Trace does not record microtask start/end when requested', wrap(() {
      system.events.take(3).toList().then(expectAsync1((events) {
        expect(events[0].toString(), 'tracing.child.start(0, 1)');
        expect(events[1].toString(), 'tracing.child.fnEnd(0, 1)');
        expect(events[2].toString(), 'test(1, microtask)');
      }));
      system.events.skip(3).listen(neverCalled());
      system.current.child(() {
        scheduleMicrotask(() {
          system.current.record(new TestEvent('microtask'));
        });
      }, asyncEvents: false);
    }));
    test('Microtasks not recorded when disabled by inner trace', wrap(() {
      system.events.take(5).toList().then(expectAsync1((events) {
        expect(events[0].toString(), 'tracing.child.start(0, 1)');
        expect(events[1].toString(), 'tracing.child.start(1, 2)');
        expect(events[2].toString(), 'tracing.child.fnEnd(1, 2)');
        expect(events[3].toString(), 'tracing.child.fnEnd(0, 1)');
        expect(events[4].toString(), 'test(2, microtask)');
      }));
      system.events.skip(5).listen(neverCalled());
      system.current.child(() {
        system.current.child(() {
          scheduleMicrotask(() {
            system.current.record(new TestEvent('microtask'));
          });
        }, asyncEvents: false);
      });
    }));
    test('exclude() prevents trace context from being propagated', wrap(() {
      system.events.take(4).toList().then(expectAsync1((events) {
        expect(events[0].toString(), 'tracing.child.start(0, 1)');
        expect(events[1].toString(), 'test(0, excluded)');
        expect(events[2].toString(), 'tracing.child.fnEnd(0, 1)');
        expect(events[3].toString(), 'test(0, microtask)');
      }));
      system.events.skip(4).listen(neverCalled());
      system.current.child(() {
        system.current.exclude(() {
          system.current.record(new TestEvent('excluded'));
          scheduleMicrotask(() {
            system.current.record(new TestEvent('microtask'));
          });
        });
      });
    }));
    test('Nested children only track microtask once', wrap(() {
      system.events.take(7).toList().then(expectAsync1((events) {
        expect(events[0].toString(), 'tracing.child.start(0, 1)');
        expect(events[1].toString(), 'tracing.child.start(1, 2)');
        expect(events[2].toString(), 'tracing.child.fnEnd(1, 2)');
        expect(events[3].toString(), 'tracing.child.fnEnd(0, 1)');
        expect(events[4].toString(), 'tracing.microtask.start(2)');
        expect(events[5].toString(), 'test(2, microtask)');
        expect(events[6].toString(), 'tracing.microtask.end(2)');
      }));
      system.events.skip(7).listen(neverCalled());
      system.current.child(() {
        system.current.child(() {
          scheduleMicrotask(() {
            system.current.record(new TestEvent('microtask'));
          });
        });
      });
    }));
    test('Nested children with child started in microtask', wrap(() {
      system.events.take(7).toList().then(expectAsync1((events) {
        expect(events[0].toString(), 'tracing.child.start(0, 1)');
        expect(events[1].toString(), 'tracing.child.fnEnd(0, 1)');
        expect(events[2].toString(), 'tracing.microtask.start(1)');
        expect(events[3].toString(), 'tracing.child.start(1, 2)');
        expect(events[4].toString(), 'test(2, microtask)');
        expect(events[5].toString(), 'tracing.child.fnEnd(1, 2)');
        expect(events[6].toString(), 'tracing.microtask.end(1)');
      }));
      system.events.skip(7).listen(neverCalled());
      system.current.child(() {
        scheduleMicrotask(() {
          system.current.child(() {
            system.current.record(new TestEvent('microtask'));
          });
        });
      });
    }));
    test('TraceEvents have timestamps set when recorded.', wrap(() {
      system.events.take(3).toList().then(expectAsync1((events) {
        expect(events[0].ts, 0);
        expect(events[1].ts, 1);
        expect(events[2].ts, 2);
      }));
      system.events.skip(3).listen(neverCalled());
      system.current.record(new TestEvent('event1'));
      system.current.record(new TestEvent('event2'));
      system.current.record(new TestEvent('event3'));
      expect(new TestEvent('unused').ts, isNull);
    }));
    test('TraceEvents have stack traces recorded, if asked.', wrap(() {

      system.events.take(1).toList().then(expectAsync1((events) {
        expect(events[0].stackTrace, new isInstanceOf<StackTrace>());
        expect("${events[0].stackTrace}",
            contains("Trace.record (package:perf_api/tracing.dart"));
      }));
      system.events.skip(1).listen(neverCalled());
      system.current.record(new TestEvent('event'), stackTrace: true);
    }));
  });
}

class TestEvent extends TraceEvent {
  final String message;

  TestEvent(this.message);

  String toString() => 'test($traceId, $message)';
}

neverCalled() => expectAsync1((_) {}, count: 0);