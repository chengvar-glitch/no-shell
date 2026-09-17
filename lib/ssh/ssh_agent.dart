/// 本机 SSH agent 客户端：向 agent 列出密钥、请求签名。
/// 协议见 draft-miller-ssh-agent 与 OpenSSH 的 PROTOCOL.agent。
///
/// 这一层只定义协议编解码与字节通道的抽象，不碰平台细节：真正的套接字
/// 由条件导出的 ssh_agent_io.dart（macOS / Linux 走 `SSH_AUTH_SOCK`）提供，
/// web 由 ssh_agent_stub.dart 兜底。编解码是纯 Dart，测试可直接注入假通道。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

export 'ssh_agent_stub.dart' if (dart.library.io) 'ssh_agent_io.dart';

/// agent 协议消息号与签名标志位。
abstract final class SshAgentProtocol {
  static const int failure = 5;
  static const int requestIdentities = 11;
  static const int identitiesAnswer = 12;
  static const int signRequest = 13;
  static const int signResponse = 14;

  /// RFC 8332：RSA 密钥用 SHA-256 签名（SHA-1 已被现代服务器禁用）。
  static const int rsaSha2_256 = 2;
  static const int rsaSha2_512 = 4;

  /// 安全密钥（sk- 系列）：要求触摸 / 按指纹确认在场。
  static const int skUserPresence = 1;

  /// 单帧上限（1 MB，与 OpenSSH agent 的应答上限同量级）：超过即视为
  /// 对端不是 agent 或流已错位，断开而不是把内存吃光。
  static const int maxFrameSize = 1024 * 1024;
}

/// agent 不可用：本平台没有 agent（web / 移动端）、套接字未配置或连不上。
/// 在连接发起前抛出，UI 据此给出「先 ssh-add / 启动 agent」的指引。
final class SshAgentUnavailableException implements Exception {
  const SshAgentUnavailableException(this.detail);

  final String detail;

  @override
  String toString() => 'SshAgentUnavailableException($detail)';
}

/// agent 在手但没办成事：签名被拒（密钥已被 ssh-add -d 移除）或应答格式坏掉。
final class SshAgentFailureException implements Exception {
  const SshAgentFailureException(this.detail);

  final String detail;

  @override
  String toString() => 'SshAgentFailureException($detail)';
}

/// agent 里的一把公钥身份。
final class SshAgentIdentity {
  const SshAgentIdentity({required this.blob, this.comment = ''});

  /// SSH wire 格式的公钥本体（首个 length-prefixed 字符串即算法名）。
  final Uint8List blob;

  /// 加载密钥时的备注，常为 `user@host` 或文件名；用于界面展示。
  final String comment;

  /// 算法名：`ssh-ed25519` / `ssh-rsa` / `ecdsa-sha2-nistp256` / sk- 系列。
  String get type {
    final reader = _Reader(blob);
    return utf8.decode(reader.readString());
  }

  @override
  String toString() =>
      'SshAgentIdentity($type, ${comment.isEmpty ? '<no comment>' : comment})';
}

/// 与 agent 通信的字节通道。平台实现负责真正的套接字，测试注入内存假通道。
abstract interface class SshAgentChannel {
  Stream<Uint8List> get stream;

  void add(List<int> data);

  Future<void> close();
}

/// 一条已连上的 agent：协议是严格一问一答，实现内部串行化请求。
abstract interface class SshAgentClient {
  /// 列出 agent 当前装载的公钥；agent 返回失败时应答为空列表之外的失败。
  Future<List<SshAgentIdentity>> listIdentities();

  /// 用 [identity] 对 [data] 签名，返回 wire 格式的签名
  /// （`string 算法名, string 签名值`，dartssh2 的 [SSHRawSignature] 可直接包）。
  Future<Uint8List> sign(SshAgentIdentity identity, Uint8List data);

  /// 断开与 agent 的连接；可安全重复调用。
  Future<void> close();
}

/// 在任意字节通道上跑 agent 协议；平台无关，测试注入假通道即可驱动。
SshAgentClient createSshAgentClient(SshAgentChannel channel) =>
    _ChannelAgentClient(channel);

final class _ChannelAgentClient implements SshAgentClient {
  _ChannelAgentClient(this._channel) {
    _subscription = _channel.stream.listen(
      _onData,
      onError: (Object error) =>
          _failAll(SshAgentFailureException(error.toString())),
      onDone: () => _failAll(
        const SshAgentUnavailableException('agent connection closed'),
      ),
    );
  }

  static const _requestTimeout = Duration(seconds: 10);

  final SshAgentChannel _channel;
  final List<Completer<Uint8List>> _pending = [];
  final _FrameAssembler _frames = _FrameAssembler();
  StreamSubscription<Uint8List>? _subscription;
  bool _closed = false;

  /// agent 协议不并发：上一问没答完不发下一问，避免应答串台。
  Future<void> _tail = Future.value();

  @override
  Future<List<SshAgentIdentity>> listIdentities() => _enqueue(() async {
    final response = await _request(
      Uint8List.fromList(const [SshAgentProtocol.requestIdentities]),
    );
    return _parseIdentities(_Reader(response));
  });

  @override
  Future<Uint8List> sign(SshAgentIdentity identity, Uint8List data) =>
      _enqueue(() async {
        final response = await _request(_encodeSignRequest(identity, data));
        return _parseSignature(_Reader(response));
      });

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _subscription?.cancel();
    await _channel.close();
    _failAll(
      const SshAgentUnavailableException('agent connection closed by client'),
    );
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final run = _tail.then((_) => action());
    // 排队本身不允许抛：失败只属于这一次请求，不该截断后续请求。
    _tail = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  Future<Uint8List> _request(Uint8List payload) {
    if (_closed) {
      throw const SshAgentUnavailableException('agent connection closed');
    }
    final completer = Completer<Uint8List>();
    _pending.add(completer);
    _channel.add(_encodeFrame(payload));
    return completer.future.timeout(
      _requestTimeout,
      onTimeout: () =>
          throw const SshAgentFailureException('agent did not answer in time'),
    );
  }

  void _onData(Uint8List chunk) {
    try {
      _frames.add(chunk);
      for (var frame = _frames.next(); frame != null; frame = _frames.next()) {
        final completer = _pending.isEmpty ? null : _pending.removeAt(0);
        if (completer == null || completer.isCompleted) continue;
        completer.complete(frame);
      }
    } on Object catch (error) {
      // 流已错位（坏帧长等）：后面的应答再也对不上号，全部判失败并断开，
      // 不让请求挂在超时上。
      _failAll(
        error is SshAgentFailureException
            ? error
            : SshAgentFailureException(error.toString()),
      );
      unawaited(close());
    }
  }

  void _failAll(Object error) {
    for (final completer in _pending) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
  }

  /// 签名请求：`uint8 13, string 密钥, string 数据, uint32 flags`；
  /// RSA 带上 SHA-256 标志（服务器不再接受 SHA-1 签名），
  /// 安全密钥按 OpenSSH 约定追加 application 命名空间。
  Uint8List _encodeSignRequest(SshAgentIdentity identity, Uint8List data) {
    final writer = _Writer()
      ..writeUint8(SshAgentProtocol.signRequest)
      ..writeString(identity.blob)
      ..writeString(data);
    switch (identity.type) {
      case 'ssh-rsa':
        writer.writeUint32(SshAgentProtocol.rsaSha2_256);
      case final String type when type.startsWith('sk-'):
        writer
          ..writeUint32(SshAgentProtocol.skUserPresence)
          ..writeString(utf8.encode('ssh:'));
      default:
        writer.writeUint32(0);
    }
    return writer.takeBytes();
  }
}

List<SshAgentIdentity> _parseIdentities(_Reader reader) {
  final messageType = reader.readUint8();
  if (messageType == SshAgentProtocol.failure) {
    throw const SshAgentFailureException('agent refused to list identities');
  }
  if (messageType != SshAgentProtocol.identitiesAnswer) {
    throw SshAgentFailureException('unexpected agent answer $messageType');
  }
  final count = reader.readUint32();
  return List.generate(count, (_) {
    final blob = reader.readString();
    final comment = utf8.decode(reader.readString(), allowMalformed: true);
    return SshAgentIdentity(blob: Uint8List.fromList(blob), comment: comment);
  });
}

/// 签名应答：`uint8 14, string 签名`；agent 拒签（密钥已被移除等）回 failure。
Uint8List _parseSignature(_Reader reader) {
  final messageType = reader.readUint8();
  if (messageType == SshAgentProtocol.failure) {
    throw const SshAgentFailureException('agent refused to sign');
  }
  if (messageType != SshAgentProtocol.signResponse) {
    throw SshAgentFailureException('unexpected agent answer $messageType');
  }
  return Uint8List.fromList(reader.readString());
}

Uint8List _encodeFrame(Uint8List payload) {
  final writer = _Writer()
    ..writeUint32(payload.length)
    ..writeBytes(payload);
  return writer.takeBytes();
}

/// 把字节流按 `uint32 长度 + 载荷` 切成帧；不足一帧时先攒着。
final class _FrameAssembler {
  Uint8List _buffer = Uint8List(0);

  void add(List<int> chunk) {
    if (_buffer.isEmpty) {
      _buffer = Uint8List.fromList(chunk);
      return;
    }
    final merged = Uint8List(_buffer.length + chunk.length)
      ..setAll(0, _buffer)
      ..setAll(_buffer.length, chunk);
    _buffer = merged;
  }

  Uint8List? next() {
    if (_buffer.length < 4) return null;
    final length = ByteData.sublistView(_buffer, 0, 4).getUint32(0);
    if (length == 0 || length > SshAgentProtocol.maxFrameSize) {
      throw const SshAgentFailureException('invalid agent frame length');
    }
    if (_buffer.length < 4 + length) return null;
    final frame = Uint8List.fromList(
      Uint8List.sublistView(_buffer, 4, 4 + length),
    );
    _buffer = Uint8List.fromList(Uint8List.sublistView(_buffer, 4 + length));
    return frame;
  }
}

final class _Reader {
  _Reader(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;

  int readUint8() {
    _require(1);
    return _bytes[_offset++];
  }

  int readUint32() {
    _require(4);
    final value = ByteData.sublistView(
      _bytes,
      _offset,
      _offset + 4,
    ).getUint32(0);
    _offset += 4;
    return value;
  }

  Uint8List readString() {
    final length = readUint32();
    _require(length);
    final value = Uint8List.sublistView(_bytes, _offset, _offset + length);
    _offset += length;
    return value;
  }

  void _require(int length) {
    if (_offset + length > _bytes.length) {
      throw const SshAgentFailureException('truncated agent message');
    }
  }
}

final class _Writer {
  final _builder = BytesBuilder(copy: false);

  void writeUint8(int value) => _builder.addByte(value);

  void writeUint32(int value) {
    _builder.add(Uint8List(4)..buffer.asByteData().setUint32(0, value));
  }

  void writeString(List<int> value) {
    writeUint32(value.length);
    _builder.add(value);
  }

  void writeBytes(List<int> value) => _builder.add(value);

  Uint8List takeBytes() => _builder.takeBytes();
}

/// 把 agent 的密钥映射成 dartssh2 的认证身份。
///
/// RSA 的 blob 算法名是 `ssh-rsa`，但认证必须按 RFC 8332 用 `rsa-sha2-256`
/// 协商（签名请求由 [SshAgentClient.sign] 内部带 SHA-256 标志）；
/// `shouldProbe` 先用公钥探一探服务器认不认这把钥匙，避免对每把落选的
/// 密钥都白弹一次触摸确认。
List<SSHIdentity> agentIdentitiesAsSsh(
  SshAgentClient client,
  List<SshAgentIdentity> keys,
) => [
  for (final key in keys)
    SSHIdentity.custom(
      type: key.type == 'ssh-rsa' ? 'rsa-sha2-256' : key.type,
      publicKey: SSHRawHostKey(key.blob),
      comment: key.comment.isEmpty ? null : key.comment,
      shouldProbe: true,
      signer: (data) async => SSHRawSignature(await client.sign(key, data)),
    ),
];
