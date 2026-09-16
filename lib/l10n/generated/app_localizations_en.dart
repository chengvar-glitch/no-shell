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
  String get connectNow => 'Connect now';

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
  String get switchToDark => 'Switch to dark';

  @override
  String get switchToLight => 'Switch to light';

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
  String get deleteHost => 'Delete host';

  @override
  String get hostAddress => 'Host address';

  @override
  String get copyAddress => 'Copy address';

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
      'name: fofo\nhost: 127.0.0.1\nport: 22\nuser: root\npassword: password';

  @override
  String get sessionDesktopHint =>
      'No session yet — click \"Connect\" at the top right to start an SSH session and use the terminal.\n';

  @override
  String get sessionMobileHint =>
      'No session yet — tap \"Connect now\" at the bottom to start an SSH session and use the terminal.\n';

  @override
  String connectAuthTitle(String name) {
    return 'Connect to \"$name\"';
  }

  @override
  String get authMemoryHint =>
      'Credentials are used for this connection; check \"Remember credentials\" to store them securely.';

  @override
  String get rememberCredentials => 'Remember credentials';

  @override
  String get fieldPrivateKey => 'Private key (PEM)';

  @override
  String get privateKeyHint => '-----BEGIN OPENSSH PRIVATE KEY-----';

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
  String get reconnect => 'Reconnect';

  @override
  String get fieldName => 'Name';

  @override
  String get nameHint => 'e.g. web-prod-01';

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
  String get usernameHint => 'e.g. root';

  @override
  String get usernameRequired => 'Please enter a username';

  @override
  String get groupHint => 'e.g. Production';

  @override
  String get navServers => 'Servers';

  @override
  String get navKeys => 'Keys';

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
  String get keysComingSoon => 'Key management coming soon';

  @override
  String get keysComingSoonHint =>
      'You will be able to generate and import Ed25519 / RSA keys';

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
  String get appFont => 'App font';

  @override
  String get fontSystemDefault => 'System default';

  @override
  String get fontMonospace => 'Monospace';

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
  String get fontCustom => 'Custom font…';

  @override
  String get terminalFontCustomName => 'Font family';

  @override
  String get terminalFontCustomHint => 'e.g. Fira Code, Sarasa Mono SC';

  @override
  String get presetDefaultDark => 'Default dark';

  @override
  String get biometricLock => 'Biometric lock';

  @override
  String get comingSoon => 'Coming soon';

  @override
  String get settingsSubtitle => 'Theme, terminal and language';

  @override
  String get appearanceHint => 'Theme and font for the app UI';

  @override
  String get terminalSectionHint => 'Colors, font and size used by terminals';

  @override
  String get languageHint => 'UI language; Automatic follows the system';

  @override
  String get terminalPreview => 'Preview';

  @override
  String get terminalPreviewCommand => 'ssh deploy@10.0.0.1';

  @override
  String get settingsApplyHint => 'Changes apply immediately';

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
  String get sftpSortAscending => 'Ascending';

  @override
  String get sftpSortDescending => 'Descending';

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
  String get sftpCanceled => 'Canceled';

  @override
  String get sftpDone => 'Done';

  @override
  String get sftpFailed => 'Failed';

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
}
