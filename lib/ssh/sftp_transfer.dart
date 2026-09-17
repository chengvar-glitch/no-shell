import 'dart:async';

import 'package:flutter/foundation.dart';

import 'local_files.dart';
import 'sftp.dart';

/// 传输方向。
enum SftpTransferDirection { upload, download }

enum SftpTransferState { queued, running, done, failed, canceled }

/// 单个传输任务。
///
/// 进度只通知自身，界面按行订阅：传输中每块数据都让整个面板重建，
/// 会连带面包屑、列表一起重绘。
final class SftpTransfer extends ChangeNotifier {
  SftpTransfer._({
    required this.id,
    required this.name,
    required this.direction,
    required this.remotePath,
    required this.total,
  });

  static int _sequence = 0;

  final String id;

  /// 文件名（界面主标题）。
  final String name;
  final SftpTransferDirection direction;
  final String remotePath;

  /// 总字节数；0 表示未知，此时进度按不确定态展示。
  final int total;

  int _done = 0;
  SftpTransferState _state = SftpTransferState.queued;
  SftpErrorKind? _errorKind;
  String? _errorDetail;
  bool _cancelRequested = false;
  DateTime? _startedAt;
  DateTime? _finishedAt;
  DateTime? _lastProgressNotifyAt;

  int get done => _done;
  SftpTransferState get state => _state;
  SftpErrorKind? get errorKind => _errorKind;

  /// 原始错误串，仅作兜底展示。
  String? get errorDetail => _errorDetail;

  bool get isFinished =>
      _state == SftpTransferState.done ||
      _state == SftpTransferState.failed ||
      _state == SftpTransferState.canceled;

  /// 0~1；总量未知时为 null，界面按不确定进度条渲染。
  double? get progress =>
      total > 0 ? (_done / total).clamp(0, 1).toDouble() : null;

  /// 已请求取消（排队中的任务会立即结束，运行中的在此标记后由执行体收尾）。
  bool get isCancelRequested => _cancelRequested;

  /// 取消已请求但尚未结束：界面展示「正在取消」而不是进度。
  bool get isCanceling => _cancelRequested && !isFinished;

  /// 平均速率（字节 / 秒），仅在运行中有意义。
  double get bytesPerSecond {
    final started = _startedAt;
    if (started == null || _done == 0) return 0;
    final end = _finishedAt ?? DateTime.now();
    final elapsed = end.difference(started).inMilliseconds;
    return elapsed <= 0 ? 0 : _done * 1000 / elapsed;
  }

  /// 预估剩余时间；总量未知时为空。
  Duration? get remaining {
    final speed = bytesPerSecond;
    if (speed <= 0 || total <= 0) return null;
    final left = total - _done;
    if (left <= 0) return Duration.zero;
    return Duration(seconds: (left / speed).ceil());
  }

  /// 请求取消：排队中的任务直接结束，运行中的由执行体在下一个数据块处结束。
  void cancel() {
    if (isFinished || _cancelRequested) return;
    _cancelRequested = true;
    if (_state == SftpTransferState.queued) {
      _state = SftpTransferState.canceled;
      _finishedAt = DateTime.now();
    }
    notifyListeners();
  }

  void _start() {
    _state = SftpTransferState.running;
    _startedAt = DateTime.now();
    notifyListeners();
  }

  /// 进度按整百分比节流；总量未知时按时间节流（每 250ms 至多一次），
  /// 既让速度 / 字节数持续刷新，又不至于每个数据块都重建整行。
  void _report(int done) {
    if (done == _done) return;
    final total = this.total;
    if (total <= 0) {
      _done = done;
      final now = DateTime.now();
      final last = _lastProgressNotifyAt;
      if (last == null ||
          now.difference(last) >= const Duration(milliseconds: 250)) {
        _lastProgressNotifyAt = now;
        notifyListeners();
      }
      return;
    }
    final stepped = (done * 100) ~/ total != (_done * 100) ~/ total;
    _done = done;
    if (stepped) {
      _lastProgressNotifyAt = DateTime.now();
      notifyListeners();
    }
  }

  void _finish(SftpTransferState state) {
    _state = state;
    _finishedAt = DateTime.now();
    if (state == SftpTransferState.done && total > 0) _done = total;
    notifyListeners();
  }

  void _fail(Object error) {
    if (error is SftpException) {
      _errorKind = error.kind;
      _errorDetail = error.detail;
    } else {
      _errorKind = SftpErrorKind.other;
      _errorDetail = error.toString();
    }
    _finish(SftpTransferState.failed);
  }
}

/// 传输队列：串行执行，一次只跑一个任务。
/// 并发传输会互相争抢连接带宽，进度条也会一起变慢，串行反而更好读。
final class SftpTransferQueue extends ChangeNotifier {
  SftpTransferQueue({
    required this.fileSystem,
    required this.localFiles,
    this.onRemoteMutated,
  });

  /// 延迟取用文件系统：SFTP 通道在首次进入面板时才建立。
  final SftpFileSystem Function() fileSystem;
  final LocalFileGateway localFiles;

  /// 远端内容被写入后的回调（上传完成后刷新当前目录）。
  final Future<void> Function()? onRemoteMutated;

  /// 单个任务结束时回调，供界面弹提示。
  void Function(SftpTransfer transfer)? onTransferFinished;

  /// 本地缓冲区达到该阈值就 flush 一次，避免高带宽下内存无限增长。
  static const _flushThreshold = 4 * 1024 * 1024;

  /// 上传临时文件的后缀。与目标同目录，收尾的 rename 才是同卷操作。
  /// 队列串行执行，同一目标的上传不会并发，因此这个后缀够用。
  static const _partialSuffix = '.noshell-part';

  final List<SftpTransfer> _transfers = [];
  final List<_PendingJob> _pending = [];
  bool _draining = false;
  bool _disposed = false;

  List<SftpTransfer> get transfers => List.unmodifiable(_transfers);

  bool get hasFinished => _transfers.any((transfer) => transfer.isFinished);

  /// 是否仍有排队 / 运行中的任务。
  bool get isBusy => _transfers.any((transfer) => !transfer.isFinished);

  /// 上传一个本地文件到 [remoteDir]；重名是否覆盖由调用方先行确认。
  SftpTransfer enqueueUpload({
    required LocalUpload source,
    required String remoteDir,
  }) {
    final remotePath = sftpJoin(remoteDir, source.name);
    final transfer = _create(
      name: source.name,
      direction: SftpTransferDirection.upload,
      remotePath: remotePath,
      total: source.length,
    );
    return _enqueue(transfer, (transfer) async {
      // 先传到同目录的临时文件，成功后再改名到目标：直接往目标上写
      // （truncate）一旦中途失败或取消，用户原有的同名文件就没了。
      final temporaryPath = '$remotePath$_partialSuffix';
      try {
        await fileSystem().write(
          temporaryPath,
          _guarded(source, transfer),
          onProgress: transfer._report,
        );
        await fileSystem().rename(temporaryPath, remotePath);
      } on Object {
        // 失败 / 取消留下的半截内容是临时文件，删它不动目标。
        await _discardRemote(temporaryPath);
        await onRemoteMutated?.call();
        rethrow;
      }
      await onRemoteMutated?.call();
    });
  }

  /// 下载远端文件到本地落点。
  SftpTransfer enqueueDownload({
    required SftpEntry entry,
    required LocalTarget target,
  }) {
    final transfer = _create(
      name: entry.name,
      direction: SftpTransferDirection.download,
      remotePath: entry.path,
      total: entry.size,
    );
    return _enqueue(transfer, (transfer) async {
      // 同理：先写临时文件，成功了再改名到落点。桌面的「另存为」可以
      // 选中一个已存在的文件，直接覆写再失败会把那份旧文件毁掉。
      final temporaryPath = localFiles.temporaryPath(target.path);
      final sink = localFiles.openWrite(temporaryPath);
      var written = 0;
      var unflushed = 0;
      try {
        await for (final chunk in fileSystem().read(entry.path)) {
          // 取消，或队列已在传输途中被销毁（会话断开 / 删主机）：
          // 立刻收手，别继续往一个已经没人要的文件里写。
          if (transfer.isCancelRequested || _disposed) {
            throw const _TransferCanceled();
          }
          sink.add(chunk);
          written += chunk.length;
          transfer._report(written);
          unflushed += chunk.length;
          if (unflushed >= _flushThreshold) {
            unflushed = 0;
            await sink.flush();
          }
        }
        await sink.flush();
        await sink.close();
        await localFiles.promote(temporaryPath, target.path);
      } on Object {
        await _closeQuietly(sink);
        // 中断的下载只清掉临时文件，落点上原有的文件保持不动。
        await localFiles.discard(temporaryPath);
        rethrow;
      }
    });
  }

  /// 清除已结束的任务记录。
  void clearFinished() {
    final done = _transfers.where((transfer) => transfer.isFinished).toList();
    if (done.isEmpty) return;
    _transfers.removeWhere((transfer) => transfer.isFinished);
    for (final transfer in done) {
      transfer.dispose();
    }
    notifyListeners();
  }

  SftpTransfer _create({
    required String name,
    required SftpTransferDirection direction,
    required String remotePath,
    required int total,
  }) {
    SftpTransfer._sequence++;
    return SftpTransfer._(
      id: 'tx-${SftpTransfer._sequence}',
      name: name,
      direction: direction,
      remotePath: remotePath,
      total: total,
    );
  }

  SftpTransfer _enqueue(
    SftpTransfer transfer,
    Future<void> Function(SftpTransfer) run,
  ) {
    _transfers.add(transfer);
    _pending.add(_PendingJob(transfer, run));
    notifyListeners();
    unawaited(_drain());
    return transfer;
  }

  Future<void> _drain() async {
    if (_draining || _disposed) return;
    _draining = true;
    try {
      while (_pending.isNotEmpty && !_disposed) {
        final job = _pending.removeAt(0);
        final transfer = job.transfer;
        // 排队期间被取消（或队列已销毁）的任务直接跳过。
        if (transfer.isFinished) continue;
        transfer._start();
        var canceled = false;
        try {
          await job.run(transfer);
        } on _TransferCanceled {
          canceled = true;
        } catch (error) {
          // 队列在传输途中被销毁（会话断开 / 删主机）时也会走到这里。
          // dispose 只清了自己的记录，transfer 已经 dispose 过，再改状态
          // 或通知就是「used after being disposed」，而且队列早已无人订阅。
          if (_disposed) return;
          transfer._fail(error);
          notifyListeners();
          continue;
        }
        if (_disposed) return;
        transfer._finish(
          canceled || transfer.isCancelRequested
              ? SftpTransferState.canceled
              : SftpTransferState.done,
        );
        notifyListeners();
        // 界面提示回调不许打断队列：抛了异常剩下的任务还得继续跑。
        try {
          onTransferFinished?.call(transfer);
        } catch (_) {}
      }
    } finally {
      _draining = false;
    }
  }

  /// 把取消标记接入源流：命中即报错，远端 writer 随之停止。
  Stream<List<int>> _guarded(LocalUpload source, SftpTransfer transfer) async* {
    await for (final chunk in source.openRead()) {
      if (transfer.isCancelRequested) throw const _TransferCanceled();
      yield chunk;
    }
  }

  Future<void> _discardRemote(String remotePath) async {
    try {
      await fileSystem().removeFile(remotePath);
    } on Object {
      // 清理失败不影响错误上报：远端可能已断开。
    }
  }

  static Future<void> _closeQuietly(LocalWriteHandle sink) async {
    try {
      await sink.close();
    } on Object {
      // 关闭失败（磁盘写满等）只需保留原始错误。
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pending.clear();
    for (final transfer in _transfers) {
      transfer.dispose();
    }
    _transfers.clear();
    super.dispose();
  }
}

final class _PendingJob {
  _PendingJob(this.transfer, this.run);

  final SftpTransfer transfer;
  final Future<void> Function(SftpTransfer) run;
}

/// 内部取消信号：不是失败，不计入错误归类。
final class _TransferCanceled implements Exception {
  const _TransferCanceled();
}
