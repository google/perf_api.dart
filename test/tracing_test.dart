library tracing.test;

import 'dart:async';

import 'package:unittest/unittest.dart';
import 'package:perf_api/perf_api.dart';

main() {
  group('Tracing', () {
    var system;
    var clock;
    setUp(() {
      clock = 0;
      system = new TraceSystem(clock: () => clock++);
    });
    test('basic traced events', () {
      system.tracing.take(2).toList().then(expectAsync1((events) {
        expect(events[0].toString(), 'test(0, event1)');
        expect(events[1].toString(), 'test(0, event2)');
      }));
      system.tracing.skip(2).listen(neverCalled());
      system.trace.record(new TestEvent('event1'));
      system.trace.record(new TestEvent('event2'));
    });
    test('nested traced events', () {
      system.tracing.take(5).toList().then(expectAsync1((events) {
        expect(events[0].toString(), 'test(0, event1)');
        expect(events[1].toString(), 'tracing.child.start(0, 1)');
        expect(events[2].toString(), 'test(1, child)');
        expect(events[3].toString(), 'tracing.child.fnEnd(0, 1)');
        expect(events[4].toString(), 'test(0, event2)');
      }));
      system.tracing.skip(5).listen(neverCalled());
      system.trace.record(new TestEvent('event1'));
      system.trace.child(() {
        system.trace.record(new TestEvent('child'));
      });
      system.trace.record(new TestEvent('event2'));
    });
    test('Trace propagates into microtask', () {
      system.tracing.take(5).toList().then(expectAsync1((events) {
        expect(events[0].toString(), 'tracing.child.start(0, 1)');
        expect(events[1].toString(), 'tracing.child.fnEnd(0, 1)');
        expect(events[2].toString(), 'tracing.microtask.start(1)');
        expect(events[3].toString(), 'test(1, microtask)');
        expect(events[4].toString(), 'tracing.microtask.end(1)');
      }));
      system.tracing.skip(5).listen(neverCalled());
      system.trace.child(() {
        scheduleMicrotask(() {
          system.trace.record(new TestEvent('microtask'));
        });
      });
    });
    test('Trace does not record microtask start/end when requested', () {
      system.tracing.take(3).toList().then(expectAsync1((events) {
        expect(events[0].toString(), 'tracing.child.start(0, 1)');
        expect(events[1].toString(), 'tracing.child.fnEnd(0, 1)');
        expect(events[2].toString(), 'test(1, microtask)');
      }));
      system.tracing.skip(3).listen(neverCalled());
      system.trace.child(() {
        scheduleMicrotask(() {
          system.trace.record(new TestEvent('microtask'));
        });
      }, traceMicrotasks: false);
    });
    test('Microtasks recorded by outer trace when disabled by inner trace', () {
      system.tracing.take(7).toList().then(expectAsync1((events) {
        expect(events[0].toString(), 'tracing.child.start(0, 1)');
        expect(events[1].toString(), 'tracing.child.start(1, 2)');
        expect(events[2].toString(), 'tracing.child.fnEnd(1, 2)');
        expect(events[3].toString(), 'tracing.child.fnEnd(0, 1)');
        expect(events[4].toString(), 'tracing.microtask.start(2)');
        expect(events[5].toString(), 'test(2, microtask)');
        expect(events[6].toString(), 'tracing.microtask.end(2)');
      }));
      system.tracing.skip(7).listen(neverCalled());
      system.trace.child(() {
        system.trace.child(() {
          scheduleMicrotask(() {
            system.trace.record(new TestEvent('microtask'));
          });
        }, traceMicrotasks: false);
      });
    });
    test('exclude() prevents trace context from being propagated', () {
      system.tracing.take(4).toList().then(expectAsync1((events) {
        expect(events[0].toString(), 'tracing.child.start(0, 1)');
        expect(events[1].toString(), 'test(0, excluded)');
        expect(events[2].toString(), 'tracing.child.fnEnd(0, 1)');
        expect(events[3].toString(), 'test(0, microtask)');
      }));
      system.tracing.skip(4).listen(neverCalled());
      system.trace.child(() {
        system.trace.exclude(() {
          system.trace.record(new TestEvent('excluded'));
          scheduleMicrotask(() {
            system.trace.record(new TestEvent('microtask'));
          });
        });
      });
    });
    test('Nested children only track microtask once', () {
      system.tracing.take(7).toList().then(expectAsync1((events) {
        expect(events[0].toString(), 'tracing.child.start(0, 1)');
        expect(events[1].toString(), 'tracing.child.start(1, 2)');
        expect(events[2].toString(), 'tracing.child.fnEnd(1, 2)');
        expect(events[3].toString(), 'tracing.child.fnEnd(0, 1)');
        expect(events[4].toString(), 'tracing.microtask.start(2)');
        expect(events[5].toString(), 'test(2, microtask)');
        expect(events[6].toString(), 'tracing.microtask.end(2)');
      }));
      system.tracing.skip(7).listen(neverCalled());
      system.trace.child(() {
        system.trace.child(() {
          scheduleMicrotask(() {
            system.trace.record(new TestEvent('microtask'));
          });
        });
      });
    });
    test('Nested children with child started in microtask', () {
      system.tracing.take(7).toList().then(expectAsync1((events) {
        expect(events[0].toString(), 'tracing.child.start(0, 1)');
        expect(events[1].toString(), 'tracing.child.fnEnd(0, 1)');
        expect(events[2].toString(), 'tracing.microtask.start(1)');
        expect(events[3].toString(), 'tracing.child.start(1, 2)');
        expect(events[4].toString(), 'test(2, microtask)');
        expect(events[5].toString(), 'tracing.child.fnEnd(1, 2)');
        expect(events[6].toString(), 'tracing.microtask.end(1)');
      }));
      system.tracing.skip(7).listen(neverCalled());
      system.trace.child(() {
        scheduleMicrotask(() {
          system.trace.child(() {
            system.trace.record(new TestEvent('microtask'));
          });
        });
      });
    });
    test('TraceEvents have timestamps set when recorded.', () {
      system.tracing.take(3).toList().then(expectAsync1((events) {
        expect(events[0].ts, 0);
        expect(events[1].ts, 1);
        expect(events[2].ts, 2);
      }));
      system.tracing.skip(3).listen(neverCalled());
      system.trace.record(new TestEvent('event1'));
      system.trace.record(new TestEvent('event2'));
      system.trace.record(new TestEvent('event3'));
      expect(new TestEvent('unused').ts, isNull);
    });
  });
}

class TestEvent extends TraceEvent {
  final String message;

  TestEvent(this.message);

  String toString() => 'test($traceId, $message)';
}

neverCalled() => expectAsync1((_) {}, count: 0);