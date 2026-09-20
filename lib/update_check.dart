/// 软件版本检测：查远端最新发布版，与当前版本比较，得出「有没有新版」。
///
/// 版本号来源见 `app_version.dart`，远端来源是 GitHub Releases
/// （发布流程见 `.github/workflows/release.yml`）。查询只需读接口，
/// 不认证也能查到 release（仓库私有与否都一样）。
library;

export 'update_check_stub.dart' if (dart.library.io) 'update_check_io.dart';
export 'update_check_client.dart';
export 'update_check_state.dart';
export 'update_launcher.dart';
