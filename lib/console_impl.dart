library perf_api.console_impl;

import 'dart:html' as dom;
import 'dart:collection';
import 'perf_api.dart';
import 'package:quiver/collection.dart';

/**
 * Simple window.console based implementation.
 */
class ConsoleProfiler extends Profiler {
  int _nextId = 0;
  Map<int, String> _timers = new HashMap<int, String>();
  Multimap<String, int> _timerIds = new ListMultimap<String, int>();
  final dom.Window window;

  ConsoleProfiler() :this.window = dom.window;

  ConsoleProfiler.forWindow(this.window);

  dynamic startTimer(String name, [dynamic extraData]) {
    var timerId = _nextId++;
    _timers[timerId] = _timerName(name, extraData);
    _timerIds.add(name, timerId);
    window.console.time(_timerStr(timerId, _timers[timerId]));
    return timerId;
  }

  String _timerName(String name, dynamic extraData) =>
      '$name${_stringifyExtraData(extraData)}';

  String _stringifyExtraData(extraData) =>
      (extraData == null || extraData is! String) ? '' : ' $extraData';

  String _timerStr(id, name) => '${name} ($id)';

  void stopTimer(dynamic idOrName) {
    List<int> timerIds;
    String timerName;
    if (idOrName is int) {
      if (idOrName != null) {
        timerIds = [idOrName];
        timerName = _timers[idOrName];
      }
    } else {
      timerName = idOrName;
      timerIds = _timerIds[idOrName];
    }
    if (timerName == null || timerIds == null || timerIds.isEmpty) {
      throw new ProfilerError('Unable for find timer for $idOrName');
    }
    timerIds.toList().forEach((int timerId) {
      window.console.timeEnd(_timerStr(timerId, _timers[timerId]));
      _timers.remove(timerId);
      _timerIds.remove(timerName, timerId);
    });
  }

  void markTime(String name, [dynamic extraData]) {
    window.console.timeStamp(_timerName(name, extraData));
  }
}