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

HostKeyRecord _rec(String fingerprint) =>
    HostKeyRecord(fingerprint: fingerprint);

/// 取出该主机已记录的全部指纹。
List<HostKeyRecord> _recordsOf(FakeHostKeyStore store, String host, int port) =>
    store.records(host, port);

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
      expect(_recordsOf(store, 'h1', 22), [_rec('SHA256:k1')]);
    });

    test('同指纹放行且不改写记录', () async {
      final store = FakeHostKeyStore();
      await store.save('h1', 22, _rec('SHA256:k1'));
      final decision = await verifyHostKey(
        store,
        host: 'h1',
        port: 22,
        keyType: 'ssh-ed25519',
        fingerprint: 'SHA256:k1',
      );
      expect(decision, HostKeyDecision.trusted);
      expect(_recordsOf(store, 'h1', 22), [_rec('SHA256:k1')]);
    });

    test('指纹不一致拒绝，且保留旧记录待用户显式清除', () async {
      final store = FakeHostKeyStore();
      await store.save('h1', 22, _rec('SHA256:k1'));
      final decision = await verifyHostKey(
        store,
        host: 'h1',
        port: 22,
        keyType: 'ssh-ed25519',
        fingerprint: 'SHA256:evil',
      );
      expect(decision, HostKeyDecision.mismatch);
      expect(_recordsOf(store, 'h1', 22), [_rec('SHA256:k1')]);
    });

    test('同一把密钥换算法名仍放行（记录里不含算法名）', () async {
      // dartssh2 的指纹只哈希密钥体、不含算法名，所以同一把密钥以不同
      // 算法名出示时指纹相同。服务器同时提供 ed25519 与 rsa、或客户端
      // 升级后改变了算法偏好，都会走到这里——这不是中间人，不能误报。
      final store = FakeHostKeyStore();
      await store.save('h1', 22, _rec('SHA256:k1'));
      final decision = await verifyHostKey(
        store,
        host: 'h1',
        port: 22,
        keyType: 'rsa-sha2-512',
        fingerprint: 'SHA256:k1',
      );
      expect(decision, HostKeyDecision.trusted);
      // 指纹没变就不必再记一条。
      expect(_recordsOf(store, 'h1', 22), [_rec('SHA256:k1')]);
    });

    test('服务器换了一把新密钥仍然拒绝，且不改写记录', () async {
      // 新指纹必须先由用户显式确认（清除记录）才会被信任；
      // 多条记录不等于放宽判据。
      final store = FakeHostKeyStore();
      await store.save('h1', 22, _rec('SHA256:k1'));
      final decision = await verifyHostKey(
        store,
        host: 'h1',
        port: 22,
        keyType: 'ssh-ed25519',
        fingerprint: 'SHA256:brand-new-key',
      );
      expect(decision, HostKeyDecision.mismatch);
      expect(_recordsOf(store, 'h1', 22), [_rec('SHA256:k1')]);
    });

    test('已记多条时命中任意一条即放行', () async {
      final store = FakeHostKeyStore();
      await store.save('h1', 22, _rec('SHA256:k1'));
      await store.save('h1', 22, _rec('SHA256:k2'));
      final decision = await verifyHostKey(
        store,
        host: 'h1',
        port: 22,
        keyType: 'rsa-sha2-512',
        fingerprint: 'SHA256:k2',
      );
      expect(decision, HostKeyDecision.trusted);
    });

    test('指纹存储读不出来时拒绝连接，且不改写记录', () async {
      // 安全底线：若按「从未记录」放行，任何能让读取失败的人
      // 都能让客户端接受自己的密钥。
      final store = FakeHostKeyStore()..unavailable = true;
      final decision = await verifyHostKey(
        store,
        host: 'h1',
        port: 22,
        keyType: 'ssh-ed25519',
        fingerprint: 'SHA256:evil',
      );
      expect(decision, HostKeyDecision.unavailable);
      expect(_recordsOf(store, 'h1', 22), isEmpty);
    });

    test('存储层直接抛异常时同样拒绝，不冒泡给调用方', () async {
      final store = FakeHostKeyStore()
        ..loadError = StateError('keyring locked');
      final decision = await verifyHostKey(
        store,
        host: 'h1',
        port: 22,
        keyType: 'ssh-ed25519',
        fingerprint: 'SHA256:evil',
      );
      expect(decision, HostKeyDecision.unavailable);
    });

    test('同主机不同端口互不影响', () async {
      final store = FakeHostKeyStore();
      await store.save('h1', 22, _rec('SHA256:k1'));
      final decision = await verifyHostKey(
        store,
        host: 'h1',
        port: 2222,
        keyType: 'ssh-ed25519',
        fingerprint: 'SHA256:k2',
      );
      expect(decision, HostKeyDecision.firstUse);
      expect(_recordsOf(store, 'h1', 22), [_rec('SHA256:k1')]);
      expect(_recordsOf(store, 'h1', 2222), [_rec('SHA256:k2')]);
    });
  });

  group('SharedPreferencesHostKeyStore', () {
    test('save / load / delete 往返：一台主机可存多条，同指纹去重', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPreferencesHostKeyStore();
      expect(await store.load('h1', 22), isA<HostKeysNeverRecorded>());

      // 服务器有多把主机密钥时，协商到哪一把就记哪一把。
      await store.save('h1', 22, _rec('SHA256:k1'));
      await store.save('h1', 22, _rec('SHA256:k2'));
      // 重复写同一条不产生冗余。
      await store.save('h1', 22, _rec('SHA256:k1'));

      final loaded = await store.load('h1', 22);
      expect((loaded as HostKeysLoaded).records, [
        _rec('SHA256:k1'),
        _rec('SHA256:k2'),
      ]);

      await store.delete('h1', 22);
      expect(await store.load('h1', 22), isA<HostKeysNeverRecorded>());
    });

    test('不是当前格式的内容一律判为读不出来（开发阶段不背旧格式）', () async {
      SharedPreferences.setMockInitialValues({
        'ssh_host_keys_v1/h1:22': 'ssh-ed25519:SHA256:k1',
      });
      final store = SharedPreferencesHostKeyStore();
      expect(await store.load('h1', 22), isA<HostKeysUnavailable>());
    });

    test('记录内容解不出来时报「读不出来」，不冒充从未记录', () async {
      SharedPreferences.setMockInitialValues({
        'ssh_host_keys_v1/h1:22': '[{"nope":1}]',
      });
      final store = SharedPreferencesHostKeyStore();
      expect(await store.load('h1', 22), isA<HostKeysUnavailable>());
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
      await store.save(_server.host, _server.port, _rec('SHA256:old'));
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
      expect(_recordsOf(store, _server.host, _server.port), isEmpty);
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
