// 开发用冒烟脚本：用真实凭据登录目标主机并执行命令，验证 dartssh2 认证与会话链路。
// 用法：
//   dart run tool/smoke_ssh.dart <host> <port> <user> --password <密码>
//   dart run tool/smoke_ssh.dart <host> <port> <user> --identity <PEM路径> [--passphrase <口令>]
//   追加 --shell 验证 PTY 交互式 shell；追加 --sftp 验证 SFTP 浏览与上传 / 下载链路。
// 凭据只经命令行传入，不写入本文件。
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
// 只引入纯 Dart 的适配器与领域层：冒烟脚本由 `dart run` 启动，
// 一旦牵扯到 Flutter（models / l10n）就无法编译。
import 'package:no_shell/ssh/dartssh2_sftp.dart';
import 'package:no_shell/ssh/sftp.dart';

Future<void> main(List<String> args) async {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  String? option(String name) {
    final index = args.indexOf(name);
    if (index == -1 || index + 1 >= args.length) return null;
    final value = args[index + 1];
    return value.startsWith('--') ? null : value;
  }

  bool flag(String name) => args.contains(name);

  if (positional.length < 3) {
    stderr.writeln(
      '用法: dart run tool/smoke_ssh.dart <host> <port> <user> '
      '--password <密码> | --identity <PEM路径> [--passphrase <口令>] '
      '[--shell] [--sftp]',
    );
    exitCode = 64;
    return;
  }
  final host = positional[0];
  final port = int.parse(positional[1]);
  final username = positional[2];
  final password = option('--password');
  final identityPath = option('--identity');
  final passphrase = option('--passphrase');

  // --sftp 走 App 自己的传输层与适配器，覆盖界面用到的全部 SFTP 操作。
  if (flag('--sftp')) {
    await smokeSftp(
      host: host,
      port: port,
      username: username,
      password: password,
      identityPath: identityPath,
      passphrase: passphrase,
    );
    return;
  }

  final socket = await SSHSocket.connect(
    host,
    port,
    timeout: const Duration(seconds: 10),
  );
  // ignore: avoid_print
  print('TCP OK -> $host:$port');

  final identities = <SSHIdentity>[
    if (identityPath != null)
      ...SSHKeyPair.fromPem(File(identityPath).readAsStringSync(), passphrase),
  ];

  final client = SSHClient(
    socket,
    username: username,
    identities: identities,
    onPasswordRequest: () => password,
    onUserInfoRequest: (request) {
      if (password == null) return null;
      return List.filled(request.prompts.length, password);
    },
    handshakeTimeout: const Duration(seconds: 10),
  );
  try {
    // --shell：走 App 真实使用的 PTY 交互式 shell 路径（shell + stdin/stdout）。
    if (flag('--shell')) {
      final session = await client.shell(
        pty: const SSHPtyConfig(type: 'xterm-256color', width: 80, height: 24),
      );
      final buffer = StringBuffer();
      final subscription = session.stdout
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(buffer.write);
      session.stdin.add(utf8.encode('echo shell-pty-ok\n'));
      await Future<void>.delayed(const Duration(seconds: 3));
      await subscription.cancel();
      final output = buffer.toString();
      if (output.contains('shell-pty-ok')) {
        // ignore: avoid_print
        print('SHELL PTY OK: prompt echo round-trip received');
      } else {
        // ignore: avoid_print
        print('SHELL PTY FAIL, collected tail:\n$output');
        exitCode = 1;
      }
      session.close();
      return;
    }

    final whoami = utf8.decode(await client.run('whoami')).trim();
    final uname = utf8.decode(await client.run('uname -a')).trim();
    final uptime = utf8.decode(await client.run('uptime')).trim();
    // ignore: avoid_print
    print('AUTH OK: whoami=$whoami');
    // ignore: avoid_print
    print(uname);
    // ignore: avoid_print
    print(uptime);
    // ignore: avoid_print
    print('SMOKE PASS');
  } on SSHAuthFailError catch (error) {
    // ignore: avoid_print
    print('SMOKE FAIL: auth rejected — ${error.message}');
    exitCode = 1;
  } finally {
    client.close();
  }
}

/// SFTP 冒烟：用 App 的 SFTP 适配器跑一遍
/// 「家目录 → 建目录 → 上传 → 回读 → 改名 → 删除」，结束时清理现场。
Future<void> smokeSftp({
  required String host,
  required int port,
  required String username,
  String? password,
  String? identityPath,
  String? passphrase,
}) async {
  final identities = <SSHIdentity>[
    if (identityPath != null)
      ...SSHKeyPair.fromPem(File(identityPath).readAsStringSync(), passphrase),
  ];

  final scratch = '.no_shell_smoke_${DateTime.now().millisecondsSinceEpoch}';
  var scratchPath = '';
  SftpFileSystem? fileSystem;
  SSHClient? client;
  try {
    final socket = await SSHSocket.connect(
      host,
      port,
      timeout: const Duration(seconds: 10),
    );
    client = SSHClient(
      socket,
      username: username,
      identities: identities,
      onPasswordRequest: () => password,
      onUserInfoRequest: (request) {
        if (password == null) return null;
        return List.filled(request.prompts.length, password);
      },
      handshakeTimeout: const Duration(seconds: 10),
    );
    final sftp = await client.sftp();
    // 与 App 一致：显式等版本握手，服务端没有 sftp 子系统时在这里就会失败。
    await sftp.handshake;
    fileSystem = DartSsh2SftpFileSystem(sftp);
    final fs = fileSystem;

    final home = await fs.homeDirectory();
    // ignore: avoid_print
    print('SFTP OK: home=$home');

    final listing = await fs.list(home);
    // ignore: avoid_print
    print(
      'SFTP list OK: ${listing.length} entries, first: '
      '${listing.take(5).map((entry) => entry.name).join(', ')}',
    );

    scratchPath = sftpJoin(home, scratch);
    await fs.createDirectory(scratchPath);
    final created = (await fs.list(home))
        .any((entry) => entry.path == scratchPath && entry.isDirectory);
    if (!created) {
      throw StateError('created directory missing from listing');
    }

    const payload = 'hello sftp\n';
    final file = sftpJoin(scratchPath, 'upload.txt');
    var reported = 0;
    await fs.write(
      file,
      Stream.value(utf8.encode(payload)),
      onProgress: (bytes) => reported = bytes,
    );
    final uploaded = (await fs.list(scratchPath)).single;
    if (uploaded.size != payload.length || reported != payload.length) {
      throw StateError(
        'uploaded size mismatch: size=${uploaded.size} progress=$reported',
      );
    }

    final readBack = StringBuffer();
    await for (final chunk in fs.read(file)) {
      readBack.write(utf8.decode(chunk));
    }
    if (readBack.toString() != payload) {
      throw StateError('read back mismatch: $readBack');
    }
    // ignore: avoid_print
    print('SFTP round-trip OK: write + read ${payload.length} bytes');

    final renamed = sftpJoin(scratchPath, 'renamed.txt');
    await fs.rename(file, renamed);
    await fs.removeFile(renamed);
    await fs.removeDirectory(scratchPath);
    scratchPath = '';
    // ignore: avoid_print
    print('SFTP cleanup OK: rename + remove');
    // ignore: avoid_print
    print('SMOKE PASS (sftp)');
  } on Object catch (error) {
    // ignore: avoid_print
    print('SMOKE FAIL (sftp): $error');
    exitCode = 1;
  } finally {
    // 失败时也尽量把临时目录收拾干净，不给目标主机留残留。
    final fs = fileSystem;
    if (fs != null && scratchPath.isNotEmpty) {
      try {
        for (final entry in await fs.list(scratchPath)) {
          await fs.removeFile(entry.path);
        }
        await fs.removeDirectory(scratchPath);
      } on Object {
        // 清理失败只影响现场整洁，不影响结论。
      }
    }
    fs?.dispose();
    client?.close();
  }
}
