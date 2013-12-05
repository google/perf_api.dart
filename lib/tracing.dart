part of perf_api;

/// A function which returns the current unix timestamp, in millis.
typedef int ClockFn();

/// Default implementation of [ClockFn].
int _dateTimeClock() => new DateTime.now().millisecondsSinceEpoch;

const _TRACE_KEY = const Symbol('perf_api.trace');
const _TRACE_MICROTASKS_KEY = const Symbol('perf_api.traceMicrotasks');

/// A [TraceSystem] encapsulates state which otherwise would be static and makes
/// it easier to test tracing.
class TraceSystem {

  /// The default [TraceSystem], used by global getters.
  static final TraceSystem DEFAULT = new TraceSystem();

  /// Monotonically increasing trace id, which must be unique within the
  /// [TraceEvent] stream.
  int traceId = 1;

  /// The clock to use when recording timestamps.
  final ClockFn clock;

  /// The root [Trace], which has id 0. Top-level events and child [Trace]s are
  /// tagged with the root trace.
  Trace rootTrace;

  /// [StreamController] that sinks [TraceEvent]s.
  final traceEventSink = new StreamController<TraceEvent>.broadcast(sync: true);

  /// Synchronous [Stream] of all [TraceEvent]s.
  Stream<TraceEvent> get tracing => traceEventSink.stream;

  /// [ZoneSpecification] for child traces within this system. This zone wraps
  /// microtasks to record their start and finish times.
  ZoneSpecification tracingZoneSpec;

  /// [ZoneSpecification] which deactivates tracing (until activated again).
  ZoneSpecification noTracingZoneSpec;

  /// Tracks whether a microtask being scheduled has already been wrapped by an
  /// inner tracing zone. Multiple tracing zones can be nested at any given
  /// time, and this flag ensures that only the inner one records the microtask.
  bool microtaskWrapInProgress = false;

  /// Generate a new trace id.
  int newTraceId() => traceId++;

  /// Construct a new TraceSystem (probably only useful for tests).
  TraceSystem({ClockFn this.clock: _dateTimeClock}) {
    rootTrace = new Trace(this, 0);
    tracingZoneSpec = new ZoneSpecification(
        scheduleMicrotask: _traceMicrotask);
    noTracingZoneSpec = new ZoneSpecification(
        scheduleMicrotask: _dontTraceMicrotask);
  }

  /// Note that this will return traces from other [TraceSystem]s if they are
  /// currently active.
  Trace get trace {
    var trace = Zone.current[_TRACE_KEY];
    if (trace == null) {
      return rootTrace;
    }
    return trace;
  }

  bool get traceMicrotasks {
    var current = Zone.current[_TRACE_MICROTASKS_KEY];
    if (current == null) {
      return false;
    }
    return current;
  }

  /// Possibly wrap a microtask that occurs during a trace, if this is the first
  /// time that microtask has been seen here.
  _traceMicrotask(self, parent, zone, microtask) {
    if (microtaskWrapInProgress || !traceMicrotasks) {
      // A nested zone has already wrapped this one or the user has requested
      // that microtasks not be traced. Either way, schedule without wrapping so
      // a parent zone can determine whether or not to wrap them.
      parent.scheduleMicrotask(zone, microtask);
      return;
    }
    microtaskWrapInProgress = true;
    // Need to save the current trace here, because once inside the wrapped
    // microtask, the parent zone will be current.
    var traceCached = trace;
    // Wrap the microtask in a function that records its start/end times.
    var wrapped = () {
      traceCached.record(new MicrotaskStartEvent());
      microtask();
      traceCached.record(new MicrotaskEndEvent());
    };
    // This is the call that could result in recursion to [_traceMicrotask].
    parent.scheduleMicrotask(zone, wrapped);
    microtaskWrapInProgress = false;
  }

/// Schedule a microtask without tracing it, either in this zone or any further.
  _dontTraceMicrotask(self, parent, zone, microtask) {
    // Don't want to catch any async events happening within this zone (if
    // they're not already being caught down the zone stack).
    var oldVal = microtaskWrapInProgress;
    microtaskWrapInProgress = true;
    parent.scheduleMicrotask(zone, microtask);
    microtaskWrapInProgress = oldVal;
  }
}

/// Get the currently active [Trace], regardless of [TraceSystem]. This will
/// return the default [TraceSystem] root [Trace] if there is no active [Trace].
Trace get trace => TraceSystem.DEFAULT.trace;

/// [Stream] of [TraceEvent]s from the default [TraceSystem].
Stream<TraceEvent> get tracing => TraceSystem.DEFAULT.tracing;

/// An event that occurs during a trace. [TraceEvent]s can represent child
/// [Trace]s, beginning or ending asynchronous operations, and user events.
abstract class TraceEvent {
   int _traceId;
   int _ts;

  TraceEvent();

  /// Trace id associated with this event.
  int get traceId => _traceId;

  /// Timestamp at which this event was recorded via [Trace.record].
  int get ts => _ts;
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

/// An active [Trace] is a destination for [TraceEvent]s (via [record]), and
/// allows child traces to be spawned.
class Trace {
  final TraceSystem system;
  final int id;

  Trace(this.system, this.id);

  /// Record a [TraceEvent] within this trace.
  void record(TraceEvent event) {
    event._traceId = id;
    event._ts = system.clock();
    system.traceEventSink.add(event);
  }

  /// Spawn a child [Trace] by running the given function. [start] and [end] can
  /// optionally be specified as child classes of [ChildTraceEvent] and
  /// [ChildTraceFunctionEndEvent], respectfully, and will be used in place of
  /// those default events to indicate the beginning and end of the execution of
  /// [fn] within the child [Trace]. A child [Trace] extends into microtasks
  /// scheduled within [fn] and subsequent asynchronous operations. These
  /// microtasks will have start/end events recorded via [MicrotaskStartEvent]
  /// and [MicrotaskEndEvent] unless [traceMicrotasks] is false.
  Trace child(void fn(), {
      ChildTraceEvent start: null,
      ChildTraceFunctionEndEvent end: null,
      bool traceMicrotasks: true}) {
    if (start == null) {
      start = new ChildTraceEvent();
    }
    start._childTraceId = system.newTraceId();
    record(start);
    var childTrace = new Trace(system, start.childTraceId);
    runZoned(fn, zoneSpecification: system.tracingZoneSpec, zoneValues: {
        _TRACE_KEY: childTrace,
        _TRACE_MICROTASKS_KEY: traceMicrotasks || system.traceMicrotasks});
    if (end == null) {
      end = new ChildTraceFunctionEndEvent();
    }
    end._childTraceId = start.childTraceId;
    record(end);
    return childTrace;
  }

  /// Stop including [TraceEvent]s and asynchronous calls made within [fn] in
  /// the current [Trace].
  void exclude(void fn()) =>
      runZoned(fn, zoneSpecification: system.noTracingZoneSpec, zoneValues: {
          _TRACE_KEY: system.rootTrace,
          _TRACE_MICROTASKS_KEY: false});
}
