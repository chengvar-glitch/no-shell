/// 本地写入句柄：只暴露 SFTP 下载需要的三个操作。
/// 刻意比 dart:io 的 `IOSink` 更窄——接口里一旦出现 dart:io 类型，
/// web 端就无法编译，因此这里单独成一库，平台实现见 `local_write_io` / `local_write_stub`。
abstract interface class LocalWriteHandle {
  void add(List<int> chunk);

  /// 把已缓冲的数据刷到磁盘：高带宽下载时靠它把内存占用压在几 MB 内。
  Future<void> flush();

  Future<void> close();
}
