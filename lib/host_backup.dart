/// 主机备份文件的编解码：把主机清单文本包进一个口令保护的加密信封。
///
/// 明文就是 [encodeHostsText] 的输出，前面加一行格式标记；整份明文用口令
/// 派生的密钥一次性加密（AES-256-GCM），因此一份文件只做一次密钥派生。
/// 密钥派生用 PBKDF2-HMAC-SHA256，每个文件一份新的随机盐；
/// GCM 自带认证标签，口令不对或文件被改动都会解密失败而不是解出乱码。
///
/// 信封本体是 UTF-8 的 JSON：
/// ```json
/// {"scheme":"no-shell-hosts","version":1,"kdf":"pbkdf2-hmac-sha256","iterations":50000,
///  "cipher":"aes-256-gcm","salt":"<base64>","nonce":"<base64>","payload":"<base64>"}
/// ```
///
/// 加解密是同步的：五万轮 PBKDF2 约两三百毫秒，一次导入 / 导出只算一遍，
/// 换来的是纯净的调用约定（不依赖 isolate，六端行为一致，也好测）。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/random/fortuna_random.dart';

import 'host_portable.dart';

/// 备份文件后缀：导出时的默认文件名与导入侧的文件识别共用。
const backupFileExtension = 'nsbak';

/// 备份文本的第一行，用来在解密后确认拿到的确实是本应用的备份。
const _formatMarker = 'no-shell-hosts: 1';

/// 加密信封的版本；将来换算法时靠它区分。
const _backupVersion = 1;

/// 派生密钥的迭代次数：一次导出只算一遍，取够抵御离线爆破的量级。
const _keyIterations = 50000;

const _scheme = 'no-shell-hosts';
const _kdfName = 'pbkdf2-hmac-sha256';
const _cipherName = 'aes-256-gcm';

const _keyLength = 32;
const _saltLength = 16;
const _nonceLength = 12;
const _macBits = 128;

const _minIterations = 10000;
const _maxIterations = 2000000;

/// 把主机清单文本加密成备份文件内容。
String encodeHostsBackup(String hostsText, String password) =>
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
String decodeHostsBackup(String contents, String password) =>
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

String _encode(String hostsText, String password) {
  final salt = _randomBytes(_saltLength);
  final nonce = _randomBytes(_nonceLength);
  final key = _deriveKey(password, salt, _keyIterations);
  try {
    final sealed = _seal(key, nonce, utf8.encode('$_formatMarker\n$hostsText'));
    return jsonEncode({
      'scheme': _scheme,
      'version': _backupVersion,
      'kdf': _kdfName,
      'iterations': _keyIterations,
      'cipher': _cipherName,
      'salt': base64.encode(salt),
      'nonce': base64.encode(nonce),
      'payload': base64.encode(sealed),
    });
  } finally {
    key.fillRange(0, key.length, 0);
  }
}

String _decode(String contents, String password) {
  final envelope = _readEnvelope(contents);
  final key = _deriveKey(password, envelope.salt, envelope.iterations);
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

/// 信封里解出来的定长字段。
final class _Envelope {
  const _Envelope({
    required this.salt,
    required this.nonce,
    required this.payload,
    required this.iterations,
  });

  final Uint8List salt;
  final Uint8List nonce;
  final Uint8List payload;
  final int iterations;
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
  if (decoded['scheme'] != _scheme ||
      decoded['kdf'] != _kdfName ||
      decoded['cipher'] != _cipherName) {
    throw const BackupFormatException(BackupProblem.unreadable);
  }
  if (decoded['version'] != _backupVersion) {
    throw const BackupFormatException(BackupProblem.unreadable);
  }
  final iterations = decoded['iterations'];
  // 迭代次数写在文件里：将来调高默认值时旧文件照样能读，但离谱的取值
  // 直接拒绝——否则一个改过的文件就能让解密空转很久。
  if (iterations is! int ||
      iterations < _minIterations ||
      iterations > _maxIterations) {
    throw const BackupFormatException(BackupProblem.unreadable);
  }
  final salt = _decodeField(decoded['salt'], _saltLength);
  final nonce = _decodeField(decoded['nonce'], _nonceLength);
  final payload = _decodeField(decoded['payload'], null);
  if (payload.length <= _macBits ~/ 8) {
    throw const BackupFormatException(BackupProblem.unreadable);
  }
  return _Envelope(
    salt: salt,
    nonce: nonce,
    payload: payload,
    iterations: iterations,
  );
}

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

/// PBKDF2-HMAC-SHA256 派生 [_keyLength] 字节密钥。
Uint8List _deriveKey(String password, Uint8List salt, int iterations) {
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
