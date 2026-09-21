// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'NoShell';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get connect => 'Connect';

  @override
  String get disconnect => 'Disconnect';

  @override
  String get disconnectAll => 'Disconnect all';

  @override
  String get connectNow => 'Connect now';

  @override
  String get newSession => 'New session';

  @override
  String sessionN(int n) {
    return 'Session $n';
  }

  @override
  String get closeSession => 'Close session';

  @override
  String get sessionMenu => 'Switch session';

  @override
  String statusWithCount(String status, int count) {
    return '$status · $count';
  }

  @override
  String get newConnection => 'New connection';

  @override
  String get editConnection => 'Edit connection';

  @override
  String get defaultGroupName => 'Default group';

  @override
  String get undo => 'Undo';

  @override
  String deletedSnackbar(String name) {
    return 'Deleted $name';
  }

  @override
  String deleteConfirmTitle(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get deleteConfirmBody =>
      'This host will be removed and cannot be recovered.';

  @override
  String get hostNotFound => 'Host not found';

  @override
  String get language => 'Language';

  @override
  String get followSystem => 'System';

  @override
  String get statusConnected => 'Connected';

  @override
  String get statusConnecting => 'Connecting';

  @override
  String get statusError => 'Failed';

  @override
  String get statusIdle => 'Not connected';

  @override
  String hostCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hosts',
      one: '1 host',
    );
    return '$_temp0';
  }

  @override
  String collapseSidebar(String shortcut) {
    return 'Collapse sidebar ($shortcut)';
  }

  @override
  String expandSidebar(String shortcut) {
    return 'Expand sidebar ($shortcut)';
  }

  @override
  String get windowMinimize => 'Minimize';

  @override
  String get windowMaximize => 'Maximize';

  @override
  String get windowRestore => 'Restore';

  @override
  String get windowClose => 'Close';

  @override
  String get searchHint => 'Search name, host, or tag…';

  @override
  String get noMatchingHosts => 'No matching hosts';

  @override
  String get about => 'About';

  @override
  String get selectHostToStart => 'Select a host to get started';

  @override
  String get emptyDetailHint =>
      'Pick a host from the sidebar to view its details, or create a new connection.';

  @override
  String get overview => 'Overview';

  @override
  String get terminal => 'Terminal';

  @override
  String get sftp => 'SFTP';

  @override
  String get moreActions => 'More actions';

  @override
  String get hostAddress => 'Host address';

  @override
  String get copyAddress => 'Copy address';

  @override
  String get copyHostInfo => 'Copy host info';

  @override
  String get copy => 'Copy';

  @override
  String copied(String value) {
    return 'Copied $value';
  }

  @override
  String get port => 'Port';

  @override
  String get username => 'Username';

  @override
  String get authMethod => 'Authentication';

  @override
  String get authPassword => 'Password';

  @override
  String get authKey => 'SSH key';

  @override
  String get authAgent => 'Agent';

  @override
  String get agentAuthHint =>
      'Use a key from your local SSH agent; load it with ssh-add first.';

  @override
  String get lastConnected => 'Last connected';

  @override
  String get group => 'Group';

  @override
  String get notes => 'Notes';

  @override
  String get notesOptional => 'Notes (optional)';

  @override
  String get pasteMetadata => 'Paste metadata (optional)';

  @override
  String get pasteMetadataHint =>
      'name: serverName\nhost: 127.0.0.1\nport: 22\nuser: root\npassword: password';

  @override
  String get sessionDesktopHint =>
      'No session yet — double-click a host in the sidebar or click \"Connect\" at the top right to start an SSH session and use the terminal.\n';

  @override
  String get sessionMobileHint =>
      'No session yet — tap \"Connect now\" at the bottom to start an SSH session and use the terminal.\n';

  @override
  String connectAuthTitle(String name) {
    return 'Connect to \"$name\"';
  }

  @override
  String get rememberCredentials => 'Remember credentials';

  @override
  String get fieldPrivateKey => 'Private key (PEM)';

  @override
  String get privateKeyHint => '-----BEGIN OPENSSH PRIVATE KEY-----';

  @override
  String get pickKeyFile => 'Choose key file';

  @override
  String get pickKeyFileFailedMsg => 'Could not read the selected key file.';

  @override
  String get pickKeyFileFailedHelp =>
      'Open the key file in a file manager, copy all of its contents, and paste them into the field above.';

  @override
  String get pickKeyFileFailedAndroidHelp =>
      'Xiaomi HyperOS\'s Secure Access picker filters by file type, so it may hide key files that have no extension (such as id_rsa). Rename the key to add a .txt suffix and choose it again, or open it in a file manager, copy its contents, and paste them above. NoShell only reads the one file you choose; it does not ask for access to all of your storage.';

  @override
  String get rememberedCredentials => 'Remembered credentials';

  @override
  String credentialRememberedKind(String kind) {
    return 'Remembered: $kind';
  }

  @override
  String get noRememberedCredential => 'No credentials remembered';

  @override
  String credentialRememberOnSave(String kind) {
    return 'Will remember: $kind';
  }

  @override
  String get credentialClearOnSave => 'Credentials will be cleared on save';

  @override
  String get replaceCredential => 'Replace…';

  @override
  String get rememberCredential => 'Remember…';

  @override
  String get clearStoredCredential => 'Clear';

  @override
  String credentialsDialogTitle(String name) {
    return 'Credentials for \"$name\"';
  }

  @override
  String get credentialsDialogHint =>
      'Saved encrypted and reused automatically.';

  @override
  String get fieldPassphrase => 'Key passphrase (optional)';

  @override
  String get credentialsRequired => 'Please enter a password or paste a key';

  @override
  String connectingTo(String account) {
    return 'Connecting to $account…';
  }

  @override
  String get sessionClosedMsg => 'Session closed';

  @override
  String get authFailedMsg =>
      'Authentication failed — check your password or key';

  @override
  String get credentialsSaveFailedMsg =>
      'Failed to save credentials — this connection is unaffected, but you\'ll need to enter them again next time. Check the system keychain settings.';

  @override
  String get agentErrorMsg =>
      'Cannot use the local SSH agent — make sure it is running and your key is loaded (ssh-add), then retry.';

  @override
  String get networkErrorMsg =>
      'Cannot reach host — check address, port and network';

  @override
  String get webUnsupportedMsg =>
      'SSH connections are not supported on web yet';

  @override
  String get hostKeyChangedMsg =>
      'Host key verification failed — the server\'s fingerprint no longer matches the one recorded at first connection, so the connection was refused. If the server was rebuilt on purpose, forget the recorded fingerprint and reconnect; otherwise beware of a man-in-the-middle attack.';

  @override
  String get hostKeyForgetAndRetry => 'Forget fingerprint and reconnect';

  @override
  String get hostKeyForgetConfirmTitle => 'Forget this host key?';

  @override
  String hostKeyForgetConfirmBody(String host) {
    return 'After forgetting, the next connection will trust whatever key $host presents. Only do this if you have verified the new fingerprint out of band — a mismatched fingerprint can also mean someone is intercepting this connection.';
  }

  @override
  String get hostKeyForgetConfirmAction => 'Forget and reconnect';

  @override
  String get reconnect => 'Reconnect';

  @override
  String get fieldName => 'Name';

  @override
  String get nameHint => 'name';

  @override
  String get nameRequired => 'Please enter a name';

  @override
  String get fieldHost => 'Host';

  @override
  String get hostHint => 'IP or domain';

  @override
  String get hostRequired => 'Please enter a host';

  @override
  String get portInvalid => '1-65535';

  @override
  String get usernameHint => 'username';

  @override
  String get usernameRequired => 'Please enter a username';

  @override
  String get groupHint => 'group';

  @override
  String get groupNew => 'New group';

  @override
  String get groupRename => 'Rename group';

  @override
  String get groupDelete => 'Delete group';

  @override
  String groupDeleteConfirm(String name) {
    return 'Delete group \"$name\"?';
  }

  @override
  String get groupDeleteEmptyBody => 'This group has no hosts.';

  @override
  String groupDeleteBody(int count, String target) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Its $count hosts will move to \"$target\".',
      one: 'Its 1 host will move to \"$target\".',
    );
    return '$_temp0';
  }

  @override
  String get groupMoveUp => 'Move group up';

  @override
  String get groupMoveDown => 'Move group down';

  @override
  String get groupNewConnection => 'New connection in this group';

  @override
  String get groupMoveTo => 'Move to group…';

  @override
  String groupMoveTitle(String name) {
    return 'Move \"$name\" to';
  }

  @override
  String get groupCreateFirst => 'No other group yet — create one first';

  @override
  String get groupKeepOne => 'Keep at least one group';

  @override
  String get groupNameRequired => 'Enter a group name';

  @override
  String get groupNameExists => 'A group with this name already exists';

  @override
  String get navServers => 'Servers';

  @override
  String get navSettings => 'Settings';

  @override
  String get search => 'Search';

  @override
  String get cancelSearch => 'Cancel search';

  @override
  String get noHostsYet => 'No hosts yet';

  @override
  String get createFirstConnection =>
      'Tap the button below to create a connection';

  @override
  String get noHostsHint => 'Create one with the + button above';

  @override
  String get tryAnotherKeyword => 'Try a different keyword';

  @override
  String get noActiveSessions => 'No active sessions';

  @override
  String get sessionsEmptyHint =>
      'Connect to a host on the Servers tab and sessions will show up here';

  @override
  String get appearance => 'Appearance';

  @override
  String get theme => 'Theme';

  @override
  String get light => 'Light';

  @override
  String get dark => 'Dark';

  @override
  String get fontSystemMonospace => 'System monospace';

  @override
  String get terminalPreset => 'Terminal theme';

  @override
  String get terminalFont => 'Terminal font';

  @override
  String get terminalFontSize => 'Terminal font size';

  @override
  String get fontSizeDecrease => 'Decrease font size';

  @override
  String get fontSizeIncrease => 'Increase font size';

  @override
  String get presetDefaultDark => 'Default dark';

  @override
  String get terminalPreview => 'Preview';

  @override
  String get terminalPreviewCommand => 'ssh deploy@10.0.0.1';

  @override
  String get done => 'Done';

  @override
  String get sftpSessionHint =>
      'No session yet — click \"Connect\" at the top right to browse the server files.\n';

  @override
  String get sftpSessionMobileHint =>
      'No session yet — tap \"Connect now\" below to browse the server files.\n';

  @override
  String get sftpRetry => 'Retry';

  @override
  String get sftpUp => 'Parent folder';

  @override
  String get sftpRefresh => 'Refresh';

  @override
  String get sftpUpload => 'Upload';

  @override
  String get sftpDownload => 'Download';

  @override
  String get sftpNewFolder => 'New folder';

  @override
  String get sftpEditPath => 'Edit path';

  @override
  String get sftpPathHint => 'Remote path';

  @override
  String get sftpFilter => 'Filter';

  @override
  String get sftpFilterHint => 'Filter in this folder…';

  @override
  String get sftpShowHidden => 'Show hidden files';

  @override
  String get sftpHideHidden => 'Hide hidden files';

  @override
  String get sftpSortBy => 'Sort by';

  @override
  String get sftpSortName => 'Name';

  @override
  String get sftpSortSize => 'Size';

  @override
  String get sftpSortModified => 'Modified';

  @override
  String get sftpCopyPath => 'Copy path';

  @override
  String get sftpRename => 'Rename';

  @override
  String get sftpColumnName => 'Name';

  @override
  String get sftpColumnSize => 'Size';

  @override
  String get sftpColumnModified => 'Modified';

  @override
  String get sftpColumnPermissions => 'Permissions';

  @override
  String sftpItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String sftpSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selected',
      one: '1 selected',
    );
    return '$_temp0';
  }

  @override
  String sftpTotalSize(String size) {
    return '$size total';
  }

  @override
  String get sftpFolderEmpty => 'This folder is empty';

  @override
  String get sftpFolderEmptyHint => 'Use Upload to send local files here';

  @override
  String get sftpNoMatches => 'No matching items';

  @override
  String get sftpNewFolderTitle => 'New folder';

  @override
  String get sftpFolderNameField => 'Folder name';

  @override
  String sftpRenameTitle(String name) {
    return 'Rename \"$name\"';
  }

  @override
  String get sftpNameInvalid => 'Name cannot contain \"/\" or \"..\"';

  @override
  String sftpDeleteTitle(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String sftpDeleteMultiTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete these $count items?',
      one: 'Delete this item?',
    );
    return '$_temp0';
  }

  @override
  String get sftpDeleteFileBody => 'Deleted files cannot be recovered.';

  @override
  String get sftpDeleteFolderBody =>
      'The folder and everything inside it will be deleted, and cannot be recovered.';

  @override
  String get sftpOverwriteTitle => 'File already exists';

  @override
  String sftpOverwriteBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count files with the same name already exist here. Overwrite them?',
      one: '1 file with the same name already exists here. Overwrite it?',
    );
    return '$_temp0';
  }

  @override
  String get sftpOverwrite => 'Overwrite';

  @override
  String get sftpTransfersTitle => 'Transfers';

  @override
  String get sftpClearFinished => 'Clear finished';

  @override
  String get sftpCanceling => 'Canceling…';

  @override
  String get sftpCanceled => 'Canceled';

  @override
  String get sftpDone => 'Done';

  @override
  String sftpRemaining(String time) {
    return '$time left';
  }

  @override
  String sftpUploaded(String name) {
    return 'Uploaded $name';
  }

  @override
  String sftpDownloaded(String name) {
    return 'Saved $name';
  }

  @override
  String sftpUploadFailed(String name) {
    return 'Upload failed: $name';
  }

  @override
  String sftpDownloadFailed(String name) {
    return 'Download failed: $name';
  }

  @override
  String sftpTransferCanceledMsg(String name) {
    return 'Canceled $name';
  }

  @override
  String get sftpPickerFailed => 'Cannot open the file picker';

  @override
  String get sftpTargetUnavailable => 'Cannot determine where to save the file';

  @override
  String get sftpErrorPermission => 'Permission denied';

  @override
  String get sftpErrorNotFound => 'Path not found';

  @override
  String get sftpErrorUnsupported => 'This connection does not support SFTP';

  @override
  String get sftpErrorNetwork => 'Connection lost';

  @override
  String get sftpErrorBusy => 'Another file operation is still running';

  @override
  String get sftpErrorOther => 'Operation failed';

  @override
  String get neverConnected => 'Never connected';

  @override
  String get justNow => 'Just now';

  @override
  String minutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes ago',
      one: '1 minute ago',
    );
    return '$_temp0';
  }

  @override
  String hoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours ago',
      one: '1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String daysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String get importHosts => 'Import hosts';

  @override
  String get exportHosts => 'Export hosts';

  @override
  String get importExportHosts => 'Import / export hosts';

  @override
  String importDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hosts imported',
      one: '1 host imported',
    );
    return '$_temp0';
  }

  @override
  String importSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count duplicates skipped',
      one: '1 duplicate skipped',
    );
    return '$_temp0';
  }

  @override
  String get importEmpty =>
      'No valid host entries found. Please check the file format.';

  @override
  String exportDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hosts exported',
      one: '1 host exported',
    );
    return '$_temp0';
  }

  @override
  String get exportEmpty => 'No hosts to export';

  @override
  String get exportFailed => 'Export failed. Please try again.';

  @override
  String get backupCreateTitle => 'Set a backup password';

  @override
  String get backupCreateHint =>
      'The whole list is encrypted with this password, saved passwords included. You will need it to restore the backup, and it cannot be recovered.';

  @override
  String get backupOpenTitle => 'Enter the backup password';

  @override
  String get backupOpenHint =>
      'Enter the password that was set when this backup was created.';

  @override
  String get backupPassword => 'Backup password';

  @override
  String get backupPasswordConfirm => 'Repeat password';

  @override
  String get backupPasswordRequired => 'Please enter a backup password';

  @override
  String get backupPasswordMismatch => 'The two passwords do not match';

  @override
  String get backupPasswordWarning =>
      'Lose the password and the backup cannot be restored.';

  @override
  String get backupCreateConfirm => 'Export';

  @override
  String get backupOpenConfirm => 'Import';

  @override
  String get backupWrongPassword =>
      'Wrong backup password, nothing was imported';

  @override
  String get backupUnreadable => 'This file cannot be read as a host backup';

  @override
  String get connectionSection => 'Connection';

  @override
  String get allowLegacyHostKeysHint =>
      'Only needed by old gear (switches and the like) that offers nothing but an ssh-rsa (SHA-1) host key.';

  @override
  String get archiveUnreadableTitle => 'Saved host list could not be read';

  @override
  String get archiveUnreadableHint =>
      'The saved data is unreadable and has been left untouched; changes in this session are not saved. Re-import a .nsbak backup to recover.';

  @override
  String hostKeyChangedMsgWithFingerprint(String keyType, String fingerprint) {
    return 'Host key verification failed — the server presented $keyType $fingerprint, which does not match what was recorded at first connection. If the server was rebuilt on purpose, forget the recorded fingerprint and reconnect; otherwise beware of a man-in-the-middle attack.';
  }

  @override
  String get hostKeyUnavailableMsg =>
      'Could not read the recorded host key fingerprint, so the connection was refused. This is a local storage problem, not a key change — your recorded fingerprint has been left untouched.';

  @override
  String get privateKeyUnsupportedMsg =>
      'This private key format is not supported. Paste a key in OpenSSH or PEM (RSA/EC) format — a PKCS#8 key starting with \"BEGIN PRIVATE KEY\" must be converted first.';

  @override
  String get portForwarding => 'Port forwarding';

  @override
  String get portForwardEmpty => 'No port forwards yet';

  @override
  String get portForwardEmptyHint =>
      'Create a rule, then start it while the host is connected.';

  @override
  String get portForwardAdd => 'New forward';

  @override
  String get portForwardEdit => 'Edit forward';

  @override
  String get portForwardDeleteTitle => 'Delete this port forward?';

  @override
  String get portForwardDeleteBody =>
      'Only this rule is removed; other running forwards are untouched.';

  @override
  String get portForwardStatusStarting => 'Starting';

  @override
  String get portForwardStatusRunning => 'Running';

  @override
  String get portForwardStatusStopped => 'Stopped';

  @override
  String get portForwardStatusFailed => 'Failed';

  @override
  String get portForwardSessionHint =>
      'No session yet — connect to the host to start or stop port forwards.';

  @override
  String get portForwardAutoTag => 'Auto';

  @override
  String portForwardSummaryLocal(String listen, String target) {
    return '$listen → $target (via server)';
  }

  @override
  String portForwardSummaryRemote(String listen, String target) {
    return 'Server $listen → local $target';
  }

  @override
  String portForwardSummaryDynamic(String listen) {
    return 'SOCKS5 proxy $listen';
  }

  @override
  String portForwardBoundPort(int port) {
    return 'Bound to port $port';
  }

  @override
  String get portForwardErrorNotConnected =>
      'No session, so the forward was not started';

  @override
  String get portForwardErrorUnsupported =>
      'Port forwarding is not available on this platform (the browser has no raw TCP)';

  @override
  String get portForwardErrorRefused =>
      'The server refused this forward (port in use, or listening is not permitted)';

  @override
  String get portForwardErrorNetwork =>
      'The network dropped, so the forward was not started';

  @override
  String get portForwardErrorOther => 'The forward was not started';

  @override
  String get portForwardModeLocal => 'Local (-L)';

  @override
  String get portForwardModeRemote => 'Remote (-R)';

  @override
  String get portForwardModeDynamic => 'Dynamic (-D)';

  @override
  String get portForwardLocalDesc =>
      'Listen locally, reach the target through the server';

  @override
  String get portForwardRemoteDesc =>
      'Let the server listen, reach a local address';

  @override
  String get portForwardDynamicDesc =>
      'Run a local SOCKS5 proxy; clients choose the target';

  @override
  String get portForwardListenAddress => 'Listen address';

  @override
  String get portForwardListenPort => 'Listen port';

  @override
  String get portForwardTargetAddress => 'Target address';

  @override
  String get portForwardTargetPort => 'Target port';

  @override
  String get portForwardAutoStart => 'Start automatically on connect';

  @override
  String get portForwardAutoStartHint =>
      'Auto start needs saved credentials; otherwise you will be asked for them on connect.';

  @override
  String get portForwardAddressRequired => 'Please enter an address';

  @override
  String get portForwardExposeWarning =>
      'The listen address is not a loopback address: anyone on the same network can reach this tunnel (for dynamic forwarding that means an unauthenticated proxy).';

  @override
  String get portForwardExposeTitle =>
      'This forward will be exposed to the network';

  @override
  String portForwardExposeBody(String host) {
    return 'Listen address $host is not a loopback address — anyone on the same network can connect to it. Save anyway?';
  }

  @override
  String get portForwardExposeConfirm => 'Save anyway';

  @override
  String get jumpHost => 'Jump host';

  @override
  String get jumpHostNone => 'None';

  @override
  String get jumpHostHint =>
      'Log in to it first, then reach this host through it';

  @override
  String jumpCredentialsHint(String name) {
    return 'These credentials are for the jump host “$name”, used to log in to it first.';
  }

  @override
  String jumpHostMissing(String name) {
    return 'The jump host of “$name” no longer exists — pick another one in the host settings';
  }

  @override
  String jumpHostCycle(String name) {
    return 'The jump host of “$name” forms a loop — fix it in the host settings';
  }

  @override
  String jumpHostTooDeep(int count) {
    return 'Too many jump hosts in the chain (limit is $count)';
  }

  @override
  String get jumpChainErrorMsg =>
      'The jump host chain is not usable — check it in the host settings';

  @override
  String jumpHopFailure(String hop, String reason) {
    return 'Failed through jump host “$hop”: $reason';
  }

  @override
  String get jumpHostUnavailable =>
      'Unavailable (deleted, or would form a loop)';

  @override
  String get sessionLog => 'Session log';

  @override
  String get sessionLogHint =>
      'A plain-text snapshot of the terminal screen and its scrollback — colors and control sequences are stripped. Content wiped by clear or by a full-screen app is not included; passwords typed at hidden prompts are not echoed by the server, so they never enter the log.';

  @override
  String get sessionLogEmpty =>
      'Nothing logged yet — output will appear here as the session runs.';

  @override
  String get sessionLogSave => 'Save log';

  @override
  String sessionLogSaved(String name) {
    return 'Log saved: $name';
  }

  @override
  String get sessionLogSaveFailed =>
      'Failed to save the log. Please try again.';

  @override
  String get sessionLogCopied => 'Log copied to clipboard';

  @override
  String get snippets => 'Snippets';

  @override
  String get snippetsHint => 'Tap a snippet to run it in this session.';

  @override
  String get snippetNew => 'New snippet';

  @override
  String get snippetEdit => 'Edit snippet';

  @override
  String get snippetName => 'Name';

  @override
  String get snippetNameRequired => 'Please enter a name';

  @override
  String get snippetCommand => 'Command';

  @override
  String get snippetCommandRequired => 'Please enter a command';

  @override
  String get snippetCommandHint => 'Sent as-is, followed by Enter.';

  @override
  String get snippetEmpty => 'No snippets yet';

  @override
  String get snippetEmptyHint =>
      'Save commands you run often and fire them with one tap.';

  @override
  String snippetDeleteTitle(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get snippetDeleteBody => 'This snippet will be removed.';

  @override
  String autoReconnectCountdown(int seconds, int attempt) {
    return 'Reconnecting automatically in $seconds s (attempt $attempt)';
  }

  @override
  String get autoReconnectStop => 'Stop auto reconnect';

  @override
  String get paste => 'Paste';

  @override
  String get selectAll => 'Select All';

  @override
  String get copyOnSelect => 'Copy on Select';

  @override
  String get linkOpenFailed => 'Could not open link';

  @override
  String get openLink => 'Open Link';

  @override
  String get scrollToBottom => 'Jump to latest';

  @override
  String get keyBarTitle => 'Keys';

  @override
  String get keyBarExpand => 'Show key bar';

  @override
  String get keyBarCollapse => 'Hide key bar';

  @override
  String stickyModifierHint(String modifier) {
    return '$modifier armed · applies to the next key';
  }

  @override
  String get updateSection => 'Updates';

  @override
  String get updateRowTitle => 'Check for updates';

  @override
  String updateRowSubtitle(String version) {
    return 'Current version v$version';
  }

  @override
  String get updateCheck => 'Check';

  @override
  String get updateChecking => 'Checking…';

  @override
  String updateAvailableSubtitle(String version) {
    return 'Version $version is available';
  }

  @override
  String get updateDownload => 'Get it';

  @override
  String get updateUpToDate => 'You are on the latest version';

  @override
  String updateCurrentVersionHint(String version) {
    return 'Current version v$version';
  }

  @override
  String updateResultDate(String date, String version) {
    return 'Released $date · you have v$version';
  }

  @override
  String get updateNotesToggle => 'Release notes';

  @override
  String get updateRetry => 'Retry';

  @override
  String get updateFailedNetwork =>
      'Could not reach the release server. Check your network and try again.';

  @override
  String get updateFailedNotFound => 'No published release was found';

  @override
  String get updateFailedServer =>
      'The release server returned an error. Try again later.';

  @override
  String get updateFailedMalformed =>
      'The release information could not be read';

  @override
  String get updateFailedUnsupported =>
      'Update check is not available on this platform';

  @override
  String get updateOpenFailed => 'Could not open the release page';
}
