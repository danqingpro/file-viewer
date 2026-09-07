import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../plugin_manager/event_bus.dart';
import 'encoding.dart';

/// Snapshot of a file that was just loaded. Carries everything the editor
/// needs to populate a tab: text content, detected encoding, byte size,
/// and the on-disk path.
class LoadedFile {
  final String? path;
  final String content;
  final String encodingLabel;
  final int byteSize;
  const LoadedFile({
    required this.path,
    required this.content,
    required this.encodingLabel,
    required this.byteSize,
  });
}

/// Result of writing a file back to disk.
class SavedFile {
  final String path;
  final String encodingLabel;
  final int byteSize;
  const SavedFile({required this.path, required this.encodingLabel, required this.byteSize});
}

/// Kernel-level file operations: read with auto encoding detection,
/// write with a chosen encoding, and large-file size probing.
///
/// This is part of the *stable* kernel — not a swappable plugin — because
/// every plugin and UI surface depends on a consistent file contract.
/// The *encoding adapter* is implemented via [EncodingDetector], which is
/// the built-in counterpart to a future swappable encoding plugin.
class FileKernel {
  FileKernel(this._bus);

  final EventBus _bus;
  static const EncodingDetector _detector = EncodingDetector();

  /// Probe the byte length of [path] without loading the whole file into
  /// memory. Used by the status bar for very large files.
  Future<int> sizeOf(String path) async {
    try {
      return await File(path).length();
    } catch (_) {
      return -1;
    }
  }

  /// Open and decode [path]. Performs encoding detection and strips a
  /// UTF-8 BOM if present. Files larger than [chunkLimit] bytes are still
  /// loaded fully (the design's "分片加载" is a future enhancement), but
  /// the size is reported so the UI can warn the user.
  Future<LoadedFile> read(String path, {int chunkLimit = 8 * 1024 * 1024}) async {
    final raw = await File(path).readAsBytes();
    final result = _detector.detect(raw);
    final bytes = result.hasBom ? raw.sublist(result.bomLength) : raw;
    String text;
    try {
      text = result.encoding.decode(bytes);
    } catch (_) {
      text = utf8.decode(bytes, allowMalformed: true);
    }
    _bus.emit(AppEvents.fileOpened, {'path': path, 'encoding': result.label, 'bytes': raw.length});
    return LoadedFile(
      path: path,
      content: text,
      encodingLabel: result.label,
      byteSize: raw.length,
    );
  }

  /// Read raw bytes without any decoding. Used by the binary viewer.
  Future<Uint8List> readBytes(String path) async {
    return await File(path).readAsBytes();
  }

  /// Write raw bytes directly to disk (no encoding). Used by the binary
  /// viewer's save operation.
  Future<SavedFile> writeBytes(String path, Uint8List bytes) async {
    await File(path).writeAsBytes(bytes, flush: true);
    final saved = SavedFile(path: path, encodingLabel: 'BINARY', byteSize: bytes.length);
    _bus.emit(AppEvents.fileSaved, {'path': path, 'bytes': bytes.length});
    return saved;
  }

  /// Encode [content] to bytes using [encodingLabel] WITHOUT writing.
  /// Used by the service to pass bytes directly to `FilePicker.saveFile()`
  /// on Android (where the native SAF handler writes the bytes).
  Uint8List encode(String content, {String encodingLabel = 'UTF-8'}) {
    return _encode(content, encodingLabel);
  }

  /// Write [content] to [path] using [encodingLabel] ('UTF-8' by default).
  /// A BOM is added only when the label is 'UTF-8-BOM'.
  Future<SavedFile> write(
    String path,
    String content, {
    String encodingLabel = 'UTF-8',
  }) async {
    final bytes = _encode(content, encodingLabel);
    await File(path).writeAsBytes(bytes, flush: true);
    final saved = SavedFile(path: path, encodingLabel: encodingLabel, byteSize: bytes.length);
    _bus.emit(AppEvents.fileSaved, {'path': path, 'bytes': bytes.length});
    return saved;
  }

  Uint8List _encode(String text, String label) {
    if (label == 'UTF-8-BOM') {
      final body = utf8.encode(text);
      final out = Uint8List(body.length + 3)
        ..[0] = 0xEF
        ..[1] = 0xBB
        ..[2] = 0xBF
        ..setRange(3, 3 + body.length, body);
      return out;
    }
    if (label == 'UTF-16-BE-BOM') {
      final body = utf16be.encode(text);
      final out = Uint8List(body.length + 2)
        ..[0] = 0xFE
        ..[1] = 0xFF
        ..setRange(2, 2 + body.length, body);
      return out;
    }
    if (label == 'UTF-16-LE-BOM') {
      final body = utf16le.encode(text);
      final out = Uint8List(body.length + 2)
        ..[0] = 0xFF
        ..[1] = 0xFE
        ..setRange(2, 2 + body.length, body);
      return out;
    }
    if (label == 'GBK') {
      // Round-trip via latin1 so GBK-tagged content stays byte-stable.
      return Uint8List.fromList(latin1.encode(text));
    }
    if (label == 'ANSI') {
      // ANSI on Windows is typically the system codepage; we approximate
      // with latin1 (ISO-8859-1) which covers byte values 0..255.
      return Uint8List.fromList(latin1.encode(text));
    }
    // UTF-8 / ASCII default.
    return Uint8List.fromList(utf8.encode(text));
  }
}
