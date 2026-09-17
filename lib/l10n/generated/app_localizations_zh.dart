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
  String get authAgent => 'Agent';

  @override
  String get agentAuthHint =>
      '使用本机 SSH agent 里的密钥认证（macOS / Linux）。请先 ssh-add 装入密钥，agent 未运行或没有密钥时会连接失败。';

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
      '名称: serverName\n地址: 127.0.0.1\n端口: 22\n用户: root\n密码: password';

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
  String get credentialsSaveFailedMsg =>
      '凭据保存失败：本次连接不受影响，但下次连接需要重新输入。请检查系统钥匙串权限。';

  @override
  String get agentErrorMsg =>
      '无法使用本机 SSH agent：请确认 agent 正在运行且已装入密钥（ssh-add），必要时重新加载后重试。';

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
  String get groupNew => '新建分组';

  @override
  String get groupRename => '重命名分组';

  @override
  String get groupDelete => '删除分组';

  @override
  String groupDeleteConfirm(String name) {
    return '删除分组「$name」？';
  }

  @override
  String get groupDeleteEmptyBody => '该分组下还没有主机。';

  @override
  String groupDeleteBody(int count, String target) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '其中 $count 台主机将移到「$target」。',
    );
    return '$_temp0';
  }

  @override
  String get groupMoveUp => '上移分组';

  @override
  String get groupMoveDown => '下移分组';

  @override
  String get groupNewConnection => '在此分组新建连接';

  @override
  String get groupMoveTo => '移动到分组…';

  @override
  String groupMoveTitle(String name) {
    return '移动「$name」到';
  }

  @override
  String get groupCreateFirst => '还没有其它分组，先新建一个';

  @override
  String get groupKeepOne => '至少保留一个分组';

  @override
  String get groupNameRequired => '请填写分组名';

  @override
  String get groupNameExists => '同名分组已存在';

  @override
  String get navServers => '服务器';

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
  String get fontSystemMonospace => '系统等宽';

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
  String get presetDefaultDark => '默认深色';

  @override
  String get settingsSubtitle => '主题、终端与语言';

  @override
  String get terminalPreview => '预览';

  @override
  String get terminalPreviewCommand => 'ssh deploy@10.0.0.1';

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
  String get sftpCanceling => '正在取消…';

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
  String get sftpErrorBusy => '上一个文件操作还没结束';

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

  @override
  String get backupCreateTitle => '设置备份口令';

  @override
  String get backupCreateHint => '整份清单都用这个口令加密，其中包含已记住的密码。恢复备份时需要输入该口令，且无法找回。';

  @override
  String get backupOpenTitle => '输入备份口令';

  @override
  String get backupOpenHint => '请输入创建这份备份时设置的口令。';

  @override
  String get backupPassword => '备份口令';

  @override
  String get backupPasswordConfirm => '再次输入口令';

  @override
  String get backupPasswordRequired => '请输入备份口令';

  @override
  String get backupPasswordMismatch => '两次输入的口令不一致';

  @override
  String get backupPasswordWarning => '没有这个口令就无法恢复备份，请妥善保管。';

  @override
  String get backupCreateConfirm => '导出';

  @override
  String get backupOpenConfirm => '导入';

  @override
  String get backupWrongPassword => '备份口令不正确，未导入任何主机';

  @override
  String get backupUnreadable => '无法读取该文件，请确认它是主机备份';

  @override
  String get connectionSection => '连接';

  @override
  String get allowLegacyHostKeys => '允许连接旧式 ssh-rsa 主机';

  @override
  String get allowLegacyHostKeysHint =>
      '仅用于只提供 ssh-rsa（SHA-1）主机密钥的老设备，例如交换机与嵌入式设备。现代服务器不受影响。';

  @override
  String get archiveUnreadableTitle => '已保存的主机列表读不出来';

  @override
  String get archiveUnreadableHint =>
      '磁盘上的存档解析失败，已原样保留、未被覆盖；本次会话的改动不会落盘。可导入一份 .nsbak 备份把主机找回来。';

  @override
  String hostKeyChangedMsgWithFingerprint(String keyType, String fingerprint) {
    return '主机密钥校验失败：服务器出示的是 $keyType $fingerprint，与首次连接时记录的不一致。若服务器确实是重建过，可清除记录的指纹后重连；否则请警惕中间人攻击。';
  }

  @override
  String get hostKeyUnavailableMsg =>
      '已记录的主机密钥指纹读不出来，连接被拒绝。这是本地存储故障、不是密钥变更，原有记录未被改动。';

  @override
  String get privateKeyUnsupportedMsg =>
      '不支持这份私钥的格式。请粘贴 OpenSSH 或 PEM（RSA / EC）格式的私钥——以 \"BEGIN PRIVATE KEY\" 开头的 PKCS#8 密钥需要先转换。';

  @override
  String get portForwarding => '端口转发';

  @override
  String get portForwardEmpty => '还没有转发规则';

  @override
  String get portForwardEmptyHint => '新建一条规则，连接主机后即可启停。';

  @override
  String get portForwardAdd => '新建转发';

  @override
  String get portForwardEdit => '编辑转发';

  @override
  String get portForwardDeleteTitle => '删除这条转发？';

  @override
  String get portForwardDeleteBody => '只删除这条规则，其它已经在跑的转发不受影响。';

  @override
  String get portForwardStart => '启动';

  @override
  String get portForwardStop => '停止';

  @override
  String get portForwardStatusStarting => '启动中';

  @override
  String get portForwardStatusRunning => '运行中';

  @override
  String get portForwardStatusStopped => '未启动';

  @override
  String get portForwardStatusFailed => '启动失败';

  @override
  String get portForwardSessionHint => '会话未建立 —— 先连接主机，才能启停端口转发。';

  @override
  String get portForwardAutoTag => '自动';

  @override
  String portForwardSummaryLocal(String listen, String target) {
    return '$listen → $target（经服务器）';
  }

  @override
  String portForwardSummaryRemote(String listen, String target) {
    return '服务器 $listen → 本机 $target';
  }

  @override
  String portForwardSummaryDynamic(String listen) {
    return 'SOCKS5 代理 $listen';
  }

  @override
  String portForwardBoundPort(int port) {
    return '实际端口 $port';
  }

  @override
  String get portForwardErrorNotConnected => '会话未建立，转发没有启动';

  @override
  String get portForwardErrorUnsupported => '当前平台不支持端口转发（浏览器没有原生 TCP）';

  @override
  String get portForwardErrorRefused => '服务端拒绝了这条转发（端口被占用或不允许监听）';

  @override
  String get portForwardErrorNetwork => '网络中断，转发没有启动';

  @override
  String get portForwardErrorOther => '转发没有启动';

  @override
  String get portForwardRuleIncomplete => '规则没填完整：请补全地址与端口';

  @override
  String get portForwardMode => '转发类型';

  @override
  String get portForwardModeLocal => '本地转发 (-L)';

  @override
  String get portForwardModeRemote => '远程转发 (-R)';

  @override
  String get portForwardModeDynamic => '动态转发 (-D)';

  @override
  String get portForwardLocalDesc => '本机监听，连接经服务器转给目标地址';

  @override
  String get portForwardRemoteDesc => '让服务器监听，连接转回本机地址';

  @override
  String get portForwardDynamicDesc => '本机开一个 SOCKS5 代理，目标由客户端逐次指定';

  @override
  String get portForwardListenAddress => '监听地址';

  @override
  String get portForwardListenPort => '监听端口';

  @override
  String get portForwardTargetAddress => '目标地址';

  @override
  String get portForwardTargetPort => '目标端口';

  @override
  String get portForwardAutoStart => '连接后自动启动';

  @override
  String get portForwardAutoStartHint => '自动启动需要已记住凭据，否则连接时会先弹凭据框。';

  @override
  String get portForwardAddressRequired => '请填写地址';

  @override
  String get jumpHost => '跳板机';

  @override
  String get jumpHostNone => '不使用';

  @override
  String get jumpHostHint => '先登录它，再由它连到本机';

  @override
  String jumpCredentialsHint(String name) {
    return '这是跳板机「$name」的凭据，用于先登录它。';
  }

  @override
  String jumpHostMissing(String name) {
    return '「$name」的跳板机已被删除，请在主机设置里重新选择';
  }

  @override
  String jumpHostCycle(String name) {
    return '「$name」的跳板机形成了环，请在主机设置里重新选择';
  }

  @override
  String jumpHostTooDeep(int count) {
    return '跳板机层数超过上限（$count 层）';
  }

  @override
  String get jumpChainErrorMsg => '跳板机配置不成立，请在主机设置里检查';

  @override
  String jumpHopFailure(String hop, String reason) {
    return '经跳板机「$hop」时失败：$reason';
  }

  @override
  String get jumpHostUnavailable => '已失效（跳板机被删除，或会形成环）';
}
