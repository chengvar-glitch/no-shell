import 'dart:convert';

/// 一次 SSH 会话的认证凭据。
/// 默认仅在内存中使用；用户勾选「记住凭据」时经 CredentialStore
/// 加密持久化，删除主机或取消勾选即随之清除。
class SshCredentials {
  const SshCredentials({this.password, this.privateKey, this.passphrase});

  final String? password;
  final String? privateKey;
  final String? passphrase;

  Map<String, Object?> toJson() => {
    if (password != null) 'password': password,
    if (privateKey != null) 'privateKey': privateKey,
    if (passphrase != null) 'passphrase': passphrase,
  };

  factory SshCredentials.fromJson(Map<String, Object?> json) => SshCredentials(
    password: json['password'] as String?,
    privateKey: json['privateKey'] as String?,
    passphrase: json['passphrase'] as String?,
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
