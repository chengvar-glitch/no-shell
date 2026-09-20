import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_version.dart';
import 'update_check_client.dart';

/// 检测状态：一次查询的进展。与「上次查到的结论」正交——
/// 查询失败时上次「有新版」的结论仍然有效，不该被清掉。
enum UpdateCheckStatus { idle, checking, done, failed }

/// 查询失败的归类落点。
///
/// [unsupported] 必须与 [failed] 分开：web 桩实现抛 `UnsupportedError`，
/// 那是「这里查不了」，不是「查了但没成功」。混在一起会让 web 用户
/// 反复点一个永远不会成功的按钮。
enum UpdateCheckFailure { network, notFound, server, malformed, unsupported }

/// 一次成功查询的结论。
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.latestVersion,
    required this.updateAvailable,
    required this.notes,
    required this.pageUrl,
    this.publishedAt,
  });

  /// 远端最新版本号（原样，可能带 `v` 前缀）。
  final String latestVersion;

  /// 是否比当前版本新。
  final bool updateAvailable;

  /// 发布说明，用于说明新版改了什么；可能为空。
  final String notes;

  /// 发布页地址。
  final String pageUrl;

  /// 发布日期；解析不出时为 null。只用于展示。
  final DateTime? publishedAt;
}

/// 上次成功查询的结论落盘通道。只存一个字符串（可用的新版本号）。
///
/// 刻意**不**存「已是最新」：那是一次网络事实，下次启动仍要重查；
/// 存下来只会在用户升级失败后继续骗自己。
abstract class UpdateCheckPersistence {
  /// 读上次记录的新版本号；没有记录或读不出来返回 null。
  ///
  /// 读失败按「没有记录」处理：大不了下次联网再查一遍。这里丢的只是
  /// 一条提示，不是用户数据，不值得像主机存档那样 fail closed。
  Future<String?> loadAvailableVersion();

  Future<void> saveAvailableVersion(String? version);
}

/// shared_preferences 实现：键固定，值是可用的新版本号。
class SharedPreferencesUpdateCheckPersistence
    implements UpdateCheckPersistence {
  const SharedPreferencesUpdateCheckPersistence();

  static const String _key = 'update_available_version';

  @override
  Future<String?> loadAvailableVersion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveAvailableVersion(String? version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (version == null) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, version);
      }
    } catch (_) {
      // 存不上只影响下次启动少一条提示，不该打断本次会话。
    }
  }
}

/// 版本检测的唯一状态源。界面经 `ListenableBuilder` 订阅。别把它塞进
/// [ServerStore] / [SessionManager]：那两者是主机与会话的状态源，与版本无关。
///
/// 刻意**不**在构造时自动查：什么时候查由调用方决定（启动后延迟一次 /
/// 用户点按钮），测试才好控制。
class UpdateCheckService extends ChangeNotifier {
  UpdateCheckService({
    required this.client,
    this.persistence,
    this.startupDelay = const Duration(seconds: 4),
  });

  /// 查询通道：真机是 GitHub Releases，测试注入假实现。
  final UpdateCheckClient client;

  /// 「有新版本」的落盘通道；为 null 时只在内存里记。
  final UpdateCheckPersistence? persistence;

  /// 启动后静默查询的延迟：晚一点再联网，别和启动时的读盘 / 首次渲染抢。
  ///
  /// **为 null 时不排这次查询**。测试默认就该传 null：待触发的计时器会让
  /// `pumpAndSettle` 一直等到它到期，而测试关心的是手动检查与已有结论的展示。
  final Duration? startupDelay;

  UpdateCheckStatus _status = UpdateCheckStatus.idle;
  UpdateCheckFailure? _failure;
  UpdateCheckResult? _result;
  Timer? _startupTimer;
  bool _disposed = false;
  bool _startupScheduled = false;

  UpdateCheckStatus get status => _status;
  UpdateCheckFailure? get failure => _failure;
  UpdateCheckResult? get result => _result;

  /// 当前版本号（`x.y.z`），界面展示用。
  String get currentVersion => appVersion;

  /// 是否需要提示「有新版」：上次已查明的结论，跨重启有效，
  /// 直到某次查询确认已是最新才撤下。
  bool get updateAvailable => _result?.updateAvailable ?? false;

  /// 可用的新版本号；没有新版时为 null。
  String? get latestVersion => updateAvailable ? _result?.latestVersion : null;

  /// 发布页地址；永远给得出（解析不到 `html_url` 时落到发布页总入口）。
  String get releasePageUrl {
    final url = _result?.pageUrl;
    return url == null || url.isEmpty ? kReleasesPageUrl : url;
  }

  /// 读到上次记录的新版本号（若仍比当前版本新）就先挂上提示，
  /// 免得「有新版」这件事每次启动都要等联网查过才亮起来。
  Future<void> load() async {
    final persistence = this.persistence;
    if (persistence == null) return;
    final saved = await persistence.loadAvailableVersion();
    if (saved == null || saved.isEmpty) return;
    if (!isNewerVersion(saved, appVersion)) return;
    _result = UpdateCheckResult(
      latestVersion: saved,
      updateAvailable: true,
      notes: '',
      pageUrl: kReleasesPageUrl,
      // 落盘只记版本号：发布日期与更新说明那次会话没留，界面据此只说
      // 「有新版本」而不编一个日期出来。
      publishedAt: null,
    );
    _notify();
  }

  /// 启动后静默查一次；已知有新版时直接跳过，省一次请求。
  /// 只调度一次，重复调用无副作用（含 [startupDelay] 为 null 时）。
  void scheduleStartupCheck() {
    final delay = startupDelay;
    if (delay == null || _startupScheduled) return;
    _startupScheduled = true;
    _startupTimer = Timer(delay, () async {
      if (_disposed || updateAvailable) return;
      await check();
    });
  }

  /// 查一次并更新状态；返回是否查到了比当前版本新的版本。
  ///
  /// 失败**不抛**：状态落到 [UpdateCheckStatus.failed] 并带上归类，
  /// 由界面决定说什么。抛出去只会让每个调用方各自 try 一遍。
  Future<bool> check() async {
    if (_status == UpdateCheckStatus.checking) return updateAvailable;
    _status = UpdateCheckStatus.checking;
    _failure = null;
    _notify();
    ReleaseInfo release;
    try {
      release = await client.fetchLatestRelease();
    } on ReleaseLookupException catch (error) {
      return _fail(_failureFor(error.kind), error);
    } on UnsupportedError catch (error) {
      // web 桩实现：这里压根没有网络能力。上次查明的新版结论仍然有效，
      // 一并清掉会让提示随一次点按钮凭空消失。
      return _fail(UpdateCheckFailure.unsupported, error);
    } on Object catch (error) {
      // 兜底：实现方没归类干净也不能让一次检查把界面打崩。
      return _fail(UpdateCheckFailure.network, error);
    }
    final available = isNewerVersion(release.version, appVersion);
    _result = UpdateCheckResult(
      latestVersion: release.version,
      updateAvailable: available,
      notes: release.notes,
      pageUrl: release.pageUrl ?? kReleasesPageUrl,
      publishedAt: release.publishedAt,
    );
    _status = UpdateCheckStatus.done;
    _failure = null;
    // 落盘：有新版本记下来（下次启动不用联网也提示），追平了就把旧记录撤掉。
    await persistence?.saveAvailableVersion(available ? release.version : null);
    _notify();
    return available;
  }

  /// 归类并落下失败状态。返回值恒为 false，方便调用处直接 `return _fail(...)`。
  ///
  /// [UpdateCheckFailure.notFound] 不打日志：它多半是「还没发布过任何版本」，
  /// 或测试里那个不联网的替身，每次启动打一行纯属噪音。
  bool _fail(UpdateCheckFailure failure, Object error) {
    if (kDebugMode && failure != UpdateCheckFailure.notFound) {
      debugPrint('update_check: ${failure.name} ($error)');
    }
    _failure = failure;
    _status = UpdateCheckStatus.failed;
    _notify();
    return false;
  }

  UpdateCheckFailure _failureFor(ReleaseLookupError kind) => switch (kind) {
    ReleaseLookupError.network => UpdateCheckFailure.network,
    ReleaseLookupError.notFound => UpdateCheckFailure.notFound,
    ReleaseLookupError.server => UpdateCheckFailure.server,
    ReleaseLookupError.malformed => UpdateCheckFailure.malformed,
  };

  // 无变化守卫用的上一份快照：状态、归类与结论三者都没动过就不通知，
  // 免得下游整块设置面板白重建一次。
  Object? _notifiedFailure;
  Object? _notifiedResult;

  void _notify() {
    if (_disposed) return;
    if (identical(_notifiedFailure, _failure) &&
        identical(_notifiedResult, _result)) {
      return;
    }
    _notifiedFailure = _failure;
    _notifiedResult = _result;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _startupTimer?.cancel();
    _startupTimer = null;
    super.dispose();
  }
}
