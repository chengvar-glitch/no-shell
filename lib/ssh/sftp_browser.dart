import 'dart:async';

import 'package:flutter/foundation.dart';

import 'local_files.dart';
import 'sftp.dart';
import 'sftp_transfer.dart';

/// 列表排序字段。
enum SftpSortField { name, size, modified }

/// 下载编排结果，供界面决定提示文案。
enum SftpDownloadOutcome { enqueued, canceled, unavailable, empty }

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

  /// 最近一次成功载入的目录。[navigate] 用它判重：
  /// 载入失败的路径仍留在 [_path]（路径栏如实展示），再次进入要能重试。
  String? _loadedPath;
  List<SftpEntry> _entries = const [];
  List<SftpEntry> _visible = const [];

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

  bool _showHidden = false;
  String _query = '';
  SftpSortField _sortField = SftpSortField.name;
  bool _sortAscending = true;

  /// 当前目录；尚未载入时为 null。
  String? get path => _path;

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
      if (_path == null) await _load(await fileSystem.homeDirectory());
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
    await _load(target);
  }

  Future<void> goUp() async {
    final path = _path;
    if (path == null) return;
    final parent = sftpParent(path);
    if (parent == path) return;
    await _load(parent);
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
    if (destinations.isEmpty) return SftpDownloadOutcome.unavailable;
    for (var i = 0; i < targets.length; i++) {
      transfers.enqueueDownload(entry: targets[i], target: destinations[i]);
    }
    return SftpDownloadOutcome.enqueued;
  }

  Future<void> _load(String target, {bool keepSelection = false}) async {
    final fileSystem = _fileSystem;
    if (fileSystem == null) return;
    final token = ++_loadToken;
    final firstLoad = _path == null;
    _error = null;
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
      _path = target;
      _loadedPath = target;
      _entries = listing;
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
      _selected.clear();
      _rebuildVisible();
      _recomputeTotalBytes();
      _error = _wrap(error);
    } finally {
      if (token == _loadToken && !_disposed) {
        _isLoading = false;
        _isRefreshing = false;
        notifyListeners();
      }
    }
  }

  /// 结构性操作：期间禁用工具栏，结束后刷新列表；失败向上抛由界面提示。
  Future<void> _mutate(Future<void> Function() action) async {
    if (_isMutating) return;
    _isMutating = true;
    notifyListeners();
    try {
      await action();
    } finally {
      _isMutating = false;
      if (!_disposed) notifyListeners();
      // 等刷新落地再返回：调用方 await 结束后列表已经是新状态。
      await refresh();
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
    final list = [
      for (final entry in _entries)
        if ((_showHidden || !entry.name.startsWith('.')) &&
            (query.isEmpty || entry.name.toLowerCase().contains(query)))
          entry,
    ];
    list.sort(_compare);
    _visible = List.unmodifiable(list);
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
