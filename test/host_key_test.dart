import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:no_shell/l10n/generated/app_localizations.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/settings.dart';
import 'package:no_shell/ssh/host_key_store.dart';
import 'package:no_shell/ssh/sftp.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';
import 'package:no_shell/ssh/ssh_transport.dart';
import 'package:no_shell/ssh/terminal_session.dart';
import 'package:no_shell/ssh/terminal_view.dart';
import 'package:no_shell/theme.dart';
import 'package:xterm/core.dart';

import 'support/host_key_store_fake.dart';

const _server = SshServer(
  id: 'srv-hostkey',
  group: '测试',
  name: 'hostkey-test',
  host: '10.0.0.9',
  username: 'root',
);

/// attach 即抛密钥变更异常的假传输。
final class HostKeyChangedTransport implements SshTransport {
  @override
  Future<void> attach(
    Terminal terminal, {
    required void Function() onConnected,
    required void Function() onClosed,
  }) async {
    throw const HostKeyChangedException(
      host: '10.0.0.9',
      port: 22,
      keyType: 'ssh-ed25519',
      fingerprint: 'SHA256:aaaaaaaa',
    );
  }

  @override
  Future<SftpFileSystem> openSftp() async {
    throw UnimplementedError();
  }

  @override
  void dispose() {}
}

/// attach 即抛普通异常的假传输，对照「非密钥类失败」。
final class BrokenTransport implements SshTransport {
  @override
  Future<void> attach(
    Terminal terminal, {
    required void Function() onConnected,
    required void Function() onClosed,
  }) async {
    throw Exception('boom');
  }

  @override
  Future<SftpFileSystem> openSftp() async {
    throw UnimplementedError();
  }

  @override
  void dispose() {}
}

Widget host(Widget child) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: AppTheme.light(),
  // 终端视图依赖全局终端样式作用域（正式入口在 MaterialApp builder 中注入）。
  home: TerminalStyleScope(
    notifier: ValueNotifier(const TerminalStylePrefs()),
    child: Scaffold(body: child),
  ),
);

void main() {
  group('TOFU 决策', () {
    test('首次连接记录指纹并放行', () async {
      final store = FakeHostKeyStore();
      final decision = await verifyHostKey(
        store,
        host: 'h1',
        port: 22,
        keyType: 'ssh-ed25519',
        fingerprint: 'SHA256:k1',
      );
      expect(decision, HostKeyDecision.firstUse);
      expect(store.peek('h1', 22), 'ssh-ed25519:SHA256:k1');
    });

    test('同指纹放行且不改写记录', () async {
      final store = FakeHostKeyStore();
      await store.save('h1', 22, 'ssh-ed25519:SHA256:k1');
      final decision = await verifyHostKey(
        store,
        host: 'h1',
        port: 22,
        keyType: 'ssh-ed25519',
        fingerprint: 'SHA256:k1',
      );
      expect(decision, HostKeyDecision.trusted);
      expect(store.peek('h1', 22), 'ssh-ed25519:SHA256:k1');
    });

    test('指纹不一致拒绝，且保留旧记录待用户显式清除', () async {
      final store = FakeHostKeyStore();
      await store.save('h1', 22, 'ssh-ed25519:SHA256:k1');
      final decision = await verifyHostKey(
        store,
        host: 'h1',
        port: 22,
        keyType: 'ssh-ed25519',
        fingerprint: 'SHA256:evil',
      );
      expect(decision, HostKeyDecision.mismatch);
      expect(store.peek('h1', 22), 'ssh-ed25519:SHA256:k1');
    });

    test('密钥类型变化同样视为不一致', () async {
      final store = FakeHostKeyStore();
      await store.save('h1', 22, 'ssh-ed25519:SHA256:k1');
      final decision = await verifyHostKey(
        store,
        host: 'h1',
        port: 22,
        keyType: 'rsa-sha2-512',
        fingerprint: 'SHA256:k1',
      );
      expect(decision, HostKeyDecision.mismatch);
    });

    test('同主机不同端口互不影响', () async {
      final store = FakeHostKeyStore();
      await store.save('h1', 22, 'ssh-ed25519:SHA256:k1');
      final decision = await verifyHostKey(
        store,
        host: 'h1',
        port: 2222,
        keyType: 'ssh-ed25519',
        fingerprint: 'SHA256:k2',
      );
      expect(decision, HostKeyDecision.firstUse);
      expect(store.peek('h1', 22), 'ssh-ed25519:SHA256:k1');
      expect(store.peek('h1', 2222), 'ssh-ed25519:SHA256:k2');
    });
  });

  group('SharedPreferencesHostKeyStore', () {
    test('save / load / delete 往返', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPreferencesHostKeyStore();
      expect(await store.load('h1', 22), isNull);
      await store.save('h1', 22, 'ssh-ed25519:SHA256:k1');
      expect(await store.load('h1', 22), 'ssh-ed25519:SHA256:k1');
      await store.delete('h1', 22);
      expect(await store.load('h1', 22), isNull);
    });

    test('读失败按未记录处理，不抛异常', () async {
      SharedPreferences.setMockInitialValues({
        'ssh_host_keys_v1/h1:22': 'ssh-ed25519:SHA256:k1',
      });
      final store = SharedPreferencesHostKeyStore();
      expect(await store.load('h1', 22), 'ssh-ed25519:SHA256:k1');
    });
  });

  group('会话层密钥变更归类与处置入口', () {
    test('HostKeyChangedException 归类为 hostKey', () async {
      final session = TerminalSession(
        server: _server,
        credentials: const SshCredentials(password: 'pw'),
        transport: HostKeyChangedTransport(),
        hostKeys: FakeHostKeyStore(),
      );
      addTearDown(session.dispose);
      await session.start();
      expect(session.phase, TerminalPhase.failed);
      expect(session.errorKind, TerminalErrorKind.hostKey);
    });

    testWidgets('密钥变更失败时展示处置按钮，点击清除记录并触发重连', (tester) async {
      final store = FakeHostKeyStore();
      await store.save(_server.host, _server.port, 'ssh-ed25519:SHA256:old');
      final session = TerminalSession(
        server: _server,
        credentials: const SshCredentials(password: 'pw'),
        transport: HostKeyChangedTransport(),
        hostKeys: store,
      );
      addTearDown(session.dispose);
      await session.start();
      var retried = 0;
      await tester.pumpWidget(
        host(SshTerminalView(session: session, onRetry: () => retried++)),
      );
      await tester.pump();

      expect(find.text('清除记录的指纹并重连'), findsOneWidget);

      await tester.tap(find.text('清除记录的指纹并重连'));
      await tester.pumpAndSettle();
      expect(store.peek(_server.host, _server.port), isNull);
      expect(retried, 1);
    });

    testWidgets('普通失败不展示密钥处置按钮', (tester) async {
      final session = TerminalSession(
        server: _server,
        credentials: const SshCredentials(password: 'pw'),
        transport: BrokenTransport(),
        hostKeys: FakeHostKeyStore(),
      );
      addTearDown(session.dispose);
      await session.start();
      var retried = 0;
      await tester.pumpWidget(
        host(SshTerminalView(session: session, onRetry: () => retried++)),
      );
      await tester.pump();

      expect(session.errorKind, TerminalErrorKind.other);
      expect(find.text('清除记录的指纹并重连'), findsNothing);
      expect(find.text('重连'), findsOneWidget);
    });
  });
}
