// SFTP 文件行的彩色类型图标：vscode-icons（MIT）的常用子集，随包内置。
// 只按扩展名粗分，外加少数按整个文件名认的（Dockerfile / .gitignore）；
// 认不出的一律回落到 default_file.svg，调用方没有空值分支。
// 目录与软链接不在这里：它们保持主题色的 Material 图形（见 sftp_browser_list.dart）。
// SVG 子集升级：替换 assets/icons/file_type/ 下的文件并同步这里的表与 LICENSE。

/// 图标资产目录（pubspec 的 assets 按整个目录声明）。
const String _kIconDir = 'assets/icons/file_type';

/// 扩展名认不出时的兜底图标。
const String _kDefaultIcon = 'default_file.svg';

/// 扩展名（小写）→ 图标资产文件名。
const Map<String, String> kFileTypeIconByExtension = {
  'js': 'file_type_javascript.svg',
  'mjs': 'file_type_javascript.svg',
  'jsx': 'file_type_reactjs.svg',
  'ts': 'file_type_typescript.svg',
  'tsx': 'file_type_reactjs.svg',
  'py': 'file_type_python.svg',
  'go': 'file_type_go.svg',
  'rs': 'file_type_rust.svg',
  'java': 'file_type_java.svg',
  'rb': 'file_type_ruby.svg',
  'php': 'file_type_php.svg',
  'sh': 'file_type_shell.svg',
  'bash': 'file_type_shell.svg',
  'zsh': 'file_type_shell.svg',
  'c': 'file_type_c.svg',
  'h': 'file_type_c.svg',
  'cpp': 'file_type_cpp.svg',
  'cc': 'file_type_cpp.svg',
  'cxx': 'file_type_cpp.svg',
  'hpp': 'file_type_cpp.svg',
  'cs': 'file_type_csharp.svg',
  'swift': 'file_type_swift.svg',
  'kt': 'file_type_kotlin.svg',
  'kts': 'file_type_kotlin.svg',
  'dart': 'file_type_dartlang.svg',
  'vue': 'file_type_vue.svg',
  'html': 'file_type_html.svg',
  'htm': 'file_type_html.svg',
  'css': 'file_type_css.svg',
  'scss': 'file_type_sass.svg',
  'sass': 'file_type_sass.svg',
  'less': 'file_type_less.svg',
  'json': 'file_type_json.svg',
  'yaml': 'file_type_yaml.svg',
  'yml': 'file_type_yaml.svg',
  'toml': 'file_type_toml.svg',
  'xml': 'file_type_xml.svg',
  'ini': 'file_type_config.svg',
  'conf': 'file_type_config.svg',
  'cfg': 'file_type_config.svg',
  'env': 'file_type_config.svg',
  'properties': 'file_type_config.svg',
  'txt': 'file_type_text.svg',
  'md': 'file_type_markdown.svg',
  'markdown': 'file_type_markdown.svg',
  'log': 'file_type_log.svg',
  'sql': 'file_type_sql.svg',
  'db': 'file_type_sql.svg',
  'sqlite': 'file_type_sql.svg',
  'sqlite3': 'file_type_sql.svg',
  'png': 'file_type_image.svg',
  'jpg': 'file_type_image.svg',
  'jpeg': 'file_type_image.svg',
  'gif': 'file_type_image.svg',
  'webp': 'file_type_image.svg',
  'bmp': 'file_type_image.svg',
  'ico': 'file_type_image.svg',
  'svg': 'file_type_image.svg',
  'mp4': 'file_type_video.svg',
  'mkv': 'file_type_video.svg',
  'avi': 'file_type_video.svg',
  'mov': 'file_type_video.svg',
  'webm': 'file_type_video.svg',
  'mp3': 'file_type_audio.svg',
  'wav': 'file_type_audio.svg',
  'flac': 'file_type_audio.svg',
  'ogg': 'file_type_audio.svg',
  'm4a': 'file_type_audio.svg',
  'zip': 'file_type_zip.svg',
  'tar': 'file_type_zip.svg',
  'gz': 'file_type_zip.svg',
  'tgz': 'file_type_zip.svg',
  'bz2': 'file_type_zip.svg',
  'xz': 'file_type_zip.svg',
  '7z': 'file_type_zip.svg',
  'rar': 'file_type_zip.svg',
  'iso': 'file_type_zip.svg',
  'deb': 'file_type_zip.svg',
  'rpm': 'file_type_zip.svg',
  'pdf': 'file_type_pdf.svg',
  'pem': 'file_type_key.svg',
  'key': 'file_type_key.svg',
  'crt': 'file_type_key.svg',
  'cer': 'file_type_key.svg',
  'pub': 'file_type_key.svg',
  'ttf': 'file_type_font.svg',
  'otf': 'file_type_font.svg',
  'woff': 'file_type_font.svg',
  'woff2': 'file_type_font.svg',
  'bin': 'file_type_binary.svg',
  'exe': 'file_type_binary.svg',
  'dll': 'file_type_binary.svg',
  'so': 'file_type_binary.svg',
  'dylib': 'file_type_binary.svg',
};

/// 按整个文件名认的（大小写不敏感）：这些名字没有扩展名，或点开头的
/// 隐藏文件 `lastIndexOf('.') == 0` 取不到扩展名。
const Map<String, String> kFileTypeIconByName = {
  'dockerfile': 'file_type_docker.svg',
  '.dockerignore': 'file_type_docker.svg',
  '.gitignore': 'file_type_git.svg',
  '.gitattributes': 'file_type_git.svg',
  '.gitmodules': 'file_type_git.svg',
};

/// 该文件应显示的图标资产路径；认不出时回落到通用文件图标，永不返回空。
String fileTypeIconAsset(String name) {
  final byName = kFileTypeIconByName[name.toLowerCase()];
  if (byName != null) return '$_kIconDir/$byName';
  final dot = name.lastIndexOf('.');
  final extension = dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
  final icon = kFileTypeIconByExtension[extension] ?? _kDefaultIcon;
  return '$_kIconDir/$icon';
}

/// 图标集的许可登记（MIT 要求分发时随附许可与版权声明）。
/// 启动时随内置字体一起注册进 LicenseRegistry（见 main.dart）。
const Map<String, String> kFileTypeIconLicenses = {
  'vscode-icons': '$_kIconDir/LICENSE',
};
