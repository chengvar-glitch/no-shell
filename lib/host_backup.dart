/// 主机备份文件的编解码：把主机清单文本包进一个口令保护的加密信封。
///
/// 明文就是 [encodeHostsText] 的输出，前面加一行格式标记；整份明文用口令
/// 派生的密钥一次性加密（AES-256-GCM），因此一份文件只做一次密钥派生。
/// 每个文件一份新的随机盐；GCM 自带认证标签，口令不对或文件被改动都会
/// 解密失败而不是解出乱码。
///
/// 信封本体是 UTF-8 的 JSON：
/// ```json
/// {"scheme":"no-shell-hosts","kdf":"scrypt","N":32768,"r":8,"p":1,
///  "cipher":"aes-256-gcm","salt":"<base64>","nonce":"<base64>","payload":"<base64>"}
/// ```
///
/// 为什么是 scrypt 而不是把 PBKDF2 的轮数往上堆：备份的明文里是 SSH 密码，
/// 派生必须内存硬才有意义；而 PBKDF2 到 OWASP 建议的六十万轮，在测试机上要
/// 2.5 秒——低端设备更久，界面会明显卡住。scrypt 取 N=32768/r=8/p=1
/// （32 MiB）只要约 0.35 秒，抗爆破强度反而不低于六十万轮 PBKDF2。
///
/// 派生刻意**不开 isolate**：scrypt 参数低到同步可接受；而 widget 测试跑在
/// fake-async 区域里，`Isolate.run` 的 Future 由真实事件循环完成，fake-async
/// 看不见它，`pumpAndSettle` 会一直等到超时（已验证过）。
///
/// 格式处于开发阶段，不背历史包袱：只写也只读 scrypt，没有版本号、
/// 没有旧 KDF 回退分支（见 AGENTS.md「导入 / 导出」一节）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/scrypt.dart';
import 'package:pointycastle/random/fortuna_random.dart';

import 'host_portable.dart';

/// 备份文件后缀：导出时的默认文件名与导入侧的文件识别共用。
const backupFileExtension = 'nsbak';

/// 备份文本的第一行。它的用处不是标版本，而是「解出来的到底是不是备份」：
/// 口令就算巧合地对上了认证标签，或者密文来自别的用途，少了这一行也认不出来，
/// 而「一份没有主机的备份」解出来是空文本，两者必须能分开。
const _formatMarker = 'no-shell-hosts';

/// scrypt 参数：N 是 CPU / 内存代价（N=2^15、r=8 ⇒ 约 32 MiB），
/// r 是块大小，p 是并行度（保持 1，六端一致）。
///
/// 流程可注入一份自定义参数：生产恒用 [HostBackupParams.standard]，
/// 测试注入更低的 N，否则几十个用例各派生一遍会明显拖慢套件。
@immutable
class HostBackupParams {
  const HostBackupParams({required this.n, required this.r, required this.p});

  /// 生产参数：测试机上约 0.35 秒。
  static const standard = HostBackupParams(n: 32768, r: 8, p: 1);

  final int n;
  final int r;
  final int p;

  /// 派生是否放到独立 isolate 里跑。
  ///
  /// 生产要放：六十万轮级别的纯 CPU 计算在主 isolate 上会把界面冻住。
  /// 测试要留在这里：widget 测试跑在 fake-async 区域里，`Isolate.run`
  /// 的 Future 由真实事件循环完成，fake-async 看不见它，`pumpAndSettle`
  /// 会一直等到超时（已验证，代价是十分钟挂死）。
  ///
  /// 低参数（测试用的那些）也不值得开 isolate，直接同步算。
  static const isolateThreshold = 1 << 15;

  bool get useIsolate => n >= isolateThreshold;
}

const _scheme = 'no-shell-hosts';
const _kdfScrypt = 'scrypt';
const _cipherName = 'aes-256-gcm';

const _keyLength = 32;
const _saltLength = 16;
const _nonceLength = 12;
const _macBits = 128;

/// 下限保持在一万：更早的备份是五万轮，仍要解得开。
/// scrypt 的 N 必须是 2 的幂；上限防呆，不让改过的文件吃掉几十 GB 内存。
const _minScryptN = 1024;
const _maxScryptN = 1 << 20;

/// 把主机清单文本加密成备份文件内容。
///
/// [params] 只给测试注入低参数用，生产路径不传。
Future<String> encodeHostsBackup(
  String hostsText,
  String password, {
  HostBackupParams params = HostBackupParams.standard,
}) => _encode(hostsText, password, params);

/// 只做信封层面的识别，不碰口令也不解密。
///
/// 让导入流程在开口令输入框之前就能判断「这文件根本不是备份」，避免用户
/// 白输一遍口令才被告知文件不对。
bool isHostsBackup(String contents) {
  try {
    _readEnvelope(contents);
    return true;
  } on BackupFormatException {
    return false;
  }
}

/// 解密备份文件内容，返回其中的主机清单文本。
///
/// 口令不对、文件被改动、格式不认识、版本不支持都会抛 [BackupFormatException]，
/// 调用方按「备份无法读取」统一提示即可。
/// [derive] 只给测试注入同步派生用（见 [HostBackupParams.useIsolate]）。
Future<String> decodeHostsBackup(
  String contents,
  String password, {
  DeriveRunner? derive,
}) => _decode(contents, password, derive ?? _deriveInIsolate);

/// 备份读取失败的分类；界面据此给出「口令不对」还是「文件不可用」。
enum BackupProblem { wrongPassword, unreadable, notHostList }

/// 备份无法读取：文件不是本应用的备份、版本不支持或口令不对。
final class BackupFormatException implements Exception {
  const BackupFormatException(this.problem);

  final BackupProblem problem;

  @override
  String toString() => 'BackupFormatException(${problem.name})';
}

Future<String> _encode(
  String hostsText,
  String password,
  HostBackupParams params,
) => _encodeScrypt(hostsText, password, params);

/// 用 scrypt 派生并封装信封。
Future<String> _encodeScrypt(
  String hostsText,
  String password,
  HostBackupParams params,
) async {
  final salt = _randomBytes(_saltLength);
  final nonce = _randomBytes(_nonceLength);
  final key = await _deriveInIsolate(password, salt, params);
  // 明文里是各主机的密码：用完即抹（_seal 内部还会再拷一份，那份也在那里抹掉）。
  final plain = utf8.encode('$_formatMarker\n$hostsText');
  try {
    final sealed = _seal(key, nonce, plain);
    return jsonEncode({
      'scheme': _scheme,
      'kdf': _kdfScrypt,
      'N': params.n,
      'r': params.r,
      'p': params.p,
      'cipher': _cipherName,
      'salt': base64.encode(salt),
      'nonce': base64.encode(nonce),
      'payload': base64.encode(sealed),
    });
  } finally {
    key.fillRange(0, key.length, 0);
    plain.fillRange(0, plain.length, 0);
  }
}

Future<String> _decode(
  String contents,
  String password,
  DeriveRunner derive,
) async {
  final envelope = _readEnvelope(contents);
  final key = await derive(
    password,
    envelope.salt,
    HostBackupParams(n: envelope.n, r: envelope.r, p: envelope.p),
  );
  final Uint8List plain;
  try {
    plain = _open(key, envelope.nonce, envelope.payload);
  } on InvalidCipherTextException {
    throw const BackupFormatException(BackupProblem.wrongPassword);
  } finally {
    key.fillRange(0, key.length, 0);
  }

  // 明文带格式标记：即使密文来自别的用途，也要能识别出「这不是主机清单」。
  final String text;
  try {
    text = utf8.decode(plain, allowMalformed: true);
  } finally {
    // 解出来的明文里是各主机的密码，取出文本后立刻抹掉这份字节。
    plain.fillRange(0, plain.length, 0);
  }
  final breakAt = text.indexOf('\n');
  if (breakAt < 0 || text.substring(0, breakAt).trim() != _formatMarker) {
    throw const BackupFormatException(BackupProblem.notHostList);
  }
  return text.substring(breakAt + 1);
}

/// 信封里解出来的字段。
final class _Envelope {
  const _Envelope({
    required this.salt,
    required this.nonce,
    required this.payload,
    required this.n,
    required this.r,
    required this.p,
  });

  final Uint8List salt;
  final Uint8List nonce;
  final Uint8List payload;
  final int n;
  final int r;
  final int p;
}

/// 解析并校验信封；任何一项不合规都归为 [BackupProblem.unreadable]。
_Envelope _readEnvelope(String contents) {
  final Object? decoded;
  try {
    decoded = jsonDecode(contents);
  } on FormatException {
    throw const BackupFormatException(BackupProblem.unreadable);
  }
  if (decoded is! Map<String, Object?>) {
    throw const BackupFormatException(BackupProblem.unreadable);
  }
  if (decoded['scheme'] != _scheme || decoded['cipher'] != _cipherName) {
    throw const BackupFormatException(BackupProblem.unreadable);
  }
  final salt = _decodeField(decoded['salt'], _saltLength);
  final nonce = _decodeField(decoded['nonce'], _nonceLength);
  final payload = _decodeField(decoded['payload'], null);
  if (payload.length <= _macBits ~/ 8) {
    throw const BackupFormatException(BackupProblem.unreadable);
  }

  // 派生参数是解密必需的，所以写在文件里；离谱的取值直接拒绝，
  // 否则一个改过的文件就能让 scrypt 吃掉几十 GB 内存。
  if (decoded['kdf'] != _kdfScrypt) {
    throw const BackupFormatException(BackupProblem.unreadable);
  }
  final n = decoded['N'];
  final r = decoded['r'];
  final p = decoded['p'];
  if (n is! int ||
      r is! int ||
      p is! int ||
      n < _minScryptN ||
      n > _maxScryptN ||
      !_isPowerOfTwo(n) ||
      r < 1 ||
      r > 32 ||
      p < 1 ||
      p > 16) {
    throw const BackupFormatException(BackupProblem.unreadable);
  }
  return _Envelope(
    salt: salt,
    nonce: nonce,
    payload: payload,
    n: n,
    r: r,
    p: p,
  );
}

bool _isPowerOfTwo(int value) => value > 0 && (value & (value - 1)) == 0;

/// 解出定长 base64 字段；[length] 为 null 表示长度不限。
Uint8List _decodeField(Object? raw, int? length) {
  if (raw is! String) {
    throw const BackupFormatException(BackupProblem.unreadable);
  }
  final Uint8List bytes;
  try {
    bytes = base64.decode(raw);
  } on FormatException {
    throw const BackupFormatException(BackupProblem.unreadable);
  }
  if (length != null && bytes.length != length) {
    throw const BackupFormatException(BackupProblem.unreadable);
  }
  return bytes;
}

/// 派生执行器：把口令 + 盐 + 参数算成密钥。可注入，见 [HostBackupParams.useIsolate]。
typedef DeriveRunner = Future<Uint8List> Function(
  String password,
  Uint8List salt,
  HostBackupParams params,
);

/// 生产用：低参数直接算，生产参数丢进 isolate（不冻界面）。
Future<Uint8List> _deriveInIsolate(
  String password,
  Uint8List salt,
  HostBackupParams params,
) {
  if (!params.useIsolate) {
    return Future.value(deriveScryptSync(password, salt, params));
  }
  // salt / 口令作为消息复制过去；参数是常量对象，同样可送。
  return Isolate.run(
    () => deriveScryptSync(
      password,
      salt,
      HostBackupParams(n: params.n, r: params.r, p: params.p),
    ),
  );
}

/// 测试用：始终同步算，不碰 isolate（fake-async 区域里 isolate 永不完成）。
Future<Uint8List> deriveSyncForTest(
  String password,
  Uint8List salt,
  HostBackupParams params,
) async => deriveScryptSync(password, salt, params);

/// scrypt 派生 [_keyLength] 字节密钥（同步）。
///
/// 生产参数调用它会阻塞当前 isolate 约 0.35 秒，因此生产路径只经
/// [_deriveInIsolate] 在独立 isolate 里调它；低参数（测试）则直接调。
Uint8List deriveScryptSync(
  String password,
  Uint8List salt,
  HostBackupParams params,
) {
  final derivator = Scrypt()
    ..init(ScryptParameters(params.n, params.r, params.p, _keyLength, salt));
  // 口令的字节副本用完即抹掉：String 本身无法清零（Dart 的不可变字符串），
  // 但这份副本可以，没必要让明文口令一直躺在堆上。
  final bytes = Uint8List.fromList(utf8.encode(password));
  try {
    return derivator.process(bytes);
  } finally {
    bytes.fillRange(0, bytes.length, 0);
  }
}

/// AES-256-GCM 加密，返回「密文 + 认证标签」。
Uint8List _seal(Uint8List key, Uint8List nonce, List<int> plain) {
  final cipher = GCMBlockCipher(AESEngine())
    ..init(true, AEADParameters(KeyParameter(key), _macBits, nonce, _empty));
  final input = Uint8List.fromList(plain);
  try {
    final out = Uint8List(cipher.getOutputSize(input.length));
    var written = cipher.processBytes(input, 0, input.length, out, 0);
    written += cipher.doFinal(out, written);
    return Uint8List.sublistView(out, 0, written);
  } finally {
    // 这份明文副本里是各主机的密码，加密完就抹掉。
    input.fillRange(0, input.length, 0);
  }
}

/// AES-256-GCM 解密；标签校验失败抛 [InvalidCipherTextException]。
Uint8List _open(Uint8List key, Uint8List nonce, Uint8List sealed) {
  final cipher = GCMBlockCipher(AESEngine())
    ..init(false, AEADParameters(KeyParameter(key), _macBits, nonce, _empty));
  final out = Uint8List(cipher.getOutputSize(sealed.length));
  var written = cipher.processBytes(sealed, 0, sealed.length, out, 0);
  written += cipher.doFinal(out, written);
  return Uint8List.sublistView(out, 0, written);
}

/// GCM 的附加认证数据：本格式不用，固定传空。
final _empty = Uint8List(0);

/// 密码学安全的随机字节。
Uint8List _randomBytes(int length) {
  final source = Random.secure();
  final seed = Uint8List.fromList([
    for (var i = 0; i < _seedLength; i++) source.nextInt(256),
  ]);
  return (FortunaRandom()..seed(KeyParameter(seed))).nextBytes(length);
}

const _seedLength = 32;

/// 用指定的 scrypt 参数产出备份内容，并强制同步派生。
///
/// 生产路径只有 [encodeHostsBackup]（参数是 [HostBackupParams.standard]）。
/// 这个入口存在只为可测性：生产参数一次派生约 0.35 秒、占 32 MiB，
/// 几十个用例各派生一遍会明显拖慢套件；而 isolate 在 widget 测试的
/// fake-async 区域里根本不会完成。
Future<String> encodeHostsBackupForTest(
  String hostsText,
  String password, {
  HostBackupParams params = const HostBackupParams(n: 1024, r: 8, p: 1),
}) => _encodeScrypt(hostsText, password, params);
