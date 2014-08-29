library perf_api;

import 'dart:async';
import 'dart:collection';

/**
 * A simple profiler api.
 */
class Profiler {
  final Counters counters = new Counters();

  /**
   * Starts a new timer for a given action [name]. A timer id will be
   * returned which can be used in [stopTimer] to stop the timer.
   *
   * [extraData] is additional information about the timed action. Implementing
   * profiler should not assume any semantic or syntactic structure of that
   * data and is free to ignore it in aggregate reports.
   */
  dynamic startTimer(String name, [dynamic extraData]) => null;

  /**
   * Stop a timer for a given [idOrName]. [idOrName] can either be a timer
   * identifier returned from [startTimer] or a timer name string. If [idOrName]
   * is invalid or timer for that [idOrName] was already stopped then
   * [ProfilerError] will be thrown. If [idOrName] is a String timer name then
   * the latest active timer with that name will be stopped.
   */
  void stopTimer(dynamic idOrName) {}

  /**
   * A simple zero-duration marker.
   */
  void markTime(String name, [dynamic extraData]) {}

  /**
   * Times execution of the [functionOrFuture]. Body can either be a no argument
   * function or a [Future]. If function, it is executed synchronously and its
   * return value is returned. If it's a Future, then timing is stopped when the
   * future completes either successfully or with error.
   */
  dynamic time(String name, functionOrFuture, [dynamic extraData]) {
    var id = startTimer(name, extraData);
    if (functionOrFuture is Function) {
      try {
        return functionOrFuture();
      } finally {
        stopTimer(id);
      }
    }
    if (functionOrFuture is Future) {
      return functionOrFuture.then(
          (v) {
            stopTimer(id);
            return v;
          },
          onError: (e) {
            stopTimer(id);
            throw e;
          });
    }
    throw new ProfilerError(
        'Invalid functionOrFuture or type ${functionOrFuture.runtimeType}');
  }
}

class Counters {

  final Map<String, int> _counters = new HashMap<String, int>();

  /**
   * Increments the counter under [counterName] by [delta]. Default [delta]
   * is 1. If counter is not yet initialized, its value is assumed to be 0.
   * [delta] is allowed to be negative and it is possible for the counter value
   * to become negative.
   */
  int increment(String counterName, [int delta = 1]) {
    _counters.putIfAbsent(counterName, _initWithZero);
    _counters[counterName] += delta;
    return _counters[counterName];
  }

  /**
   * Returns the current value of the counter. If the counter value is not
   * initialized then null is returned.
   */
  int operator [](String counterName) => _counters[counterName];

  /**
   * Sets a [value] for a [counterName]. Any previous value is overridden.
   */
  operator []=(String counterName, int value) => _counters[counterName] = value;

  /**
   * Returns an immutable map of all known counter values.
   */
  Map<String, int> get all => new UnmodifiableMapView<String, int>(_counters);
}

int _initWithZero() => 0;

class ProfilerError extends Error {
  final String message;
  ProfilerError(this.message);
  String toString() => message;
}
