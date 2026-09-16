import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/ssh/dartssh2_sftp.dart';
import 'package:no_shell/ssh/sftp.dart';

/// 适配层里可以脱离连接测试的纯逻辑：权限位格式化与错误归类。
void main() {
  group('权限位格式化', () {
    test('按 ls -l 风格输出类型与三段权限', () {
      // 0x4000 = 目录标志位，0x1ED = 0o755（rwxr-xr-x）
      expect(
        formatSftpPermissions(SftpFileMode.value(0x4000 | 0x1ED)),
        'drwxr-xr-x',
      );
      // 0x8000 = 普通文件标志位，0x100 = 0o400
      expect(
        formatSftpPermissions(SftpFileMode.value(0x8000 | 0x100)),
        '-r--------',
      );
      // 0xA000 = 符号链接标志位，0x1FF = 0o777
      expect(
        formatSftpPermissions(SftpFileMode.value(0xA000 | 0x1FF)),
        'lrwxrwxrwx',
      );
      // 0x1A4 = 0o644
      expect(
        formatSftpPermissions(SftpFileMode.value(0x8000 | 0x1A4)),
        '-rw-r--r--',
      );
      expect(formatSftpPermissions(null), isNull);
    });
  });

  group('错误归类', () {
    test('SFTP 状态码映射到界面文案分类', () {
      expect(
        sftpErrorFrom(SftpStatusError(SftpStatusCode.permissionDenied, ''))
            .kind,
        SftpErrorKind.permission,
      );
      expect(
        sftpErrorFrom(SftpStatusError(SftpStatusCode.noSuchFile, '')).kind,
        SftpErrorKind.notFound,
      );
      expect(
        sftpErrorFrom(SftpStatusError(SftpStatusCode.opUnsupported, '')).kind,
        SftpErrorKind.unsupported,
      );
      expect(
        sftpErrorFrom(SftpStatusError(SftpStatusCode.connectionLost, '')).kind,
        SftpErrorKind.network,
      );
      expect(
        sftpErrorFrom(SftpStatusError(SftpStatusCode.failure, '')).kind,
        SftpErrorKind.other,
      );
    });

    test('平台不支持与连接中断各归其类', () {
      expect(
        sftpErrorFrom(UnsupportedError('no tcp')).kind,
        SftpErrorKind.unsupported,
      );
      expect(
        sftpErrorFrom(SSHSocketError('refused')).kind,
        SftpErrorKind.network,
      );
      expect(
        sftpErrorFrom(SftpAbortError('channel closed')).kind,
        SftpErrorKind.network,
      );
    });

    test('已归类的异常原样返回，未知错误归入 other', () {
      const known = SftpException(SftpErrorKind.permission, 'denied');
      expect(identical(sftpErrorFrom(known), known), isTrue);
      expect(sftpErrorFrom(StateError('boom')).kind, SftpErrorKind.other);
    });
  });
}
