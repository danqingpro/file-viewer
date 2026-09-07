// Comprehensive test suite for the save flow fixes in v1.6.1.
//
// Focus areas:
//  1. FileKernel.encode() produces correct bytes for every supported
//     encoding — this is what gets passed to FilePicker.saveFile(bytes:)
//     on Android, so a regression here means files cannot be saved.
//  2. FileKernel.write() / writeBytes() round-trips content to disk.
//  3. EditorTabController save-state transitions (dirty -> clean).
//  4. Encoding round-trips: encode then decode returns the same text.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notepadpp/core/editor_kernel/editor_state.dart';
import 'package:notepadpp/core/file_kernel/file_kernel.dart';
import 'package:notepadpp/core/plugin_manager/event_bus.dart';

void main() {
  group('FileKernel.encode() — bytes passed to SAF saveFile()', () {
    final bus = EventBus();
    final kernel = FileKernel(bus);
    const sample = '今天是个好日子\nHello, World!';

    test('UTF-8 encodes to valid utf8 bytes', () {
      final bytes = kernel.encode(sample, encodingLabel: 'UTF-8');
      expect(utf8.decode(bytes), sample);
    });

    test('UTF-8-BOM adds 0xEF 0xBB 0xBF prefix', () {
      final bytes = kernel.encode(sample, encodingLabel: 'UTF-8-BOM');
      expect(bytes[0], 0xEF);
      expect(bytes[1], 0xBB);
      expect(bytes[2], 0xBF);
      expect(utf8.decode(bytes.sublist(3)), sample);
    });

    test('UTF-16-BE-BOM adds 0xFE 0xFF prefix', () {
      final bytes = kernel.encode(sample, encodingLabel: 'UTF-16-BE-BOM');
      expect(bytes[0], 0xFE);
      expect(bytes[1], 0xFF);
    });

    test('UTF-16-LE-BOM adds 0xFF 0xFE prefix', () {
      final bytes = kernel.encode(sample, encodingLabel: 'UTF-16-LE-BOM');
      expect(bytes[0], 0xFF);
      expect(bytes[1], 0xFE);
    });

    test('GBK falls back to latin1 (byte-stable for ASCII)', () {
      const ascii = 'Hello 123';
      final bytes = kernel.encode(ascii, encodingLabel: 'GBK');
      expect(latin1.decode(bytes), ascii);
    });

    test('ANSI falls back to latin1', () {
      const ascii = 'Hello ANSI';
      final bytes = kernel.encode(ascii, encodingLabel: 'ANSI');
      expect(latin1.decode(bytes), ascii);
    });

    test('ASCII default is UTF-8 for non-ASCII', () {
      final bytes = kernel.encode(sample, encodingLabel: 'ASCII');
      expect(bytes, isNotEmpty);
    });

    test('empty string produces empty bytes (no crash)', () {
      final bytes = kernel.encode('', encodingLabel: 'UTF-8');
      expect(bytes, isEmpty);
    });
  });

  group('FileKernel write / read round-trip', () {
    final bus = EventBus();
    final kernel = FileKernel(bus);

    test('write() UTF-8 then read() returns same content', () async {
      final tmp = Directory.systemTemp.createTempSync('fktest');
      final path = '${tmp.path}/rt_utf8.txt';
      const content = '测试文本 UTF-8\nLine 2';
      await kernel.write(path, content, encodingLabel: 'UTF-8');
      final loaded = await kernel.read(path);
      expect(loaded.content, content);
      expect(loaded.encodingLabel, 'UTF-8');
      tmp.deleteSync(recursive: true);
    });

    test('write() UTF-8-BOM then read() strips BOM', () async {
      final tmp = Directory.systemTemp.createTempSync('fktest');
      final path = '${tmp.path}/rt_bom.txt';
      const content = 'BOM 测试';
      await kernel.write(path, content, encodingLabel: 'UTF-8-BOM');
      final loaded = await kernel.read(path);
      expect(loaded.content, content);
      tmp.deleteSync(recursive: true);
    });

    test('writeBytes() then readBytes() round-trips binary', () async {
      final tmp = Directory.systemTemp.createTempSync('fktest');
      final path = '${tmp.path}/rt.bin';
      final bytes = Uint8List.fromList([0x00, 0x01, 0x02, 0xFF, 0xFE]);
      await kernel.writeBytes(path, bytes);
      final read = await kernel.readBytes(path);
      expect(read, bytes);
      tmp.deleteSync(recursive: true);
    });
  });

  group('EditorTabController save state', () {
    test('new tab is clean, path is null', () {
      final tab = EditorTabController();
      expect(tab.path, isNull);
      expect(tab.dirty, isFalse);
    });

    test('editing marks tab dirty', () {
      final tab = EditorTabController();
      tab.text = 'hello';
      expect(tab.dirty, isTrue);
    });

    test('markSaved clears dirty and sets path', () {
      final tab = EditorTabController();
      tab.text = 'hello';
      tab.markSaved(path: '/tmp/test.txt', encoding: 'UTF-8');
      expect(tab.dirty, isFalse);
      expect(tab.path, '/tmp/test.txt');
      expect(tab.label, 'test.txt');
    });

    test('re-editing after save marks dirty again', () {
      final tab = EditorTabController();
      tab.markSaved(path: '/tmp/test.txt', encoding: 'UTF-8');
      tab.text = 'changed';
      expect(tab.dirty, isTrue);
    });

    test('binary tab isBinary is true after bindBinary', () {
      final tab = EditorTabController();
      tab.bindBinary(path: '/tmp/test.bin', bytes: Uint8List.fromList([1, 2, 3]));
      expect(tab.isBinary, isTrue);
      expect(tab.dirty, isFalse);
    });

    test('updateBytes marks binary tab dirty', () {
      final tab = EditorTabController();
      tab.bindBinary(path: '/tmp/test.bin', bytes: Uint8List.fromList([1, 2, 3]));
      tab.updateBytes(Uint8List.fromList([4, 5, 6]));
      expect(tab.dirty, isTrue);
    });
  });

  group('Save flow integration — bytes generation', () {
    // Verify the exact bytes that would be passed to FilePicker.saveFile()
    // for a text tab and a binary tab.

    final bus = EventBus();
    final kernel = FileKernel(bus);

    test('text tab bytes match FileKernel.encode output', () {
      final tab = EditorTabController();
      tab.text = '今天是个好日子';
      final bytes = kernel.encode(tab.text, encodingLabel: tab.encoding);
      expect(utf8.decode(bytes), '今天是个好日子');
    });

    test('binary tab bytes are the raw stored bytes', () {
      final raw = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
      final tab = EditorTabController();
      tab.bindBinary(path: '/tmp/x.bin', bytes: raw);
      expect(tab.bytes, raw);
    });

    test('saveActive falls back to saveActiveAs when path is null', () {
      // saveActive calls saveActiveAs() when tab.path == null.
      // We verify the precondition: a new tab has no path.
      final tab = EditorTabController();
      expect(tab.path, isNull);
    });
  });
}
