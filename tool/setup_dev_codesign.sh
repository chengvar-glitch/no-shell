#!/usr/bin/env bash
# 一次性配置 macOS 本机开发代码签名证书。
#
# 背景：本项目无 Apple 团队签名（ad-hoc），二进制每次重签哈希都变，钥匙串会把
# 新构建当陌生应用，读「记住凭据」时反复弹「想要使用登录钥匙串」授权框。
# 本脚本生成一个自签证书并设为代码签名信任锚，让签名身份跨构建稳定；
# 配合 macos/Runner/Configs/local.xcconfig（gitignore）覆盖默认的 ad-hoc 签名。
# CI 与新 clone 没有这份 local.xcconfig，行为不变（ad-hoc）。
#
# 幂等：身份已可用时直接退出；证书已导入但未受信时只补信任设置。
# 信任设置需要输入一次登录密码（macOS 弹授权框）。
set -euo pipefail

NAME="NoShell Dev Codesign"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCAL_XCCONFIG="$REPO_ROOT/macos/Runner/Configs/local.xcconfig"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$NAME\""; then
  echo "签名身份「$NAME」已可用，无需重复配置。"
else
  WORK="$(mktemp -d)"
  # 临时目录里生成私钥材料，结束时连同 p12 一并删除；密钥本体只留在登录钥匙串。
  trap 'rm -rf "$WORK"' EXIT

  if security find-identity -p codesigning 2>/dev/null | grep -q "\"$NAME\""; then
    echo "证书已导入但未受信，补设信任设置……"
    security find-certificate -c "$NAME" -p > "$WORK/crt.pem"
  else
    echo "生成自签证书「$NAME」（RSA 2048，10 年，仅代码签名用途）……"
    openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
      -subj "/CN=$NAME/O=NoShell Dev" \
      -keyout "$WORK/key.pem" -out "$WORK/crt.pem" \
      -addext "basicConstraints=critical,CA:TRUE" \
      -addext "keyUsage=critical,digitalSignature" \
      -addext "extendedKeyUsage=critical,codeSigning"
    PASS="$(openssl rand -hex 16)"
    # macOS security 只认传统 3DES/SHA1 打包的 p12；空口令会 MAC 校验失败，必须非空。
    openssl pkcs12 -export -name "$NAME" \
      -inkey "$WORK/key.pem" -in "$WORK/crt.pem" \
      -out "$WORK/cert.p12" -passout "pass:$PASS" \
      -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1
    security import "$WORK/cert.p12" -P "$PASS" -k "$KEYCHAIN" \
      -T /usr/bin/codesign -T /usr/bin/security
  fi

  echo "设为代码签名信任锚（macOS 会要求输入一次登录密码）……"
  security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/crt.pem" ||
    security add-trusted-cert -r trustRoot -k "$KEYCHAIN" "$WORK/crt.pem"
fi

if [ ! -f "$LOCAL_XCCONFIG" ]; then
  cat > "$LOCAL_XCCONFIG" <<'EOF'
// 本机开发签名覆盖（gitignore，不提交）：证书创建与信任设置见 tool/setup_dev_codesign.sh。
// 证书身份跨构建稳定，钥匙串凭据条目读起来不再弹授权框；旧的「记住凭据」条目在新身份
// 首次访问时还会弹最后一轮授权框，点「始终允许」后永久安静。
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY = NoShell Dev Codesign
EOF
  echo "已创建 $LOCAL_XCCONFIG"
fi

echo
echo "可用签名身份："
security find-identity -v -p codesigning
echo
echo "完成。重新构建后生效：flutter run -d macos / flutter build macos"
