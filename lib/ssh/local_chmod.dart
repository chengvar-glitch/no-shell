/// 把文件权限收到仅当前用户可读写（POSIX 0600）。
///
/// 为什么要动 FFI：导出主机备份时写出的明文里带着密码，而 `dart:io` 建文件
/// 一律走进程 umask（默认 umask 022 下是 0644，同机器上任何本地账号都能读），
/// Dart 没有暴露设置权限位的 API，`File.open` 的打开模式也不控制权限。
///
/// 只绑定 `chmod` 一个函数；任何失败一律静默——权限没收紧不该让导出直接
/// 失败，文件内容本身仍然是对的。
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _ChmodNative = Int32 Function(Pointer<Utf8>, Uint32);
typedef _ChmodDart = int Function(Pointer<Utf8>, int);

/// 0600：仅属主可读写。
const int _ownerReadWrite = 0x180;

/// 仅在支持 POSIX 权限位的平台上真正执行。
bool get _supported =>
    Platform.isMacOS ||
    Platform.isLinux ||
    Platform.isAndroid ||
    Platform.isIOS ||
    Platform.isFuchsia;

/// 为文件设置权限位（默认 0600），文件不存在时先建出来。
///
/// 已存在的文件也照样收紧：调用方只在写入机密内容时传 ownerOnly
/// （导出含密码的备份、保存会话日志），此时「目标文件恰好已存在」多半是
/// 上一次的导出，沿用它的权限位（例如 0644）等于让同机器上任何本地账号
/// 都能读到这次刚写进去的密码。用户在选择器里点了覆盖，就是同意按本应用
/// 的规则重写这个文件，权限一并归位。
void restrictFileToOwner(File file, {int mode = _ownerReadWrite}) {
  if (!_supported) return;
  try {
    if (!file.existsSync()) file.createSync();
  } on Object {
    return;
  }
  _chmod(file.path, mode);
}

void _chmod(String path, int mode) {
  final fn = _chmodFn;
  if (fn == null) return;
  final pointer = path.toNativeUtf8();
  try {
    fn(pointer, mode);
  } on Object {
    // 只影响权限，不影响导出本身。
  } finally {
    malloc.free(pointer);
  }
}

/// 解析 `chmod`；拿不到符号时返回 null（该平台就不收紧权限）。
final _ChmodDart? _chmodFn = _resolveChmod();

_ChmodDart? _resolveChmod() {
  if (!_supported) return null;
  // iOS 不允许查进程自身的 libc 符号（App Store 审核会拒），跳过。
  if (Platform.isIOS) return null;
  for (final attempt in <DynamicLibrary Function()>[
    DynamicLibrary.process,
    () => DynamicLibrary.open('libc.so.6'),
    () => DynamicLibrary.open('libc.so'),
  ]) {
    try {
      return attempt().lookupFunction<_ChmodNative, _ChmodDart>('chmod');
    } on Object {
      continue;
    }
  }
  return null;
}
