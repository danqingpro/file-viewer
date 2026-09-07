import 'dart:io';

import 'package:flutter/material.dart';

import '../../editor_service.dart';

/// A collapsible folder tree panel, shown when the user opens a workspace
/// (文件 → 打开文件夹作为工作区). Folders are collapsed by default and
/// expand when tapped. Files open in a new tab on tap.
class WorkspaceTree extends StatefulWidget {
  const WorkspaceTree({
    super.key,
    required this.rootPath,
    required this.service,
    required this.onClose,
  });

  final String rootPath;
  final EditorService service;
  final VoidCallback onClose;

  @override
  State<WorkspaceTree> createState() => _WorkspaceTreeState();
}

class _WorkspaceTreeState extends State<WorkspaceTree> {
  /// Set of expanded directory paths. Folders are collapsed by default.
  final Set<String> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF252526) : const Color(0xFFF3F3F3);
    final fg = isDark ? Colors.white70 : Colors.black87;

    return Container(
      width: 260,
      color: bg,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: isDark ? const Color(0xFF333) : const Color(0xFFE0E0E0))),
            ),
            child: Row(
              children: [
                const Icon(Icons.folder_outlined, size: 14, color: Color(0xFF007ACC)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _baseName(widget.rootPath),
                    style: TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: widget.onClose,
                  child: Icon(Icons.close, size: 14, color: isDark ? Colors.white54 : Colors.black45),
                ),
              ],
            ),
          ),
          // Tree
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: _buildChildren(widget.rootPath, 0),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildChildren(String dirPath, int depth) {
    final dir = Directory(dirPath);
    List<FileSystemEntity> entities;
    try {
      entities = dir.listSync(followLinks: false).toList()
        ..sort((a, b) {
          final aDir = a is Directory;
          final bDir = b is Directory;
          if (aDir != bDir) return aDir ? -1 : 1;
          return a.path.toLowerCase().compareTo(b.path.toLowerCase());
        });
    } catch (_) {
      return [Padding(
        padding: EdgeInsets.only(left: 12.0 * (depth + 1), top: 4, bottom: 4),
        child: Text('无读取权限', style: const TextStyle(fontSize: 11, color: Colors.red)),
      )];
    }

    final widgets = <Widget>[];
    for (final entity in entities) {
      if (entity is Directory) {
        final name = _baseName(entity.path);
        final isExpanded = _expanded.contains(entity.path);
        widgets.add(_folderTile(entity.path, name, depth, isExpanded));
        if (isExpanded) {
          widgets.addAll(_buildChildren(entity.path, depth + 1));
        }
      } else if (entity is File) {
        final name = _baseName(entity.path);
        widgets.add(_fileTile(entity.path, name, depth));
      }
    }
    return widgets;
  }

  Widget _folderTile(String path, String name, int depth, bool expanded) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white70 : Colors.black87;
    return InkWell(
      onTap: () {
        setState(() {
          if (expanded) {
            _expanded.remove(path);
          } else {
            _expanded.add(path);
          }
        });
      },
      child: Padding(
        padding: EdgeInsets.only(left: 8.0 + depth * 12, top: 3, bottom: 3, right: 8),
        child: Row(
          children: [
            Icon(
              expanded ? Icons.folder_open : Icons.folder,
              size: 14,
              color: const Color(0xFFD8B04C),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                name,
                style: TextStyle(fontSize: 12, color: fg, fontFamily: 'monospace'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fileTile(String path, String name, int depth) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white60 : Colors.black54;
    return InkWell(
      onTap: () => widget.service.openRecentFile(path),
      child: Padding(
        padding: EdgeInsets.only(left: 8.0 + depth * 12, top: 2, bottom: 2, right: 8),
        child: Row(
          children: [
            Icon(Icons.insert_drive_file_outlined, size: 14, color: fg),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                name,
                style: TextStyle(fontSize: 12, color: fg, fontFamily: 'monospace'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _baseName(String path) {
    final i = path.lastIndexOf(RegExp(r'[/\\]'));
    return i == -1 ? path : path.substring(i + 1);
  }
}
