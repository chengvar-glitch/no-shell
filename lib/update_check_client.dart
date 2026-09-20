/// 检测结果的数据模型与版本比较。纯 Dart，六端通用（web 也要能编译）。
library;

/// 远端最新发布版；解析不出必需字段时整个查询算失败，不返回半份数据。
class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.notes,
    this.pageUrl,
    this.publishedAt,
  });

  /// 标签去掉前缀后的版本号，如 `4.1.3`（标签 `v4.1.3`）。
  final String version;

  /// 发布说明正文（release body）；可能为空。
  final String notes;

  /// 发布页地址，用于「前往下载」；取不到时按 [kReleasesPageUrl] 兜底。
  final String? pageUrl;

  /// 发布日期（GitHub 的 `published_at`）；解析不出时为 null。
  /// 只用于展示「这个版本是什么时候发的」，不参与任何判定。
  final DateTime? publishedAt;
}

/// 把 [DateTime] 显示成 `2026-09-21`。
///
/// 不走 `intl` 的日期格式：这里的日期是信息而非本地化内容，而 yyyy-MM-dd
/// 在中英两种界面下同样清楚，还能让测试断言稳定。取本地时区——用户看到的
/// 应该是自己这边的日期。
String formatReleaseDate(DateTime date) {
  final local = date.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

/// 发布页地址：没解析出 `html_url` 时的兜底落点。
const String kReleasesPageUrl =
    'https://github.com/chengvar-glitch/no-shell/releases';

/// 查询远端最新发布版的通道。实现见 `update_check_io.dart`（原生）与
/// `update_check_stub.dart`（web）。测试注入假实现，不打真实网络。
abstract class UpdateCheckClient {
  /// 查询最新发布版。失败按 [ReleaseLookupException] 抛出，由调用方归类展示。
  Future<ReleaseInfo> fetchLatestRelease();
}

/// 查询失败的归类：文案不同，且「网络不通」与「查不到发布」对用户的
/// 可操作性完全不同（一个是检查网络，一个是去发布页看看）。
enum ReleaseLookupError {
  /// 网络不通 / 超时 / 被墙。
  network,

  /// 没查到发布版（404，通常是一个都还没发布）。
  notFound,

  /// 服务端返回了非成功状态码。
  server,

  /// 响应不是预期结构（GitHub 改了接口、中间被劫持插了页面）。
  malformed,
}

class ReleaseLookupException implements Exception {
  const ReleaseLookupException(this.kind, [this.detail]);

  final ReleaseLookupError kind;

  /// 原始错误摘要，只进日志，不给用户看。
  final String? detail;

  @override
  String toString() =>
      'ReleaseLookupException(${kind.name}${detail == null ? '' : ': $detail'})';
}

/// 查到的版本是否比 [current] 新。
///
/// 只在**两边的数字段都解析得出**时才下结论：当前版本或远端版本读不出
/// 数字（`dev`、`unknown`、空串）时返回 false——宁可不说，也不能凭
/// 「解析不出来」就报一个不存在的新版本。
bool isNewerVersion(String candidate, String current) {
  final a = parseVersion(candidate);
  final b = parseVersion(current);
  if (a == null || b == null) return false;
  final length = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < length; i++) {
    final left = i < a.length ? a[i] : 0;
    final right = i < b.length ? b[i] : 0;
    if (left != right) return left > right;
  }
  return false;
}

/// 把 `v4.1.3` / `4.1.3` / `4.1.3+2` / `4.1.3-beta.1` 解析成数字段列表。
///
/// 只取前置的数字段：`+` 之后的构建号与 `-` 之后的预发布标记都不是
/// 「比大小」的依据（本项目发版只用 `x.y.z` 形式）。完全没有数字段
/// （空串、`latest`）时返回 null，交给调用方按「无法比较」处理。
List<int>? parseVersion(String raw) {
  var text = raw.trim();
  if (text.startsWith('v') || text.startsWith('V')) text = text.substring(1);
  final match = RegExp(r'^\d+(?:\.\d+)*').firstMatch(text);
  if (match == null) return null;
  return [
    for (final part in match.group(0)!.split('.')) int.tryParse(part) ?? 0,
  ];
}
