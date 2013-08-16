library perf_api;

import 'dart:async';

/**
 * A simple profiler api.
 */
abstract class Profiler {

  /**
   * Starts a new timer for a given action [name]. An [int] timer id will be
   * returned which can be used in [stopTimer] to stop the timer.
   *
   * [extraData] is additional information about the timed action. Implementing
   * profiler should not assume any semantic or syntactic structure of that
   * data and is free to ignore it in aggregate reports.
   */
  int startTimer(String name, [String extraData]);

  /**
   * Stop a timer for a given [idOrName]. If [idOrName] is [int] then it's
   * treated as an action identifier returned from [startTimer]. If id is
   * invalid or timer for that id was already stopped then [ProfilerError]
   * will be thrown. If [idOrName] is [String] then the latest active timer
   * with that name will be stopped. If no active timer exists then
   * [ProfilerError] will be thrown.
   */
  void stopTimer(dynamic idOrName);

  /**
   * A simple zero-duration marker.
   */
  void markTime(String name, [String extraData]);

  /**
   * Times execution of the [functionOrFuture]. Body can either be a no argument
   * function or a [Future]. If function, it is executed synchronously and its
   * return value is returned. If it's a Future, then timing is stopped when the
   * future completes either successfully or with error.
   */
  dynamic time(String name, functionOrFuture, [String extraData]) {
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

class ProfilerError extends Error {
  final String message;
  ProfilerError(String this.message);
  toString() => message;
}