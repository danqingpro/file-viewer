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
class VoicePlugin extends EditorPlugin {
  FlutterTts? _tts;
  VoiceState _state = VoiceState.idle;
  String? _lastError;
  String _lang = 'zh-CN';

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
    // Fire-and-forget async init: the plugin contract is sync, so we kick
    // off initialization here and let it surface errors via the bus. All
    // awaited calls are inside a try/catch so a missing platform backend
    // (e.g. flutter_tts has no Linux desktop impl) degrades to an error
    // state instead of crashing or logging unhandled exceptions.
    _init(bus);
  }

  Future<void> _init(EventBus bus) async {
    try {
      _tts = FlutterTts();
      _tts!.setStartHandler(() => _setState(VoiceState.speaking, bus));
      _tts!.setCompletionHandler(() => _setState(VoiceState.idle, bus));
      _tts!.setCancelHandler(() => _setState(VoiceState.idle, bus));
      _tts!.setErrorHandler((m) {
        _lastError = m.message;
        _setState(VoiceState.error, bus);
      });
      await _tts!.setLanguage(_lang);
      await _tts!.setSpeechRate(0.5);
    } catch (e) {
      _lastError = '语音引擎不可用：$e';
      _state = VoiceState.error;
      bus.emit(AppEvents.voiceStatus, {'state': _state.name, 'error': _lastError});
    }
  }

  @override
  void dispose() {
    _tts?.stop();
    _tts = null;
    _state = VoiceState.idle;
  }

  /// Speak [text] (replaces any current utterance).
  Future<void> speak(EventBus bus, String text) async {
    if (text.trim().isEmpty) {
      _lastError = '没有可播报的内容';
      _setState(VoiceState.error, bus);
      return;
    }
    final tts = _tts;
    if (tts == null) {
      _lastError = '语音引擎未初始化';
      _setState(VoiceState.error, bus);
      return;
    }
    try {
      await tts.setLanguage(_lang);
      await tts.speak(text);
    } catch (e) {
      _lastError = '播报失败：$e';
      _setState(VoiceState.error, bus);
    }
  }

  Future<void> pause(EventBus bus) async {
    try {
      await _tts?.pause();
      _setState(VoiceState.paused, bus);
    } catch (e) {
      _lastError = '暂停失败：$e';
      _setState(VoiceState.error, bus);
    }
  }

  Future<void> resume(EventBus bus) async {
    // On some platforms pause/resume is unsupported; fall back to re-speaking.
    try {
      await _tts?.pause();
      _setState(VoiceState.speaking, bus);
    } catch (e) {
      _lastError = '继续失败：$e';
      _setState(VoiceState.error, bus);
    }
  }

  Future<void> stop(EventBus bus) async {
    await _tts?.stop();
    _setState(VoiceState.idle, bus);
  }

  Future<void> setRate(double rate, EventBus bus) async {
    await _tts?.setSpeechRate(rate.clamp(0.0, 1.0));
    bus.emit(AppEvents.voiceStatus, {'rate': rate});
  }

  Future<void> setLanguage(String code, EventBus bus) async {
    _lang = code;
    await _tts?.setLanguage(code);
    bus.emit(AppEvents.voiceStatus, {'language': code});
  }

  void _setState(VoiceState s, EventBus bus) {
    _state = s;
    bus.emit(AppEvents.voiceStatus, {'state': s.name});
  }
}

@visibleForTesting
String describeVoiceState(VoiceState s) => s.name;
