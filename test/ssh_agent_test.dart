/// SSH agent 客户端的单元测试：协议编解码、请求配对、身份映射与
/// 平台连接路径。协议交互用注入的假通道驱动，另有一条真实 Unix 套接字
/// 的全链路（`flutter test` 跑在宿主机上，dart:io 可用）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/ssh/ssh_agent.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';
import 'package:no_shell/ssh/terminal_session.dart';

import 'support/transport_fakes.dart';

/// 构造 wire 格式公钥 blob：`string 算法名, ...`（后续字段随算法而异，
/// 这里只造测试够用的最小结构）。
Uint8List blobOf(String type, {List<List<int>> fields = const []}) {
  final builder = BytesBuilder()..add(_wstr(utf8.encode(type)));
  for (final field in fields) {
    builder.add(_wstr(field));
  }
  return builder.toBytes();
}

Uint8List _wstr(List<int> value) {
  final header = ByteData(4)..setUint32(0, value.length);
  return Uint8List.fromList([...header.buffer.asUint8List(), ...value]);
}

Uint8List _payload(List<int> bytes) => Uint8List.fromList(bytes);

Uint8List _namedSignature(String name, List<int> raw) {
  final builder = BytesBuilder()
    ..add(_wstr(utf8.encode(name)))
    ..add(_wstr(raw));
  return builder.toBytes();
}

List<int> _replyIdentities(List<(Uint8List, String)> keys) {
  final out = BytesBuilder()..addByte(SshAgentProtocol.identitiesAnswer);
  final count = ByteData(4)..setUint32(0, keys.length);
  out.add(count.buffer.asUint8List());
  for (final (blob, comment) in keys) {
    out.add(_wstr(blob));
    out.add(_wstr(utf8.encode(comment)));
  }
  return out.toBytes();
}

List<int> _replySignature(List<int> signature) {
  final out = BytesBuilder()
    ..addByte(SshAgentProtocol.signResponse)
    ..add(_wstr(signature));
  return out.toBytes();
}

List<int> _frame(List<int> payloadBytes) {
  final header = ByteData(4)..setUint32(0, payloadBytes.length);
  return [...header.buffer.asUint8List(), ...payloadBytes];
}

/// 脚本化的假 agent：收到一帧就回调测试给的应答函数，同时把发出去的
/// 帧头剥掉、载荷记下来供断言。
final class ScriptedAgent implements SshAgentChannel {
  ScriptedAgent(this._onRequest);

  final Future<List<int>> Function(List<int> payload) _onRequest;
  final _controller = StreamController<Uint8List>();

  /// 客户端发出的全部请求载荷（已剥帧头）。
  final List<List<int>> requests = [];

  /// 是否把下一个应答拆成两段喂回（测帧重组）。
  bool splitResponse = false;

  Uint8List _buffer = Uint8List(0);

  @override
  Stream<Uint8List> get stream => _controller.stream;

  @override
  void add(List<int> data) {
    _buffer = Uint8List.fromList([..._buffer, ...data]);
    while (_buffer.length >= 4) {
      final length = ByteData.sublistView(_buffer, 0, 4).getUint32(0);
      if (_buffer.length < 4 + length) break;
      final request = Uint8List.sublistView(_buffer, 4, 4 + length);
      _buffer = Uint8List.sublistView(_buffer, 4 + length);
      requests.add(List.of(request));
      unawaited(_respond(request));
    }
  }

  Future<void> _respond(List<int> request) async {
    final response = await _onRequest(request);
    if (splitResponse) {
      final framed = _frame(response);
      final half = framed.length ~/ 2;
      _controller.add(Uint8List.fromList(framed.sublist(0, half)));
      _controller.add(Uint8List.fromList(framed.sublist(half)));
      splitResponse = false;
      return;
    }
    _controller.add(Uint8List.fromList(_frame(response)));
  }

  @override
  Future<void> close() async {
    if (!_controller.isClosed) await _controller.close();
  }
}

void main() {
  final ed25519Blob = blobOf('ssh-ed25519', fields: [List.filled(32, 7)]);
  final rsaBlob = blobOf(
    'ssh-rsa',
    fields: [
      [1, 0, 1],
      List.filled(64, 3),
    ],
  );

  test('listIdentities：解析多把密钥与注释', () async {
    final agent = ScriptedAgent((request) async {
      expect(request.first, SshAgentProtocol.requestIdentities);
      return _replyIdentities([(ed25519Blob, 'dev@laptop'), (rsaBlob, '')]);
    });
    final client = createSshAgentClient(agent);
    addTearDown(client.close);

    final keys = await client.listIdentities();
    expect(keys, hasLength(2));
    expect(keys[0].type, 'ssh-ed25519');
    expect(keys[0].comment, 'dev@laptop');
    expect(keys[0].blob, ed25519Blob);
    expect(keys[1].type, 'ssh-rsa');
    expect(keys[1].comment, isEmpty);
  });

  test('sign：ed25519 请求不带标志位，签名原样返回', () async {
    const data = [9, 8, 7];
    final signature = _namedSignature('ssh-ed25519', [1, 2]);
    final agent = ScriptedAgent((request) async {
      expect(request.first, SshAgentProtocol.signRequest);
      final reader = _TestReader(request);
      reader.readUint8();
      expect(reader.readString(), ed25519Blob);
      expect(reader.readString(), data);
      expect(reader.readUint32(), 0);
      return _replySignature(signature);
    });
    final client = createSshAgentClient(agent);
    addTearDown(client.close);
    final key = SshAgentIdentity(blob: ed25519Blob);

    expect(await client.sign(key, Uint8List.fromList(data)), signature);
  });

  test('sign：ssh-rsa 自动带 rsa-sha2-256 标志', () async {
    final agent = ScriptedAgent((request) async {
      final reader = _TestReader(request);
      reader.readUint8();
      reader.readString();
      reader.readString();
      expect(reader.readUint32(), SshAgentProtocol.rsaSha2_256);
      return _replySignature(_namedSignature('rsa-sha2-256', [3]));
    });
    final client = createSshAgentClient(agent);
    addTearDown(client.close);
    final key = SshAgentIdentity(blob: rsaBlob);

    await client.sign(key, Uint8List.fromList(const [1]));
  });

  test('sign：agent 拒签抛 SshAgentFailureException', () async {
    final agent = ScriptedAgent(
      (request) async => _payload([SshAgentProtocol.failure]),
    );
    final client = createSshAgentClient(agent);
    addTearDown(client.close);

    await expectLater(
      client.sign(SshAgentIdentity(blob: ed25519Blob), Uint8List(4)),
      throwsA(isA<SshAgentFailureException>()),
    );
  });

  test('应答截断时报错而不是挂死', () async {
    final agent = ScriptedAgent(
      (request) async => _payload([SshAgentProtocol.identitiesAnswer, 0, 0]),
    );
    final client = createSshAgentClient(agent);
    addTearDown(client.close);

    await expectLater(
      client.listIdentities(),
      throwsA(
        isA<SshAgentFailureException>().having(
          (error) => error.detail,
          'detail',
          contains('truncated'),
        ),
      ),
    );
  });

  test('应答分几段到达也能拼回（帧重组）', () async {
    final agent = ScriptedAgent(
      (request) async => _replyIdentities([(ed25519Blob, 'split')]),
    )..splitResponse = true;
    final client = createSshAgentClient(agent);
    addTearDown(client.close);

    final keys = await client.listIdentities();
    expect(keys.single.comment, 'split');
  });

  test('agentIdentitiesAsSsh：RSA 对外呈现为 rsa-sha2-256，签名直通', () async {
    final signature = _namedSignature('rsa-sha2-256', [4, 5]);
    final agent = ScriptedAgent((request) async => _replySignature(signature));
    final client = createSshAgentClient(agent);
    addTearDown(client.close);

    final identities = agentIdentitiesAsSsh(client, [
      SshAgentIdentity(blob: rsaBlob, comment: 'prod@server'),
      SshAgentIdentity(blob: ed25519Blob),
    ]);
    expect(identities[0].type, 'rsa-sha2-256');
    expect(identities[0].toPublicKey().encode(), rsaBlob);
    expect(identities[0].comment, 'prod@server');
    expect(identities[0].shouldProbe, isTrue);
    expect(identities[1].type, 'ssh-ed25519');

    final signed = await identities[0].sign(Uint8List.fromList(const [6]));
    expect(signed.encode(), signature);
  });

  test('connectSshAgent：套接字不存在时报 agent 不可用', () async {
    await expectLater(
      connectSshAgent(socketPath: '/nonexistent/noshell-agent.sock'),
      throwsA(isA<SshAgentUnavailableException>()),
    );
  });

  test('真实 Unix 套接字全链路：列出密钥并签名', () async {
    // Windows 没有 Unix 套接字（InternetAddressType.unix 不支持），
    // 这条只在 macOS / Linux 上有意义；CI 与开发机都在类 Unix 上，
    // 但不加这道守卫的话在 Windows 上会直接挂。
    if (Platform.isWindows) return;

    final dir = await Directory.systemTemp.createTemp('noshell-agent-test');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/agent.sock';
    final server = await ServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    addTearDown(server.close);

    var seenSignRequest = false;
    server.listen((socket) {
      var pending = BytesBuilder();
      socket.listen((chunk) {
        pending.add(chunk);
        var bytes = pending.toBytes();
        pending = BytesBuilder();
        while (bytes.length >= 4) {
          final length = ByteData.sublistView(bytes, 0, 4).getUint32(0);
          if (bytes.length < 4 + length) break;
          bytes = Uint8List.sublistView(bytes, 4 + length);
          final reply = seenSignRequest
              ? _replySignature(
                  _namedSignature('ssh-ed25519', List.filled(64, 1)),
                )
              : _replyIdentities([(ed25519Blob, 'socket-test')]);
          seenSignRequest = true;
          socket.add(Uint8List.fromList(_frame(reply)));
        }
        // 不足一帧的尾巴留到下一个 chunk 一起解析。
        if (bytes.isNotEmpty) pending.add(bytes);
      });
    });

    final client = await connectSshAgent(socketPath: path);
    addTearDown(client.close);
    final keys = await client.listIdentities();
    expect(keys.single.type, 'ssh-ed25519');
    final signature = await client.sign(
      keys.single,
      Uint8List.fromList(const [1, 2, 3]),
    );
    expect(signature, isNotEmpty);
  });

  test('会话层把 agent 不可用归类为 TerminalErrorKind.agent', () async {
    final session = TerminalSession(
      server: SshServer(
        id: 'agent-classify-target',
        group: 'test',
        name: 'agent-classify',
        host: '192.0.2.1',
        port: 22,
        username: 'root',
        authMethod: AuthMethod.agent,
      ),
      credentials: const SshCredentials(useAgent: true),
      transport: FakeTransport(
        error: const SshAgentUnavailableException('no agent in test'),
      ),
    );
    addTearDown(session.dispose);
    await session.start();
    expect(session.phase, TerminalPhase.failed);
    expect(session.errorKind, TerminalErrorKind.agent);
  });
}

/// 最小测试读取器：只服务 sign 请求的断言，与协议实现解耦。
final class _TestReader {
  _TestReader(this._bytes);

  final List<int> _bytes;
  int _offset = 0;

  int readUint8() => _bytes[_offset++];

  List<int> readString() {
    final length = ByteData.sublistView(
      Uint8List.fromList(_bytes),
      _offset,
      _offset + 4,
    ).getUint32(0);
    _offset += 4;
    final value = _bytes.sublist(_offset, _offset + length);
    _offset += length;
    return value;
  }

  int readUint32() {
    final value = ByteData.sublistView(
      Uint8List.fromList(_bytes),
      _offset,
      _offset + 4,
    ).getUint32(0);
    _offset += 4;
    return value;
  }
}
