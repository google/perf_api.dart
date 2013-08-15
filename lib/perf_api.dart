library perf_api;

/**
 * A simple profiler api.
 */
abstract class Profiler {

  /**
   * Times execution of the [body]. Body can either be a no argument function,
   * or a Future. If function, it is executed synchronously and its return value
   * is returned. If it's a Future, then timing is stopped when the future
   * completes either successfully or with error. The "then" of the future with
   * same result values is returned. See [startTimer] for more information
   * about [extraData].
   */
  dynamic time(String id, body, [String extraData]);

  /**
   * Starts a timer for a given action [id]. If the timer is already started,
   * this method will throw a [TimerError]. [extraData] is additional
   * infromation about the timed action. Implementing profiler is free to
   * ignore it.
   */
  void startTimer(String id, [String extraData]);

  /**
   * Stop a timer for a given [descr]. A timer must already be started,
   * otherwise it will throw a [TimerError].
   */
  void stopTimer(String id);

  /**
   * A simple zero-duration marker.
   */
  void markTime(String id);
}

class TimerError extends Error {
  String message;

  TimerError(String message);

  toString() => message;
}