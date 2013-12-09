part of perf_api;

/// A function which returns the current unix timestamp, in millis.
typedef int ClockFn();

/// Default implementation of [ClockFn].
int _dateTimeClock() => new DateTime.now().millisecondsSinceEpoch;

/// Key used to indicate the current [TraceSystem] in a [Zone].
const _TRACE_SYSTEM_KEY = const Symbol('perf_api.traceSystem');

/// Get the current [TraceSystem], or [null] for none.
TraceSystem get traceSystem => Zone.current[_TRACE_SYSTEM_KEY];

/// Get the current [Trace]. This is never [null], and will return a [NoopTrace]
/// if there is no current [TraceSystem].
Trace get trace => traceSystem != null ? traceSystem.current :
    const NoopTrace();

/// A [TraceSystem] encapsulates state which otherwise would be static and makes
/// it easier to test tracing.
class TraceSystem {

  /// Clock used to take timestamps.
  final ClockFn clock;

  /// Zone specification for the traced zone.
  var _zoneSpec;

  /// Stack of currently active [Trace]s.
  var _traceStack = <Trace>[];

  /// The root [Trace], used when the [_traceStack] is empty.
  var _rootTrace;

  /// A counter that generates trace ids.
  var _traceCounter= 1;

  /// The sink for [TraceEvent]s.
  var _eventSink = new StreamController<TraceEvent>.broadcast(sync: true);

  /// Create a new [TraceSystem] with the given parameters.
  TraceSystem({
      this.clock: _dateTimeClock,
      defaultAsync: false,
      defaultAsyncEvents: false}) {
    _rootTrace = new Trace._private(this, 0, defaultAsync, defaultAsyncEvents);
    _zoneSpec = new ZoneSpecification(scheduleMicrotask: _scheduleMicrotask);
  }

  /// Get the currently active [Trace].
  Trace get current => _traceStack.isNotEmpty ? _traceStack.last : _rootTrace;

  /// Get the root [Trace].
  Trace get root => _rootTrace;

  /// Get a [Stream] of [TraceEvent]s from [Trace]s in this [TraceSystem].
  Stream<TraceEvent> get events => _eventSink.stream;

  /// Run the given function inside this a [Zone] with this [TraceSystem]. Most
  /// clients will want to wrap main() with this function.
  void traceInSystem(fn()) {
    runZoned(fn, zoneSpecification: _zoneSpec, zoneValues: {
      _TRACE_SYSTEM_KEY: this
    });
  }

  /// Spawn a child [Trace] of the current active [Trace]. The child [Trace] is
  /// configurable with the optional parameters, such as whether asynchronous
  /// events are traced ([async]), reported on ([asyncEvents]) and whether an
  /// end event for [fn] is published ([endEvent]).
  child(fn(), {bool async: true, bool asyncEvents: true, bool endEvent: true}) {
    var childTrace =
        new Trace._private(this, _nextTraceId, async, asyncEvents);
    current.record(new ChildTraceEvent().._childTraceId = childTrace.id);
    try {
      unsafeEnter(childTrace);
      return fn();
    } finally {
      unsafeExit(childTrace);
      current.record(new ChildTraceFunctionEndEvent()
        .._childTraceId = childTrace.id);
    }
  }

  /// Exclude the given [fn] from the current [Trace]. This is equivalent to
  /// re-entering the root [Trace] before running the function.
  void exclude(fn()) {
    try {
      unsafeEnter(root);
      return fn();
    } finally {
      unsafeExit(root);
    }
  }

  /// Enter a [Trace] by pushing it on the stack. This is inherently an unsafe
  /// operation because it is the caller's responsibility to later exit the
  /// [Trace].
  void unsafeEnter(Trace trace) => _traceStack.add(trace);

  /// Exit a [Trace] by removing it from the top of the stack. Currently this
  /// function doesn't check if the top of the stack is the same [trace] that's
  /// passed, but this could change.
  void unsafeExit(Trace trace) {
    if (_traceStack.isNotEmpty) {
      _traceStack.removeLast();
    }
  }

  /// Emit a [TraceEvent] on the [events] [Stream].
  void _emit(TraceEvent event) => _eventSink.add(event);

  /// Generate a new trace id.
  int get _nextTraceId => _traceCounter++;

  /// Possibly wrap the given [microtask] to run within the current [Trace].
  _scheduleMicrotask(self, parent, zone, microtask) {
    var trace = current;
    var toSchedule = microtask;
    if (trace.async) {
      toSchedule = () {
        _traceStack = <Trace>[trace];
        if (trace.asyncEvents) {
           trace.record(new MicrotaskStartEvent());
        }
        try {
          microtask();
        } finally {
          if (trace.asyncEvents) {
            trace.record(new MicrotaskEndEvent());
          }
          _traceStack = <Trace>[];
        }
      };
    }
    parent.scheduleMicrotask(zone, toSchedule);
  }
}

/// Unit of accounting for [TraceEvent]s. Only one [Trace] is active at any
/// given time.
class Trace {
  final TraceSystem system;
  final int id;

  final bool async;
  final bool asyncEvents;

  Trace._private(this.system, this.id, this.async, this.asyncEvents);

  /// Record a [TraceEvent] within this [Trace]. Optionally, take a [StackTrace]
  /// at the moment of recording.
  void record(TraceEvent event, {bool stackTrace: false}) {
    event._traceId = id;
    event._ts = system.clock();
    if (stackTrace) {
      event._stackTrace = _captureStackTrace();
    }
    system._emit(event);
  }

  /// Spawn a child [Trace] of the current active [Trace]. The child [Trace] is
  /// configurable with the optional parameters, such as whether asynchronous
  /// events are traced ([async]), reported on ([asyncEvents]) and whether an
  /// end event for [fn] is published ([endEvent]).
  child(fn(), {bool async: true, bool asyncEvents: true, bool endEvent: true})
      => system.child(
          fn, async: async, asyncEvents: asyncEvents, endEvent: endEvent);

  /// Exclude the given [fn] from the current [Trace]. This is equivalent to
  /// re-entering the root [Trace] before running the function.
  exclude(fn()) => system.exclude(fn);

  /// Enter a [Trace] by pushing it on the stack. This is inherently an unsafe
  /// operation because it is the caller's responsibility to later exit the
  /// [Trace].
  void unsafeEnter(Trace trace) => system.unsafeEnter(trace);

  /// Exit a [Trace] by removing it from the top of the stack. Currently this
  /// function doesn't check if the top of the stack is the same [trace] that's
  /// passed, but this could change.
  void unsafeExit(Trace trace) => system.unsafeExit(trace);

  String toString() => "{trace: $id, async: $async, asyncEvents: $asyncEvents}";

  /// Take a [StackTrace] and return it.
  static StackTrace _captureStackTrace() {
    try {
      throw 'trace';
    } catch (e, trace) {
      return trace;
    }
  }
}

/// A [Trace] that does nothing. Returned by [trace] when there is no active
/// [TraceSystem].
class NoopTrace implements Trace {
  TraceSystem get system => null;
  int get id => 0;
  bool get async => false;
  bool get asyncEvents => false;

  const NoopTrace();

  void record(event, {stackTrace}) {}

  void unsafeEnter(trace) {}

  void unsafeExit(trace) {}

  child(fn(), {async, asyncEvents, endEvent}) => fn();

  void exclude(fn()) => fn();
}

/// An event that occurs during a trace. [TraceEvent]s can represent child
/// [Trace]s, beginning or ending asynchronous operations, and user events.
abstract class TraceEvent {
  int _traceId;
  int _ts;
  StackTrace _stackTrace;

  TraceEvent();

  /// Trace id associated with this event.
  int get traceId => _traceId;

  /// Timestamp at which this event was recorded via [Trace.record].
  int get ts => _ts;

  /// Get the [StackTrace] associated with this [TraceEvent], if any.
  StackTrace get stackTrace => _stackTrace;
}

/// Indicates a child trace has been started within an outer trace.
class ChildTraceEvent extends TraceEvent {
  int _childTraceId;

  /// Child [Trace] id which was created within the [traceId] trace.
  int get childTraceId => _childTraceId;

  String toString() => 'tracing.child.start($traceId, $childTraceId)';
}

/// Indicates the function which represented the initial scope of the child
/// [Trace] had completed execution. This does not actually mean that the child
/// [Trace] is completely over, as asynchronous operations may have been
/// scheduled and will run with the child [Trace] context.
class ChildTraceFunctionEndEvent extends TraceEvent {
  int _childTraceId;

  /// Child [Trace] id of the function that just ended.
  int get childTraceId => _childTraceId;

  String toString() => 'tracing.child.fnEnd($traceId, $childTraceId)';
}

/// Indicates that a microtask has started running.
class MicrotaskStartEvent extends TraceEvent {
  String toString() => 'tracing.microtask.start($traceId)';
}

/// Indicates that a microtask has completed running. Other microtasks may have
/// been scheduled as a result.
class MicrotaskEndEvent extends TraceEvent {
  String toString() => 'tracing.microtask.end($traceId)';
}
