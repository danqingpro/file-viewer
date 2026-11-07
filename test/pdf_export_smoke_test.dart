import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notepadpp/core/export/pdf_exporter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('exports markdown to pdf with cjk text', () async {
    const md = '''
# 压力测试方案

验证中文字体与排版是否正常。

## 1 引言

### 1.1 编写目的

- 项目一：设备枚举
- 项目二：寄存器读写

> 引用块文本。

| 列A | 列B |
| --- | --- |
| 值1 | 值2 |

```dart
void main() {}
```
''';
    final path = await PdfExporter.exportMarkdown(
      markdown: md,
      title: '压力测试方案',
      outputPath: '/tmp/pdf_export_test/test.pdf',
    );
    final file = File(path);
    expect(file.existsSync(), true);
    expect(file.lengthSync(), greaterThan(1000));
  });
}
