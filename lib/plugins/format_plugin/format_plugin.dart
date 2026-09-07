import 'dart:convert';

import '../../core/plugin_manager/plugin.dart';
import '../../core/plugin_manager/event_bus.dart';

/// Result of a formatting operation. [text] is the reformatted content,
/// [ok] indicates success and [error] carries a human message on failure.
class FormatResult {
  final String text;
  final bool ok;
  final String? error;
  const FormatResult.ok(this.text) : ok = true, error = null;
  const FormatResult.error(this.error)
      : text = '',
        ok = false;
}

/// Contract for a single-language formatter. Pure functions: takes the raw
/// text, returns the reformatted text (or an error). No I/O.
abstract class Formatter {
  String get language;
  FormatResult format(String input);
}

/// JSON formatter. Pretty-prints via dart:convert. Accepts compact or
/// already-formatted input. Errors (e.g. trailing commas) are surfaced as
/// a [FormatResult.error] so the UI can show them without crashing.
class JsonFormatter implements Formatter {
  @override
  String get language => 'json';

  @override
  FormatResult format(String input) {
    try {
      final decoded = jsonDecode(input);
      final encoder = const JsonEncoder.withIndent('  ');
      return FormatResult.ok('${encoder.convert(decoded)}\n');
    } on FormatException catch (e) {
      return FormatResult.error('JSON 解析失败：${e.message}');
    } catch (e) {
      return FormatResult.error('JSON 格式化失败：$e');
    }
  }
}

/// XML formatter: a small hand-written indenter. It re-indents tags,
/// collapses whitespace between tags, and preserves text content inside
/// leaf nodes. Not a full parser — intentionally lenient so it degrades
/// gracefully on imperfect input.
class XmlFormatter implements Formatter {
  @override
  String get language => 'xml';

  @override
  FormatResult format(String input) {
    try {
      final out = StringBuffer();
      var depth = 0;
      var i = 0;
      final n = input.length;
      void writeIndent() {
        out.write('  ' * depth);
      }

      void pushLine() {
        if (out.isNotEmpty && !out.toString().endsWith('\n')) {
          out.writeln();
        }
      }

      while (i < n) {
        // Skip whitespace runs.
        while (i < n && _isWs(input[i])) i++;
        if (i >= n) break;
        if (input[i] != '<') {
          // Text content.
          int end = i;
          while (end < n && input[end] != '<') end++;
          final text = input.substring(i, end).trim();
          if (text.isNotEmpty) {
            writeIndent();
            out.write(_decodeEntities(text));
          }
          i = end;
          continue;
        }
        // Find matching '>'.
        int close = input.indexOf('>', i);
        if (close == -1) {
          out.write(input.substring(i));
          break;
        }
        final tag = input.substring(i, close + 1);
        if (tag.startsWith('</')) {
          depth = depth > 0 ? depth - 1 : 0;
          pushLine();
          writeIndent();
          out.write(tag);
        } else if (tag.startsWith('<!') || tag.startsWith('<?')) {
          pushLine();
          writeIndent();
          out.write(tag);
        } else if (tag.endsWith('/>')) {
          pushLine();
          writeIndent();
          out.write(tag);
        } else {
          pushLine();
          writeIndent();
          out.write(tag);
          depth++;
        }
        i = close + 1;
      }
      final result = out.toString().trimRight();
      return FormatResult.ok('$result\n');
    } catch (e) {
      return FormatResult.error('XML 格式化失败：$e');
    }
  }

  bool _isWs(String c) => c == ' ' || c == '\t' || c == '\n' || c == '\r';

  String _decodeEntities(String s) => s.replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&amp;', '&').replaceAll('&quot;', '"').replaceAll('&apos;', "'");
}

/// C++ formatter: a conservative indenter. It walks the text and adjusts
/// leading indentation per brace nesting level, leaving the rest of the
/// structure untouched. Safe to run on already-formatted code (idempotent
/// at the indentation level).
class CppFormatter implements Formatter {
  @override
  String get language => 'cpp';

  @override
  FormatResult format(String input) {
    try {
      final lines = input.split('\n');
      final out = <String>[];
      var depth = 0;
      for (final raw in lines) {
        final line = raw.replaceFirst(RegExp(r'^[ \t]*'), '');
        // Closing braces on this line reduce depth before indenting.
        final startsWithClose =
            line.startsWith('}') || line.startsWith(')') || line.startsWith(']');
        final effective = startsWithClose && depth > 0 ? depth - 1 : depth;
        out.add('${'  ' * effective}$line');
        depth = _nextDepth(line, depth);
      }
      return FormatResult.ok('${out.join('\n')}\n');
    } catch (e) {
      return FormatResult.error('C++ 格式化失败：$e');
    }
  }

  int _nextDepth(String line, int depth) {
    var d = depth;
    for (var i = 0; i < line.length; i++) {
      // Skip characters inside comments / strings — best-effort.
      final c = line[i];
      if (c == '"' || c == "'") {
        final quote = c;
        i++;
        while (i < line.length && line[i] != quote) {
          if (line[i] == '\\') i++;
          i++;
        }
        continue;
      }
      if (i + 1 < line.length && line[i] == '/' && line[i + 1] == '/') break;
      if (c == '{' || c == '(' || c == '[') {
        d++;
      } else if (c == '}' || c == ')' || c == ']') {
        d = d > 0 ? d - 1 : 0;
      }
    }
    return d;
  }
}

/// The format *plugin* surface: holds one [Formatter] per language and
/// resolves the right one for the active document.
class FormatPlugin extends EditorPlugin {
  final Map<String, Formatter> _byLang = {};

  @override
  String get id => 'format_plugin';

  @override
  String get displayName => 'JSON / XML / C++ 格式化插件';

  @override
  String get description => '一键美化 JSON、规整 XML、对齐 C/C++ 缩进。';

  @override
  void initialize(EventBus bus) {
    register(JsonFormatter());
    register(XmlFormatter());
    register(CppFormatter());
  }

  void register(Formatter f) {
    _byLang[f.language] = f;
  }

  @override
  void dispose() => _byLang.clear();

  Formatter? forLanguage(String language) => _byLang[language];
}
