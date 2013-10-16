library perf_api.noop_test;

import 'dart:async';

import 'package:unittest/unittest.dart';
import 'package:perf_api/perf_api.dart';

main() {

  test('should be able to instantiate as a noop profiler', () {
    expect(() => new Profiler(), returnsNormally);
  });

  group('Default Impl', () {
    Profiler perf;

    setUp(() {
      perf = new Profiler();
    });

    test('should do noop startTimer', () {
      expect(() => perf.startTimer('foo', 'bar'), returnsNormally);
    });

    test('should do noop stopTimer', () {
      expect(() => perf.stopTimer('foo'), returnsNormally);
    });

    test('should do noop start/stopTimer', () {
      expect(() {
        var timerId = perf.startTimer('foo');
        perf.stopTimer(timerId);
      }, returnsNormally);
    });

    test('should do noop markTime', () {
      expect(() => perf.markTime('foo'), returnsNormally);
    });

    test('should do noop time function', () {
      expect(() => perf.time('foo', () {}, 'bar'), returnsNormally);
    });

    test('should do noop time future', () {
      expect(() {
        perf.time('foo', new Future.sync(() => null), 'bar');
      }, returnsNormally);
    });

    group('counters', () {

      test('should return null for uninitialized counter', () {
        expect(perf.getCounter('foo'), null);
      });

      test('should increment counter', () {
        perf.increment('foo');
        expect(perf.getCounter('foo'), 1);
      });

      test('should increment counter by given delta', () {
        perf.increment('foo', 10);
        expect(perf.getCounter('foo'), 10);
        perf.increment('foo', 5);
        expect(perf.getCounter('foo'), 15);
      });

      test('should set counter to provided value', () {
        perf.setCounter('foo', 10);
        expect(perf.getCounter('foo'), 10);
      });

      test('should decrement counter when delta is negative', () {
        perf.setCounter('foo', 15);
        perf.increment('foo', -10);
        expect(perf.getCounter('foo'), 5);
      });

      test('should allow negative counter values', () {
        perf.setCounter('foo', 10);
        perf.increment('foo', -15);
        expect(perf.getCounter('foo'), -5);
      });

      test('should return counters map', () {
        perf.setCounter('foo', 1);
        perf.increment('bar', 2);
        perf.setCounter('baz', 3);
        expect(perf.counters, {
          'foo': 1,
          'bar': 2,
          'baz': 3
        });
      });

      test('should return immutable counters map', () {
        expect(() => perf.counters['foo'] = 0,
            throwsA(new isInstanceOf<UnsupportedError>()));
        expect(() => perf.counters.putIfAbsent('foo', () => 0),
            throwsA(new isInstanceOf<UnsupportedError>()));
        expect(() => perf.counters.remove('foo'),
            throwsA(new isInstanceOf<UnsupportedError>()));
        expect(() => perf.counters.clear(),
            throwsA(new isInstanceOf<UnsupportedError>()));
        expect(() => perf.counters.addAll({}),
            throwsA(new isInstanceOf<UnsupportedError>()));
      });

    });
  });
}