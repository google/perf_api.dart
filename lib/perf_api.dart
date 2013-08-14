library perf_api;

/**
 * A simple profiler api.
 */
abstract class Profiler {
  /**
   * Times execution of the [body].
   */
  Object time(String descr, Function body);

  /**
   * Starts a timer for a given [descr]. Allows nested timers.
   */
  void startTimer(String descr);

  /**
   * Stop a timer for a given [descr]. A timer must already be started,
   * pthrrwise it will throw an error.
   */
  void stopTimer(String descr);

  /**
   * A simple zero-duration marker.
   */
  void markTime(String descr);
}