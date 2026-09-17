/// 主机备份文件的编解码：把主机清单文本包进一个口令保护的加密信封。
///
/// 明文就是 [encodeHostsText] 的输出，前面加一行格式标记；整份明文用口令
/// 派生的密钥一次性加密（AES-256-GCM），因此一份文件只做一次密钥派生。
/// 每个文件一份新的随机盐；GCM 自带认证标签，口令不对或文件被改动都会
/// 解密失败而不是解出乱码。
///
/// 信封本体是 UTF-8 的 JSON（当前写入 scrypt）：
/// ```json
/// {"scheme":"no-shell-hosts","kdf":"scrypt","N":32768,"r":8,"p":1,
///  "cipher":"aes-256-gcm","salt":"<base64>","nonce":"<base64>","payload":"<base64>"}
/// ```
///
/// 为什么用 scrypt 而不是把 PBKDF2 的轮数往上堆：备份的明文里是 SSH 密码，
/// 派生必须是内存硬的才有意义；而 PBKDF2 到 OWASP 建议的六十万轮，在测试机
/// 上要 2.5 秒——低端设备更久，界面会明显卡住。scrypt 取 N=32768/r=8/p=1
/// （32 MiB）只要约 0.35 秒，抗爆破强度反而不低于六十万轮 PBKDF2。
///
/// 派生刻意**不开 isolate**：一是 scrypt 参数低到同步可接受；二是 widget
/// 测试跑在 fake-async 区域里，`Isolate.run` 的 Future 由真实事件循环完成，
/// fake-async 看不见，`pumpAndSettle` 会一直等到超时（已验证过）。
///
/// 解密按信封里的 `kdf` 分派：`scrypt` 与 `pbkdf2-hmac-sha256` 都认，
/// 所以更早导出的五万轮 PBKDF2 备份照旧解得开。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/key_derivators/scrypt.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/random/fortuna_random.dart';

import 'host_portable.dart';

/// 备份文件后缀：导出时的默认文件名与导入侧的文件识别共用。
const backupFileExtension = 'nsbak';

/// 备份文本的第一行。它的用处不是标版本，而是「解出来的到底是不是备份」：
/// 口令就算巧合地对上了认证标签，或者密文来自别的用途，少了这一行也认不出来，
/// 而「一份没有主机的备份」解出来是空文本，两者必须能分开。
const _formatMarker = 'no-shell-hosts';

/// scrypt 参数：N=2^15、r=8、p=1 ⇒ 约 32 MiB 内存、测试机上约 0.35 秒。
/// N 是 CPU/内存代价，r 是块大小，p 是并行度（保持 1，六端一致）。
const _scryptN = 32768;
const _scryptR = 8;
const _scryptP = 1;

const _scheme = 'no-shell-hosts';
const _kdfScrypt = 'scrypt';
const _kdfPbkdf2 = 'pbkdf2-hmac-sha256';
const _cipherName = 'aes-256-gcm';

const _keyLength = 32;
const _saltLength = 16;
const _nonceLength = 12;
const _macBits = 128;

/// 下限保持在一万：更早的备份是五万轮，仍要解得开。
/// PBKDF2 路径（只用于解旧备份）的迭代次数防呆区间。
const _minIterations = 10000;
const _maxIterations = 2000000;

/// scrypt 的 N 必须是 2 的幂；上限防呆，不让改过的文件吃掉几十 GB 内存。
const _minScryptN = 1024;
const _maxScryptN = 1 << 20;

/// 把主机清单文本加密成备份文件内容。
///
/// async：密钥派生在 isolate 里跑（六十万轮 PBKDF2 会冻结界面数秒）。
Future<String> encodeHostsBackup(String hostsText, String password) =>
    _encode(hostsText, password);

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
Future<String> decodeHostsBackup(String contents, String password) =>
    _decode(contents, password);

/// 备份读取失败的分类；界面据此给出「口令不对」还是「文件不可用」。
enum BackupProblem { wrongPassword, unreadable, notHostList }

/// 备份无法读取：文件不是本应用的备份、版本不支持或口令不对。
final class BackupFormatException implements Exception {
  const BackupFormatException(this.problem);

  final BackupProblem problem;

  @override
  String toString() => 'BackupFormatException(${problem.name})';
}

Future<String> _encode(String hostsText, String password) =>
    _encodeScrypt(hostsText, password, n: _scryptN, r: _scryptR, p: _scryptP);

/// 用 scrypt 派生并封装信封。
Future<String> _encodeScrypt(
  String hostsText,
  String password, {
  required int n,
  required int r,
  required int p,
}) async {
  final salt = _randomBytes(_saltLength);
  final nonce = _randomBytes(_nonceLength);
  final key = _deriveScrypt(password, salt, n: n, r: r, p: p);
  try {
    final sealed = _seal(key, nonce, utf8.encode('$_formatMarker\n$hostsText'));
    return jsonEncode({
      'scheme': _scheme,
      'kdf': _kdfScrypt,
      'N': n,
      'r': r,
      'p': p,
      'cipher': _cipherName,
      'salt': base64.encode(salt),
      'nonce': base64.encode(nonce),
      'payload': base64.encode(sealed),
    });
  } finally {
    key.fillRange(0, key.length, 0);
  }
}

Future<String> _decode(String contents, String password) async {
  final envelope = _readEnvelope(contents);
  final key = switch (envelope.kdf) {
    _kdfScrypt => _deriveScrypt(
      password,
      envelope.salt,
      n: envelope.n!,
      r: envelope.r!,
      p: envelope.p!,
    ),
    // 更早导出的备份是五万轮 PBKDF2，照旧解得开。
    _ => _derivePbkdf2(password, envelope.salt, envelope.iterations!),
  };
  final Uint8List plain;
  try {
    plain = _open(key, envelope.nonce, envelope.payload);
  } on InvalidCipherTextException {
    throw const BackupFormatException(BackupProblem.wrongPassword);
  } finally {
    key.fillRange(0, key.length, 0);
  }

  // 明文带格式标记：即使密文来自别的用途，也要能识别出「这不是主机清单」。
  final text = utf8.decode(plain, allowMalformed: true);
  final breakAt = text.indexOf('\n');
  if (breakAt < 0 || text.substring(0, breakAt).trim() != _formatMarker) {
    throw const BackupFormatException(BackupProblem.notHostList);
  }
  return text.substring(breakAt + 1);
}

/// 信封里解出来的字段。两种 KDF 的必需参数不同，因此各留可空字段：
/// `scrypt` 用 [n]/[r]/[p]，旧备份的 `pbkdf2-hmac-sha256` 用 [iterations]。
final class _Envelope {
  const _Envelope({
    required this.kdf,
    required this.salt,
    required this.nonce,
    required this.payload,
    this.iterations,
    this.n,
    this.r,
    this.p,
  });

  final String kdf;
  final Uint8List salt;
  final Uint8List nonce;
  final Uint8List payload;
  final int? iterations;
  final int? n;
  final int? r;
  final int? p;
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

  // 派生参数都是解密必需的，所以写在文件里；离谱的取值直接拒绝，
  // 否则一个改过的文件就能让解密空转很久（scrypt 还能吃掉几十 GB 内存）。
  switch (decoded['kdf']) {
    case _kdfScrypt:
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
        kdf: _kdfScrypt,
        salt: salt,
        nonce: nonce,
        payload: payload,
        n: n,
        r: r,
        p: p,
      );
    case _kdfPbkdf2:
      final iterations = decoded['iterations'];
      if (iterations is! int ||
          iterations < _minIterations ||
          iterations > _maxIterations) {
        throw const BackupFormatException(BackupProblem.unreadable);
      }
      return _Envelope(
        kdf: _kdfPbkdf2,
        salt: salt,
        nonce: nonce,
        payload: payload,
        iterations: iterations,
      );
    default:
      throw const BackupFormatException(BackupProblem.unreadable);
  }
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

/// scrypt 派生 [_keyLength] 字节密钥（同步：参数低到不会卡住界面，
/// 且开 isolate 会在 widget 测试的 fake-async 区域里永不完成）。
Uint8List _deriveScrypt(
  String password,
  Uint8List salt, {
  required int n,
  required int r,
  required int p,
}) {
  final derivator = Scrypt()..init(ScryptParameters(n, r, p, _keyLength, salt));
  return derivator.process(Uint8List.fromList(utf8.encode(password)));
}

/// PBKDF2-HMAC-SHA256 派生；只用于解更早导出的备份。
Uint8List _derivePbkdf2(String password, Uint8List salt, int iterations) {
  final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(salt, iterations, _keyLength));
  return derivator.process(Uint8List.fromList(utf8.encode(password)));
}

/// AES-256-GCM 加密，返回「密文 + 认证标签」。
Uint8List _seal(Uint8List key, Uint8List nonce, List<int> plain) {
  final cipher = GCMBlockCipher(AESEngine())
    ..init(true, AEADParameters(KeyParameter(key), _macBits, nonce, _empty));
  final input = Uint8List.fromList(plain);
  final out = Uint8List(cipher.getOutputSize(input.length));
  var written = cipher.processBytes(input, 0, input.length, out, 0);
  written += cipher.doFinal(out, written);
  return Uint8List.sublistView(out, 0, written);
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

/// 测试专用：用更低的 scrypt 参数（但其余流程完全一致）产出备份内容。
///
/// 存在的理由是可测性：生产参数一次派生约 0.35 秒、占 32 MiB，几十个用例
/// 各派生一遍会明显拖慢套件。生产路径只有 [encodeHostsBackup] 一个入口。
///
/// 解密侧不需要对应入口：[decodeHostsBackup] 的参数取自信封本身。
Future<String> encodeHostsBackupForTest(
  String hostsText,
  String password, {
  int n = 1024,
  int r = 8,
  int p = 1,
}) => _encodeScrypt(hostsText, password, n: n, r: r, p: p);

/// 测试专用：走旧的 PBKDF2 路径派生密钥。
///
/// 只为构造「更早版本导出的备份」来验证向后兼容；生产路径不再写 PBKDF2。
Uint8List derivePbkdf2ForTest(
  String password,
  Uint8List salt,
  int iterations,
) => _derivePbkdf2(password, salt, iterations);

/// 测试专用：按信封格式封装密文（不经过公开 API，便于手工拼装旧格式）。
Uint8List sealForTest(Uint8List key, Uint8List nonce, String plainText) =>
    _seal(key, nonce, utf8.encode(plainText));
