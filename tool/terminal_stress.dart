// 开发用极限终端压测脚本：对真实主机跑一轮限量的终端 / 传输压力测试并输出报告。
// 用法：
//   dart run tool/terminal_stress.dart <host> <port> <user> --password <密码> [--scale <倍率>]
// 可选 --scale 按比例缩放各测试的数据量（默认 1，范围 0.2–2）。
// 凭据只经命令行传入，不写入本文件；所有远端命令均有数据上限，临时文件用完即删。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dartssh2/dartssh2.dart';
// 只引 core（终端模拟核心，纯 Dart）：xterm.dart 顶层会导出 UI 层，
// 牵进 dart:ui，`dart run` 下无法编译（与 smoke_ssh 同样的取舍）。
import 'package:xterm/core.dart';

const _mb = 1024 * 1024;

void log(String line) {
  // ignore: avoid_print
  print(line);
}

String _mbps(int bytes, Duration elapsed) {
  if (elapsed.inMicroseconds == 0) return 'n/a';
  final mbs = bytes / _mb / (elapsed.inMicroseconds / 1e6);
  return mbs.toStringAsFixed(1);
}

String _mbOf(int bytes) => '${(bytes / _mb).toStringAsFixed(1)} MB';

String _rss() => '${(ProcessInfo.currentRss / _mb).toStringAsFixed(0)} MB';

const _utf8 = Utf8Decoder(allowMalformed: true);

/// 把字节块序列灌进终端模拟器，返回耗时（纯本地，隔离网络）。
Duration _feedSync(Terminal terminal, List<List<int>> chunks) {
  final sw = Stopwatch()..start();
  for (final chunk in chunks) {
    terminal.write(_utf8.convert(chunk));
  }
  return sw.elapsed;
}

/// 对本地字节串取 md5（走系统命令，避免引入依赖）。
String _localMd5(List<int> bytes) {
  final dir = Directory.systemTemp.createTempSync('noshell_stress');
  final payload = File('${dir.path}/payload');
  try {
    payload.writeAsBytesSync(bytes, flush: true);
    final result = Process.runSync('md5', ['-q', payload.path]);
    return (result.stdout as String).trim();
  } finally {
    dir.deleteSync(recursive: true);
  }
}

Future<String> _runText(SSHClient client, String command) async {
  final out = await client.run(command).timeout(const Duration(seconds: 60));
  return utf8.decode(out, allowMalformed: true).trim();
}

final class _Case {
  _Case(this.name);
  final String name;
  final notes = <String>[];
}

Future<void> main(List<String> args) async {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  String? option(String name) {
    final index = args.indexOf(name);
    if (index == -1 || index + 1 >= args.length) return null;
    final value = args[index + 1];
    return value.startsWith('--') ? null : value;
  }

  if (positional.length < 3 || option('--password') == null) {
    stderr.writeln(
      '用法: dart run tool/terminal_stress.dart <host> <port> <user> '
      '--password <密码> [--scale <倍率>]',
    );
    exitCode = 64;
    return;
  }
  final host = positional[0];
  final port = int.parse(positional[1]);
  final username = positional[2];
  final password = option('--password')!;
  final scale = math.min(
    2.0,
    math.max(0.2, double.tryParse(option('--scale') ?? '1') ?? 1),
  );
  int mbOf(int base) => math.max(1, (base * scale).round());

  final cases = <_Case>[];
  _Case newCase(String name) => _Case(name)..also((c) => cases.add(c));

  log('连接 $host:$port (user=$username, scale=$scale)…');
  final socket = await SSHSocket.connect(
    host,
    port,
    timeout: const Duration(seconds: 15),
  );
  final client = SSHClient(
    socket,
    username: username,
    onPasswordRequest: () => password,
    handshakeTimeout: const Duration(seconds: 15),
  );
  final remotePath = '/tmp/.noshell_stress.bin';

  try {
    // ── 环境 ────────────────────────────────────────────────────────
    final env = newCase('环境与基线');
    env.notes
      ..add('认证 OK: whoami=${await _runText(client, 'whoami')}')
      ..add(
        '服务端: ${await _runText(client, 'uname -sr')} / '
        '${await _runText(client, 'nproc')} 核 / '
        '负载 ${await _runText(client, "cut -d' ' -f1-3 /proc/loadavg")}',
      );

    final rtts = <int>[];
    for (var i = 0; i < 5; i++) {
      final sw = Stopwatch()..start();
      await client.run('true');
      rtts.add(sw.elapsed.inMilliseconds);
    }
    rtts.sort();
    env.notes
      ..add('exec 往返延迟: 中位 ${rtts[rtts.length ~/ 2]} ms / 最大 ${rtts.last} ms')
      ..add('本机起点 RSS: ${_rss()}');

    // ── T1 exec 通道吞吐 + 通道完整性 ───────────────────────────────
    final t1 = newCase('T1 exec 通道吞吐 + 完整性');
    {
      final sizeMb = mbOf(8);
      final bytes = sizeMb * _mb;
      await _runText(
        client,
        'head -c $bytes /dev/urandom | base64 > $remotePath',
      );
      final remoteMd5 = await _runText(
        client,
        'md5sum $remotePath | cut -d" " -f1',
      );
      final expected = int.parse(
        await _runText(client, 'stat -c %s $remotePath'),
      );
      final collected = <List<int>>[];
      var total = 0;
      final sw = Stopwatch()..start();
      final session = await client.execute('cat $remotePath');
      await for (final chunk in session.stdout) {
        total += chunk.length;
        collected.add(chunk);
      }
      session.exitCode;
      final elapsed = sw.elapsed;
      final flat = <int>[];
      for (final chunk in collected) {
        flat.addAll(chunk);
      }
      final localMd5 = _localMd5(flat);
      t1.notes
        ..add('数据: $sizeMb MB 随机数的 base64 (${_mbOf(total)} 传输)')
        ..add(
          '吞吐: ${_mbps(total, elapsed)} MB/s (${elapsed.inMilliseconds} ms)',
        )
        ..add(
          '完整性: 字节数 ${total == expected ? "一致" : "不符($total/$expected)"}, '
          'md5 ${localMd5 == remoteMd5 ? "一致" : "不符"}',
        );
    }

    // ── T2 PTY 端到端文本洪流 + 模拟器回放 ──────────────────────────
    final t2 = newCase('T2 PTY 端到端洪流 + 模拟器回放');
    {
      // 复用 T1 的远端文件。
      final expected = int.parse(
        await _runText(client, 'stat -c %s $remotePath'),
      );
      final pty = await client.shell(
        pty: const SSHPtyConfig(type: 'xterm-256color', width: 200, height: 50),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      // 单一持久订阅 + 可换回调：单订阅流只能 listen 一次，drain 二次监听会抛。
      void Function(List<int>)? onData;
      final outSub = pty.stdout.listen((chunk) => onData?.call(chunk));
      // 关提示符与回显噪音，让输出≈纯文件内容。
      final ready = Completer<void>();
      onData = (chunk) {
        if (!ready.isCompleted && _utf8.convert(chunk).contains('READY')) {
          ready.complete();
        }
      };
      pty.stdin.add(
        utf8.encode(
          'stty -echo 2>/dev/null; export PS1= PROMPT_COMMAND=; echo READY\n',
        ),
      );
      await ready.future.timeout(const Duration(seconds: 10));
      onData = null;

      final chunks = <List<int>>[];
      var total = 0;
      final done = Completer<void>();
      onData = (chunk) {
        total += chunk.length;
        chunks.add(chunk);
        if (total >= expected && !done.isCompleted) done.complete();
      };
      final sw = Stopwatch()..start();
      pty.stdin.add(utf8.encode('cat $remotePath\n'));
      await done.future.timeout(const Duration(seconds: 180));
      final elapsed = sw.elapsed;
      // 终止未尽输出并收尾。
      onData = null;
      pty.stdin.add(utf8.encode('\x03'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await outSub.cancel();
      pty.close();

      final rssBefore = ProcessInfo.currentRss;
      final terminal = Terminal(maxLines: 50000);
      final replay = _feedSync(terminal, chunks);
      final rssAfter = ProcessInfo.currentRss;
      final replayBytes = chunks.fold<int>(0, (a, c) => a + c.length);
      t2.notes
        ..add(
          'PTY 200×50, stty -echo, cat ${_mbOf(expected)}: '
          '端到端 ${_mbps(total, elapsed)} MB/s (${elapsed.inMilliseconds} ms)',
        )
        ..add(
          '模拟器回放: ${_mbps(replayBytes, replay)} MB/s (${replay.inMilliseconds} ms), '
          'lines=${terminal.buffer.lines.length}',
        )
        ..add('RSS: 回放前 ${rssBefore ~/ _mb} MB → 回放后 ${rssAfter ~/ _mb} MB');
    }

    // ── T3 二进制乱码健壮性（随机字节直灌解析器）────────────────────
    final t3 = newCase('T3 二进制乱码健壮性');
    {
      final sizeMb = mbOf(2);
      final bytes = sizeMb * _mb;
      final out = await client
          .run('head -c $bytes /dev/urandom')
          .timeout(const Duration(seconds: 120));
      final terminal = Terminal(maxLines: 50000);
      var thrown = '无';
      try {
        terminal.write(_utf8.convert(out));
      } on Object catch (e) {
        thrown = '$e';
      }
      final replay = _feedSync(Terminal(maxLines: 50000), [out]);
      t3.notes
        ..add('${_mbOf(out.length)} 纯随机字节灌入解析器, 异常: $thrown')
        ..add(
          '模拟器回放: ${_mbps(out.length, replay)} MB/s (${replay.inMilliseconds} ms)',
        )
        ..add('终端存活: ${terminal.buffer.getText().isNotEmpty}');
    }

    // ── T4 CSI 转义炸弹（SGR 洪流）──────────────────────────────────
    final t4 = newCase('T4 CSI 转义炸弹 (SGR 洪流)');
    {
      final sizeMb = mbOf(8);
      final bytes = sizeMb * _mb;
      final out = await client
          .run("yes \"\$(printf '\\033[31mabc\\033[0m')\" | head -c $bytes")
          .timeout(const Duration(seconds: 120));
      final terminal = Terminal(maxLines: 50000);
      final replay = _feedSync(terminal, [out]);
      t4.notes
        ..add('数据: $sizeMb MB 的 "ESC[31m abc ESC[0m\\n" 循环')
        ..add(
          '模拟器回放: ${_mbps(out.length, replay)} MB/s (${replay.inMilliseconds} ms)',
        )
        ..add('终端存活: ${terminal.buffer.getText().isNotEmpty}');
    }

    // ── T5 OSC 标题炸弹 ─────────────────────────────────────────────
    final t5 = newCase('T5 OSC 标题炸弹');
    {
      final sizeMb = mbOf(4);
      final bytes = sizeMb * _mb;
      final out = await client
          .run(
            "yes \"\$(printf '\\033]0;osc-title-bomb\\007')\" | head -c $bytes",
          )
          .timeout(const Duration(seconds: 120));
      final terminal = Terminal(maxLines: 50000);
      final replay = _feedSync(terminal, [out]);
      t5.notes
        ..add('数据: $sizeMb MB 的 "ESC]0;title BEL\\n" 循环')
        ..add(
          '模拟器回放: ${_mbps(out.length, replay)} MB/s (${replay.inMilliseconds} ms)',
        )
        ..add('终端存活: ${terminal.buffer.getText().isNotEmpty}');
    }

    // ── T6 CJK 宽字符洪流 ───────────────────────────────────────────
    final t6 = newCase('T6 CJK 宽字符洪流');
    {
      final sizeMb = mbOf(4);
      final bytes = sizeMb * _mb;
      final out = await client
          .run("yes '终端宽字符压测中文字符串场景终端宽字符压测' | head -c $bytes")
          .timeout(const Duration(seconds: 120));
      final terminal = Terminal(maxLines: 50000);
      final replay = _feedSync(terminal, [out]);
      final text = terminal.buffer.getText();
      t6.notes
        ..add('数据: $sizeMb MB UTF-8 中文')
        ..add(
          '模拟器回放: ${_mbps(out.length, replay)} MB/s (${replay.inMilliseconds} ms)',
        )
        ..add(
          '内容抽查: 缓冲区含原文 = ${text.contains('终端宽字符压测')}, '
          'lines=${terminal.buffer.lines.length}',
        );
    }

    // ── T7 全屏重绘帧率（模拟 htop / vim）───────────────────────────
    final t7 = newCase('T7 全屏重绘帧率');
    {
      final frames = math.max(200, (1000 * scale).round());
      final script =
          '''
for i in \$(seq 1 $frames); do
  printf '\\033[2J\\033[H'
  for j in \$(seq 1 50); do printf 'frame %06d line %02d payload %s\\n' \$i \$j \$RANDOM; done
done
''';
      final out = await client
          .run(script)
          .timeout(const Duration(seconds: 180));
      final terminal = Terminal(maxLines: 50000);
      final replay = _feedSync(terminal, [out]);
      final replayFps = frames * 1000 ~/ math.max(1, replay.inMilliseconds);
      t7.notes
        ..add('$frames 帧 × 50 行全屏重绘 (${_mbOf(out.length)})')
        ..add(
          '模拟器回放: $replayFps fps (${replay.inMilliseconds} ms, '
          '${_mbps(out.length, replay)} MB/s)',
        )
        ..add(
          '末帧抽查: ${terminal.buffer.getText().contains('frame ${frames.toString().padLeft(6, '0')}') ? "命中" : "未见"}',
        );
    }

    // ── T8 按键回显延迟（PTY 交互, 20 次取样）───────────────────────
    final t8 = newCase('T8 按键回显延迟 (PTY)');
    {
      const samples = 20;
      final echoSession = await client.shell(
        pty: const SSHPtyConfig(type: 'xterm-256color', width: 80, height: 24),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      // 同 T2：单一持久订阅，避免单订阅流二次 listen。
      void Function(List<int>)? onData;
      final outSub = echoSession.stdout.listen((c) => onData?.call(c));
      // raw 模式：规范模式下无换行的单键会滞留行缓冲，cat 收不到也回不了。
      echoSession.stdin.add(utf8.encode('stty raw -echo 2>/dev/null; cat\n'));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      onData = null;
      final latencies = <int>[];
      var timeouts = 0;
      for (var i = 0; i < samples; i++) {
        final echoed = Completer<void>();
        onData = (chunk) {
          if (!echoed.isCompleted && chunk.contains(0x7a)) {
            echoed.complete();
          }
        };
        final sw = Stopwatch()..start();
        echoSession.stdin.add(utf8.encode('z'));
        try {
          await echoed.future.timeout(const Duration(seconds: 5));
          latencies.add(sw.elapsed.inMilliseconds);
        } on TimeoutException {
          timeouts++;
        }
        onData = null;
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
      echoSession.stdin.add(utf8.encode('\x04'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await outSub.cancel();
      echoSession.close();
      latencies.sort();
      if (latencies.isEmpty) {
        t8.notes.add('$samples 次全部超时');
      } else {
        final p95 = latencies[(latencies.length * 0.95).ceil() - 1];
        t8.notes
          ..add(
            '$samples 次 z 键 → 回显: p50 ${latencies[latencies.length ~/ 2]} ms / '
            'p95 $p95 ms / 最大 ${latencies.last} ms / 超时 $timeouts 次',
          )
          ..add('对照 exec 往返中位 ${rtts[rtts.length ~/ 2]} ms');
      }
    }

    // ── T9 回滚上限 + resize reflow（本地）──────────────────────────
    final t9 = newCase('T9 回滚上限 + resize reflow (本地)');
    {
      final terminal = Terminal(maxLines: 50000);
      // 60 万行（上限的 12 倍），行内容 80 列字母。
      final line = List<int>.generate(80, (i) => 0x61 + (i % 26));
      line.add(10);
      final sw = Stopwatch()..start();
      for (var i = 0; i < 600000; i++) {
        terminal.write(_utf8.convert(line));
      }
      final feedTime = sw.elapsed;
      final cappedOk =
          terminal.buffer.lines.length <= 50000 + terminal.viewHeight;
      final textLen = terminal.buffer.getText().length;

      final swResize = Stopwatch()..start();
      for (var i = 0; i < 40; i++) {
        terminal.resize(i.isEven ? 80 : 200, i.isEven ? 24 : 50);
      }
      final resizeTime = swResize.elapsed;
      t9.notes
        ..add(
          '灌入 60 万行 × 81 字节 (${_mbOf(600000 * 81)}): ${feedTime.inMilliseconds} ms, '
          '${_mbps(600000 * 81, feedTime)} MB/s',
        )
        ..add('行数封顶生效: $cappedOk (实际 lines=${terminal.buffer.lines.length})')
        ..add('getText 快照 $textLen 字符, RSS ${_rss()}')
        ..add(
          '40 次 80×24↔200×50 reflow: ${resizeTime.inMilliseconds} ms '
          '(均摊 ${resizeTime.inMilliseconds ~/ 40} ms/次)',
        );
    }
  } on Object catch (error) {
    log('压测中止: $error');
    exitCode = 1;
  } finally {
    try {
      await _runText(client, 'rm -f $remotePath');
    } on Object {
      // 清理失败不影响报告。
    }
    client.close();
  }

  log('');
  log('================ 终端压力测试报告 ================');
  for (final c in cases) {
    log('');
    log('◆ ${c.name}');
    for (final note in c.notes) {
      log('  $note');
    }
  }
  log('');
  log('==================================================');
}

extension<T> on T {
  T also(void Function(T) block) {
    block(this);
    return this;
  }
}
