library perf_api.noop_test;

import 'dart:async';

import 'package:unittest/unittest.dart';
import 'package:perf_api/perf_api.dart';

main() {

  test('should be able to instantiate as a noop profiler', () {
    expect(() => new Profiler(), returnsNormally);
  });

  group('Default Impl', () {
    var perf;

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
  });
}