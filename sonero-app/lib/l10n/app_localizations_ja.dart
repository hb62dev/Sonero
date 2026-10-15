// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'Sonero';

  @override
  String get navHome => 'ホーム';

  @override
  String get navLibrary => 'ライブラリ';

  @override
  String get navAnalytics => '統計';

  @override
  String get navDownload => 'YouTubeからダウンロード';

  @override
  String get navSearch => '検索';

  @override
  String get downloadComplete => 'ダウンロード完了';

  @override
  String get librarySection => 'ライブラリ';

  @override
  String get newPlaylist => '新しいプレイリスト';

  @override
  String get newPlaylistHint => 'プレイリスト名';

  @override
  String get create => '作成';

  @override
  String get cancel => 'キャンセル';

  @override
  String get close => '閉じる';

  @override
  String get save => '保存';

  @override
  String get confirm => '確認';

  @override
  String get change => '変更';

  @override
  String get delete => '削除';

  @override
  String get retry => '再試行';

  @override
  String get clear => 'クリア';

  @override
  String get open => '開く';

  @override
  String get download => 'ダウンロード';

  @override
  String get refresh => '更新';

  @override
  String get renamePlaylist => 'プレイリスト名の変更';

  @override
  String get newPlaylistName => '新しい名前';

  @override
  String get rename => '名前を変更';

  @override
  String get deletePlaylist => 'プレイリストを削除';

  @override
  String deletePlaylistConfirm(String name) {
    return '「$name」を削除します。ファイルはライブラリに保持されます。';
  }

  @override
  String get settings => '設定';

  @override
  String get welcomeHome => 'Soneroへようこそ';

  @override
  String get play => '再生';

  @override
  String get moreInfo => '詳細情報';

  @override
  String get continueWatching => '再生を続ける';

  @override
  String get yourSmartPlaylists => 'スマートプレイリスト';

  @override
  String get language => '言語';

  @override
  String get languageSpanish => 'スペイン語';

  @override
  String get languageEnglish => '英語';

  @override
  String get languageJapanese => '日本語';

  @override
  String get appearance => '外観';

  @override
  String get apiConnection => 'API接続 (ローカル/リモート)';

  @override
  String get musicFolder => 'メディアフォルダ';

  @override
  String get playerShuffle => 'シャッフル';

  @override
  String get playerPrevious => '前へ';

  @override
  String get playerNext => '次へ';

  @override
  String get playerRepeat => 'リピート';

  @override
  String get playerShowVideo => 'ビデオを表示';

  @override
  String get playerGridView => 'グリッド表示';

  @override
  String get playerListView => 'リスト表示';

  @override
  String trackCount(int count) {
    return '$count 曲';
  }

  @override
  String get autoFillMetadata => 'メタデータを自動入力';

  @override
  String get exportCsv => 'CSVエクスポート';

  @override
  String csvSaved(String path) {
    return 'CSVが保存されました: $path';
  }

  @override
  String get editMetadata => 'メタデータの編集';

  @override
  String get autoFillMetadataApi => 'メタデータを自動入力 (API)';

  @override
  String get deleteFile => 'ファイルを削除';

  @override
  String get moveTo => '移動先...';

  @override
  String get libraryRoot => 'ライブラリ (ルート)';

  @override
  String get deleteSong => '曲を削除';

  @override
  String deleteSongConfirm(String name) {
    return '「$name」をディスクから削除してもよろしいですか？';
  }

  @override
  String get fileDeleted => 'ファイルを削除しました';

  @override
  String movedTo(String destination) {
    return '$destination へ移動しました';
  }

  @override
  String get emptyLibrary => 'ライブラリは空です';

  @override
  String emptyPlaylist(String name) {
    return '「$name」は空です';
  }

  @override
  String get emptyLibraryHint => 'キーボードショートカットを押して曲を認識します';

  @override
  String get scanningMetadata => 'メタデータをスキャン中';

  @override
  String get startingScan => 'スキャンを開始しています...';

  @override
  String get starting => '起動中...';

  @override
  String get unknownError => '不明なエラー';

  @override
  String get analyticsTitle => '利用統計情報';

  @override
  String get yourHabits => '再生傾向';

  @override
  String get playbackHours => '再生時間';

  @override
  String get videosCompleted => '完了したビデオ';

  @override
  String get musicListened => '聴いた音楽';

  @override
  String get recentHistory => '最近の履歴 (Benrio)';

  @override
  String get analyticsPlaceholder =>
      'Benrioとの接続が実装された後、ここにバックエンドからのデータが統合されます。';

  @override
  String get searchHint => '曲、アーティスト、またはYouTubeを検索...';

  @override
  String get typeToSearch => '入力して検索...';

  @override
  String get noLocalResults => 'ローカルの結果はありません';

  @override
  String localLibraryCount(int count) {
    return 'ローカルライブラリ ($count)';
  }

  @override
  String get noYouTubeResults => 'YouTubeの結果はありません';

  @override
  String get downloadMedia => 'メディアをダウンロード';

  @override
  String get format => '形式:';

  @override
  String formatLoadError(String error) {
    return '形式の読み込みエラー: $error';
  }

  @override
  String get destinationPlaylist => '宛先 (プレイリスト):';

  @override
  String get downloadYouTubeVideo => 'YouTubeビデオのダウンロード';

  @override
  String get fetchInfo => '情報を取得';

  @override
  String get selectFormat => '形式を選択:';

  @override
  String get videoFolder => 'ビデオフォルダ';

  @override
  String get notSelected => '未選択';

  @override
  String get selectFolder => 'フォルダを選択';

  @override
  String get selectMusicFolderDialog => '音楽の保存先フォルダを選択してください';

  @override
  String get selectVideoFolderDialog => 'ビデオの保存先フォルダを選択してください';

  @override
  String get authentication => '認証 (アンチボット)';

  @override
  String get authDescription => 'ダウンロード時のブロックを防ぐため、YouTubeのCookieを使用します。';

  @override
  String get syncBenrio => '同期する (Benrio)';

  @override
  String get cookiesSynced => 'Cookieが正常に同期されました。';

  @override
  String get loadCookiesFile => 'cookies.txtを読み込む';

  @override
  String get selectCookiesDialog => 'cookies.txtファイルを選択してください';

  @override
  String get fileLoaded => 'ファイルが正常に読み込まれました。';

  @override
  String get themeMode => 'テーマモード';

  @override
  String get themeSystem => 'システム';

  @override
  String get themeLight => 'ライト';

  @override
  String get themeDark => 'ダーク';

  @override
  String get primaryColor => 'メインカラー';

  @override
  String get sidebarColor => 'サイドバーの色';

  @override
  String get defaultColor => 'デフォルト';

  @override
  String get selectColor => '色を選択';

  @override
  String get saveUrl => 'URLを保存';

  @override
  String get refetchTest => '再取得 / テスト';

  @override
  String get connectionSuccess => '✅ バックエンドへの接続に成功しました。';

  @override
  String get connectionFailed => '❌ バックエンドに接続できませんでした。';

  @override
  String get listenDuration => '試聴時間';

  @override
  String get durationSaved => '試聴時間を保存しました';

  @override
  String get durationRange => '5秒から60秒の間。';

  @override
  String get secondsSuffix => '秒';

  @override
  String get globalHotkeys => 'グローバルキーボードショートカット';

  @override
  String get hotkeysDescription => 'ウィンドウが最小化されていても動作します。';

  @override
  String get hotkeyMic => '🎙️ マイクで聴く';

  @override
  String get hotkeySystem => '🖥️ システム音声を聴く';

  @override
  String get hotkeyVideo => '📺 ビデオをダウンロード (クリップボード)';

  @override
  String get hotkeyShow => '👀 ウィンドウを表示';

  @override
  String get hotkeyHide => '👻 ウィンドウを非表示';

  @override
  String get hotkeySaved => 'ショートカットを保存しました';

  @override
  String get hotkeyTitleMic => '🎙️ ショートカット — マイク';

  @override
  String get hotkeyTitleSystem => '🖥️ ショートカット — システム';

  @override
  String get hotkeyTitleVideo => '📺 ショートカット — ビデオ';

  @override
  String get hotkeyTitleShow => '👀 ショートカット — ウィンドウを表示';

  @override
  String get hotkeyTitleHide => '👻 ショートカット — ウィンドウを非表示';

  @override
  String get hotkeyRecordPrompt => '使用したいキーの組み合わせを押してください。';

  @override
  String get micDevice => 'マイクデバイス';

  @override
  String deviceNumber(int index) {
    return 'デバイス #$index';
  }

  @override
  String get systemDefault => 'システムデフォルト';

  @override
  String get detectDevices => 'デバイスを検出';

  @override
  String get useDefault => 'デフォルトを使用';

  @override
  String get audioDevices => 'オーディオデバイス';

  @override
  String get editMetadataTitle => 'メタデータの編集';

  @override
  String get fieldTitle => 'タイトル';

  @override
  String get fieldArtist => 'アーティスト';

  @override
  String get fieldAlbum => 'アルバム';

  @override
  String get fieldYear => '年';

  @override
  String get fieldGenre => 'ジャンル';

  @override
  String errorSaving(String error) {
    return '保存エラー: $error';
  }

  @override
  String errorPrefix(String error) {
    return 'エラー: $error';
  }

  @override
  String get playlistDetected => 'YouTubeプレイリストが検出されました';

  @override
  String get downloadPlaylist => 'プレイリストをダウンロード';

  @override
  String get playlistDownloadOptions => 'プレイリストダウンロードオプション';

  @override
  String get loadingPlaylistInfo => 'プレイリスト情報を読み込んでいます...';

  @override
  String playlistVideosCount(int count) {
    return '$count 個のビデオが見つかりました';
  }

  @override
  String enqueuingDownloads(int count) {
    return '$count 件のダウンロードをキューに追加しています...';
  }

  @override
  String playlistEnqueued(int count) {
    return '$count 件のダウンロードがマネージャーに追加されました。';
  }

  @override
  String get navShare => '共有';

  @override
  String get navActiveDownloads => 'ダウンロード';

  @override
  String get wifiTitle => 'Wi-Fiで共有';

  @override
  String get wifiTabSend => '送信';

  @override
  String get wifiTabReceive => '受信';

  @override
  String get wifiNoFilesTitle => 'ファイルが選択されていません';

  @override
  String get wifiNoFilesHint =>
      'ライブラリで曲や動画を長押しして選択モードにし、送信したいものにチェックを入れてWi-Fiアイコンをタップしてください。';

  @override
  String wifiSendCount(int count) {
    return '$count 件のファイルを送信';
  }

  @override
  String get wifiClear => 'クリア';

  @override
  String get wifiReceiverIp => '受信側のIP';

  @override
  String get wifiReceiverIpHint => '例: 192.168.1.50';

  @override
  String get wifiSend => '送信';

  @override
  String get wifiSending => '送信中';

  @override
  String get wifiQueue => '送信キュー';

  @override
  String wifiCompleted(int done, int total) {
    return '$done / $total 完了';
  }

  @override
  String get wifiEnterIp => '受信側のIPを入力してください。';

  @override
  String get wifiSendFinished => '送信が完了しました。';

  @override
  String wifiSendError(String error) {
    return '送信エラー: $error';
  }

  @override
  String get wifiReady => 'ファイルを受信できます';

  @override
  String get wifiEnterIpOnSender => '相手の端末のSoneroアプリにこのIPを入力してください。';

  @override
  String wifiOtherIps(String ips) {
    return 'その他のネットワーク: $ips';
  }

  @override
  String get wifiOrOpenInBrowser => 'アプリがない場合は、スマホのブラウザでこちらを開いてください:';

  @override
  String get wifiCopied => 'クリップボードにコピーしました。';

  @override
  String get wifiCopy => 'コピー';

  @override
  String get wifiReceiveOff => '受信はオフです';

  @override
  String get wifiReceiveOffHint =>
      '同じWi-Fiネットワーク上の他の端末から音楽や動画を受け取るには、受信をオンにしてください。';

  @override
  String get wifiStartReceiving => '受信を開始';

  @override
  String get wifiStopReceiving => '受信を停止';

  @override
  String wifiStartError(String error) {
    return '受信を開始できませんでした: $error';
  }

  @override
  String get wifiReceivedList => '受信済み / 進行中';

  @override
  String get wifiNoNetwork => 'Wi-FiまたはLANが見つかりません。共有するにはネットワークに接続してください。';

  @override
  String get wifiSameNetworkTip =>
      '両方の端末が同じWi-Fiに接続している必要があります。VPNが有効だと接続できない場合があり、コンピューターが受信接続の許可を求めることがあります。';

  @override
  String get wifiBackendUnavailable => 'Soneroサーバーに接続できません。起動しているか確認してください。';

  @override
  String get wifiStatusWaiting => '待機中…';

  @override
  String wifiStatusTransferring(int pct) {
    return '転送中… $pct%';
  }

  @override
  String get wifiStatusDone => '完了';

  @override
  String get wifiStatusDuplicate => '既に存在するためスキップ';

  @override
  String wifiStatusFailed(String error) {
    return '失敗: $error';
  }

  @override
  String get wifiUnknownError => '不明なエラー';
}
