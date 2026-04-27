import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';

class SettingsProvider extends ChangeNotifier {
  static const _keyApiUrl = 'api_url';
  static const _keyMusicFolder = 'music_folder';
  static const _keyDeviceIndex = 'device_index';
  static const _keyListenDuration = 'listen_duration';

  String _apiUrl = 'http://localhost:8000';
  String _musicFolder = '';
  int? _deviceIndex;
  int _listenDuration = 10;
  bool _isLoaded = false;

  String get apiUrl => _apiUrl;
  String get musicFolder => _musicFolder;
  int? get deviceIndex => _deviceIndex;
  int get listenDuration => _listenDuration;
  bool get isLoaded => _isLoaded;
  bool get hasMusicFolder => _musicFolder.isNotEmpty;

  late ApiClient _api;
  ApiClient get api => _api;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _apiUrl = prefs.getString(_keyApiUrl) ?? 'http://localhost:8000';
    _musicFolder = prefs.getString(_keyMusicFolder) ?? '';
    _deviceIndex = prefs.getInt(_keyDeviceIndex);
    _listenDuration = prefs.getInt(_keyListenDuration) ?? 10;
    _api = ApiClient(baseUrl: _apiUrl);
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setApiUrl(String url) async {
    _apiUrl = url;
    _api = ApiClient(baseUrl: url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiUrl, url);
    notifyListeners();
  }

  Future<void> setMusicFolder(String folder) async {
    _musicFolder = folder;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMusicFolder, folder);
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
}
