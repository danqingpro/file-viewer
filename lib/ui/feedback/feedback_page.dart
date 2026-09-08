import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/feedback/feedback_service.dart';

/// Feedback page: user enters a description, attaches images / videos /
/// archives, and submits. The feedback is pushed to the project's GitHub
/// repository as an issue (with attachments uploaded to the repo).
class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final TextEditingController _descCtrl = TextEditingController();
  final List<FeedbackAttachment> _attachments = [];
  final FeedbackService _service = FeedbackService();
  bool _submitting = false;

  static const List<String> _allowedExt = [
    // images
    'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg',
    // video
    'mp4', 'mov', 'avi', 'mkv', 'flv', 'wmv',
    // archives
    'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz',
  ];

  @override
  void dispose() {
    _descCtrl.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<void> _pickAttachments() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExt,
      allowMultiple: true,
    );
    if (result == null) return;
    setState(() {
      for (final f in result.files) {
        if (f.path != null) {
          _attachments.add(FeedbackAttachment(
            name: f.name,
            path: f.path!,
            size: f.size,
          ));
        }
      }
    });
  }

  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final result = await _service.submit(
      description: _descCtrl.text,
      attachments: List.unmodifiable(_attachments),
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('反馈已提交，感谢！'), backgroundColor: Colors.green),
      );
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? '提交失败'), backgroundColor: Colors.red),
      );
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white : Colors.black87;
    final sub = isDark ? Colors.white60 : Colors.black54;
    final cardBg = isDark ? const Color(0xFF2D2D30) : Colors.white;
    final border = isDark ? const Color(0xFF3C3C3C) : const Color(0xFFE0E0E0);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('意见反馈'),
        backgroundColor: isDark ? const Color(0xFF252526) : Colors.white,
        foregroundColor: fg,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: border),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('描述你遇到的问题或建议', style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                border: Border.all(color: border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextField(
                controller: _descCtrl,
                maxLines: 6,
                style: TextStyle(color: fg, fontSize: 14),
                decoration: InputDecoration(
                  hintText: '请详细描述问题（包括复现步骤、预期结果等）…',
                  hintStyle: TextStyle(color: sub),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Text('添加附件', style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Text('（图片 / 视频 / 压缩包）', style: TextStyle(color: sub, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _submitting ? null : _pickAttachments,
              icon: const Icon(Icons.attach_file, size: 18),
              label: const Text('选择文件'),
            ),
            const SizedBox(height: 12),
            if (_attachments.isEmpty)
              Text('暂无附件', style: TextStyle(color: sub, fontSize: 13))
            else
              ..._attachments.asMap().entries.map((e) {
                final idx = e.key;
                final att = e.value;
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: cardBg,
                    border: Border.all(color: border),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.insert_drive_file, size: 18, color: sub),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(att.name, style: TextStyle(color: fg, fontSize: 13)),
                            Text(_formatSize(att.size), style: TextStyle(color: sub, fontSize: 11)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => _removeAttachment(idx),
                        tooltip: '移除',
                      ),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: const Color(0xFF007ACC),
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('提交反馈'),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '反馈将以 Issue 的形式提交到项目的 GitHub 仓库',
              style: TextStyle(color: sub, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
