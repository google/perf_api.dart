library tracing;

import 'dart:async';

/// A function which returns the current unix timestamp, in millis.
typedef int ClockFn();

/// Default implementation of [ClockFn].
int _dateTimeClock() => new DateTime.now().millisecondsSinceEpoch;

/// A [TraceSystem] encapsulates state which otherwise would be static and makes it easier
/// to test tracing.
class TraceSystem {

  /// The default [TraceSystem], used by global getters.
  static final TraceSystem DEFAULT = new TraceSystem();

  /// Monotonically increasing trace id, which must be unique within the [TraceEvent] stream.
  int traceId = 1;

  /// The clock to use when recording timestamps.
  final ClockFn clock;

  /// The root [Trace], which has id 0. Top-level events and child [Trace]s are tagged with the root
  /// trace.
  Trace rootTrace;

  /// [StreamController] that sinks [TraceEvent]s.
  final traceEventSink = new StreamController<TraceEvent>.broadcast(sync: true);

  /// Synchronous [Stream] of all [TraceEvent]s.
  Stream<TraceEvent> get tracing => traceEventSink.stream;

  /// [ZoneSpecification] for child traces within this system. This zone wraps microtasks to record
  /// their start and finish times.
  ZoneSpecification tracingZoneSpec;

  /// [ZoneSpecification] which deactivates tracing (until activated again).
  ZoneSpecification noTracingZoneSpec;

  /// Tracks whether a microtask being scheduled has already been wrapped by an inner tracing zone.
  /// Multiple tracing zones can be nested at any given time, and this signal ensures that only the
  /// inner one records the microtask.
  bool microtaskWrapInProgress = false;

  /// Generate a new trace id.
  int newTraceId() => traceId++;

  /// Construct a new TraceSystem (probably only useful for tests).
  TraceSystem({ClockFn this.clock: _dateTimeClock}) {
    rootTrace = new Trace(this, 0);
    tracingZoneSpec = new ZoneSpecification(scheduleMicrotask: _traceMicrotask);
    noTracingZoneSpec = new ZoneSpecification(scheduleMicrotask: _dontTraceMicrotask);
  }

  /// Note that this will return traces from other [TraceSystem]s if they are currently active.
  Trace get trace {
    var trace = Zone.current['trace'];
    if (trace == null) {
      return rootTrace;
    }
    return trace;
  }

  /// Possibly wrap a microtask that occurs during a trace, if this is the first
  /// time that microtask has been seen here.
  _traceMicrotask(self, parent, zone, microtask) {
    if (microtaskWrapInProgress) {
      // A nested zone has already wrapped this one, schedule without wrapping.
      parent.scheduleMicrotask(zone, microtask);
      return;
    }
    microtaskWrapInProgress = true;
    // Wrap the microtask in a function that records its start/end times.
    void wrapped() {
      trace.record(new MicrotaskStartEvent());
      microtask();
      trace.record(new MicrotaskEndEvent());
    }
    // This is the call that could result in recursion to [_traceMicrotask].
    parent.scheduleMicrotask(zone, wrapped);
    microtaskWrapInProgress = false;
  }

  _dontTraceMicrotask(self, parent, zone, microtask) {
    // Don't want to catch any async events happening within this zone (if
    // they're not already being caught down the zone stack).
    var oldVal = microtaskWrapInProgress;
    microtaskWrapInProgress = true;
    parent.scheduleMicrotask(zone, wrapped);
    microtaskWrapInProgress = oldVal;
  }
}

/// Get the currently active [Trace], regardless of [TraceSystem]. This will
/// return the default [TraceSystem] root trace when there isn't any active [Trace].
Trace get trace => TraceSystem.DEFAULT.trace;

/// [Stream] of [TraceEvent]s from the default [TraceSystem].
Stream<TraceEvent> get tracing => TraceSystem.DEFAULT.tracing;

/// An event that occurs during a trace. Events can represent child traces beginning or ending,
/// asynchronous operations.
class TraceEvent {
   int _traceId;
   int _ts;

  TraceEvent();

  int get traceId => _traceId;
  int get ts => _ts;
}

/// Base class for [TraceEvent]s which refer to a child [Trace] from a parent [Trace].
abstract class ChildTraceEvent extends TraceEvent {
  int _childTraceId;

  int get childTraceId => _childTraceId;
}

/// Indicates a child trace has been started within an outer trace.
class ChildTraceStartEvent extends ChildTraceEvent {
  String toString() => 'tracing.child.start($childTraceId)';
}

/// Indicates the function which represented the scope of the child trace has completed execution.
/// This does not actually mean that the child trace is completely over, as asynchronous operations
/// may have been scheduled.
class ChildTraceFunctionEndEvent extends ChildTraceEvent {
  String toString() => 'tracing.child.fnEnd($childTraceId)';
}

/// Indicates that a microtask has started running.
class MicrotaskStartEvent extends TraceEvent {
  String toString() => 'tracing.microtask.start';
}

/// Indicates that a microtask has completed running. Other microtasks may have been scheduled as a
/// result.
class MicrotaskEndEvent extends TraceEvent {
  String toString() => 'tracing.microtask.end';
}

/// An active [Trace] is a destination for [TraceEvent]s (via [record]), and allows child traces to
/// be spawned.
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

  /// Spawn a child [Trace] by running the given function. [start] and [end] can optionally be
  /// specified as child classes of [ChildTraceStartEvent] and [ChildTraceFunctionEndEvent],
  /// respectfully, and will be used in place of those default events to indicate the beginning
  /// and end of the execution of [fn] within the child [Trace].
  void child(void fn(), {ChildTraceStartEvent start: null, ChildTraceFunctionEndEvent end: null}) {
    if (start == null) {
      start = new ChildTraceStartEvent();
    }
    start._childTraceId = system.newTraceId();
    record(start);
    runZoned(fn, zoneSpecification: system.tracingZoneSpec,
        zoneValues: {'trace': new Trace(system, start.childTraceId)});
    if (end == null) {
      end = new ChildTraceFunctionEndEvent();
    }
    end._childTraceId = start.childTraceId;
    record(end);
  }

  /// Stop including [TraceEvent]s and asynchronous calls made within [fn] in the current [Trace].
  void exclude(void fn()) =>
      runZoned(fn, zoneSpecification: system.noTracingZoneSpec, zoneValues: {'trace': rootTrace});
}

/// An example tracing event.
class TestEvent extends TraceEvent {
  final String message;

  TestEvent(this.message);

  String toString() => 'test($message)';
}

main() {
  tracing.listen((ev) => print('${ev.traceId} @ ${ev.ts}: $ev'));
  trace.child(() {
    trace.record(new TestEvent('before microtask'));
    scheduleMicrotask(() {
      trace.record(new TestEvent('in microtask'));
    });
  });
}