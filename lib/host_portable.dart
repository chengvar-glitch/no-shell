/// 主机列表文本格式的编解码，供导入 / 导出共用。
///
/// 格式为一台主机一个文本块，块与块之间以空行分隔，块内每行 `key: value`：
/// ```
/// 名称: fofo
/// 地址: 192.0.2.10
/// 端口: 22
/// 用户: root
/// 密码: demo-pass-123
/// ```
/// key 同时接受中英文（大小写不敏感），冒号兼容全角 `：`；`#` 开头的行视为注释。
library;

import 'models.dart';

/// 一台待导入主机的解析结果；尚未生成 id，由导入流程落库时补。
final class HostImport {
  const HostImport({
    required this.host,
    required this.name,
    required this.port,
    required this.username,
    required this.group,
    this.password,
  });

  final String host;
  final String name;
  final int port;
  final String username;
  final String group;

  /// 文本块中携带的密码；为 null 表示按私钥认证导入。
  final String? password;
}

/// 块间分隔（换行）与 `key: value` 首个冒号的切分模式。
/// 解析在每次输入变更时都会跑，正则只编译一次。
final _lineBreakPattern = RegExp(r'\r\n|\n|\r');
final _keySeparatorPattern = RegExp('[:：]');

/// 解析主机文本；无地址的块与无法识别的行直接忽略。
/// 缺省值：端口 22、名称与用户名取地址、分组取 [defaultGroup]。
List<HostImport> parseHostsText(String text, {required String defaultGroup}) {
  final drafts = <HostImport>[];
  String? name;
  String? host;
  String? username;
  String? password;
  String? group;
  int? port;

  void finishBlock() {
    final address = host?.trim();
    if (address == null || address.isEmpty) return;
    drafts.add(
      HostImport(
        host: address,
        name: _nonEmpty(name) ?? address,
        port: port ?? 22,
        username: _nonEmpty(username) ?? address,
        group: _nonEmpty(group) ?? defaultGroup,
        password: _nonEmpty(password),
      ),
    );
    name = host = username = password = group = null;
    port = null;
  }

  for (final rawLine in text.split(_lineBreakPattern)) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      finishBlock();
      continue;
    }
    if (line.startsWith('#')) continue;
    // 只在首个冒号处切分，值本身可以再含冒号（如 IPv6 地址）。
    final separator = line.indexOf(_keySeparatorPattern);
    if (separator <= 0) continue;
    final key = _normalizeKey(line.substring(0, separator));
    final value = line.substring(separator + 1).trim();
    switch (key) {
      case _keyName:
        name = value;
      case _keyHost:
        host = value;
      case _keyPort:
        final parsed = int.tryParse(value);
        if (parsed != null && parsed > 0 && parsed <= 65535) port = parsed;
      case _keyUser:
        username = value;
      case _keyPassword:
        password = value;
      case _keyGroup:
        group = value;
    }
  }
  finishBlock();
  return drafts;
}

/// 导出条目：主机 + 可选的已记住密码（私钥不导出）。
typedef HostExportEntry = ({SshServer server, String? password});

/// 把主机列表编码为文本块；导出固定用中文 key（导入侧中英文都认识）。
/// 密码仅在该条目有已记住密码时导出。
String encodeHostsText(Iterable<HostExportEntry> entries) {
  final buffer = StringBuffer();
  for (final (server: server, password: password) in entries) {
    if (buffer.isNotEmpty) buffer.writeln();
    _writeServerFields(buffer, server);
    final passwordText = password;
    if (passwordText != null) buffer.writeln('密码: $passwordText');
    if (server.group.isNotEmpty) buffer.writeln('分组: ${server.group}');
  }
  return buffer.toString();
}

/// 单台主机的复制文本：字段顺序与 [encodeHostsText] 一致，但「密码」行
/// 始终输出（[password] 为 null 时留空），也不带分组——它面向的是「把这台
/// 主机的连接信息粘贴出去」，粘贴的内容照样能被 [parseHostsText] 认出来。
String encodeServerText(SshServer server, {String? password}) {
  final buffer = StringBuffer();
  _writeServerFields(buffer, server);
  buffer.writeln('密码: ${password ?? ''}');
  return buffer.toString();
}

/// 两台编码器共用的前四行（名称 / 地址 / 端口 / 用户），只此一份。
void _writeServerFields(StringBuffer buffer, SshServer server) {
  buffer
    ..writeln('名称: ${server.name}')
    ..writeln('地址: ${server.host}')
    ..writeln('端口: ${server.port}')
    ..writeln('用户: ${server.username}');
}

const _keyName = 'name';
const _keyHost = 'host';
const _keyPort = 'port';
const _keyUser = 'user';
const _keyPassword = 'password';
const _keyGroup = 'group';

const _keyAliases = {
  '名称': _keyName,
  'name': _keyName,
  '地址': _keyHost,
  '主机': _keyHost,
  'address': _keyHost,
  'host': _keyHost,
  '端口': _keyPort,
  'port': _keyPort,
  '用户': _keyUser,
  '用户名': _keyUser,
  'user': _keyUser,
  'username': _keyUser,
  '密码': _keyPassword,
  'password': _keyPassword,
  '分组': _keyGroup,
  'group': _keyGroup,
};

/// key 归一化：去空白、转小写后查别名表（中文 key 不受小写影响）。
String? _normalizeKey(String raw) => _keyAliases[raw.trim().toLowerCase()];

String? _nonEmpty(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}
