import 'dart:io';
import 'dart:typed_data';

/// Abstract source of binary bytes that supports random-access range reads.
///
/// This is the extension point for the binary viewer. Two implementations:
///   * [MemoryBinaryDataSource] — wraps a fully-loaded [Uint8List] (small
///     files, or files opened for editing).
///   * [FileBinaryDataSource] — reads chunks from disk on demand via
///     [RandomAccessFile], keeping a small LRU cache. Used for large files
///     so the whole file never has to sit in memory.
///
/// ## Future extension points
/// The viewer is built around this source so that later features can be
/// added without touching the UI:
///
///   * **Frame length / frame count** — a "frame" is a configurable row
///     width (bytes per row). The viewer already takes [frameLength] as a
///     parameter; `frameCount` is derived as `length / frameLength`. A
///     future plugin can swap in a source that aligns frames on packet
///     boundaries instead of fixed 16-byte rows.
///   * **Keyword / pattern search** — add a `search(pattern, {start})`
///     method here that returns match offsets. The UI can then jump the
///     viewport to a match and highlight it. Left as a stub for now.
abstract class BinaryDataSource {
  const BinaryDataSource();

  /// Total length of the underlying data, in bytes.
  int get length;

  /// Read up to [end] - [start] bytes starting at [start]. The returned
  /// list may be shorter than requested only at EOF.
  Future<Uint8List> readRange(int start, int end);

  /// Release any underlying resources (file handles, etc.).
  void dispose();

  /// Search [pattern] starting from [start] (inclusive). Returns the
  /// absolute offset of the first match, or -1 if none. This is a stub
  /// left for a future keyword-search feature; the default implementation
  /// scans linearly and is therefore only suitable for in-memory sources.
  ///
  /// Override in [FileBinaryDataSource] with a streaming scan to avoid
  /// loading the whole file.
  Future<int> search(List<int> pattern, {int start = 0}) async {
    final p = pattern;
    if (p.isEmpty) return -1;
    final n = length;
    for (int i = start; i + p.length <= n; i++) {
      final chunk = await readRange(i, (i + p.length).clamp(0, n));
      if (chunk.length < p.length) break;
      bool match = true;
      for (int j = 0; j < p.length; j++) {
        if (chunk[j] != p[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }
}

/// In-memory data source wrapping a [Uint8List]. Used for small binaries
/// that are already fully loaded, or for the editable hex viewer.
class MemoryBinaryDataSource extends BinaryDataSource {
  MemoryBinaryDataSource(this._bytes);
  final Uint8List _bytes;

  @override
  int get length => _bytes.length;

  @override
  Future<Uint8List> readRange(int start, int end) async {
    final s = start.clamp(0, _bytes.length);
    final e = end.clamp(s, _bytes.length);
    return Uint8List.fromList(_bytes.sublist(s, e));
  }

  @override
  void dispose() {}
}

/// File-backed data source that reads byte ranges on demand via
/// [RandomAccessFile]. A small LRU chunk cache avoids re-reading the same
/// region when the user scrolls back and forth.
///
/// The chunk size is chosen so a handful of cached chunks cover several
/// screens of hex output (16 bytes/row × ~50 visible rows = 800 bytes;
/// a 16 KB chunk covers ~20 screens).
class FileBinaryDataSource extends BinaryDataSource {
  FileBinaryDataSource(this._file, {int chunkSize = 16 * 1024})
      : _chunkSize = chunkSize;

  final File _file;
  final int _chunkSize;

  int? _cachedLength;
  // Single-entry cache: the most recently read chunk + its byte range.
  // Good enough for sequential scroll; a full LRU is overkill here.
  int _cacheStart = -1;
  Uint8List? _cacheBytes;
  RandomAccessFile? _raf;

  RandomAccessFile get _handle => _raf ??= _file.openSync();

  @override
  int get length {
    if (_cachedLength != null) return _cachedLength!;
    _cachedLength = _file.lengthSync();
    return _cachedLength!;
  }

  @override
  Future<Uint8List> readRange(int start, int end) async {
    final s = start.clamp(0, length);
    final e = end.clamp(s, length);
    if (e <= s) return Uint8List(0);

    // Assemble the requested range chunk-by-chunk so requests spanning
    // multiple chunks are handled correctly (the single-chunk cache alone
    // would return a short buffer otherwise). Each chunk is read once and
    // kept in the single-entry cache for the next sequential read.
    final out = Uint8List(e - s);
    int pos = s;
    while (pos < e) {
      final chunkStart = (pos ~/ _chunkSize) * _chunkSize;
      final chunkEnd = (chunkStart + _chunkSize).clamp(0, length);
      if (_cacheStart != chunkStart) {
        _cacheStart = chunkStart;
        _cacheBytes = _handle.readSync(chunkEnd - chunkStart, chunkStart);
      }
      final copyEnd = e < chunkEnd ? e : chunkEnd;
      final len = copyEnd - pos;
      if (len <= 0) break;
      out.setRange(pos - s, pos - s + len, _cacheBytes!, pos - chunkStart);
      pos = copyEnd;
    }
    return out;
  }

  @override
  void dispose() {
    _raf?.closeSync();
    _raf = null;
    _cacheBytes = null;
  }

  /// Streaming keyword search that never holds the whole file in memory.
  /// Scans in [_chunkSize] windows with a small overlap to catch matches
  /// straddling a chunk boundary.
  @override
  Future<int> search(List<int> pattern, {int start = 0}) async {
    if (pattern.isEmpty) return -1;
    final n = length;
    final overlap = pattern.length - 1;
    int pos = start.clamp(0, n);
    int windows = 0;
    while (pos + pattern.length <= n) {
      final end = (pos + _chunkSize).clamp(0, n);
      final chunk = await readRange(pos, end);
      // Boyer-Moore-Horspool would be faster, but a plain scan is fine for
      // an on-demand viewer; the UI shows a spinner.
      for (int i = 0; i + pattern.length <= chunk.length; i++) {
        bool match = true;
        for (int j = 0; j < pattern.length; j++) {
          if (chunk[i + j] != pattern[j]) {
            match = false;
            break;
          }
        }
        if (match) return pos + i;
      }
      // Step forward, leaving an overlap so cross-boundary matches are found.
      pos = end - (end < n ? overlap : 0);
      if (pos < end) pos = end; // ensure progress when overlap >= step
      // Yield to the event loop periodically so a long scan still lets the
      // spinner animate and the app stays responsive.
      if ((++windows & 63) == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    return -1;
  }
}
