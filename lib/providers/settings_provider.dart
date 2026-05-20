import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../core/api_client.dart';

class SettingsProvider extends ChangeNotifier {
  static const _keyApiUrl = 'api_url';
  static const _keyMusicFolder = 'music_folder';
  static const _keyVideoFolder = 'video_folder';
  static const _keyDeviceIndex = 'device_index';
  static const _keyListenDuration = 'listen_duration';
  static const _keyThemeMode = 'theme_mode';
  static const _keyAccentColor = 'accent_color';
  static const _keySidebarColor = 'sidebar_color';
  static const _keyLocale = 'locale';
  static const _keyLyricsOffset = 'lyrics_offset';

  String _apiUrl = 'http://127.0.0.1:8000';
  String _musicFolder = '';
  String _videoFolder = '';
  int? _deviceIndex;
  int _listenDuration = 10;
  bool _isLoaded = false;

  ThemeMode _themeMode = ThemeMode.dark;
  Color _accentColor = const Color(0xFF7B2FFF);
  Color? _sidebarColor;
  String _locale = 'es';
  int _lyricsOffset = 0;

  String _defaultMusicFolder = '';
  String _defaultVideoFolder = '';
  String _effectiveMusicFolder = '';
  String _effectiveVideoFolder = '';

  String get apiUrl => _apiUrl;
  String get musicFolder => _effectiveMusicFolder.isNotEmpty ? _effectiveMusicFolder : _defaultMusicFolder;
  String get videoFolder => _effectiveVideoFolder.isNotEmpty ? _effectiveVideoFolder : _defaultVideoFolder;
  String get lyricsFolder => p.join(musicFolder, 'lyrics');
  int? get deviceIndex => _deviceIndex;
  int get listenDuration => _listenDuration;
  bool get isLoaded => _isLoaded;
  bool get hasMusicFolder => _musicFolder.isNotEmpty;
  bool get hasVideoFolder => _videoFolder.isNotEmpty;

  ThemeMode get themeMode => _themeMode;
  Color get accentColor => _accentColor;
  Color? get sidebarColor => _sidebarColor;
  String get locale => _locale;
  int get lyricsOffset => _lyricsOffset;

  late ApiClient _api;
  ApiClient get api => _api;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _apiUrl = prefs.getString(_keyApiUrl) ?? 'http://127.0.0.1:8000';
    if (_apiUrl.contains('localhost')) {
      _apiUrl = _apiUrl.replaceAll('localhost', '127.0.0.1');
      await prefs.setString(_keyApiUrl, _apiUrl);
    }
    _musicFolder = prefs.getString(_keyMusicFolder) ?? '';
    _videoFolder = prefs.getString(_keyVideoFolder) ?? '';
    _deviceIndex = prefs.getInt(_keyDeviceIndex);
    _listenDuration = prefs.getInt(_keyListenDuration) ?? 10;
    _lyricsOffset = prefs.getInt(_keyLyricsOffset) ?? 0;

    final themeModeStr = prefs.getString(_keyThemeMode);
    if (themeModeStr == 'light') _themeMode = ThemeMode.light;
    else if (themeModeStr == 'system') _themeMode = ThemeMode.system;
    else _themeMode = ThemeMode.dark;

    final accentVal = prefs.getInt(_keyAccentColor);
    if (accentVal != null) _accentColor = Color(accentVal);

    final sidebarVal = prefs.getInt(_keySidebarColor);
    if (sidebarVal != null) _sidebarColor = Color(sidebarVal);

    _locale = prefs.getString(_keyLocale) ?? 'es';

    await _resolveEffectiveFolders();

    _api = ApiClient(
      baseUrl: _apiUrl,
      musicFolder: musicFolder,
      videoFolder: videoFolder,
    );
    
    // Sync paths with backend
    try {
      await _api.updatePaths(
        music: musicFolder, 
        video: videoFolder,
      );
    } catch (_) {}
    
    _isLoaded = true;
    notifyListeners();
  }

  Future<bool> _isDirectoryWritable(String path) async {
    if (kIsWeb) return false;
    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final testFile = File(p.join(path, '.write_test_${DateTime.now().millisecondsSinceEpoch}'));
      await testFile.writeAsString('test');
      await testFile.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _resolveEffectiveFolders() async {
    if (kIsWeb) {
      _effectiveMusicFolder = _musicFolder;
      _effectiveVideoFolder = _videoFolder;
      return;
    }

    final Directory? extDir = Platform.isAndroid ? await getExternalStorageDirectory() : null;
    final fallbackBase = extDir != null ? extDir.path : (await getApplicationDocumentsDirectory()).path;
    _defaultMusicFolder = p.join(fallbackBase, 'Sonero', 'Music');
    _defaultVideoFolder = p.join(fallbackBase, 'Sonero', 'Videos');

    // Resolve Music Folder
    if (_musicFolder.isNotEmpty) {
      if (await _isDirectoryWritable(_musicFolder)) {
        _effectiveMusicFolder = _musicFolder;
      } else {
        _effectiveMusicFolder = _defaultMusicFolder;
      }
    } else {
      if (Platform.isAndroid) {
        const publicMusic = '/storage/emulated/0/Music/Sonero';
        if (await _isDirectoryWritable(publicMusic)) {
          _effectiveMusicFolder = publicMusic;
        } else {
          _effectiveMusicFolder = _defaultMusicFolder;
        }
      } else {
        _effectiveMusicFolder = _defaultMusicFolder;
      }
    }

    // Resolve Video Folder
    if (_videoFolder.isNotEmpty) {
      if (await _isDirectoryWritable(_videoFolder)) {
        _effectiveVideoFolder = _videoFolder;
      } else {
        _effectiveVideoFolder = _defaultVideoFolder;
      }
    } else {
      if (Platform.isAndroid) {
        const publicVideo = '/storage/emulated/0/Download/Sonero';
        if (await _isDirectoryWritable(publicVideo)) {
          _effectiveVideoFolder = publicVideo;
        } else {
          _effectiveVideoFolder = _defaultVideoFolder;
        }
      } else {
        _effectiveVideoFolder = _defaultVideoFolder;
      }
    }
  }
 
  Future<void> setApiUrl(String url) async {
    _apiUrl = url;
    _api = ApiClient(
      baseUrl: url,
      musicFolder: musicFolder,
      videoFolder: videoFolder,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiUrl, url);
    notifyListeners();
  }
 
  Future<void> setMusicFolder(String folder) async {
    _musicFolder = folder;
    await _resolveEffectiveFolders();
    _api.musicFolder = musicFolder;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMusicFolder, folder);
    
    try {
      await _api.updatePaths(music: musicFolder);
    } catch (_) {}
    
    notifyListeners();
  }
 
  Future<void> setVideoFolder(String folder) async {
    _videoFolder = folder;
    await _resolveEffectiveFolders();
    _api.videoFolder = videoFolder;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyVideoFolder, folder);
    
    try {
      await _api.updatePaths(video: videoFolder);
    } catch (_) {}
    
    notifyListeners();
  }

  Future<void> setDeviceIndex(int? index) async {
    _deviceIndex = index;
    final prefs = await SharedPreferences.getInstance();
    if (index == null) {
      await prefs.remove(_keyDeviceIndex);
    } else {
      await prefs.setInt(_keyDeviceIndex, index);
    }
    notifyListeners();
  }

  Future<void> setListenDuration(int seconds) async {
    _listenDuration = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyListenDuration, seconds);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeMode, mode.name);
    notifyListeners();
  }

  Future<void> setAccentColor(Color color) async {
    _accentColor = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyAccentColor, color.toARGB32());
    notifyListeners();
  }

  Future<void> setSidebarColor(Color? color) async {
    _sidebarColor = color;
    final prefs = await SharedPreferences.getInstance();
    if (color == null) {
      await prefs.remove(_keySidebarColor);
    } else {
      await prefs.setInt(_keySidebarColor, color.toARGB32());
    }
    notifyListeners();
  }

  Future<void> setLocale(String locale) async {
    _locale = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLocale, locale);
    notifyListeners();
  }

  Future<void> setLyricsOffset(int ms) async {
    _lyricsOffset = ms;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLyricsOffset, ms);
    notifyListeners();
  }
}
