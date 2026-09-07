import 'package:flutter/material.dart';

import '../../core/config/app_info.dart';
import '../../core/plugin_manager/plugin.dart';

/// The "关于" page. Surfaces version info, basic features, bundled plugins,
/// and a change log so users can tell what each version changed.
///
/// All colors are derived from [Theme.of] so the page looks correct in both
/// light and dark modes (no hardcoded light colors that glare in dark mode).
class AboutPage extends StatelessWidget {
  const AboutPage({super.key, required this.plugins});

  final List<PluginInfo> plugins;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final muted = theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6) ??
        theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return Scaffold(
      appBar: AppBar(
        title: Text('关于 ${AppInfo.name}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _header(context, accent),
          const SizedBox(height: 20),
          _section(context, accent, '版本信息', [
            _kv(context, muted, '应用名称', AppInfo.name),
            _kv(context, muted, '版本信息', AppInfo.version),
            _kv(context, muted, '版本号', AppInfo.versionNumber),
            _kv(context, muted, '构建号', AppInfo.buildNumber.toString()),
            _kv(context, muted, '运行平台', AppInfo.platforms.join(' / ')),
            _kv(context, muted, '技术栈', AppInfo.techStack),
          ]),
          const SizedBox(height: 20),
          _section(context, accent, '基本功能',
              AppInfo.coreFeatures.map((f) => _featureItem(context, f)).toList()),
          const SizedBox(height: 20),
          _section(
            context,
            accent,
            '更新日志',
            AppInfo.changeLog.map((c) => _changelogItem(context, accent, c)).toList(),
          ),
          const SizedBox(height: 20),
          _section(context, accent, '内置插件', [
            for (final p in plugins) _pluginRow(context, p, accent, muted),
          ]),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '${AppInfo.name} ${AppInfo.version} · ${AppInfo.tagline}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: muted,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  // ---- Header ------------------------------------------------------------

  Widget _header(BuildContext context, Color accent) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '文件',
            style: TextStyle(
              color: theme.colorScheme.onPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppInfo.name,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                AppInfo.tagline,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---- Section card ------------------------------------------------------

  Widget _section(BuildContext context, Color accent, String title, List<Widget> children) {
    final theme = Theme.of(context);
    final cardColor = theme.colorScheme.surfaceContainerHighest;
    final borderColor = theme.colorScheme.outlineVariant.withValues(alpha: 0.5);
    return Card(
      elevation: 0,
      color: cardColor,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  // ---- Key-value row -----------------------------------------------------

  Widget _kv(BuildContext context, Color muted, String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(k, style: TextStyle(color: muted, fontSize: 13)),
          ),
          Expanded(
            child: SelectableText(
              v,
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Feature item ------------------------------------------------------

  Widget _featureItem(BuildContext context, String feature) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Icon(Icons.check_circle, size: 14, color: accent),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(feature, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  // ---- Change log item ---------------------------------------------------

  Widget _changelogItem(BuildContext context, Color accent, VersionChangeLog c) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'v${c.version}',
                  style: TextStyle(
                    color: theme.colorScheme.onPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  c.title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                c.date,
                style: TextStyle(fontSize: 11, color: muted, fontFamily: 'monospace'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...c.changes.map(
            (change) => Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Icon(Icons.arrow_right, size: 14, color: muted),
                  ),
                  Expanded(
                    child: Text(change, style: TextStyle(fontSize: 12, color: muted)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Plugin row --------------------------------------------------------

  Widget _pluginRow(BuildContext context, PluginInfo p, Color accent, Color muted) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            p.enabled ? Icons.extension : Icons.extension_off_outlined,
            size: 14,
            color: p.enabled ? accent : muted,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(p.displayName, style: const TextStyle(fontSize: 13))),
          Text(
            'v${p.version}',
            style: TextStyle(fontSize: 11, color: muted, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}
