import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../core/plugin_manager/plugin.dart';
import '../../core/plugin_manager/event_bus.dart';

/// Voice playback state surfaced to the UI / status bar.
enum VoiceState { idle, speaking, paused, error }

/// Cross-platform text-to-speech plugin. Wraps the system native speech
/// engine via `flutter_tts` (Windows SAPI, macOS AVSpeechSynthesizer,
/// Android TextToSpeech, Linux speech-dispatcher). The kernel never
/// touches the speech engine directly — it goes through this plugin so
/// voice can be disabled or swapped without a rebuild.
///
/// Reliability notes (fix history):
///   * Android 11+ requires a `<queries>` entry for `TTS_SERVICE` in the
///     manifest or the engine is invisible and every speak() silently
///     fails — that entry lives in AndroidManifest.xml.
///   * `setErrorHandler` receives a **dynamic** payload (a String on
///     Android), not an object with a `.message` field; dereferencing
///     `.message` threw inside the handler and broke playback reporting.
///   * Android rejects utterances longer than ~4000 chars, so long
///     documents are split into sentence-aligned chunks and queued here.
///   * Initialization is awaited before the first speak() so tapping
///     播报 immediately after app start cannot race the engine setup.
class VoicePlugin extends EditorPlugin {
  FlutterTts? _tts;
  Future<void>? _initFuture;
  VoiceState _state = VoiceState.idle;
  String? _lastError;
  String _lang = 'zh-CN';

  /// Sentence-aligned playback queue. Android TextToSpeech rejects
  /// utterances above ~4000 characters, so long texts are chunked.
  List<String> _queue = const [];
  int _queueIndex = 0;
  bool _paused = false;

  /// Generation token: bumped on every new speak()/stop() so stale queue
  /// runner loops from an older utterance batch exit immediately.
  int _generation = 0;

  /// Maximum characters per TTS utterance. Android's hard limit is 4000;
  /// we stay below it to be safe across engines.
  static const int _maxChunk = 2800;

  @override
  String get id => 'voice_plugin';

  @override
  String get displayName => '跨平台语音播报插件';

  @override
  String get description => '选中文本或全文播报，支持暂停 / 继续 / 停止，跨平台兼容。';

  VoiceState get state => _state;
  String? get lastError => _lastError;

  @override
  void initialize(EventBus bus) {
    // The plugin contract is sync, so kick off async init here and keep
    // the Future: speak()/pause()/… await it before touching the engine.
    _initFuture = _init(bus);
  }

  Future<void> _init(EventBus bus) async {
    try {
      final tts = FlutterTts();
      _tts = tts;
      tts.setStartHandler(() {
        if (_state != VoiceState.paused) _setState(VoiceState.speaking, bus);
      });
      tts.setCompletionHandler(() {});
      tts.setCancelHandler(() {});
      // flutter_tts delivers a dynamic payload here — a String on Android.
      // Reading `.message` off it threw NoSuchMethodError and killed the
      // handler mid-playback; normalize defensively instead.
      tts.setErrorHandler((dynamic m) {
        _lastError = m is String ? m : m?.toString() ?? '未知语音错误';
        _setState(VoiceState.error, bus);
      });
      // Await each utterance's completion inside speak() so the chunk
      // queue advances deterministically (supported on Android/iOS;
      // ignored where unsupported).
      try {
        await tts.awaitSpeakCompletion(true);
      } catch (_) {
        // Platform without completion-await support: the queue runner
        // still works, chunks just overlap less predictably.
      }
      await tts.setLanguage(_lang);
      await tts.setSpeechRate(0.5);
      await tts.setVolume(1.0);
    } catch (e) {
      _tts = null;
      _lastError = '语音引擎不可用：$e';
      _state = VoiceState.error;
      bus.emit(AppEvents.voiceStatus, {'state': _state.name, 'error': _lastError});
    }
  }

  @override
  void dispose() {
    _generation++;
    _tts?.stop();
    _tts = null;
    _state = VoiceState.idle;
  }

  /// Speak [text] (replaces any current utterance). Long texts are split
  /// into sentence-aligned chunks so Android's utterance limit is never
  /// hit.
  Future<void> speak(EventBus bus, String text) async {
    if (text.trim().isEmpty) {
      _lastError = '没有可播报的内容';
      _setState(VoiceState.error, bus);
      return;
    }
    // Wait for engine setup; surface init failure instead of hanging.
    await _initFuture;
    final tts = _tts;
    if (tts == null) {
      _lastError ??= '语音引擎未初始化';
      _setState(VoiceState.error, bus);
      return;
    }
    try {
      await tts.setLanguage(_lang);
    } catch (_) {
      // Unsupported locale still plays with the engine default.
    }

    _generation++;
    final gen = _generation;
    _queue = _chunk(text);
    _queueIndex = 0;
    _paused = false;
    _setState(VoiceState.speaking, bus);
    unawaited(_runQueue(bus, gen));
  }

  /// Drives the chunk queue: speaks one chunk, advances on completion,
  /// exits on pause/stop/replace. With `awaitSpeakCompletion(true)` the
  /// awaited speak() returns when the chunk has finished.
  Future<void> _runQueue(EventBus bus, int gen) async {
    final tts = _tts;
    if (tts == null) return;
    while (gen == _generation && !_paused && _queueIndex < _queue.length) {
      final chunk = _queue[_queueIndex];
      try {
        await tts.speak(chunk);
      } catch (e) {
        if (gen != _generation) return; // superseded by stop()/new speak
        _lastError = '播报失败：$e';
        _setState(VoiceState.error, bus);
        return;
      }
      if (gen != _generation || _paused) return;
      _queueIndex++;
    }
    if (gen == _generation && !_paused && _queueIndex >= _queue.length) {
      _setState(VoiceState.idle, bus);
    }
  }

  /// Pause playback. Android's TTS pause behaves like stop, so we halt
  /// the current chunk and keep the queue index; resume re-speaks from
  /// the current chunk onward.
  Future<void> pause(EventBus bus) async {
    if (_state != VoiceState.speaking) return;
    _paused = true;
    try {
      await _tts?.stop();
    } catch (_) {}
    _setState(VoiceState.paused, bus);
  }

  /// Resume from the chunk where pause() stopped (Android cannot resume
  /// mid-utterance, so the current chunk restarts — acceptable for a
  /// document reader).
  Future<void> resume(EventBus bus) async {
    if (_state != VoiceState.paused) return;
    if (_queueIndex >= _queue.length) {
      _setState(VoiceState.idle, bus);
      return;
    }
    _paused = false;
    _setState(VoiceState.speaking, bus);
    unawaited(_runQueue(bus, _generation));
  }

  Future<void> stop(EventBus bus) async {
    _generation++;
    _paused = false;
    _queue = const [];
    _queueIndex = 0;
    try {
      await _tts?.stop();
    } catch (_) {}
    _setState(VoiceState.idle, bus);
  }

  Future<void> setRate(double rate, EventBus bus) async {
    await _initFuture;
    await _tts?.setSpeechRate(rate.clamp(0.0, 1.0));
    bus.emit(AppEvents.voiceStatus, {'rate': rate});
  }

  Future<void> setLanguage(String code, EventBus bus) async {
    _lang = code;
    await _initFuture;
    await _tts?.setLanguage(code);
    bus.emit(AppEvents.voiceStatus, {'language': code});
  }

  /// Split [text] into chunks of at most [_maxChunk] characters, breaking
  /// at line boundaries or sentence punctuation where possible so the
  /// engine does not cut words mid-stride.
  List<String> _chunk(String text) {
    final clean = text.trim();
    if (clean.length <= _maxChunk) return [clean];
    final chunks = <String>[];
    var start = 0;
    final n = clean.length;
    while (start < n) {
      var end = (start + _maxChunk).clamp(0, n);
      if (end < n) {
        // Prefer to break after sentence-ending punctuation or a newline
        // inside the last third of the window.
        final minBreak = start + (_maxChunk * 2 ~/ 3);
        var best = -1;
        for (var i = end - 1; i >= minBreak; i--) {
          final c = clean[i];
          if (c == '\n' ||
              c == '。' ||
              c == '！' ||
              c == '？' ||
              c == '；' ||
              c == '.' ||
              c == '!' ||
              c == '?' ||
              c == ';') {
            best = i + 1;
            break;
          }
        }
        // Fallback: break at the last whitespace in the window.
        if (best == -1) {
          for (var i = end - 1; i > start; i--) {
            if (clean[i].trim().isEmpty) {
              best = i + 1;
              break;
            }
          }
        }
        if (best > start) end = best;
      }
      final piece = clean.substring(start, end).trim();
      if (piece.isNotEmpty) chunks.add(piece);
      start = end;
    }
    return chunks.isEmpty ? [clean] : chunks;
  }

  void _setState(VoiceState s, EventBus bus) {
    _state = s;
    bus.emit(AppEvents.voiceStatus, {'state': s.name});
  }
}

@visibleForTesting
String describeVoiceState(VoiceState s) => s.name;
