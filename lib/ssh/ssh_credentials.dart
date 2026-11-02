import 'dart:convert';

/// 一次 SSH 会话的认证凭据。
/// 默认仅在内存中使用；用户勾选「记住凭据」时经 CredentialStore
/// 加密持久化，删除主机或取消勾选即随之清除。
class SshCredentials {
  const SshCredentials({
    this.password,
    this.privateKey,
    this.passphrase,
    this.useAgent = false,
  });

  final String? password;
  final String? privateKey;
  final String? passphrase;

  /// 用本机 SSH agent 里的密钥认证（Agent 认证）：此时其余字段都不参与。
  /// agent 本身没有可记的机密，「记住凭据」落盘的只是这个意图标记。
  final bool useAgent;

  /// 本次认证是否走密钥（私钥文件或本机 agent）。
  ///
  /// 服务器主机密钥变更时「自动清除旧指纹并记下新指纹」（见
  /// `host_key_store.dart` 的 `verifyHostKey`）只对这条路径生效；密码认证
  /// 仍然拦下连接、请用户先核对指纹。
  bool get isKeyAuth => useAgent || privateKey != null;

  Map<String, Object?> toJson() => {
    if (password != null) 'password': password,
    if (privateKey != null) 'privateKey': privateKey,
    if (passphrase != null) 'passphrase': passphrase,
    if (useAgent) 'useAgent': true,
  };

  factory SshCredentials.fromJson(Map<String, Object?> json) => SshCredentials(
    password: json['password'] as String?,
    privateKey: json['privateKey'] as String?,
    passphrase: json['passphrase'] as String?,
    useAgent: json['useAgent'] == true,
  );

  String encode() => jsonEncode(toJson());

  static SshCredentials? tryDecode(String? raw) {
    if (raw == null) return null;
    try {
      return SshCredentials.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}
