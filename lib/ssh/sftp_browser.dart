import 'dart:async';

import 'package:flutter/foundation.dart';

import 'local_files.dart';
import 'sftp.dart';
import 'sftp_transfer.dart';

/// 列表排序字段。
enum SftpSortField { name, size, modified }

/// 下载编排结果，供界面决定提示文案。
enum SftpDownloadOutcome { enqueued, canceled, unavailable, empty }

/// 本次目录载入要如何更新浏览历史。
enum _SftpHistoryStep {
  /// 用户发起了一次新导航：丢弃「前进」分支并追加目标。
  push,

  /// 鼠标侧键 / 后退：沿历史退一格，不追加新记录。
  back,

  /// 鼠标侧键 / 前进：沿已退出的历史进一格。
  forward,

  /// 刷新或首次载入：历史保持原样。
  none,
}

/// SFTP 面板状态：当前目录、列表、排序过滤、选中项与传输队列。
///
/// 会话层持有本对象，面板只订阅不持有，因而切换 Tab 不会丢失浏览位置、
/// 也不会打断进行中的传输。
final class SftpBrowserController extends ChangeNotifier {
  SftpBrowserController({
    required this.openFileSystem,
    this.localFiles = const NativeLocalFileGateway(),
  }) {
    transfers = SftpTransferQueue(
      fileSystem: _requireFileSystem,
      localFiles: localFiles,
      onRemoteMutated: refresh,
    );
  }

  /// 延迟打开 SFTP 通道：首次进入 SFTP Tab 时才建。
  final Future<SftpFileSystem> Function() openFileSystem;

  /// 本地文件交互入口，测试中可替换为假实现。
  final LocalFileGateway localFiles;

  /// 传输队列：与会话同生命周期，切 Tab 后仍在后台跑。
  late final SftpTransferQueue transfers;

  SftpFileSystem? _fileSystem;
  String? _path;

  /// 会话的家目录：地址栏用它折叠面包屑（`/home/deploy` → 「主目录」）
  /// 并展开 `~`。通道打开时读一次，读不到就退回逐段路径。
  String? _home;

  /// Windows 远端探测到的盘符（`C:` 形态，升序）。见 [_probeWindowsDrives]。
  List<String> _drives = const [];

  /// 最近一次成功载入的目录。[navigate] 用它判重：
  /// 载入失败的路径仍留在 [_path]（路径栏如实展示），再次进入要能重试。
  String? _loadedPath;

  /// 正在请求中的目录（含刷新）。[navigate] 用它挡掉同一目录的重复点按：
  /// 触屏上「点一下没反应就再点一下」很常见，慢链路上两次请求会互相挤，
  /// 后一次还会把前一次的结果丢掉重来（_loadToken）。
  String? _loadingTarget;
  List<SftpEntry> _entries = const [];
  List<SftpEntry> _visible = const [];

  /// [_entries] 的有序缓存（见 [_ordered]）。
  List<SftpEntry> _orderedCache = const [];
  bool _orderedStale = true;

  /// 当前列表（过滤前）所有文件的字节数，随载入算一次；
  /// 状态栏直接取用，不在每次通知时重新 fold 整份目录。
  int _totalBytes = 0;
  final Set<String> _selected = {};

  /// Shift 连选的锚点（最后一次单击的条目）。
  String? _anchor;

  bool _opening = false;
  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _isMutating = false;
  SftpException? _error;
  int _loadToken = 0;
  bool _disposed = false;

  /// 目录浏览历史。[SftpBrowserController.canGoBack] / [canGoForward] 与
  /// 鼠标侧键共用；游标只落在**成功载入**的目录上，失败路径不入史。
  final List<String> _history = [];
  int _historyCursor = -1;

  bool _showHidden = false;
  String _query = '';
  SftpSortField _sortField = SftpSortField.name;
  bool _sortAscending = true;

  /// 当前目录；尚未载入时为 null。
  String? get path => _path;

  /// 登录用户的家目录；未读到时为 null。
  String? get home => _home;

  /// 家目录是否是 Win32 OpenSSH 的盘符形态：决定快捷胶囊给哪一套
  /// （Windows 给「~ + 盘符」，Unix 给常用目录）。
  bool get isWindowsRemote => _home != null && sftpIsWindowsRemotePath(_home!);

  /// 探测到的盘符（`C:` 形态，升序）；未探测 / 探测失败时为空——
  /// 此时胶囊行仍会从家目录推导出所在盘。
  List<String> get drives => _drives;

  /// 过滤 + 排序后的展示序列（长列表按下标直取，避免每帧重排）。
  List<SftpEntry> get entries => _visible;

  /// 当前目录所有文件的总字节数（不含目录）。
  int get totalBytes => _totalBytes;

  /// 首次载入（还没有任何目录内容）。
  bool get isLoading => _isLoading;

  /// 已有内容时的刷新，界面保留旧列表并显示细进度条。
  bool get isRefreshing => _isRefreshing;

  /// 正在执行新建 / 重命名 / 删除等结构性操作。
  bool get isMutating => _isMutating;

  SftpException? get error => _error;

  /// SFTP 通道已就绪且至少载入过一次目录。
  bool get isReady => _fileSystem != null && _path != null;

  /// 是否还有更早的浏览位置（鼠标侧键「后退」可用）。
  bool get canGoBack => _historyCursor > 0;

  /// 是否还能回到退出的浏览位置（鼠标侧键「前进」可用）。
  bool get canGoForward =>
      _historyCursor >= 0 && _historyCursor + 1 < _history.length;

  bool get showHidden => _showHidden;
  String get query => _query;
  SftpSortField get sortField => _sortField;
  bool get sortAscending => _sortAscending;

  Set<String> get selectedPaths => Set.unmodifiable(_selected);

  List<SftpEntry> get selectedEntries =>
      _visible.where((entry) => _selected.contains(entry.path)).toList();

  bool isSelected(String path) => _selected.contains(path);

  @override
  void dispose() {
    _disposed = true;
    transfers.dispose();
    _fileSystem?.dispose();
    _fileSystem = null;
    super.dispose();
  }

  /// 打开 SFTP 通道并载入家目录；重复调用无副作用，
  /// 也用于首次载入失败后的重试。
  Future<void> ensureReady() async {
    if (_disposed || _opening) return;
    if (_fileSystem != null && _path != null) return;
    _opening = true;
    try {
      var fileSystem = _fileSystem;
      if (fileSystem == null) {
        fileSystem = await openFileSystem();
        if (_disposed) {
          fileSystem.dispose();
          return;
        }
        _fileSystem = fileSystem;
      }
      if (_path == null) {
        final home = await fileSystem.homeDirectory();
        if (_disposed) return;
        _home = home;
        await _load(home, history: _SftpHistoryStep.push);
        // 家目录载入成功才探测盘符；探测在后台跑，不拖慢首屏，
        // 结果到了再补进胶囊行。
        if (_loadedPath == sftpNormalizedRemotePath(home)) {
          unawaited(_probeWindowsDrives(fileSystem));
        }
      }
    } on Object catch (error) {
      if (_disposed) return;
      _error = _wrap(error);
      _isLoading = false;
      _isRefreshing = false;
      notifyListeners();
    } finally {
      _opening = false;
    }
  }

  /// 重新读取当前目录。
  Future<void> refresh() async {
    final path = _path;
    if (path == null) {
      await ensureReady();
      return;
    }
    await _load(path, keepSelection: true);
  }

  Future<void> navigate(String target) async {
    if (target.isEmpty || target == _loadedPath) return;
    // 同一目录的请求还在路上：这一次点按就是刚那一下的重复。
    if (target == _loadingTarget) return;
    await _load(target, history: _SftpHistoryStep.push);
  }

  /// 回到上一个成功浏览过的目录；没有上一页时不发请求。
  Future<void> goBack() async {
    if (!canGoBack) return;
    await _stepHistory(_history[_historyCursor - 1], _SftpHistoryStep.back);
  }

  /// 回到被「后退」离开的目录；没有下一页时不发请求。
  Future<void> goForward() async {
    if (!canGoForward) return;
    await _stepHistory(_history[_historyCursor + 1], _SftpHistoryStep.forward);
  }

  /// 侧键的历史步进：同一目标的请求还在路上时，这一下就是刚才那下的重复，
  /// 不再发请求——否则同一次载入会被两笔 back 各退一格，游标与画面错位。
  Future<void> _stepHistory(String target, _SftpHistoryStep step) async {
    if (target == _loadingTarget) return;
    await _load(target, history: step);
  }

  Future<void> goUp() async {
    final path = _path;
    if (path == null) return;
    final parent = sftpParent(path);
    if (parent == path) return;
    await _load(parent, history: _SftpHistoryStep.push);
  }

  /// 地址栏补全候选：把 [input] 当作「敲到一半的路径」，列出同目录下同前缀
  /// 的条目（目录带尾斜杠，与 shell 一致）。
  ///
  /// 候选保持**用户敲的那个写法**：`~/lo` 补出 `~/logs/` 而不是
  /// `/home/deploy/logs/`，相对路径同理——否则边敲边补时输入框会自己把
  /// `~` 换成绝对路径，越补越陌生（GNOME 也是保留原写法）。
  ///
  /// 读目录失败返回空列表——补全失败不该弹错误，用户接着敲就是了。
  /// 隐藏文件只在用户自己敲了 `.` 的时候才出现。
  Future<List<String>> completePath(String input) async {
    final fileSystem = _fileSystem;
    final query = sftpCompletionQuery(input, home: _home, base: _path);
    if (fileSystem == null || query == null) return const [];
    final List<SftpEntry> entries;
    if (query.directory == _loadedPath) {
      // 当前目录已经在手，不必为一次补全再问一遍服务端。
      entries = _entries;
    } else {
      try {
        entries = await fileSystem.list(query.directory);
      } on Object {
        return const [];
      }
      if (_disposed) return const [];
    }
    final matches = [
      for (final entry in entries)
        if (entry.name.startsWith(query.prefix) &&
            (query.prefix.startsWith('.') || !entry.name.startsWith('.')))
          entry,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    // 用户已经敲好的目录那一段（含斜杠）原样留着，只接上候选的名字。
    final typed = input.trim();
    final prefix = typed.substring(0, typed.length - query.prefix.length);
    return [
      for (final entry in matches)
        entry.isDirectory ? '$prefix${entry.name}/' : '$prefix${entry.name}',
    ];
  }

  void setQuery(String query) {
    if (_query == query) return;
    _query = query;
    _rebuildVisible();
    notifyListeners();
  }

  void toggleHidden() {
    _showHidden = !_showHidden;
    _rebuildVisible();
    notifyListeners();
  }

  /// 切换排序字段；再次点击同一字段则反转方向。
  /// 「修改时间」默认新文件在前，符合看「最近上传了什么」的直觉。
  void toggleSort(SftpSortField field) {
    if (_sortField == field) {
      _sortAscending = !_sortAscending;
    } else {
      _sortField = field;
      _sortAscending = field != SftpSortField.modified;
    }
    _orderedStale = true;
    _rebuildVisible();
    notifyListeners();
  }

  void select(String path, {bool additive = false}) {
    _anchor = path;
    if (additive) {
      if (!_selected.add(path)) return;
    } else {
      if (_selected.length == 1 && _selected.contains(path)) return;
      _selected
        ..clear()
        ..add(path);
    }
    notifyListeners();
  }

  /// Shift 连选：从上次点击的锚点到 [path] 之间的连续区间。
  void selectTo(String path, {bool additive = false}) {
    final anchor = _anchor;
    final anchorIndex = anchor == null
        ? -1
        : _visible.indexWhere((entry) => entry.path == anchor);
    final targetIndex = _visible.indexWhere((entry) => entry.path == path);
    if (anchorIndex < 0 || targetIndex < 0) {
      select(path, additive: additive);
      return;
    }
    final from = anchorIndex < targetIndex ? anchorIndex : targetIndex;
    final to = anchorIndex < targetIndex ? targetIndex : anchorIndex;
    if (!additive) _selected.clear();
    for (var i = from; i <= to; i++) {
      _selected.add(_visible[i].path);
    }
    notifyListeners();
  }

  void toggleSelection(String path) {
    if (!_selected.remove(path)) _selected.add(path);
    notifyListeners();
  }

  void selectAll() {
    _selected
      ..clear()
      ..addAll(_visible.map((entry) => entry.path));
    notifyListeners();
  }

  void clearSelection() {
    if (_selected.isEmpty) return;
    _selected.clear();
    notifyListeners();
  }

  /// 新建目录（名称非法时抛 [ArgumentError]，界面在对话框里先行校验）。
  Future<void> createFolder(String name) async {
    final path = _path;
    if (path == null) return;
    if (!isValidEntryName(name)) {
      throw ArgumentError.value(name, 'name', 'invalid entry name');
    }
    await _mutate(
      () => _requireFileSystem().createDirectory(sftpJoin(path, name.trim())),
    );
  }

  /// 重命名条目；沿用原名时直接返回。
  Future<void> renameEntry(SftpEntry entry, String newName) async {
    final trimmed = newName.trim();
    if (trimmed == entry.name) return;
    if (!isValidEntryName(trimmed)) {
      throw ArgumentError.value(newName, 'name', 'invalid entry name');
    }
    final target = sftpJoin(sftpParent(entry.path), trimmed);
    await _mutate(() async {
      await _requireFileSystem().rename(entry.path, target);
      if (_selected.remove(entry.path)) _selected.add(target);
    });
  }

  /// 递归删除条目（目录先清空再删自身）。
  Future<void> deleteEntries(List<SftpEntry> entries) async {
    if (entries.isEmpty) return;
    final fileSystem = _requireFileSystem();
    await _mutate(() async {
      for (final entry in entries) {
        // 符号链接只删链接本身，不递归进目标目录。
        if (entry.isDirectory && !entry.isSymlink) {
          await _removeTree(fileSystem, entry.path);
        } else {
          await fileSystem.removeFile(entry.path);
        }
        _selected.remove(entry.path);
      }
    });
  }

  /// 选择待上传的本地文件（用户取消时返回空列表）。
  Future<List<LocalUpload>> pickUploads(String confirmLabel) =>
      localFiles.pickUploads(confirmLabel: confirmLabel);

  /// 当前目录中已存在同名远端条目、需要覆盖确认的上传源。
  List<LocalUpload> conflictsWith(List<LocalUpload> sources) {
    final names = {for (final entry in _entries) entry.name};
    return [
      for (final source in sources)
        if (names.contains(source.name)) source,
    ];
  }

  /// 入队上传；重名是否覆盖由界面先行确认。
  void startUpload(List<LocalUpload> sources) {
    final path = _path;
    if (path == null) return;
    for (final source in sources) {
      transfers.enqueueUpload(source: source, remoteDir: path);
    }
  }

  /// 下载条目：单个走「另存为」，多个走一次目录选择。
  Future<SftpDownloadOutcome> downloadEntries(
    List<SftpEntry> targets,
    String confirmLabel,
  ) async {
    if (targets.isEmpty) return SftpDownloadOutcome.empty;
    final List<LocalTarget>? destinations;
    if (targets.length == 1) {
      final target = await localFiles.pickDownloadTarget(
        targets.single.name,
        confirmLabel: confirmLabel,
      );
      if (target == null) return SftpDownloadOutcome.canceled;
      destinations = [target];
    } else {
      destinations = await localFiles.pickDownloadDirectory([
        for (final entry in targets) entry.name,
      ], confirmLabel: confirmLabel);
      if (destinations == null) return SftpDownloadOutcome.canceled;
    }
    // 落点数量必须与目标一一对应。网关换了实现（移动端的 SAF 选择器
    // 就可能只回一个目录）时宁可整体不下载，也不能在下标越界处半途炸掉：
    // 那时前面的任务已经入队，用户看到的是「下了一半 + 一个异常」。
    if (destinations.length < targets.length) {
      return SftpDownloadOutcome.unavailable;
    }
    for (var i = 0; i < targets.length; i++) {
      transfers.enqueueDownload(entry: targets[i], target: destinations[i]);
    }
    return SftpDownloadOutcome.enqueued;
  }

  /// 预览等只读界面直接取远端字节；下载仍走传输队列，
  /// 两条路径互不抢队列，也不会把临时预览文件写进用户可见目录。
  Stream<List<int>> readRemoteFile(String path) =>
      _requireFileSystem().read(path);

  Future<void> _load(
    String target, {
    bool keepSelection = false,
    _SftpHistoryStep history = _SftpHistoryStep.none,
  }) async {
    final fileSystem = _fileSystem;
    if (fileSystem == null) return;
    // 光秃盘符（`/C:`）在 Win32 OpenSSH 下指「该盘的当前目录」而不是盘根，
    // 面包屑与地址栏都可能给出这种写法：统一补上斜杠，浏览永远落在盘根。
    target = sftpNormalizedRemotePath(target);
    final token = ++_loadToken;
    final firstLoad = _path == null;
    _error = null;
    _loadingTarget = target;
    if (firstLoad) {
      _isLoading = true;
    } else {
      _isRefreshing = true;
    }
    notifyListeners();
    try {
      final listing = await fileSystem.list(target);
      // 期间用户又切换了目录：丢弃这次结果，由最新请求收尾。
      if (token != _loadToken || _disposed) return;
      _applyHistory(target, history);
      _path = target;
      _loadedPath = target;
      _entries = listing;
      _orderedStale = true;
      if (keepSelection) {
        final names = {for (final entry in listing) entry.path};
        _selected.retainWhere(names.contains);
      } else {
        _selected.clear();
      }
      _rebuildVisible();
      _recomputeTotalBytes();
    } on Object catch (error) {
      if (token != _loadToken || _disposed) return;
      // 路径栏如实反映「想打开哪里」，列表清空并把错误交给界面展示。
      _path = target;
      _entries = const [];
      _orderedStale = true;
      _selected.clear();
      _rebuildVisible();
      _recomputeTotalBytes();
      _error = _wrap(error);
    } finally {
      if (token == _loadToken && !_disposed) {
        _loadingTarget = null;
        _isLoading = false;
        _isRefreshing = false;
        notifyListeners();
      }
    }
  }

  /// Windows 远端探测盘符：Win32 OpenSSH 把根目录列成全部盘（`c:`、
  /// `d:`…），一次 `list('/')` 就是全部结果。失败不惊动用户——家目录所在盘
  /// 仍能从家目录推导出来，胶囊照常出现，只是少几块盘。
  Future<void> _probeWindowsDrives(SftpFileSystem fileSystem) async {
    final home = _home;
    if (home == null || !sftpIsWindowsRemotePath(home)) return;
    try {
      final entries = await fileSystem.list('/');
      if (_disposed) return;
      final drives = <String>{};
      for (final entry in entries) {
        if (!entry.isDirectory) continue;
        final name = sftpDriveName(entry.name);
        if (name != null) drives.add(name);
      }
      final ordered = drives.toList()..sort();
      // 通知前先做无变化守卫：探测没找到任何盘符时不开这一轮重建。
      if (listEquals(ordered, _drives)) return;
      _drives = List.unmodifiable(ordered);
      notifyListeners();
    } on Object {
      // 根目录读不了：停在「家目录所在盘」这一档。
    }
  }

  /// 目录真正载入成功后才移动游标：失败的路径不该把侧键历史带歪。
  void _applyHistory(String target, _SftpHistoryStep step) {
    switch (step) {
      case _SftpHistoryStep.push:
        if (_historyCursor >= 0 && _history[_historyCursor] == target) return;
        _history.length = _historyCursor + 1;
        _history.add(target);
        _historyCursor = _history.length - 1;
      case _SftpHistoryStep.back:
        if (canGoBack) _historyCursor--;
      case _SftpHistoryStep.forward:
        if (canGoForward) _historyCursor++;
      case _SftpHistoryStep.none:
        break;
    }
  }

  /// 结构性操作：期间禁用工具栏，结束后刷新列表；失败向上抛由界面提示。
  ///
  /// 已经在忙时抛 [SftpErrorKind.busy] 而不是静默返回：调用方 await 之后
  /// 会去报「完成」，静默返回等于告诉用户改成功了，而其实什么都没做。
  /// 工具栏在忙时会禁用按钮，正常路径到不了这里，这是兜底。
  ///
  /// [isMutating] 必须一直保持到**刷新结束**：刷新在大目录 / 慢链路上要花
  /// 几百毫秒，那段时间同样是「结构性操作进行中」，提前放开守卫等于允许
  /// 第二个操作挤进刷新窗口。
  Future<void> _mutate(Future<void> Function() action) async {
    if (_isMutating) {
      throw const SftpException(SftpErrorKind.busy);
    }
    _isMutating = true;
    notifyListeners();
    try {
      await action();
      // 等刷新落地再返回：调用方 await 结束后列表已经是新状态。
      await refresh();
    } finally {
      _isMutating = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _removeTree(SftpFileSystem fileSystem, String path) async {
    // 调用方已把顶层符号链接当文件删；这里对嵌套的子项同样不穿链接：
    // list / 递归会跟着链接进到目标目录，把目标内容删空而链接还留着，
    // 等于误删别人的数据。SFTP REMOVE 按 unlink 语义删链接，不碰目标。
    for (final child in await fileSystem.list(path)) {
      if (child.isDirectory && !child.isSymlink) {
        await _removeTree(fileSystem, child.path);
      } else {
        await fileSystem.removeFile(child.path);
      }
    }
    await fileSystem.removeDirectory(path);
  }

  void _rebuildVisible() {
    final query = _query.trim().toLowerCase();
    // 先按当前排序键取一份有序序列，再过滤：过滤不改相对顺序，结果与
    // 「先过滤再排序」完全一致，但连续输入时省掉了每个字符一次全量排序
    // （大目录里是 O(n log n)，而筛选本身只要 O(n)）。
    _visible = List.unmodifiable([
      for (final entry in _ordered)
        if ((_showHidden || !entry.name.startsWith('.')) &&
            (query.isEmpty || entry.name.toLowerCase().contains(query)))
          entry,
    ]);
  }

  /// [_entries] 按当前排序键排好的一份缓存；目录内容或排序键变化时作废。
  List<SftpEntry> get _ordered {
    if (!_orderedStale) return _orderedCache;
    _orderedCache = [..._entries]..sort(_compare);
    _orderedStale = false;
    return _orderedCache;
  }

  /// 载入结果落地后重算一次总量，状态栏只在目录变化时拿到新值。
  void _recomputeTotalBytes() {
    _totalBytes = [
      for (final entry in _entries)
        if (!entry.isDirectory) entry.size,
    ].fold(0, (sum, size) => sum + size);
  }

  int _compare(SftpEntry a, SftpEntry b) {
    // 目录恒排在文件之前，便于先进入目录再挑文件。
    if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
    final result = switch (_sortField) {
      SftpSortField.name => a.name.toLowerCase().compareTo(
        b.name.toLowerCase(),
      ),
      SftpSortField.size => a.size.compareTo(b.size),
      SftpSortField.modified =>
        (a.modifiedAt?.millisecondsSinceEpoch ?? 0).compareTo(
          b.modifiedAt?.millisecondsSinceEpoch ?? 0,
        ),
    };
    return _sortAscending ? result : -result;
  }

  SftpFileSystem _requireFileSystem() {
    final fileSystem = _fileSystem;
    if (fileSystem == null) {
      throw const SftpException(
        SftpErrorKind.other,
        'SFTP session is not ready',
      );
    }
    return fileSystem;
  }

  static SftpException _wrap(Object error) => error is SftpException
      ? error
      : SftpException(SftpErrorKind.other, error.toString());
}
