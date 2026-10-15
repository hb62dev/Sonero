// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Sonero';

  @override
  String get navHome => 'Home';

  @override
  String get navLibrary => 'Library';

  @override
  String get navAnalytics => 'Analytics';

  @override
  String get navDownload => 'Download from YouTube';

  @override
  String get navSearch => 'Search';

  @override
  String get downloadComplete => 'Download Completed';

  @override
  String get librarySection => 'LIBRARY';

  @override
  String get newPlaylist => 'New Playlist';

  @override
  String get newPlaylistHint => 'Playlist name';

  @override
  String get create => 'Create';

  @override
  String get cancel => 'Cancel';

  @override
  String get close => 'Close';

  @override
  String get save => 'Save';

  @override
  String get confirm => 'Confirm';

  @override
  String get change => 'Change';

  @override
  String get delete => 'Delete';

  @override
  String get retry => 'Retry';

  @override
  String get clear => 'Clear';

  @override
  String get open => 'Open';

  @override
  String get download => 'Download';

  @override
  String get refresh => 'Refresh';

  @override
  String get renamePlaylist => 'Rename Playlist';

  @override
  String get newPlaylistName => 'New name';

  @override
  String get rename => 'Rename';

  @override
  String get deletePlaylist => 'Delete Playlist';

  @override
  String deletePlaylistConfirm(String name) {
    return '\"$name\" will be deleted. The items will remain in your Library.';
  }

  @override
  String get settings => 'Settings';

  @override
  String get welcomeHome => 'Welcome to Sonero';

  @override
  String get play => 'Play';

  @override
  String get moreInfo => 'More info';

  @override
  String get continueWatching => 'Continue Playing';

  @override
  String get yourSmartPlaylists => 'Smart Playlists';

  @override
  String get language => 'Language';

  @override
  String get languageSpanish => 'Spanish';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageJapanese => 'Japanese';

  @override
  String get appearance => 'Appearance';

  @override
  String get apiConnection => 'API Connection (Local/Remote)';

  @override
  String get musicFolder => 'Media Folder';

  @override
  String get playerShuffle => 'Shuffle';

  @override
  String get playerPrevious => 'Previous';

  @override
  String get playerNext => 'Next';

  @override
  String get playerRepeat => 'Repeat';

  @override
  String get playerShowVideo => 'Show Video';

  @override
  String get playerGridView => 'Grid View';

  @override
  String get playerListView => 'List View';

  @override
  String trackCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 's',
      one: '',
    );
    return '$count song$_temp0';
  }

  @override
  String get autoFillMetadata => 'Auto-fill Metadata';

  @override
  String get exportCsv => 'Export CSV';

  @override
  String csvSaved(String path) {
    return 'CSV saved: $path';
  }

  @override
  String get editMetadata => 'Edit metadata';

  @override
  String get autoFillMetadataApi => 'Auto-fill metadata (API)';

  @override
  String get deleteFile => 'Delete file';

  @override
  String get moveTo => 'Move to...';

  @override
  String get libraryRoot => 'Library (root)';

  @override
  String get deleteSong => 'Delete song';

  @override
  String deleteSongConfirm(String name) {
    return 'Are you sure you want to delete \"$name\" from disk?';
  }

  @override
  String get fileDeleted => 'File deleted';

  @override
  String movedTo(String destination) {
    return 'Moved to $destination';
  }

  @override
  String get emptyLibrary => 'Your library is empty';

  @override
  String emptyPlaylist(String name) {
    return '$name is empty';
  }

  @override
  String get emptyLibraryHint =>
      'Press the keyboard hotkey to recognize a song';

  @override
  String get scanningMetadata => 'Scanning Metadata';

  @override
  String get startingScan => 'Starting scan...';

  @override
  String get starting => 'Starting...';

  @override
  String get unknownError => 'Unknown error';

  @override
  String get analyticsTitle => 'Consumption Analytics';

  @override
  String get yourHabits => 'Your Habits';

  @override
  String get playbackHours => 'Playback hours';

  @override
  String get videosCompleted => 'Videos Completed';

  @override
  String get musicListened => 'Music Listened';

  @override
  String get recentHistory => 'Recent History (Benrio)';

  @override
  String get analyticsPlaceholder =>
      'Backend data will be integrated here once the connection to Benrio is implemented.';

  @override
  String get searchHint => 'Search songs, artists, or YouTube...';

  @override
  String get typeToSearch => 'Type to search...';

  @override
  String get noLocalResults => 'No local results';

  @override
  String localLibraryCount(int count) {
    return 'Local Library ($count)';
  }

  @override
  String get noYouTubeResults => 'No YouTube results';

  @override
  String get downloadMedia => 'Download Media';

  @override
  String get format => 'Format:';

  @override
  String formatLoadError(String error) {
    return 'Error loading formats: $error';
  }

  @override
  String get destinationPlaylist => 'Destination (Playlist):';

  @override
  String get downloadYouTubeVideo => 'Download YouTube Video';

  @override
  String get fetchInfo => 'Get Info';

  @override
  String get selectFormat => 'Select Format:';

  @override
  String get videoFolder => 'Video Folder';

  @override
  String get notSelected => 'Not selected';

  @override
  String get selectFolder => 'Select folder';

  @override
  String get selectMusicFolderDialog =>
      'Select the folder where you want to save music';

  @override
  String get selectVideoFolderDialog =>
      'Select the folder where you want to save videos';

  @override
  String get authentication => 'Authentication (Anti-Bot)';

  @override
  String get authDescription =>
      'Use your YouTube cookies to prevent blocks when downloading.';

  @override
  String get syncBenrio => 'Synchronize (Benrio)';

  @override
  String get cookiesSynced => 'Cookies synchronized successfully.';

  @override
  String get loadCookiesFile => 'Load cookies.txt';

  @override
  String get selectCookiesDialog => 'Select your cookies.txt file';

  @override
  String get fileLoaded => 'File loaded successfully.';

  @override
  String get themeMode => 'Theme mode';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get primaryColor => 'Primary color';

  @override
  String get sidebarColor => 'Sidebar color';

  @override
  String get defaultColor => 'Default';

  @override
  String get selectColor => 'Select color';

  @override
  String get saveUrl => 'Save URL';

  @override
  String get refetchTest => 'Refetch / Test';

  @override
  String get connectionSuccess => '✅ Successful connection to backend.';

  @override
  String get connectionFailed => '❌ Could not connect to backend.';

  @override
  String get listenDuration => 'Listen duration';

  @override
  String get durationSaved => 'Duration saved';

  @override
  String get durationRange => 'Between 5 and 60 seconds.';

  @override
  String get secondsSuffix => 'sec';

  @override
  String get globalHotkeys => 'Global keyboard shortcuts';

  @override
  String get hotkeysDescription => 'Work even when the window is minimized.';

  @override
  String get hotkeyMic => '🎙️ Listen with Microphone';

  @override
  String get hotkeySystem => '🖥️ Listen to System Audio';

  @override
  String get hotkeyVideo => '📺 Download Video (Clipboard)';

  @override
  String get hotkeyShow => '👀 Show Window';

  @override
  String get hotkeyHide => '👻 Hide Window';

  @override
  String get hotkeySaved => 'Hotkey saved';

  @override
  String get hotkeyTitleMic => '🎙️ Hotkey — Microphone';

  @override
  String get hotkeyTitleSystem => '🖥️ Hotkey — System';

  @override
  String get hotkeyTitleVideo => '📺 Hotkey — Video';

  @override
  String get hotkeyTitleShow => '👀 Hotkey — Show Window';

  @override
  String get hotkeyTitleHide => '👻 Hotkey — Hide Window';

  @override
  String get hotkeyRecordPrompt => 'Press the key combination you want to use.';

  @override
  String get micDevice => 'Microphone device';

  @override
  String deviceNumber(int index) {
    return 'Device #$index';
  }

  @override
  String get systemDefault => 'System default';

  @override
  String get detectDevices => 'Detect devices';

  @override
  String get useDefault => 'Use default';

  @override
  String get audioDevices => 'Audio devices';

  @override
  String get editMetadataTitle => 'Edit Metadata';

  @override
  String get fieldTitle => 'Title';

  @override
  String get fieldArtist => 'Artist';

  @override
  String get fieldAlbum => 'Album';

  @override
  String get fieldYear => 'Year';

  @override
  String get fieldGenre => 'Genre';

  @override
  String errorSaving(String error) {
    return 'Error saving: $error';
  }

  @override
  String errorPrefix(String error) {
    return 'Error: $error';
  }

  @override
  String get playlistDetected => 'YouTube Playlist detected';

  @override
  String get downloadPlaylist => 'Download Playlist';

  @override
  String get playlistDownloadOptions => 'Playlist Download Options';

  @override
  String get loadingPlaylistInfo => 'Loading playlist information...';

  @override
  String playlistVideosCount(int count) {
    return '$count videos found';
  }

  @override
  String enqueuingDownloads(int count) {
    return 'Enqueuing $count downloads...';
  }

  @override
  String playlistEnqueued(int count) {
    return '$count downloads have been enqueued in the manager.';
  }

  @override
  String get navShare => 'Share';

  @override
  String get navActiveDownloads => 'Downloads';

  @override
  String get wifiTitle => 'Share via WiFi';

  @override
  String get wifiTabSend => 'Send';

  @override
  String get wifiTabReceive => 'Receive';

  @override
  String get wifiNoFilesTitle => 'No files selected';

  @override
  String get wifiNoFilesHint =>
      'Go to your Library, long-press a song or video to start selecting, check what you want to send and tap the WiFi icon.';

  @override
  String wifiSendCount(int count) {
    return 'Send $count file(s)';
  }

  @override
  String get wifiClear => 'Clear';

  @override
  String get wifiReceiverIp => 'Receiver IP';

  @override
  String get wifiReceiverIpHint => 'e.g. 192.168.1.50';

  @override
  String get wifiSend => 'Send';

  @override
  String get wifiSending => 'Sending';

  @override
  String get wifiQueue => 'Send queue';

  @override
  String wifiCompleted(int done, int total) {
    return '$done / $total completed';
  }

  @override
  String get wifiEnterIp => 'Enter the receiver\'s IP.';

  @override
  String get wifiSendFinished => 'Transfer finished.';

  @override
  String wifiSendError(String error) {
    return 'Transfer error: $error';
  }

  @override
  String get wifiReady => 'Ready to receive files';

  @override
  String get wifiEnterIpOnSender =>
      'Enter this IP in the Sonero app on the other device.';

  @override
  String wifiOtherIps(String ips) {
    return 'Other networks: $ips';
  }

  @override
  String get wifiOrOpenInBrowser =>
      'No app? Open this in your phone\'s browser:';

  @override
  String get wifiCopied => 'Copied to clipboard.';

  @override
  String get wifiCopy => 'Copy';

  @override
  String get wifiReceiveOff => 'Receiving is off';

  @override
  String get wifiReceiveOffHint =>
      'Turn on receiving to get music or videos from other devices on the same WiFi network.';

  @override
  String get wifiStartReceiving => 'Start receiving';

  @override
  String get wifiStopReceiving => 'Stop receiving';

  @override
  String wifiStartError(String error) {
    return 'Couldn\'t start receiving: $error';
  }

  @override
  String get wifiReceivedList => 'Received / in progress';

  @override
  String get wifiNoNetwork =>
      'No WiFi or LAN network found. Connect to a network to share.';

  @override
  String get wifiSameNetworkTip =>
      'Both devices must be on the same WiFi network. An active VPN may block the connection, and your computer may ask permission to accept incoming connections.';

  @override
  String get wifiBackendUnavailable =>
      'Can\'t reach the Sonero server. Make sure it\'s running.';

  @override
  String get wifiStatusWaiting => 'Waiting…';

  @override
  String wifiStatusTransferring(int pct) {
    return 'Transferring… $pct%';
  }

  @override
  String get wifiStatusDone => 'Completed';

  @override
  String get wifiStatusDuplicate => 'Already there, skipped';

  @override
  String wifiStatusFailed(String error) {
    return 'Failed: $error';
  }

  @override
  String get wifiUnknownError => 'Unknown error';
}
