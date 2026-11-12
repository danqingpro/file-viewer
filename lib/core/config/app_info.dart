/// Global application metadata and version info.
///
/// Lives in the config core layer so both the UI (About page / status bar)
/// and the plugin manager can reference the same single source of truth.
class AppInfo {
  const AppInfo._();

  /// Human-readable version label.
  static const String version = '1.10.12';

  /// Numeric version number, mirrors pubspec `version` field.
  static const String versionNumber = '1.10.12';

  /// Internal build number.
  static const int buildNumber = 24;

  /// Application display name.
  static const String name = '文件查看器';

  /// Short tagline describing the product.
  static const String tagline = '跨平台插件式文本 / 代码查看与编辑器';

  /// Target platforms.
  static const List<String> platforms = [
    'Windows',
    'macOS',
    'Android',
    'HarmonyOS',
  ];

  /// Core capabilities. Surfaced verbatim on the About page under "基本功能".
  static const List<String> coreFeatures = [
    '多标签页编辑（对标经典文本编辑器布局）',
    '文件修改状态实时指示（标签页圆点 + 状态栏"未保存"）',
    '基础编辑：输入 / 删除 / 撤销 / 重做 / 复制 / 粘贴 / 剪切',
    '文件操作：新建 / 打开 / 保存 / 另存为 / 拷贝另存为 / 全部保存 / 重命名',
    '文件操作：重新读取文件 / 从磁盘删除 / 全部关闭',
    '最近打开的文件列表（最多 10 条）',
    '恢复最近一个关闭的文件',
    '打开文件夹作为工作区（可折叠文件树）',
    '保存逻辑：首次保存需选择路径，再次保存直接写入原路径',
    '多格式语法高亮：txt / md / cpp / h / hpp / json / xml / html / css / js / py / yaml / bat / mermaid',
    'Markdown 实时预览（GFM 表格/任务列表，横屏分屏）',
    'Markdown 大纲导航（点击标题跳转章节）',
    'Mermaid 图表预览与编辑（.mmd/.mermaid，离线渲染，支持深色主题）',
    '导出 PDF（带可点击目录，内置中文字体，离线可用）',
    '二进制文件查看：.bin / .bit / .raw / .dat / .exe / .apk 十六进制查看与编辑',
    'Word 文档预览：.doc / .docx 调用系统查看器渲染（只读）',
    '代码格式化：JSON / XML / C++ 基础排版',
    '跨平台语音播报：选中文本或全文播报，暂停 / 继续 / 停止',
    '行号显示、光标行列、文件大小、修改状态底部状态栏',
    '文件编码自动识别（ANSI / UTF-8 / UTF-8-BOM / GBK / UTF-16 BE/LE BOM / ASCII）',
    '状态栏与菜单栏均可切换编码格式',
    '状态栏与菜单栏均可切换语法高亮语言',
    '主题切换：浅色 / 深色 / 跟随系统',
    '工具栏三种显示模式：仅图标 / 仅文字 / 图标+文字',
    '插件式架构：内核稳定、功能可插拔、可无限迭代',
    '全平台统一体验：Windows / macOS / Android / 鸿蒙',
  ];

  /// Plugin modules bundled with the current release.
  static const List<String> bundledPlugins = [
    '文件格式识别插件 (file_type_plugin)',
    '多格式语法高亮插件 (highlight_plugin)',
    'JSON / XML / C++ 格式化插件 (format_plugin)',
    '跨平台语音播报插件 (voice_plugin)',
    '二进制查看插件 (binary_viewer_plugin)',
    'PDF 预览插件 (pdf_viewer_plugin)',
    'Word 文档预览插件 (word_viewer_plugin)',
    '文件编码自动适配插件 (encoding adapter, 内置于 file_kernel)',
  ];

  /// Tech stack line shown on the About page.
  static const String techStack = 'Flutter (Dart) · 内核极简 + 功能插件化三层架构';

  /// Version change log, newest first. Rendered on the About page under
  /// "更新日志" so users can tell what each version changed.
  static const List<VersionChangeLog> changeLog = [
    VersionChangeLog(
      version: '1.10.12',
      date: '2026-11-12',
      title: '新增全屏沉浸式阅读',
      changes: [
        '新增：视图 → 全屏沉浸式阅读，隐藏菜单栏 / 工具栏 / 标签栏 / 状态栏，文档铺满整个屏幕',
        '同时隐藏 Android 状态栏与导航栏（immersiveSticky），预览顶部工具条也一并隐藏',
        '退出方式：右上角「退出全屏」浮动按钮、Esc 键或系统返回手势',
        '桌面端支持 F11 快速切换全屏',
      ],
    ),
    VersionChangeLog(
      version: '1.10.11',
      date: '2026-11-11',
      title: '修复更新检测 + 分享 APK',
      changes: [
        '修复：cdn.jsdelivr.net 长期缓存旧 version.json，导致 1.10.9 在 1.10.10 发布后误报"已是最新版本"',
        '更新检测移除易滞后的 CDN 节点，新增多个镜像，并为请求添加时间戳与禁用缓存头',
        '新增：帮助 → 分享 APK，通过系统分享面板将当前安装包发送到微信 / QQ / 蓝牙等应用',
        '分享文件使用当前安装版本号命名，并通过 FileProvider 临时授权接收方读取',
      ],
    ),
    VersionChangeLog(
      version: '1.10.10',
      date: '2026-11-08',
      title: '支持「打开方式 / 分享到」直接打开文件',
      changes: [
        '新增：在微信 / QQ / 文件管理器中选择「用其他应用打开」或「分享 → 发送到」时，本应用出现在候选列表中',
        '支持 ACTION_VIEW / ACTION_EDIT（打开方式）与 ACTION_SEND / ACTION_SEND_MULTIPLE（分享）',
        'content:// 共享文件自动复制到应用缓存目录后再打开，确保 Flutter 可正常读取',
        '冷启动与运行中分享均可处理（singleTop + onNewIntent），多文件依次打开并激活最后一个标签',
      ],
    ),
    VersionChangeLog(
      version: '1.10.9',
      date: '2026-11-08',
      title: '修复更新安装冲突（固定应用签名）',
      changes: [
        '修复：在线更新提示"已安装了一个版本"／安装冲突。根因是历史版本使用各构建机自动生成的 debug 签名，每个版本证书都不同，Android 不允许覆盖安装',
        '改用永久 release 签名密钥（android/key.properties + upload-keystore.jks），此后所有版本签名一致，可正常覆盖升级',
        '注意：从旧版本升级到 1.10.9 需要先卸载一次（签名更换无法避免），此后可一直在线更新',
        '安装失败时提示文案补充签名冲突的排查指引',
      ],
    ),
    VersionChangeLog(
      version: '1.10.8',
      date: '2026-11-07',
      title: '语音可停止 + 编辑/预览互斥 + 大纲导航 + 导出 PDF',
      changes: [
        '语音播报按钮改为开关：播放中再次点击即停止；新增悬浮播报控制条（暂停/继续/停止）',
        '横屏下「预览/编辑」改为互斥模式，不再左右分屏；预览顶部固定「编辑 / 导出 PDF」按钮',
        '预览工具栏按钮前移至工具栏最左侧，横屏滚动时不再被挤到屏幕外',
        'Markdown 预览新增文档大纲导航：按标题层级列出，点击跳转到对应章节',
        '新增「导出 PDF」：生成带可点击目录的 A4 PDF（内置中文字体、页码、章节内链）',
      ],
    ),
    VersionChangeLog(
      version: '1.10.7',
      date: '2026-11-07',
      title: '语音播报修复 + 深色对比度 + 横屏 + Markdown/Mermaid 预览',
      changes: [
        '修复语音播报：Android 11+ TTS 引擎可见性声明、错误回调崩溃、长文分段播报、暂停/继续逻辑',
        '深色模式语法高亮全面换用 VS Code Dark+ 配色，对比度达标；浅色模式保持原配色',
        '横屏自适应：横屏手机自动压缩菜单栏与工具栏高度',
        'Markdown 实时预览：横屏/宽屏左右分屏，竖屏整页预览，支持表格/任务列表/删除线',
        '新增 Mermaid 图表：.mmd/.mermaid 文件识别、语法高亮、内嵌实时渲染、全屏查看',
        'Markdown 内 ```mermaid 代码块直接渲染为图表，支持点击放大',
      ],
    ),
    VersionChangeLog(
      version: '1.10.6',
      date: '2026-09-08',
      title: '后台自动更新 + 大文件按需加载',
      changes: [
        '新增：更新功能支持后台自动更新，退出更新弹窗时提示是否后台下载，下载完成后可一键安装',
        '新增：后台下载悬浮横幅（进度/完成/失败三态）+ 完成时 SnackBar 安装提示',
        '新增：大二进制文件（≥1MB 的 .exe/.apk/.bin 等）按需加载，仅渲染可视区域，滚动时增量读取，避免大文件卡顿',
        '扩展：大文件查看器预留帧长（8/16/32）、帧数量统计与关键字/十六进制字节查找，便于后续按帧长/关键字定位',
        '版本号升级至 1.10.6',
      ],
    ),
    VersionChangeLog(
      version: '1.10.5',
      date: '2026-09-08',
      title: '更新下载断电续传 + 关闭未保存文件提示',
      changes: [
        '新增：APK 下载支持断点续传（HTTP Range），中断后重新下载从上次中断处继续',
        '新增：关闭标签页时，若文件未保存弹出"保存 / 不保存 / 取消"确认对话框',
        '改进：关闭标签页的 Ctrl+W 快捷键、标签页 X 按钮、菜单栏均走统一确认流程',
        '版本号升级至 1.10.5',
      ],
    ),
    VersionChangeLog(
      version: '1.10.4',
      date: '2026-09-08',
      title: '二进制查看新增 EXE / APK + 发布工作流文档',
      changes: [
        '新增：二进制查看插件识别范围扩展至 .exe / .apk',
        '新增：docs/RELEASE_WORKFLOW.md 发布工作流检查清单，覆盖版本号、构建、推送、tag、Release、APK 上传全流程',
        '修复：github_config.dart token 清空，避免 GitHub Push Protection 拦截',
        '版本号升级至 1.10.4',
      ],
    ),
    VersionChangeLog(
      version: '1.10.3',
      date: '2026-09-08',
      title: '修复：更新检测在所有镜像不可达时静默误报"已是最新版本"',
      changes: [
        '修复：checkForUpdate 在所有镜像均不可达（网络异常 / 超时 / DNS 失败）时仍然返回 null',
        '原因：null 返回值与"所有可达镜像均显示无更新"的正常返回值相同，调用方无法区分',
        '修复：checkForUpdate 新增 succeeded 计数器，所有镜像均失败时抛出 UpdateFetchException',
        '修复：manualCheckForUpdate 的 catch 分支现在能捕获该异常并正确显示"检查失败"提示',
        '验证：遍历镜像取最高版本逻辑保留不变，仅新增异常区分语义',
        '版本号升级至 1.10.3',
      ],
    ),
    VersionChangeLog(
      version: '1.10.2',
      date: '2026-09-08',
      title: 'Word 文档预览插件',
      changes: [
        '新增：Word 文档预览插件，打开 .doc / .docx 文件时调用系统查看器渲染（只读）',
        '新增：支持所有 Word 文档格式（.doc 旧二进制格式 + .docx 新 XML 格式），由系统文档应用原生渲染',
        '新增：EditorTabController.isWord 判断 + WordViewer 组件 + word_viewer_plugin 插件注册',
        '设计：Word 文档以二进制字节读入临时文件（保留原扩展名），交由系统查看器打开，无需新增第三方依赖',
        '版本号升级至 1.10.2',
      ],
    ),
    VersionChangeLog(
      version: '1.10.1',
      date: '2026-09-08',
      title: '修复更新检测：stale CDN 缓存导致误报"已是最新版本"',
      changes: [
        '修复：更新检测在 CDN 返回旧版本（jsDelivr 缓存数天未刷新）时直接判定"已是最新版本"',
        '修复：mirror URL 排序错误，fastly（更稳定、缓存更短）未排在第一位',
        '改进：更新检测改为遍历所有 mirror 并取最高版本，不再"first-success wins"',
        '改进：三个 mirror 位置——fastly → raw.githubusercontent → cdn.jsdelivr（仅作最后兜底）',
        '版本号升级至 1.10.1',
      ],
    ),
    VersionChangeLog(
      version: '1.10.0',
      date: '2026-09-08',
      title: '工作区抽屉式面板',
      changes: [
        '新增：工作区改为 Drawer 抽屉式面板，不再常驻占用编辑区空间',
        '新增：打开工作区后抽屉自动展开，工具栏/视图菜单可随时折叠和展开',
        '新增：抽屉支持边缘滑动唤出、点击遮罩关闭、返回键关闭',
        '新增：在工作区中选择文件后自动关闭抽屉，聚焦到编辑区',
        '改进：编辑区始终保持全宽显示，抽屉关闭后用户可完整查看文件数据',
        '版本号升级至 1.10.0',
      ],
    ),
    VersionChangeLog(
      version: '1.9.0',
      date: '2026-09-08',
      title: '手动检查更新 + 重命名修复',
      changes: [
        '新增：帮助 → 检查更新，手动检查是否有新版本',
        '新增：检查结果弹窗（发现新版本 / 已是最新版本 / 检查失败）',
        '改进：取消启动时自动检查更新，改为用户主动触发',
        '改进：更新检查使用多个镜像源（raw.githubusercontent + jsDelivr），提高国内可达性',
        '修复：文件重命名在 Android 上不可用，新增 SAF 回退方案（saveFile + 删除旧文件）',
        '修复：重命名失败时错误提示不显示（SnackBars 上下文丢失）',
        '版本号升级至 1.9.0',
      ],
    ),
    VersionChangeLog(
      version: '1.8.0',
      date: '2026-09-08',
      title: 'PDF 预览 + 意见反馈 + 重命名与工作区修复',
      changes: [
        '新增：PDF 预览插件，打开 .pdf 文件时直接渲染预览（支持翻页）',
        '新增：意见反馈功能（帮助 → 意见反馈），支持文字描述与图片/视频/压缩包附件',
        '新增：反馈自动推送到 GitHub 仓库 Issue，附件上传到仓库 feedback 目录',
        '修复：文件重命名功能失效，改为原地重命名（File.rename）并弹出文件名输入框',
        '修复：打开工作区后文件夹下的文件无法打开，补充 Android 存储权限（MANAGE_EXTERNAL_STORAGE）',
        '版本号升级至 1.8.0',
      ],
    ),
    VersionChangeLog(
      version: '1.7.0',
      date: '2026-09-07',
      title: '应用内自动更新功能',
      changes: [
        '新增：应用启动时自动检查 GitHub Releases 上的新版本',
        '新增：发现新版本弹窗，显示版本号与更新日志',
        '新增：应用内下载 APK（带进度条）并调用系统安装器覆盖安装',
        '新增：Android 适配 REQUEST_INSTALL_PACKAGES 权限与 FileProvider',
        '更新检测失败时静默处理，不影响编辑器正常使用',
        '版本号升级至 1.7.0',
      ],
    ),
    VersionChangeLog(
      version: '1.6.1',
      date: '2026-09-07',
      title: '修复：新建文件无法保存的问题',
      changes: [
        '修复：新建文件（无路径）保存/另存为/拷贝另存为/重命名在 Android 上失效的问题',
        '原因：FilePicker.saveFile 在 Android 上必须传入 bytes 参数，否则原生 SAF 写入时崩溃',
        '修复：所有保存操作（保存/另存为/拷贝另存为/重命名/全部保存）均改为传入编码后的字节',
        '修复：已保存文件的二次保存，先尝试直接写入，失败则回退到 SAF 写入流程',
        '版本号升级至 1.6.1',
      ],
    ),
    VersionChangeLog(
      version: '1.6.0',
      date: '2026-09-08',
      title: '二进制查看插件 + 工作区 + 保存修复',
      changes: [
        '修复：文件修改状态实时显示（标签页橙色圆点 + 状态栏"未保存"橙色提示）',
        '修复：保存/另存为对话框改用 FileType.any，所有格式均可选择，新文件默认 .txt',
        '修复：打开文件不再限制扩展名，支持任意格式打开',
        '新增：二进制查看插件，自动识别 .bin/.bit/.raw/.dat 并以十六进制显示',
        '二进制查看器布局：左侧地址（00000000...）、顶部偏移（0-F）、中间十六进制、右侧 ASCII',
        '二进制查看器支持编辑十六进制并保存为二进制文件',
        '新增：打开文件夹作为工作区，左侧显示可折叠的文件树',
        '工作区文件夹默认折叠，点击展开；点击文件在新标签页打开',
        '版本号升级至 1.6.0',
      ],
    ),
    VersionChangeLog(
      version: '1.5.0',
      date: '2026-09-08',
      title: 'Notepad++ 风格文件菜单与编码扩展',
      changes: [
        '文件菜单新增：重新读取文件（Ctrl+R）',
        '文件菜单新增：拷贝另存为（保存副本不切换当前标签）',
        '文件菜单新增：全部保存（保存所有已修改标签）',
        '文件菜单新增：重命名文件（改名并删除旧文件）',
        '文件菜单新增：全部关闭（Ctrl+Shift+W）',
        '文件菜单新增：从磁盘删除',
        '文件菜单新增：恢复最近一个关闭的文件（Ctrl+Shift+T）',
        '文件菜单新增：最近打开的文件列表（最多 10 条）',
        '文件菜单新增：打开所有最近的文件 / 清空最近文件列表',
        '文件菜单新增：退出（Alt+F4）',
        '编码扩展：新增 ANSI / UTF-16 BE BOM / UTF-16 LE BOM',
        '状态栏与菜单栏编码菜单同步更新',
        'UTF-16 编解码自研实现（含代理对）',
        '版本号升级至 1.5.0',
      ],
    ),
    VersionChangeLog(
      version: '1.4.0',
      date: '2026-09-07',
      title: '编码切换与多语言高亮',
      changes: [
        '保存逻辑优化：首次保存需选择路径，再次保存直接写入原路径',
        '另存为功能完善：弹出文件保存对话框选择路径',
        '状态栏编码可点击切换（UTF-8 / UTF-8-BOM / GBK / ASCII）',
        '菜单栏新增「编码」菜单，支持切换编码格式',
        '状态栏语言可点击切换语法高亮语言',
        '菜单栏新增「语言」菜单，支持切换高亮语言',
        '新增语法高亮：HTML / CSS / JavaScript / Python / YAML / 批处理',
        '扩展文件扩展名识别：html/css/js/py/yaml/bat 等',
        '文件打开支持更多扩展名（html/css/js/py/yaml/bat 等）',
        '版本号升级至 1.4.0',
      ],
    ),
    VersionChangeLog(
      version: '1.3.0',
      date: '2026-09-07',
      title: '移动端适配与屏幕旋转',
      changes: [
        '修复手机端菜单栏被状态栏遮挡的问题（新增 SafeArea）',
        '手机端菜单栏高度压缩，按钮更易点击',
        '手机端支持屏幕自动旋转（横屏 / 竖屏随系统）',
        '手机端图标与文字尺寸自适应缩小',
        '版本号升级至 1.3.0',
      ],
    ),
    VersionChangeLog(
      version: '1.2.0',
      date: '2026-09-07',
      title: '暗色主题优化与体验改进',
      changes: [
        '「关于」页面全面适配暗色主题，修复颜色刺眼问题',
        '工具栏新增主题切换快捷按钮（浅色 / 深色 / 跟随系统）',
        '「关于」页面新增更新日志，清晰展示各版本改动',
        'APK 打包文件名规范化：程序名 + 版本号 + 编译日期',
        '版本号升级至 1.2.0',
      ],
    ),
    VersionChangeLog(
      version: '1.1.0',
      date: '2026-09-07',
      title: '菜单栏重构与主题切换',
      changes: [
        '软件名称更改为「文件查看器」',
        '菜单栏参照 VSCode 布局重构，水平紧凑排列',
        '「另存为」文件名自动追加版本号',
        '工具栏支持三种显示模式：仅图标 / 仅文字 / 图标+文字',
        '新增主题切换：浅色 / 深色 / 跟随系统',
        '编辑器、标签页、状态栏全面适配暗色主题',
        '版本号升级至 1.1.0',
      ],
    ),
    VersionChangeLog(
      version: '1.0.0',
      date: '2026-09-07',
      title: '初始版本',
      changes: [
        '基础文件操作：新建 / 打开 / 保存 / 另存为 / 多选导入',
        '基础编辑：输入 / 删除 / 撤销 / 重做 / 复制 / 粘贴 / 剪切',
        '多格式语法高亮：txt / md / cpp / h / hpp / json / xml',
        'JSON / XML / C++ 基础代码格式化',
        '跨平台语音播报（选中 / 全文，暂停 / 继续 / 停止）',
        '多标签页编辑、行号栏、底部状态栏',
        '文件编码自动识别（UTF-8 / GBK）',
        '插件式架构内核',
      ],
    ),
  ];
}

/// A single version entry in the change log.
class VersionChangeLog {
  const VersionChangeLog({
    required this.version,
    required this.date,
    required this.title,
    required this.changes,
  });

  final String version;
  final String date;
  final String title;
  final List<String> changes;
}
