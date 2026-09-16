// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appName => 'NoShell';

  @override
  String get cancel => '取消';

  @override
  String get save => '保存';

  @override
  String get delete => '删除';

  @override
  String get edit => '编辑';

  @override
  String get connect => '连接';

  @override
  String get disconnect => '断开连接';

  @override
  String get connectNow => '立即连接';

  @override
  String get newConnection => '新建连接';

  @override
  String get editConnection => '编辑连接';

  @override
  String get defaultGroupName => '默认分组';

  @override
  String get undo => '撤销';

  @override
  String deletedSnackbar(String name) {
    return '已删除 $name';
  }

  @override
  String deleteConfirmTitle(String name) {
    return '删除「$name」？';
  }

  @override
  String get deleteConfirmBody => '该主机将被移除，且无法恢复。';

  @override
  String get hostNotFound => '主机不存在';

  @override
  String get language => '语言';

  @override
  String get followSystem => '跟随系统';

  @override
  String get statusConnected => '已连接';

  @override
  String get statusConnecting => '连接中';

  @override
  String get statusError => '连接失败';

  @override
  String get statusIdle => '未连接';

  @override
  String hostCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 台主机',
    );
    return '$_temp0';
  }

  @override
  String collapseSidebar(String shortcut) {
    return '收起侧边栏 ($shortcut)';
  }

  @override
  String expandSidebar(String shortcut) {
    return '展开侧边栏 ($shortcut)';
  }

  @override
  String get windowMinimize => '最小化';

  @override
  String get windowMaximize => '最大化';

  @override
  String get windowRestore => '还原';

  @override
  String get windowClose => '关闭';

  @override
  String get searchHint => '搜索名称、主机或标签…';

  @override
  String get noMatchingHosts => '没有匹配的主机';

  @override
  String get about => '关于';

  @override
  String get switchToDark => '切换为深色';

  @override
  String get switchToLight => '切换为浅色';

  @override
  String get selectHostToStart => '选择左侧主机开始';

  @override
  String get emptyDetailHint => '从侧边栏选择一个主机查看详情，或新建一个连接';

  @override
  String get overview => '概览';

  @override
  String get terminal => '终端';

  @override
  String get sftp => 'SFTP';

  @override
  String get moreActions => '更多操作';

  @override
  String get deleteHost => '删除主机';

  @override
  String get hostAddress => '主机地址';

  @override
  String get copyAddress => '复制地址';

  @override
  String copied(String value) {
    return '已复制 $value';
  }

  @override
  String get port => '端口';

  @override
  String get username => '用户名';

  @override
  String get authMethod => '认证方式';

  @override
  String get authPassword => '密码';

  @override
  String get authKey => 'SSH 密钥';

  @override
  String get lastConnected => '最近连接';

  @override
  String get group => '分组';

  @override
  String get notes => '备注';

  @override
  String get notesOptional => '备注（可选）';

  @override
  String get pasteMetadata => '粘贴元数据（可选）';

  @override
  String get pasteMetadataHint =>
      '名称: fofo\n地址: 127.0.0.1\n端口: 22\n用户: root\n密码: password';

  @override
  String get sessionDesktopHint => '会话未建立 —— 点击右上角「连接」建立 SSH 会话后即可使用终端。\n';

  @override
  String get sessionMobileHint => '会话未建立 —— 点击底部「立即连接」建立 SSH 会话后即可使用终端。\n';

  @override
  String connectAuthTitle(String name) {
    return '连接「$name」';
  }

  @override
  String get authMemoryHint => '凭据用于本次连接；勾选「记住凭据」后加密保存，下次免输。';

  @override
  String get rememberCredentials => '记住凭据';

  @override
  String get fieldPrivateKey => '私钥内容（PEM）';

  @override
  String get privateKeyHint => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get fieldPassphrase => '私钥口令（可选）';

  @override
  String get credentialsRequired => '请输入密码或粘贴私钥';

  @override
  String connectingTo(String account) {
    return '正在连接 $account …';
  }

  @override
  String get sessionClosedMsg => '连接已断开';

  @override
  String get authFailedMsg => '认证失败，请检查密码或密钥';

  @override
  String get networkErrorMsg => '无法连接主机，请检查地址、端口与网络';

  @override
  String get webUnsupportedMsg => 'Web 端暂不支持 SSH 直连';

  @override
  String get hostKeyChangedMsg =>
      '主机密钥校验失败：服务器指纹与首次连接记录不一致，已拒绝连接。若确认服务器确实更换（如重装系统），可清除记录的指纹后重连；否则请警惕中间人攻击。';

  @override
  String get hostKeyForgetAndRetry => '清除记录的指纹并重连';

  @override
  String get reconnect => '重连';

  @override
  String get fieldName => '名称';

  @override
  String get nameHint => '例：web-prod-01';

  @override
  String get nameRequired => '请输入名称';

  @override
  String get fieldHost => '主机';

  @override
  String get hostHint => 'IP 或域名';

  @override
  String get hostRequired => '请输入主机';

  @override
  String get portInvalid => '1-65535';

  @override
  String get usernameHint => '例：root';

  @override
  String get usernameRequired => '请输入用户名';

  @override
  String get groupHint => '例：生产环境';

  @override
  String get navServers => '服务器';

  @override
  String get navKeys => '密钥';

  @override
  String get navSettings => '设置';

  @override
  String get search => '搜索';

  @override
  String get cancelSearch => '取消搜索';

  @override
  String get noHostsYet => '还没有主机';

  @override
  String get createFirstConnection => '点击右下角按钮新建一个连接';

  @override
  String get noHostsHint => '点击上方的 + 新建一个连接';

  @override
  String get tryAnotherKeyword => '换个关键词试试';

  @override
  String get keysComingSoon => '密钥管理即将推出';

  @override
  String get keysComingSoonHint => '将支持生成与导入 Ed25519 / RSA 密钥';

  @override
  String get noActiveSessions => '暂无活跃会话';

  @override
  String get sessionsEmptyHint => '在「服务器」页连接主机后，会话将在这里统一管理';

  @override
  String get appearance => '外观';

  @override
  String get theme => '主题';

  @override
  String get light => '浅色';

  @override
  String get dark => '深色';

  @override
  String get appFont => '界面字体';

  @override
  String get fontSystemDefault => '系统默认';

  @override
  String get fontMonospace => '等宽字体';

  @override
  String get terminalPreset => '终端主题';

  @override
  String get terminalFont => '终端字体';

  @override
  String get terminalFontSize => '终端字号';

  @override
  String get fontSizeDecrease => '减小字号';

  @override
  String get fontSizeIncrease => '增大字号';

  @override
  String get fontCustom => '自定义字体…';

  @override
  String get terminalFontCustomName => '字体名';

  @override
  String get terminalFontCustomHint => '例如 Fira Code、Sarasa Mono SC';

  @override
  String get presetDefaultDark => '默认深色';

  @override
  String get biometricLock => '生物识别锁定';

  @override
  String get comingSoon => '即将推出';

  @override
  String get settingsSubtitle => '主题、终端与语言';

  @override
  String get appearanceHint => '界面主题与字体';

  @override
  String get terminalSectionHint => '终端使用的配色、字体与字号';

  @override
  String get languageHint => '界面语言；跟随系统时按系统语言匹配';

  @override
  String get terminalPreview => '预览';

  @override
  String get terminalPreviewCommand => 'ssh deploy@10.0.0.1';

  @override
  String get settingsApplyHint => '更改即时生效';

  @override
  String get done => '完成';

  @override
  String get sftpSessionHint => '会话未建立 —— 点击右上角「连接」建立 SSH 会话后即可浏览服务器文件。\n';

  @override
  String get sftpSessionMobileHint =>
      '会话未建立 —— 点击底部「立即连接」建立 SSH 会话后即可浏览服务器文件。\n';

  @override
  String get sftpRetry => '重试';

  @override
  String get sftpUp => '上级目录';

  @override
  String get sftpRefresh => '刷新';

  @override
  String get sftpUpload => '上传';

  @override
  String get sftpDownload => '下载';

  @override
  String get sftpNewFolder => '新建文件夹';

  @override
  String get sftpEditPath => '编辑路径';

  @override
  String get sftpPathHint => '远端路径';

  @override
  String get sftpFilter => '筛选';

  @override
  String get sftpFilterHint => '在当前目录中筛选…';

  @override
  String get sftpShowHidden => '显示隐藏文件';

  @override
  String get sftpHideHidden => '隐藏隐藏文件';

  @override
  String get sftpSortBy => '排序方式';

  @override
  String get sftpSortName => '名称';

  @override
  String get sftpSortSize => '大小';

  @override
  String get sftpSortModified => '修改时间';

  @override
  String get sftpSortAscending => '升序';

  @override
  String get sftpSortDescending => '降序';

  @override
  String get sftpCopyPath => '复制路径';

  @override
  String get sftpRename => '重命名';

  @override
  String get sftpColumnName => '名称';

  @override
  String get sftpColumnSize => '大小';

  @override
  String get sftpColumnModified => '修改时间';

  @override
  String get sftpColumnPermissions => '权限';

  @override
  String sftpItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 项',
    );
    return '$_temp0';
  }

  @override
  String sftpSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已选 $count 项',
    );
    return '$_temp0';
  }

  @override
  String sftpTotalSize(String size) {
    return '共 $size';
  }

  @override
  String get sftpFolderEmpty => '此目录为空';

  @override
  String get sftpFolderEmptyHint => '点击「上传」把本地文件传到这个目录';

  @override
  String get sftpNoMatches => '没有匹配的条目';

  @override
  String get sftpNewFolderTitle => '新建文件夹';

  @override
  String get sftpFolderNameField => '文件夹名称';

  @override
  String sftpRenameTitle(String name) {
    return '重命名「$name」';
  }

  @override
  String get sftpNameInvalid => '名称不能包含「/」或「..」';

  @override
  String sftpDeleteTitle(String name) {
    return '删除「$name」？';
  }

  @override
  String sftpDeleteMultiTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '删除这 $count 个条目？',
    );
    return '$_temp0';
  }

  @override
  String get sftpDeleteFileBody => '删除后无法恢复。';

  @override
  String get sftpDeleteFolderBody => '该目录及其中的全部内容都会被删除，且无法恢复。';

  @override
  String get sftpOverwriteTitle => '文件已存在';

  @override
  String sftpOverwriteBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '该目录中已有 $count 个同名文件，是否覆盖？',
    );
    return '$_temp0';
  }

  @override
  String get sftpOverwrite => '覆盖';

  @override
  String get sftpTransfersTitle => '传输';

  @override
  String get sftpClearFinished => '清除已完成';

  @override
  String get sftpCanceled => '已取消';

  @override
  String get sftpDone => '已完成';

  @override
  String get sftpFailed => '失败';

  @override
  String sftpRemaining(String time) {
    return '剩余 $time';
  }

  @override
  String sftpUploaded(String name) {
    return '已上传 $name';
  }

  @override
  String sftpDownloaded(String name) {
    return '已保存 $name';
  }

  @override
  String sftpUploadFailed(String name) {
    return '上传失败：$name';
  }

  @override
  String sftpDownloadFailed(String name) {
    return '下载失败：$name';
  }

  @override
  String sftpTransferCanceledMsg(String name) {
    return '已取消 $name';
  }

  @override
  String get sftpPickerFailed => '无法打开文件选择器';

  @override
  String get sftpTargetUnavailable => '无法确定本地保存位置';

  @override
  String get sftpErrorPermission => '没有权限访问该位置';

  @override
  String get sftpErrorNotFound => '路径不存在';

  @override
  String get sftpErrorUnsupported => '当前连接不支持 SFTP';

  @override
  String get sftpErrorNetwork => '连接已断开';

  @override
  String get sftpErrorOther => '操作失败';

  @override
  String get neverConnected => '从未连接';

  @override
  String get justNow => '刚刚';

  @override
  String minutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 分钟前',
    );
    return '$_temp0';
  }

  @override
  String hoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 小时前',
    );
    return '$_temp0';
  }

  @override
  String daysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 天前',
    );
    return '$_temp0';
  }

  @override
  String get importHosts => '导入主机';

  @override
  String get exportHosts => '导出主机';

  @override
  String get importExportHosts => '导入 / 导出主机';

  @override
  String importDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已导入 $count 台主机',
    );
    return '$_temp0';
  }

  @override
  String importSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已跳过 $count 台重复主机',
    );
    return '$_temp0';
  }

  @override
  String get importEmpty => '未识别到有效主机条目，请检查文件格式';

  @override
  String exportDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已导出 $count 台主机',
    );
    return '$_temp0';
  }

  @override
  String get exportEmpty => '没有可导出的主机';

  @override
  String get exportFailed => '导出失败，请重试';
}
