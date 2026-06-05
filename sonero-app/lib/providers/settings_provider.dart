import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:google_sign_in/google_sign_in.dart';
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
  static const _keyUserId = 'user_id';
  static const _keyUserName = 'user_name';
  static const _keyUserEmail = 'user_email';
  static const _keyGoogleClientId = 'google_client_id';
  static const _keyGoogleClientSecret = 'google_client_secret';
  static const _keyIsLoggedIn = 'is_logged_in';
  static const _keyLyricsOffset = 'lyrics_offset';
  static const _keyRecognitionService = 'recognition_service';
  static const _keyGeminiApiKey = 'gemini_api_key';
  static const _keyAudDApiToken = 'audd_api_token';
  static const _keyRapidApiKey = 'rapidapi_key';
  static const _keyRapidApiHost = 'rapidapi_host';
  static const _keyShazamProxyUrl = 'shazam_proxy_url';

  String _apiUrl = 'http://127.0.0.1:8000';
  String _musicFolder = '';
  String _videoFolder = '';
  int? _deviceIndex;
  int _listenDuration = 15;
  bool _isLoaded = false;

  ThemeMode _themeMode = ThemeMode.dark;
  Color _accentColor = const Color(0xFF7B2FFF);
  Color? _sidebarColor;
  String _locale = 'es';

  // Auth fields
  String _currentUserId = '1';
  String? _currentUserName;
  String? _currentUserEmail;
  bool _isLoggedIn = false;
  String _googleClientId = '';
  String _googleClientSecret = '';
  String? _googleAccessToken;
  bool _isSyncing = false;
  String? _syncError;
  DateTime? _lastSyncTime;

  // Mobile fields
  int _lyricsOffset = 0;
  String _recognitionService = 'gemini';
  String _geminiApiKey = '';
  String _auddApiToken = '';
  String _rapidApiKey = '';
  String _rapidApiHost = 'shazam-song-recognizer.p.rapidapi.com';
  String _shazamProxyUrl = '';

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

  String get currentUserId => _currentUserId;
  String? get currentUserName => _currentUserName;
  String? get currentUserEmail => _currentUserEmail;
  bool get isLoggedIn => _isLoggedIn;
  String get googleClientId => _googleClientId;
  String get googleClientSecret => _googleClientSecret;
  String? get googleAccessToken => _googleAccessToken;
  bool get isSyncing => _isSyncing;
  String? get syncError => _syncError;
  DateTime? get lastSyncTime => _lastSyncTime;

  bool get hasGoogleCredentials {
    final id = _googleClientId.isNotEmpty 
        ? _googleClientId 
        : const String.fromEnvironment('DEFAULT_GOOGLE_CLIENT_ID_WINDOWS');
    final secret = _googleClientSecret.isNotEmpty 
        ? _googleClientSecret 
        : const String.fromEnvironment('DEFAULT_GOOGLE_CLIENT_SECRET_WINDOWS');
    return id.isNotEmpty && secret.isNotEmpty;
  }

  int get lyricsOffset => _lyricsOffset;
  String get recognitionService => _recognitionService;
  String get geminiApiKey => _geminiApiKey;
  String get auddApiToken => _auddApiToken;
  String get rapidApiKey => _rapidApiKey;
  String get rapidApiHost => _rapidApiHost;
  String get shazamProxyUrl => _shazamProxyUrl;

  late ApiClient _api;
  ApiClient get api => _api;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    _apiUrl = prefs.getString(_keyApiUrl) ?? 'http://127.0.0.1:8000';
    if (_apiUrl.contains('localhost')) {
      _apiUrl = _apiUrl.replaceAll('localhost', '127.0.0.1');
      await prefs.setString(_keyApiUrl, _apiUrl);
    }
    _musicFolder = prefs.getString(_keyMusicFolder) ?? '';
    _videoFolder = prefs.getString(_keyVideoFolder) ?? '';
    _deviceIndex = prefs.getInt(_keyDeviceIndex);
    _listenDuration = prefs.getInt(_keyListenDuration) ?? 15;
    _lyricsOffset = prefs.getInt(_keyLyricsOffset) ?? 0;
    _recognitionService = prefs.getString(_keyRecognitionService) ?? 'gemini';
    _geminiApiKey = prefs.getString(_keyGeminiApiKey) ?? '';
    _auddApiToken = prefs.getString(_keyAudDApiToken) ?? '';
    _rapidApiKey = prefs.getString(_keyRapidApiKey) ?? '';
    _rapidApiHost = prefs.getString(_keyRapidApiHost) ?? 'shazam-song-recognizer.p.rapidapi.com';
    _shazamProxyUrl = prefs.getString(_keyShazamProxyUrl) ?? '';

    final themeModeStr = prefs.getString(_keyThemeMode);
    if (themeModeStr == 'light') _themeMode = ThemeMode.light;
    else if (themeModeStr == 'system') _themeMode = ThemeMode.system;
    else _themeMode = ThemeMode.dark;

    final accentVal = prefs.getInt(_keyAccentColor);
    if (accentVal != null) _accentColor = Color(accentVal);

    final sidebarVal = prefs.getInt(_keySidebarColor);
    if (sidebarVal != null) _sidebarColor = Color(sidebarVal);

    _locale = prefs.getString(_keyLocale) ?? 'es';

    _googleClientId = prefs.getString(_keyGoogleClientId) ?? '';
    _googleClientSecret = prefs.getString(_keyGoogleClientSecret) ?? '';
    _currentUserId = prefs.getString(_keyUserId) ?? '1';
    _currentUserName = prefs.getString(_keyUserName);
    _currentUserEmail = prefs.getString(_keyUserEmail);
    _isLoggedIn = prefs.getBool(_keyIsLoggedIn) ?? false;
    _googleAccessToken = prefs.getString('google_access_token');
    final lastSyncMs = prefs.getInt('last_sync_time');
    if (lastSyncMs != null) {
      _lastSyncTime = DateTime.fromMillisecondsSinceEpoch(lastSyncMs);
    }

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

  Future<void> setGoogleClientId(String value) async {
    _googleClientId = value.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGoogleClientId, _googleClientId);
    notifyListeners();
  }

  Future<void> setGoogleClientSecret(String value) async {
    _googleClientSecret = value.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGoogleClientSecret, _googleClientSecret);
    notifyListeners();
  }

  Future<void> registerUser(String name, String email, String password) async {
    final res = await _api.register(name, email, password);
    final user = res['user'];
    _currentUserId = user['id'];
    _currentUserName = user['name'];
    _currentUserEmail = user['email'];
    _isLoggedIn = true;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserId, _currentUserId);
    if (_currentUserName != null) await prefs.setString(_keyUserName, _currentUserName!);
    if (_currentUserEmail != null) await prefs.setString(_keyUserEmail, _currentUserEmail!);
    await prefs.setBool(_keyIsLoggedIn, true);
    notifyListeners();
  }

  Future<void> loginUser(String email, String password) async {
    final res = await _api.login(email, password);
    final user = res['user'];
    _currentUserId = user['id'];
    _currentUserName = user['name'];
    _currentUserEmail = user['email'];
    _isLoggedIn = true;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserId, _currentUserId);
    if (_currentUserName != null) await prefs.setString(_keyUserName, _currentUserName!);
    if (_currentUserEmail != null) await prefs.setString(_keyUserEmail, _currentUserEmail!);
    await prefs.setBool(_keyIsLoggedIn, true);
    notifyListeners();
  }

  Future<void> loginWithGoogle() async {
    if (Platform.isAndroid) {
      try {
        final googleSignIn = GoogleSignIn(
          clientId: _googleClientId.isNotEmpty ? _googleClientId : null,
          scopes: [
            'email',
            'profile',
            'openid',
            'https://www.googleapis.com/auth/drive.appdata',
          ],
        );
        final account = await googleSignIn.signIn();
        if (account == null) {
          throw Exception('Inicio de sesión cancelado por el usuario.');
        }
        final auth = await account.authentication;
        final idToken = auth.idToken;
        if (idToken == null) {
          throw Exception('No se pudo obtener el ID Token de Google.');
        }
        
        _googleAccessToken = auth.accessToken;
        final prefs = await SharedPreferences.getInstance();
        if (_googleAccessToken != null) {
          await prefs.setString('google_access_token', _googleAccessToken!);
        }
        
        await _authenticateWithBackend(idToken);
      } catch (e) {
        throw Exception('Error en Google Sign-In (Android): $e');
      }
    } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final clientId = _googleClientId.isNotEmpty 
          ? _googleClientId 
          : const String.fromEnvironment('DEFAULT_GOOGLE_CLIENT_ID_WINDOWS');
      
      if (clientId.isEmpty) {
        throw Exception('Google Client ID no está configurado. Configúralo en los Ajustes.');
      }

      final clientSecret = _googleClientSecret.isNotEmpty 
          ? _googleClientSecret 
          : const String.fromEnvironment('DEFAULT_GOOGLE_CLIENT_SECRET_WINDOWS');

      HttpServer? server;
      try {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final port = server.port;
        final redirectUri = 'http://127.0.0.1:$port';

        final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
          'client_id': clientId,
          'redirect_uri': redirectUri,
          'response_type': 'code',
          'scope': 'openid email profile https://www.googleapis.com/auth/drive.appdata',
        });

        await launchUrl(authUrl, mode: LaunchMode.externalApplication);

        String? authCode;
        await for (var request in server) {
          final code = request.uri.queryParameters['code'];
          if (code != null) {
            authCode = code;
            request.response.headers.contentType = ContentType.html;
            request.response.write('''
              <html>
                <head>
                  <meta charset="utf-8">
                  <title>Conexión Exitosa</title>
                  <style>
                    body {
                      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                      background-color: #0b0b0d;
                      color: #e1e1e6;
                      display: flex;
                      align-items: center;
                      justify-content: center;
                      height: 100vh;
                      margin: 0;
                    }
                    .card {
                      background: linear-gradient(135deg, #121216 0%, #1a1a24 100%);
                      padding: 40px;
                      border-radius: 16px;
                      box-shadow: 0 12px 40px rgba(0, 0, 0, 0.6);
                      text-align: center;
                      border: 1px solid #2d2d3d;
                      max-width: 400px;
                    }
                    h1 { color: #8b5cf6; font-size: 24px; margin-bottom: 12px; }
                    p { color: #9ca3af; font-size: 14px; line-height: 1.5; }
                  </style>
                </head>
                <body>
                  <div class="card">
                    <h1>¡Conexión Exitosa!</h1>
                    <p>La autenticación con Google se completó correctamente en tu navegador.</p>
                    <p>Ya puedes cerrar esta pestaña de forma segura y regresar a la aplicación de Sonero.</p>
                  </div>
                </body>
              </html>
            ''');
            await request.response.close();
            break;
          } else {
            request.response.statusCode = 400;
            request.response.write('Código de autenticación no recibido.');
            await request.response.close();
          }
        }
        await server.close();
        server = null;

        if (authCode == null) {
          throw Exception('El código de autorización no fue recibido.');
        }

        final tokenRes = await http.post(
          Uri.parse('https://oauth2.googleapis.com/token'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'code': authCode,
            'client_id': clientId,
            if (clientSecret.isNotEmpty) 'client_secret': clientSecret,
            'redirect_uri': redirectUri,
            'grant_type': 'authorization_code',
          },
        );

        if (tokenRes.statusCode != 200) {
          throw Exception('Error al intercambiar el código por token con Google: ${tokenRes.body}');
        }

        final tokenData = jsonDecode(tokenRes.body);
        final idToken = tokenData['id_token'] as String?;
        if (idToken == null) {
          throw Exception('El servidor de Google no devolvió id_token en la respuesta.');
        }

        _googleAccessToken = tokenData['access_token'] as String?;
        final prefs = await SharedPreferences.getInstance();
        if (_googleAccessToken != null) {
          await prefs.setString('google_access_token', _googleAccessToken!);
        }

        await _authenticateWithBackend(idToken);
      } catch (e) {
        if (server != null) {
          await server.close();
        }
        throw Exception('Error en Google Sign-In (Desktop): $e');
      }
    } else {
      throw Exception('Plataforma no soportada para Google Sign-in.');
    }
  }

  Future<void> _authenticateWithBackend(String idToken) async {
    final res = await _api.googleAuth(idToken);
    final user = res['user'];
    _currentUserId = user['id'];
    _currentUserName = user['name'];
    _currentUserEmail = user['email'];
    _isLoggedIn = true;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserId, _currentUserId);
    if (_currentUserName != null) await prefs.setString(_keyUserName, _currentUserName!);
    if (_currentUserEmail != null) await prefs.setString(_keyUserEmail, _currentUserEmail!);
    await prefs.setBool(_keyIsLoggedIn, true);
    notifyListeners();
  }

  Future<void> logout() async {
    _currentUserId = '1';
    _currentUserName = null;
    _currentUserEmail = null;
    _isLoggedIn = false;
    _googleAccessToken = null;
    _syncError = null;
    _lastSyncTime = null;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserId, '1');
    await prefs.remove(_keyUserName);
    await prefs.remove(_keyUserEmail);
    await prefs.setBool(_keyIsLoggedIn, false);
    await prefs.remove('google_access_token');
    await prefs.remove('last_sync_time');
    notifyListeners();
  }

  Future<void> syncWithGoogleDrive() async {
    if (_googleAccessToken == null) {
      _syncError = "No se ha iniciado sesión con Google.";
      notifyListeners();
      return;
    }

    _isSyncing = true;
    _syncError = null;
    notifyListeners();

    try {
      // 1. Search for existing file in appDataFolder
      final searchUri = Uri.https('www.googleapis.com', '/drive/v3/files', {
        'spaces': 'appDataFolder',
        'q': "name = 'sonero_sync.json'",
        'fields': 'files(id, name)',
      });

      final searchRes = await http.get(searchUri, headers: {
        'Authorization': 'Bearer $_googleAccessToken',
      });

      if (searchRes.statusCode != 200) {
        throw Exception('Error al buscar archivo en Drive: ${searchRes.body}');
      }

      final searchData = jsonDecode(searchRes.body);
      final files = searchData['files'] as List?;
      String? fileId;
      if (files != null && files.isNotEmpty) {
        fileId = files[0]['id'] as String?;
      }

      // 2. If it exists, download and merge it locally
      if (fileId != null) {
        final downloadUri = Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId?alt=media');
        final downloadRes = await http.get(downloadUri, headers: {
          'Authorization': 'Bearer $_googleAccessToken',
        });

        if (downloadRes.statusCode == 200) {
          final syncPayload = jsonDecode(downloadRes.body) as Map<String, dynamic>;
          await _api.importSyncData(syncPayload);
        } else {
          throw Exception('Error al descargar archivo de Drive: ${downloadRes.body}');
        }
      }

      // 3. Export the latest merged database state from backend
      final localData = await _api.exportSyncData(_currentUserId);

      // 4. Upload updated database JSON back to Google Drive
      if (fileId == null) {
        final boundary = 'sonero_sync_boundary';
        final uploadHeaders = {
          'Authorization': 'Bearer $_googleAccessToken',
          'Content-Type': 'multipart/related; boundary=$boundary',
        };

        final body = '--$boundary\r\n'
            'Content-Type: application/json; charset=UTF-8\r\n\r\n'
            '${jsonEncode({"name": "sonero_sync.json", "parents": ["appDataFolder"]})}\r\n'
            '--$boundary\r\n'
            'Content-Type: application/json; charset=UTF-8\r\n\r\n'
            '${jsonEncode(localData)}\r\n'
            '--$boundary--';

        final createRes = await http.post(
          Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart'),
          headers: uploadHeaders,
          body: body,
        );

        if (createRes.statusCode != 200 && createRes.statusCode != 201) {
          throw Exception('Error al crear archivo de sincronización: ${createRes.body}');
        }
      } else {
        final updateUri = Uri.parse('https://www.googleapis.com/upload/drive/v3/files/$fileId?uploadType=media');
        final updateRes = await http.patch(
          updateUri,
          headers: {
            'Authorization': 'Bearer $_googleAccessToken',
            'Content-Type': 'application/json; charset=UTF-8',
          },
          body: jsonEncode(localData),
        );

        if (updateRes.statusCode != 200) {
          throw Exception('Error al actualizar archivo en Drive: ${updateRes.body}');
        }
      }

      _lastSyncTime = DateTime.now();
      _syncError = null;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_sync_time', _lastSyncTime!.millisecondsSinceEpoch);

    } catch (e) {
      _syncError = e.toString();
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> setLyricsOffset(int ms) async {
    _lyricsOffset = ms;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLyricsOffset, ms);
    notifyListeners();
  }

  Future<void> setRecognitionService(String service) async {
    _recognitionService = service;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRecognitionService, service);
    notifyListeners();
  }

  Future<void> setGeminiApiKey(String key) async {
    _geminiApiKey = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGeminiApiKey, key);
    notifyListeners();
  }

  Future<void> setAudDApiToken(String token) async {
    _auddApiToken = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAudDApiToken, token);
    notifyListeners();
  }

  Future<void> setRapidApiKey(String key) async {
    _rapidApiKey = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRapidApiKey, key);
    notifyListeners();
  }

  Future<void> setRapidApiHost(String host) async {
    _rapidApiHost = host;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRapidApiHost, host);
    notifyListeners();
  }

  Future<void> setShazamProxyUrl(String url) async {
    _shazamProxyUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyShazamProxyUrl, url);
    notifyListeners();
  }
}
