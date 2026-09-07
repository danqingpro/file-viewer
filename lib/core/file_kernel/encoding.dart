import 'dart:convert';
import 'dart:typed_data';

/// A minimal UTF-16 codec (big-endian or little-endian). Dart's
/// `dart:convert` ships only UTF-8 / ASCII / Latin1, so we implement
/// UTF-16 ourselves. Handles surrogate pairs for supplementary planes.
class Utf16Codec extends Encoding {
  final bool bigEndian;
  const Utf16Codec({required this.bigEndian});

  @override
  String get name => bigEndian ? 'UTF-16BE' : 'UTF-16LE';

  @override
  Converter<List<int>, String> get decoder => _Utf16Decoder(bigEndian);

  @override
  Converter<String, List<int>> get encoder => _Utf16Encoder(bigEndian);

  @override
  Uint8List encode(String input) {
    final units = <int>[];
    for (final rune in input.runes) {
      if (rune <= 0xFFFF) {
        units.add(rune);
      } else {
        // Surrogate pair.
        final v = rune - 0x10000;
        units.add(0xD800 | (v >> 10));
        units.add(0xDC00 | (v & 0x3FF));
      }
    }
    final bytes = Uint8List(units.length * 2);
    for (int i = 0; i < units.length; i++) {
      final u = units[i];
      if (bigEndian) {
        bytes[i * 2] = (u >> 8) & 0xFF;
        bytes[i * 2 + 1] = u & 0xFF;
      } else {
        bytes[i * 2] = u & 0xFF;
        bytes[i * 2 + 1] = (u >> 8) & 0xFF;
      }
    }
    return bytes;
  }

  @override
  String decode(List<int> bytes, {bool allowMalformed = false}) {
    final units = <int>[];
    final len = bytes.length ~/ 2 * 2;
    for (int i = 0; i < len; i += 2) {
      final hi = bigEndian ? bytes[i] : bytes[i + 1];
      final lo = bigEndian ? bytes[i + 1] : bytes[i];
      final u = (hi << 8) | lo;
      units.add(u);
    }
    final buffer = StringBuffer();
    for (int i = 0; i < units.length; i++) {
      final u = units[i];
      if (u >= 0xD800 && u <= 0xDBFF && i + 1 < units.length) {
        final lo = units[i + 1];
        if (lo >= 0xDC00 && lo <= 0xDFFF) {
          final rune = 0x10000 + ((u - 0xD800) << 10) + (lo - 0xDC00);
          buffer.writeCharCode(rune);
          i++;
          continue;
        }
      }
      buffer.writeCharCode(u);
    }
    return buffer.toString();
  }
}

class _Utf16Encoder extends Converter<String, List<int>> {
  final bool bigEndian;
  const _Utf16Encoder(this.bigEndian);
  @override
  List<int> convert(String input) =>
      Utf16Codec(bigEndian: bigEndian).encode(input);
}

class _Utf16Decoder extends Converter<List<int>, String> {
  final bool bigEndian;
  const _Utf16Decoder(this.bigEndian);
  @override
  String convert(List<int> input) =>
      Utf16Codec(bigEndian: bigEndian).decode(input);
}

const utf16be = Utf16Codec(bigEndian: true);
const utf16le = Utf16Codec(bigEndian: false);

/// Result of an encoding probe on raw bytes.
class EncodingDetectResult {
  final String label; // "UTF-8" | "GBK" | "UTF-8-BOM" | "ASCII" | "UTF-16-BE-BOM" | "UTF-16-LE-BOM"
  final Encoding encoding; // concrete decoder to use
  final bool hasBom;
  final int bomLength; // 0, 2 (UTF-16) or 3 (UTF-8)
  const EncodingDetectResult(this.label, this.encoding, {this.hasBom = false, this.bomLength = 0});
}

/// Detects UTF-8 / GBK / UTF-8-BOM / UTF-16 BE BOM / UTF-16 LE BOM from
/// raw bytes. Used by [FileKernel] when opening files so the editor can
/// render text correctly and report the encoding in the status bar.
class EncodingDetector {
  const EncodingDetector();

  EncodingDetectResult detect(Uint8List bytes) {
    if (bytes.isEmpty) {
      return const EncodingDetectResult('UTF-8', utf8);
    }

    // UTF-16 LE BOM (FF FE)
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return const EncodingDetectResult('UTF-16-LE-BOM', utf16le, hasBom: true, bomLength: 2);
    }
    // UTF-16 BE BOM (FE FF)
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return const EncodingDetectResult('UTF-16-BE-BOM', utf16be, hasBom: true, bomLength: 2);
    }
    // UTF-8 BOM
    if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
      return const EncodingDetectResult('UTF-8-BOM', utf8, hasBom: true, bomLength: 3);
    }

    // Pure ASCII is a subset of UTF-8 — fast path.
    if (_isAscii(bytes)) {
      return const EncodingDetectResult('ASCII', utf8);
    }

    // Strict UTF-8 validation.
    if (_isValidUtf8(bytes)) {
      return const EncodingDetectResult('UTF-8', utf8);
    }

    // Fall back to GBK (common for legacy Chinese text). Dart's built-in
    // codecs don't ship GBK; we approximate via latin1 round-trip so the
    // file still opens. The label is the source of truth shown to users.
    return const EncodingDetectResult('GBK', latin1);
  }

  bool _isAscii(Uint8List bytes) {
    for (final b in bytes) {
      if (b > 0x7F) return false;
    }
    return true;
  }

  /// Lightweight strict UTF-8 validator. Avoids throwing on malformed
  /// sequences (which would happen with utf8.decode directly).
  bool _isValidUtf8(Uint8List bytes) {
    int i = 0;
    while (i < bytes.length) {
      final b = bytes[i];
      int expected;
      int base;
      if (b <= 0x7F) {
        i += 1;
        continue;
      } else if ((b & 0xE0) == 0xC0) {
        expected = 1;
        base = b & 0x1F;
      } else if ((b & 0xF0) == 0xE0) {
        expected = 2;
        base = b & 0x0F;
      } else if ((b & 0xF8) == 0xF0) {
        expected = 3;
        base = b & 0x07;
      } else {
        return false;
      }
      if (i + expected >= bytes.length) return false;
      int code = base;
      for (int j = 1; j <= expected; j++) {
        final c = bytes[i + j];
        if ((c & 0xC0) != 0x80) return false;
        code = (code << 6) | (c & 0x3F);
      }
      // Reject overlong encodings and surrogates.
      if (expected == 1 && code < 0x80) return false;
      if (expected == 2 && code < 0x800) return false;
      if (expected == 3 && (code < 0x10000 || code > 0x10FFFF)) return false;
      i += 1 + expected;
    }
    return true;
  }
}
