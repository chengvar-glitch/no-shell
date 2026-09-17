import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'NoShell'**
  String get appName;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @disconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// No description provided for @connectNow.
  ///
  /// In en, this message translates to:
  /// **'Connect now'**
  String get connectNow;

  /// No description provided for @newConnection.
  ///
  /// In en, this message translates to:
  /// **'New connection'**
  String get newConnection;

  /// No description provided for @editConnection.
  ///
  /// In en, this message translates to:
  /// **'Edit connection'**
  String get editConnection;

  /// No description provided for @defaultGroupName.
  ///
  /// In en, this message translates to:
  /// **'Default group'**
  String get defaultGroupName;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @deletedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Deleted {name}'**
  String deletedSnackbar(String name);

  /// No description provided for @deleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String deleteConfirmTitle(String name);

  /// No description provided for @deleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This host will be removed and cannot be recovered.'**
  String get deleteConfirmBody;

  /// No description provided for @hostNotFound.
  ///
  /// In en, this message translates to:
  /// **'Host not found'**
  String get hostNotFound;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @followSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get followSystem;

  /// No description provided for @statusConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get statusConnected;

  /// No description provided for @statusConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get statusConnecting;

  /// No description provided for @statusError.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get statusError;

  /// No description provided for @statusIdle.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get statusIdle;

  /// No description provided for @hostCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 host} other{{count} hosts}}'**
  String hostCount(int count);

  /// No description provided for @collapseSidebar.
  ///
  /// In en, this message translates to:
  /// **'Collapse sidebar ({shortcut})'**
  String collapseSidebar(String shortcut);

  /// No description provided for @expandSidebar.
  ///
  /// In en, this message translates to:
  /// **'Expand sidebar ({shortcut})'**
  String expandSidebar(String shortcut);

  /// No description provided for @windowMinimize.
  ///
  /// In en, this message translates to:
  /// **'Minimize'**
  String get windowMinimize;

  /// No description provided for @windowMaximize.
  ///
  /// In en, this message translates to:
  /// **'Maximize'**
  String get windowMaximize;

  /// No description provided for @windowRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get windowRestore;

  /// No description provided for @windowClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get windowClose;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search name, host, or tag…'**
  String get searchHint;

  /// No description provided for @noMatchingHosts.
  ///
  /// In en, this message translates to:
  /// **'No matching hosts'**
  String get noMatchingHosts;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @switchToDark.
  ///
  /// In en, this message translates to:
  /// **'Switch to dark'**
  String get switchToDark;

  /// No description provided for @switchToLight.
  ///
  /// In en, this message translates to:
  /// **'Switch to light'**
  String get switchToLight;

  /// No description provided for @selectHostToStart.
  ///
  /// In en, this message translates to:
  /// **'Select a host to get started'**
  String get selectHostToStart;

  /// No description provided for @emptyDetailHint.
  ///
  /// In en, this message translates to:
  /// **'Pick a host from the sidebar to view its details, or create a new connection.'**
  String get emptyDetailHint;

  /// No description provided for @overview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get overview;

  /// No description provided for @terminal.
  ///
  /// In en, this message translates to:
  /// **'Terminal'**
  String get terminal;

  /// No description provided for @sftp.
  ///
  /// In en, this message translates to:
  /// **'SFTP'**
  String get sftp;

  /// No description provided for @moreActions.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get moreActions;

  /// No description provided for @deleteHost.
  ///
  /// In en, this message translates to:
  /// **'Delete host'**
  String get deleteHost;

  /// No description provided for @hostAddress.
  ///
  /// In en, this message translates to:
  /// **'Host address'**
  String get hostAddress;

  /// No description provided for @copyAddress.
  ///
  /// In en, this message translates to:
  /// **'Copy address'**
  String get copyAddress;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied {value}'**
  String copied(String value);

  /// No description provided for @port.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get port;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @authMethod.
  ///
  /// In en, this message translates to:
  /// **'Authentication'**
  String get authMethod;

  /// No description provided for @authPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPassword;

  /// No description provided for @authKey.
  ///
  /// In en, this message translates to:
  /// **'SSH key'**
  String get authKey;

  /// No description provided for @lastConnected.
  ///
  /// In en, this message translates to:
  /// **'Last connected'**
  String get lastConnected;

  /// No description provided for @group.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get group;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @notesOptional.
  ///
  /// In en, this message translates to:
  /// **'Notes (optional)'**
  String get notesOptional;

  /// No description provided for @pasteMetadata.
  ///
  /// In en, this message translates to:
  /// **'Paste metadata (optional)'**
  String get pasteMetadata;

  /// No description provided for @pasteMetadataHint.
  ///
  /// In en, this message translates to:
  /// **'name: serverName\nhost: 127.0.0.1\nport: 22\nuser: root\npassword: password'**
  String get pasteMetadataHint;

  /// No description provided for @sessionDesktopHint.
  ///
  /// In en, this message translates to:
  /// **'No session yet — click \"Connect\" at the top right to start an SSH session and use the terminal.\n'**
  String get sessionDesktopHint;

  /// No description provided for @sessionMobileHint.
  ///
  /// In en, this message translates to:
  /// **'No session yet — tap \"Connect now\" at the bottom to start an SSH session and use the terminal.\n'**
  String get sessionMobileHint;

  /// No description provided for @connectAuthTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect to \"{name}\"'**
  String connectAuthTitle(String name);

  /// No description provided for @authMemoryHint.
  ///
  /// In en, this message translates to:
  /// **'Credentials are used for this connection; check \"Remember credentials\" to store them securely.'**
  String get authMemoryHint;

  /// No description provided for @rememberCredentials.
  ///
  /// In en, this message translates to:
  /// **'Remember credentials'**
  String get rememberCredentials;

  /// No description provided for @fieldPrivateKey.
  ///
  /// In en, this message translates to:
  /// **'Private key (PEM)'**
  String get fieldPrivateKey;

  /// No description provided for @privateKeyHint.
  ///
  /// In en, this message translates to:
  /// **'-----BEGIN OPENSSH PRIVATE KEY-----'**
  String get privateKeyHint;

  /// No description provided for @fieldPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Key passphrase (optional)'**
  String get fieldPassphrase;

  /// No description provided for @credentialsRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a password or paste a key'**
  String get credentialsRequired;

  /// No description provided for @connectingTo.
  ///
  /// In en, this message translates to:
  /// **'Connecting to {account}…'**
  String connectingTo(String account);

  /// No description provided for @sessionClosedMsg.
  ///
  /// In en, this message translates to:
  /// **'Session closed'**
  String get sessionClosedMsg;

  /// No description provided for @authFailedMsg.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed — check your password or key'**
  String get authFailedMsg;

  /// No description provided for @networkErrorMsg.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach host — check address, port and network'**
  String get networkErrorMsg;

  /// No description provided for @webUnsupportedMsg.
  ///
  /// In en, this message translates to:
  /// **'SSH connections are not supported on web yet'**
  String get webUnsupportedMsg;

  /// No description provided for @hostKeyChangedMsg.
  ///
  /// In en, this message translates to:
  /// **'Host key verification failed — the server\'s fingerprint no longer matches the one recorded at first connection, so the connection was refused. If the server was rebuilt on purpose, forget the recorded fingerprint and reconnect; otherwise beware of a man-in-the-middle attack.'**
  String get hostKeyChangedMsg;

  /// No description provided for @hostKeyForgetAndRetry.
  ///
  /// In en, this message translates to:
  /// **'Forget fingerprint and reconnect'**
  String get hostKeyForgetAndRetry;

  /// No description provided for @reconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get reconnect;

  /// No description provided for @fieldName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get fieldName;

  /// No description provided for @nameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. web-prod-01'**
  String get nameHint;

  /// No description provided for @nameRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a name'**
  String get nameRequired;

  /// No description provided for @fieldHost.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get fieldHost;

  /// No description provided for @hostHint.
  ///
  /// In en, this message translates to:
  /// **'IP or domain'**
  String get hostHint;

  /// No description provided for @hostRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a host'**
  String get hostRequired;

  /// No description provided for @portInvalid.
  ///
  /// In en, this message translates to:
  /// **'1-65535'**
  String get portInvalid;

  /// No description provided for @usernameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. root'**
  String get usernameHint;

  /// No description provided for @usernameRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a username'**
  String get usernameRequired;

  /// No description provided for @groupHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Production'**
  String get groupHint;

  /// No description provided for @groupNew.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get groupNew;

  /// No description provided for @groupRename.
  ///
  /// In en, this message translates to:
  /// **'Rename group'**
  String get groupRename;

  /// No description provided for @groupDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete group'**
  String get groupDelete;

  /// No description provided for @groupDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete group \"{name}\"?'**
  String groupDeleteConfirm(String name);

  /// No description provided for @groupDeleteEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'This group has no hosts.'**
  String get groupDeleteEmptyBody;

  /// No description provided for @groupDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Its 1 host will move to \"{target}\".} other{Its {count} hosts will move to \"{target}\".}}'**
  String groupDeleteBody(int count, String target);

  /// No description provided for @groupMoveUp.
  ///
  /// In en, this message translates to:
  /// **'Move group up'**
  String get groupMoveUp;

  /// No description provided for @groupMoveDown.
  ///
  /// In en, this message translates to:
  /// **'Move group down'**
  String get groupMoveDown;

  /// No description provided for @groupNewConnection.
  ///
  /// In en, this message translates to:
  /// **'New connection in this group'**
  String get groupNewConnection;

  /// No description provided for @groupMoveTo.
  ///
  /// In en, this message translates to:
  /// **'Move to group…'**
  String get groupMoveTo;

  /// No description provided for @groupMoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Move \"{name}\" to'**
  String groupMoveTitle(String name);

  /// No description provided for @groupCreateFirst.
  ///
  /// In en, this message translates to:
  /// **'No other group yet — create one first'**
  String get groupCreateFirst;

  /// No description provided for @groupKeepOne.
  ///
  /// In en, this message translates to:
  /// **'Keep at least one group'**
  String get groupKeepOne;

  /// No description provided for @groupNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a group name'**
  String get groupNameRequired;

  /// No description provided for @groupNameExists.
  ///
  /// In en, this message translates to:
  /// **'A group with this name already exists'**
  String get groupNameExists;

  /// No description provided for @navServers.
  ///
  /// In en, this message translates to:
  /// **'Servers'**
  String get navServers;

  /// No description provided for @navKeys.
  ///
  /// In en, this message translates to:
  /// **'Keys'**
  String get navKeys;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @cancelSearch.
  ///
  /// In en, this message translates to:
  /// **'Cancel search'**
  String get cancelSearch;

  /// No description provided for @noHostsYet.
  ///
  /// In en, this message translates to:
  /// **'No hosts yet'**
  String get noHostsYet;

  /// No description provided for @createFirstConnection.
  ///
  /// In en, this message translates to:
  /// **'Tap the button below to create a connection'**
  String get createFirstConnection;

  /// No description provided for @noHostsHint.
  ///
  /// In en, this message translates to:
  /// **'Create one with the + button above'**
  String get noHostsHint;

  /// No description provided for @tryAnotherKeyword.
  ///
  /// In en, this message translates to:
  /// **'Try a different keyword'**
  String get tryAnotherKeyword;

  /// No description provided for @keysComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Key management coming soon'**
  String get keysComingSoon;

  /// No description provided for @keysComingSoonHint.
  ///
  /// In en, this message translates to:
  /// **'You will be able to generate and import Ed25519 / RSA keys'**
  String get keysComingSoonHint;

  /// No description provided for @noActiveSessions.
  ///
  /// In en, this message translates to:
  /// **'No active sessions'**
  String get noActiveSessions;

  /// No description provided for @sessionsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Connect to a host on the Servers tab and sessions will show up here'**
  String get sessionsEmptyHint;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// No description provided for @fontSystemMonospace.
  ///
  /// In en, this message translates to:
  /// **'System monospace'**
  String get fontSystemMonospace;

  /// No description provided for @terminalPreset.
  ///
  /// In en, this message translates to:
  /// **'Terminal theme'**
  String get terminalPreset;

  /// No description provided for @terminalFont.
  ///
  /// In en, this message translates to:
  /// **'Terminal font'**
  String get terminalFont;

  /// No description provided for @terminalFontSize.
  ///
  /// In en, this message translates to:
  /// **'Terminal font size'**
  String get terminalFontSize;

  /// No description provided for @fontSizeDecrease.
  ///
  /// In en, this message translates to:
  /// **'Decrease font size'**
  String get fontSizeDecrease;

  /// No description provided for @fontSizeIncrease.
  ///
  /// In en, this message translates to:
  /// **'Increase font size'**
  String get fontSizeIncrease;

  /// No description provided for @presetDefaultDark.
  ///
  /// In en, this message translates to:
  /// **'Default dark'**
  String get presetDefaultDark;

  /// No description provided for @biometricLock.
  ///
  /// In en, this message translates to:
  /// **'Biometric lock'**
  String get biometricLock;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get comingSoon;

  /// No description provided for @settingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Theme, terminal and language'**
  String get settingsSubtitle;

  /// No description provided for @terminalPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get terminalPreview;

  /// No description provided for @terminalPreviewCommand.
  ///
  /// In en, this message translates to:
  /// **'ssh deploy@10.0.0.1'**
  String get terminalPreviewCommand;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @sftpSessionHint.
  ///
  /// In en, this message translates to:
  /// **'No session yet — click \"Connect\" at the top right to browse the server files.\n'**
  String get sftpSessionHint;

  /// No description provided for @sftpSessionMobileHint.
  ///
  /// In en, this message translates to:
  /// **'No session yet — tap \"Connect now\" below to browse the server files.\n'**
  String get sftpSessionMobileHint;

  /// No description provided for @sftpRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get sftpRetry;

  /// No description provided for @sftpUp.
  ///
  /// In en, this message translates to:
  /// **'Parent folder'**
  String get sftpUp;

  /// No description provided for @sftpRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get sftpRefresh;

  /// No description provided for @sftpUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get sftpUpload;

  /// No description provided for @sftpDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get sftpDownload;

  /// No description provided for @sftpNewFolder.
  ///
  /// In en, this message translates to:
  /// **'New folder'**
  String get sftpNewFolder;

  /// No description provided for @sftpEditPath.
  ///
  /// In en, this message translates to:
  /// **'Edit path'**
  String get sftpEditPath;

  /// No description provided for @sftpPathHint.
  ///
  /// In en, this message translates to:
  /// **'Remote path'**
  String get sftpPathHint;

  /// No description provided for @sftpFilter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get sftpFilter;

  /// No description provided for @sftpFilterHint.
  ///
  /// In en, this message translates to:
  /// **'Filter in this folder…'**
  String get sftpFilterHint;

  /// No description provided for @sftpShowHidden.
  ///
  /// In en, this message translates to:
  /// **'Show hidden files'**
  String get sftpShowHidden;

  /// No description provided for @sftpHideHidden.
  ///
  /// In en, this message translates to:
  /// **'Hide hidden files'**
  String get sftpHideHidden;

  /// No description provided for @sftpSortBy.
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get sftpSortBy;

  /// No description provided for @sftpSortName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get sftpSortName;

  /// No description provided for @sftpSortSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get sftpSortSize;

  /// No description provided for @sftpSortModified.
  ///
  /// In en, this message translates to:
  /// **'Modified'**
  String get sftpSortModified;

  /// No description provided for @sftpSortAscending.
  ///
  /// In en, this message translates to:
  /// **'Ascending'**
  String get sftpSortAscending;

  /// No description provided for @sftpSortDescending.
  ///
  /// In en, this message translates to:
  /// **'Descending'**
  String get sftpSortDescending;

  /// No description provided for @sftpCopyPath.
  ///
  /// In en, this message translates to:
  /// **'Copy path'**
  String get sftpCopyPath;

  /// No description provided for @sftpRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get sftpRename;

  /// No description provided for @sftpColumnName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get sftpColumnName;

  /// No description provided for @sftpColumnSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get sftpColumnSize;

  /// No description provided for @sftpColumnModified.
  ///
  /// In en, this message translates to:
  /// **'Modified'**
  String get sftpColumnModified;

  /// No description provided for @sftpColumnPermissions.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get sftpColumnPermissions;

  /// No description provided for @sftpItemCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String sftpItemCount(int count);

  /// No description provided for @sftpSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 selected} other{{count} selected}}'**
  String sftpSelectedCount(int count);

  /// No description provided for @sftpTotalSize.
  ///
  /// In en, this message translates to:
  /// **'{size} total'**
  String sftpTotalSize(String size);

  /// No description provided for @sftpFolderEmpty.
  ///
  /// In en, this message translates to:
  /// **'This folder is empty'**
  String get sftpFolderEmpty;

  /// No description provided for @sftpFolderEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Use Upload to send local files here'**
  String get sftpFolderEmptyHint;

  /// No description provided for @sftpNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matching items'**
  String get sftpNoMatches;

  /// No description provided for @sftpNewFolderTitle.
  ///
  /// In en, this message translates to:
  /// **'New folder'**
  String get sftpNewFolderTitle;

  /// No description provided for @sftpFolderNameField.
  ///
  /// In en, this message translates to:
  /// **'Folder name'**
  String get sftpFolderNameField;

  /// No description provided for @sftpRenameTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename \"{name}\"'**
  String sftpRenameTitle(String name);

  /// No description provided for @sftpNameInvalid.
  ///
  /// In en, this message translates to:
  /// **'Name cannot contain \"/\" or \"..\"'**
  String get sftpNameInvalid;

  /// No description provided for @sftpDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String sftpDeleteTitle(String name);

  /// No description provided for @sftpDeleteMultiTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Delete this item?} other{Delete these {count} items?}}'**
  String sftpDeleteMultiTitle(int count);

  /// No description provided for @sftpDeleteFileBody.
  ///
  /// In en, this message translates to:
  /// **'Deleted files cannot be recovered.'**
  String get sftpDeleteFileBody;

  /// No description provided for @sftpDeleteFolderBody.
  ///
  /// In en, this message translates to:
  /// **'The folder and everything inside it will be deleted, and cannot be recovered.'**
  String get sftpDeleteFolderBody;

  /// No description provided for @sftpOverwriteTitle.
  ///
  /// In en, this message translates to:
  /// **'File already exists'**
  String get sftpOverwriteTitle;

  /// No description provided for @sftpOverwriteBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file with the same name already exists here. Overwrite it?} other{{count} files with the same name already exist here. Overwrite them?}}'**
  String sftpOverwriteBody(int count);

  /// No description provided for @sftpOverwrite.
  ///
  /// In en, this message translates to:
  /// **'Overwrite'**
  String get sftpOverwrite;

  /// No description provided for @sftpTransfersTitle.
  ///
  /// In en, this message translates to:
  /// **'Transfers'**
  String get sftpTransfersTitle;

  /// No description provided for @sftpClearFinished.
  ///
  /// In en, this message translates to:
  /// **'Clear finished'**
  String get sftpClearFinished;

  /// No description provided for @sftpCanceled.
  ///
  /// In en, this message translates to:
  /// **'Canceled'**
  String get sftpCanceled;

  /// No description provided for @sftpDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get sftpDone;

  /// No description provided for @sftpFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get sftpFailed;

  /// No description provided for @sftpRemaining.
  ///
  /// In en, this message translates to:
  /// **'{time} left'**
  String sftpRemaining(String time);

  /// No description provided for @sftpUploaded.
  ///
  /// In en, this message translates to:
  /// **'Uploaded {name}'**
  String sftpUploaded(String name);

  /// No description provided for @sftpDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Saved {name}'**
  String sftpDownloaded(String name);

  /// No description provided for @sftpUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Upload failed: {name}'**
  String sftpUploadFailed(String name);

  /// No description provided for @sftpDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed: {name}'**
  String sftpDownloadFailed(String name);

  /// No description provided for @sftpTransferCanceledMsg.
  ///
  /// In en, this message translates to:
  /// **'Canceled {name}'**
  String sftpTransferCanceledMsg(String name);

  /// No description provided for @sftpPickerFailed.
  ///
  /// In en, this message translates to:
  /// **'Cannot open the file picker'**
  String get sftpPickerFailed;

  /// No description provided for @sftpTargetUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Cannot determine where to save the file'**
  String get sftpTargetUnavailable;

  /// No description provided for @sftpErrorPermission.
  ///
  /// In en, this message translates to:
  /// **'Permission denied'**
  String get sftpErrorPermission;

  /// No description provided for @sftpErrorNotFound.
  ///
  /// In en, this message translates to:
  /// **'Path not found'**
  String get sftpErrorNotFound;

  /// No description provided for @sftpErrorUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This connection does not support SFTP'**
  String get sftpErrorUnsupported;

  /// No description provided for @sftpErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Connection lost'**
  String get sftpErrorNetwork;

  /// No description provided for @sftpErrorOther.
  ///
  /// In en, this message translates to:
  /// **'Operation failed'**
  String get sftpErrorOther;

  /// No description provided for @neverConnected.
  ///
  /// In en, this message translates to:
  /// **'Never connected'**
  String get neverConnected;

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get justNow;

  /// No description provided for @minutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 minute ago} other{{count} minutes ago}}'**
  String minutesAgo(int count);

  /// No description provided for @hoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hour ago} other{{count} hours ago}}'**
  String hoursAgo(int count);

  /// No description provided for @daysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day ago} other{{count} days ago}}'**
  String daysAgo(int count);

  /// No description provided for @importHosts.
  ///
  /// In en, this message translates to:
  /// **'Import hosts'**
  String get importHosts;

  /// No description provided for @exportHosts.
  ///
  /// In en, this message translates to:
  /// **'Export hosts'**
  String get exportHosts;

  /// No description provided for @importExportHosts.
  ///
  /// In en, this message translates to:
  /// **'Import / export hosts'**
  String get importExportHosts;

  /// No description provided for @importDone.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 host imported} other{{count} hosts imported}}'**
  String importDone(int count);

  /// No description provided for @importSkipped.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 duplicate skipped} other{{count} duplicates skipped}}'**
  String importSkipped(int count);

  /// No description provided for @importEmpty.
  ///
  /// In en, this message translates to:
  /// **'No valid host entries found. Please check the file format.'**
  String get importEmpty;

  /// No description provided for @exportDone.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 host exported} other{{count} hosts exported}}'**
  String exportDone(int count);

  /// No description provided for @exportEmpty.
  ///
  /// In en, this message translates to:
  /// **'No hosts to export'**
  String get exportEmpty;

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed. Please try again.'**
  String get exportFailed;

  /// No description provided for @backupCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Set a backup password'**
  String get backupCreateTitle;

  /// No description provided for @backupCreateHint.
  ///
  /// In en, this message translates to:
  /// **'The whole list is encrypted with this password, saved passwords included. You will need it to restore the backup, and it cannot be recovered.'**
  String get backupCreateHint;

  /// No description provided for @backupOpenTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the backup password'**
  String get backupOpenTitle;

  /// No description provided for @backupOpenHint.
  ///
  /// In en, this message translates to:
  /// **'Enter the password that was set when this backup was created.'**
  String get backupOpenHint;

  /// No description provided for @backupPassword.
  ///
  /// In en, this message translates to:
  /// **'Backup password'**
  String get backupPassword;

  /// No description provided for @backupPasswordConfirm.
  ///
  /// In en, this message translates to:
  /// **'Repeat password'**
  String get backupPasswordConfirm;

  /// No description provided for @backupPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a backup password'**
  String get backupPasswordRequired;

  /// No description provided for @backupPasswordMismatch.
  ///
  /// In en, this message translates to:
  /// **'The two passwords do not match'**
  String get backupPasswordMismatch;

  /// No description provided for @backupPasswordWarning.
  ///
  /// In en, this message translates to:
  /// **'Without this password the backup cannot be restored. Please keep it safe.'**
  String get backupPasswordWarning;

  /// No description provided for @backupCreateConfirm.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get backupCreateConfirm;

  /// No description provided for @backupOpenConfirm.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get backupOpenConfirm;

  /// No description provided for @backupWrongPassword.
  ///
  /// In en, this message translates to:
  /// **'Wrong backup password, nothing was imported'**
  String get backupWrongPassword;

  /// No description provided for @backupUnreadable.
  ///
  /// In en, this message translates to:
  /// **'This file cannot be read as a host backup'**
  String get backupUnreadable;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
