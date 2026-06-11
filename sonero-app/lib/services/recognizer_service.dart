import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'log_service.dart';

class TrackInfo {
  final String title;
  final String artist;
  final String? album;
  final String? coverUrl;
  final String? genre;
  final String? year;
  final String? shazamUrl;
  final String? trackKey;

  TrackInfo({
    required this.title,
    required this.artist,
    this.album,
    this.coverUrl,
    this.genre,
    this.year,
    this.shazamUrl,
    this.trackKey,
  });

  factory TrackInfo.fromJson(Map<String, dynamic> track) {
    String? coverUrl;
    final images = track['images'] as Map<String, dynamic>?;
    if (images != null) {
      coverUrl = images['coverarthq'] ?? images['coverart'];
    }

    String? genre;
    final genres = track['genres'] as Map<String, dynamic>?;
    if (genres != null) {
      genre = genres['primary'];
    }

    String? year;
    String? album;
    final sections = track['sections'] as List<dynamic>?;
    if (sections != null) {
      for (var section in sections) {
        if (section['type'] == 'SONG') {
          final metadata = section['metadata'] as List<dynamic>?;
          if (metadata != null) {
            for (var meta in metadata) {
              final titleKey = meta['title']?.toString().toLowerCase();
              if (titleKey == 'released') {
                year = meta['text'];
              } else if (titleKey == 'album') {
                album = meta['text'];
              }
            }
          }
        }
      }
    }

    return TrackInfo(
      title: track['title'] ?? 'Unknown',
      artist: track['subtitle'] ?? track['artist'] ?? 'Unknown',
      album: album ?? track['album'],
      coverUrl: coverUrl ?? track['coverUrl'] ?? track['cover_url'],
      genre: genre ?? track['genre'],
      year: year ?? track['year'],
      shazamUrl: track['url'] ?? track['shazamUrl'] ?? track['shazam_url'],
      trackKey: track['key'] ?? track['trackKey'] ?? track['track_key'],
    );
  }

  TrackInfo copyWith({
    String? title,
    String? artist,
    String? album,
    String? coverUrl,
    String? genre,
    String? year,
    String? shazamUrl,
    String? trackKey,
  }) {
    return TrackInfo(
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      coverUrl: coverUrl ?? this.coverUrl,
      genre: genre ?? this.genre,
      year: year ?? this.year,
      shazamUrl: shazamUrl ?? this.shazamUrl,
      trackKey: trackKey ?? this.trackKey,
    );
  }
}

class RecognizerService {
  /// Main recognition method
  static Future<TrackInfo?> recognize(String audioPath) async {
    try {
      LogService.log('Cargando configuraciones de reconocimiento...');
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      TrackInfo? track;
      final proxyUrl = prefs.getString('shazam_proxy_url') ?? '';

      if (proxyUrl.isNotEmpty) {
        LogService.log('Intentando primero con Shazam Proxy ($proxyUrl)...');
        try {
          track = await _recognizeWithShazamProxy(audioPath, proxyUrl);
          if (track != null) {
            LogService.log('Reconocimiento exitoso con Shazam Proxy.');
          } else {
            LogService.log('Shazam Proxy no pudo reconocer el audio. Continuando con el servicio configurado...');
          }
        } catch (e) {
          LogService.log('Error al usar Shazam Proxy: $e. Continuando con el servicio configurado...');
        }
      }

      if (track == null) {
        final service = prefs.getString('recognition_service') ?? 'shazam_proxy';
        LogService.log('Servicio configurado (fallback): $service');

        if (service == 'gemini') {
          final apiKey = prefs.getString('gemini_api_key') ?? '';
          if (apiKey.isEmpty) {
            LogService.log('Error: API Key de Gemini vacía. Configúrala en Ajustes.');
            return null;
          }
          track = await _recognizeWithGemini(audioPath, apiKey);
        } else if (service == 'audd') {
          final apiToken = prefs.getString('audd_api_token') ?? '';
          if (apiToken.isEmpty) {
            LogService.log('Error: API Token de AudD vacío. Configúrala en Ajustes.');
            return null;
          }
          track = await _recognizeWithAudD(audioPath, apiToken);
        } else if (service == 'rapidapi') {
          final apiKey = prefs.getString('rapidapi_key') ?? '';
          final apiHost = prefs.getString('rapidapi_host') ?? 'shazam-song-recognizer.p.rapidapi.com';
          if (apiKey.isEmpty) {
            LogService.log('Error: API Key de RapidAPI vacía. Configúrala en Ajustes.');
            return null;
          }
          track = await _recognizeWithRapidAPI(audioPath, apiKey, apiHost);
        } else if (service == 'shazam_proxy') {
          if (proxyUrl.isEmpty) {
            LogService.log('Error: URL del Servidor Proxy de Shazam vacía. Configúrala en Ajustes.');
            return null;
          }
          // Ya se intentó arriba y no tuvo éxito.
        } else {
          LogService.log('Error: Servicio de reconocimiento desconocido: $service');
          return null;
        }
      }

      if (track != null) {
        // Fallback: search iTunes for artwork if coverUrl is missing
        if (track.coverUrl == null || track.coverUrl!.isEmpty) {
          LogService.log('Carátula ausente en la respuesta. Buscando en iTunes Search API...');
          final itunesCover = await _fetchiTunesArtwork(track.title, track.artist);
          if (itunesCover != null) {
            LogService.log('Carátula encontrada en iTunes: $itunesCover');
            track = track.copyWith(coverUrl: itunesCover);
          } else {
            LogService.log('No se encontró carátula en iTunes.');
          }
        }
        return track;
      }
    } catch (e) {
      LogService.log('Error en RecognizerService.recognize: $e');
    }
    return null;
  }

  static Future<TrackInfo?> _recognizeWithGemini(String audioPath, String apiKey) async {
    LogService.log('Preparando audio para Gemini...');
    try {
      final file = File(audioPath);
      if (!await file.exists()) {
        LogService.log('Error: El archivo de audio no existe en $audioPath');
        return null;
      }

      final bytes = await file.readAsBytes();
      final base64Audio = base64Encode(bytes);
      LogService.log('Audio codificado en Base64 (${(bytes.length / 1024).toStringAsFixed(1)} KB)');

      final dio = Dio();
      final modelsToTry = [
        'gemini-2.5-flash',
        'gemini-2.0-flash',
        'gemini-1.5-flash',
      ];

      for (var modelName in modelsToTry) {
        LogService.log('Intentando reconocimiento con modelo: $modelName...');
        
        final requestDataBeta = {
          "contents": [
            {
              "parts": [
                {
                  "inlineData": {
                    "mimeType": "audio/wav",
                    "data": base64Audio
                  }
                },
                {
                  "text": "You are a professional music recognition engine like Shazam. "
                      "Identify the song playing in the provided audio recording. "
                      "The audio is recorded from a device's microphone, so it might contain background noise, voice hum, reverb, or low volume. "
                      "Ignore any background noise or speech, focus entirely on the music, rhythm, melody, and lyrics. "
                      "Even if the audio is short or noisy, try your absolute best to recognize the song and return your best guess. "
                      "Only return empty strings for 'title' and 'artist' if the recording is completely silent or only contains noise/speech without any background music."
                }
              ]
            }
          ],
          "generationConfig": {
            "responseMimeType": "application/json",
            "responseSchema": {
              "type": "OBJECT",
              "properties": {
                "title": {"type": "STRING", "description": "The song title. Empty string if not recognized."},
                "artist": {"type": "STRING", "description": "The artist name. Empty string if not recognized."},
                "album": {"type": "STRING", "description": "The album name if available."},
                "genre": {"type": "STRING", "description": "The primary genre if available."},
                "year": {"type": "STRING", "description": "The release year (4 digits) if available."}
              },
              "required": ["title", "artist"]
            }
          }
        };

        try {
          final urlBeta = 'https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent?key=$apiKey';
          LogService.log('Enviando solicitud a $modelName (v1beta)...');
          final response = await dio.post(
            urlBeta,
            data: requestDataBeta,
            options: Options(
              headers: {"Content-Type": "application/json"},
              sendTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );

          if (response.statusCode == 200) {
            LogService.log('Respuesta de Gemini ($modelName v1beta) recibida exitosamente.');
            final track = _parseGeminiResponse(response.data);
            if (track != null) return track;
          }
        } catch (e) {
          if (e is DioException) {
            final statusCode = e.response?.statusCode;
            final errBody = e.response?.data;
            
            if (statusCode == 404) {
              LogService.log('Modelo $modelName no encontrado (404) en v1beta. Probando siguiente...');
              continue;
            }
            
            LogService.log('Fallo con $modelName en v1beta (Status $statusCode): $errBody. Reintentando con endpoint v1 (estable) sin esquema...');
            
            final requestDataV1 = {
              "contents": [
                {
                  "parts": [
                    {
                      "inlineData": {
                        "mimeType": "audio/wav",
                        "data": base64Audio
                      }
                    },
                    {
                      "text": "You are a professional music recognition engine like Shazam. "
                          "Identify the song playing in the provided audio recording. "
                          "The audio is recorded from a device's microphone, so it might contain background noise, voice hum, reverb, or low volume. "
                          "Ignore any background noise or speech, focus entirely on the music, rhythm, melody, and lyrics. "
                          "Even if the audio is short or noisy, try your absolute best to recognize the song and return your best guess. "
                          "Return ONLY a JSON object containing the song information. "
                          "The JSON object must have exactly these keys: "
                          "\"title\": (string, empty if not recognized), "
                          "\"artist\": (string, empty if not recognized), "
                          "\"album\": (string or null), "
                          "\"genre\": (string or null), "
                          "\"year\": (string or null, 4-digit release year). "
                          "Do not include any markdown wrappers, code block backticks (like ```json), explanations, or extra text. Just return the raw JSON object."
                    }
                  ]
                }
              ],
              "generationConfig": {
                "temperature": 0.0
              }
            };

            try {
              final urlV1 = 'https://generativelanguage.googleapis.com/v1/models/$modelName:generateContent?key=$apiKey';
              final responseV1 = await dio.post(
                urlV1,
                data: requestDataV1,
                options: Options(
                  headers: {"Content-Type": "application/json"},
                  sendTimeout: const Duration(seconds: 30),
                  receiveTimeout: const Duration(seconds: 30),
                ),
              );

              if (responseV1.statusCode == 200) {
                LogService.log('Respuesta de Gemini ($modelName v1) recibida exitosamente.');
                final track = _parseGeminiResponse(responseV1.data);
                if (track != null) return track;
              }
            } catch (e2) {
              if (e2 is DioException && e2.response?.statusCode == 404) {
                LogService.log('Modelo $modelName tampoco encontrado en v1 (404). Probando siguiente...');
                continue;
              }
              LogService.log('Error llamando a Gemini API ($modelName v1): $e2');
            }
          } else {
            LogService.log('Error llamando a Gemini API ($modelName): $e');
          }
        }
      }
    } catch (e) {
      LogService.log('Error general en _recognizeWithGemini: $e');
    }
    return null;
  }

  static TrackInfo? _parseGeminiResponse(dynamic data) {
    try {
      final candidates = data['candidates'] as List<dynamic>?;
      if (candidates != null && candidates.isNotEmpty) {
        final content = candidates.first['content'] as Map<String, dynamic>?;
        if (content != null) {
          final parts = content['parts'] as List<dynamic>?;
          if (parts != null && parts.isNotEmpty) {
            final text = parts.first['text'] as String?;
            if (text != null && text.trim().isNotEmpty) {
              LogService.log('Respuesta texto de Gemini: ${text.trim()}');
              
              var cleanedText = text.trim();
              if (cleanedText.startsWith('```')) {
                cleanedText = cleanedText
                    .replaceAll(RegExp(r'^```json\s*'), '')
                    .replaceAll(RegExp(r'^```\s*'), '')
                    .replaceAll(RegExp(r'\s*```$'), '')
                    .trim();
              }
              
              final parsedJson = jsonDecode(cleanedText) as Map<String, dynamic>;
              final title = parsedJson['title']?.toString().trim() ?? '';
              final artist = parsedJson['artist']?.toString().trim() ?? '';

              if (title.isNotEmpty && artist.isNotEmpty) {
                return TrackInfo(
                  title: title,
                  artist: artist,
                  album: parsedJson['album']?.toString().trim(),
                  genre: parsedJson['genre']?.toString().trim(),
                  year: parsedJson['year']?.toString().trim(),
                );
              } else {
                LogService.log('Gemini no pudo identificar la canción de forma definitiva (título o artista vacíos en JSON).');
              }
            }
          }
        }
      }
    } catch (e) {
      LogService.log('Error al parsear la respuesta JSON de Gemini: $e');
    }
    return null;
  }

  static Future<TrackInfo?> _recognizeWithAudD(String audioPath, String apiToken) async {
    LogService.log('Enviando audio a AudD API...');
    try {
      final file = File(audioPath);
      if (!await file.exists()) {
        LogService.log('Error: El archivo de audio no existe en $audioPath');
        return null;
      }

      final dio = Dio();
      final formData = FormData.fromMap({
        'api_token': apiToken,
        'file': await MultipartFile.fromFile(audioPath, filename: 'audio.wav'),
        'return': 'apple_music,spotify',
      });

      final response = await dio.post(
        'https://api.audd.io/',
        data: formData,
        options: Options(
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['status'] == 'success') {
          final result = data['result'];
          if (result != null) {
            final title = result['title']?.toString() ?? 'Unknown';
            final artist = result['artist']?.toString() ?? 'Unknown';
            final album = result['album']?.toString();
            final releaseDate = result['release_date']?.toString();
            
            String? year;
            if (releaseDate != null && releaseDate.length >= 4) {
              year = releaseDate.substring(0, 4);
            }

            String? coverUrl;
            if (result['spotify'] != null && result['spotify']['album'] != null) {
              final images = result['spotify']['album']['images'] as List<dynamic>?;
              if (images != null && images.isNotEmpty) {
                coverUrl = images.first['url']?.toString();
              }
            }

            LogService.log('AudD reconoció la canción: $title - $artist');
            return TrackInfo(
              title: title,
              artist: artist,
              album: album,
              coverUrl: coverUrl,
              year: year,
            );
          } else {
            LogService.log('AudD no encontró coincidencias para este audio.');
          }
        } else {
          final errorMsg = data['error']?['error_message'] ?? 'Error desconocido';
          LogService.log('AudD API reportó error: $errorMsg');
        }
      } else {
        LogService.log('Error de API AudD: Status ${response.statusCode}');
      }
    } catch (e) {
      LogService.log('Error llamando a AudD API: $e');
    }
    return null;
  }

  static Future<TrackInfo?> _recognizeWithRapidAPI(String audioPath, String apiKey, String apiHost) async {
    LogService.log('Enviando audio a RapidAPI ($apiHost)...');
    try {
      final file = File(audioPath);
      if (!await file.exists()) {
        LogService.log('Error: El archivo de audio no existe en $audioPath');
        return null;
      }

      final dio = Dio();
      final headers = {
        'x-rapidapi-key': apiKey,
        'x-rapidapi-host': apiHost,
      };

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(audioPath, filename: 'audio.wav'),
        'upload': await MultipartFile.fromFile(audioPath, filename: 'audio.wav'),
      });

      final endpoint = apiHost.contains('shazam.p.rapidapi.com') 
          ? 'https://$apiHost/songs/v2/detect' 
          : 'https://$apiHost/recognize';

      LogService.log('Llamando endpoint: $endpoint');

      final response = await dio.post(
        endpoint,
        data: formData,
        options: Options(
          headers: headers,
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        LogService.log('Respuesta RapidAPI recibida.');
        
        Map<String, dynamic>? trackData;
        if (data is Map<String, dynamic>) {
          if (data.containsKey('track')) {
            trackData = data['track'] as Map<String, dynamic>?;
          } else if (data.containsKey('matches') && (data['matches'] as List).isNotEmpty) {
            trackData = data;
          } else {
            trackData = data;
          }
        }

        if (trackData != null) {
          final title = trackData['title'] ?? 'Unknown';
          final artist = trackData['subtitle'] ?? trackData['artist'] ?? 'Unknown';
          
          String? coverUrl;
          final images = trackData['images'] as Map<String, dynamic>?;
          if (images != null) {
            coverUrl = images['coverarthq'] ?? images['coverart'];
          }

          LogService.log('RapidAPI reconoció la canción: $title - $artist');
          return TrackInfo(
            title: title,
            artist: artist,
            coverUrl: coverUrl,
          );
        } else {
          LogService.log('RapidAPI no devolvió información de pista válida.');
        }
      } else {
        LogService.log('Error de API RapidAPI: Status ${response.statusCode}');
      }
    } catch (e) {
      LogService.log('Error llamando a RapidAPI: $e');
    }
    return null;
  }

  static Future<TrackInfo?> _recognizeWithShazamProxy(String audioPath, String proxyUrl) async {
    LogService.log('Enviando audio a Shazam Proxy ($proxyUrl)...');
    try {
      final file = File(audioPath);
      if (!await file.exists()) {
        LogService.log('Error: El archivo de audio no existe en $audioPath');
        return null;
      }

      final dio = Dio();
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(audioPath, filename: 'audio.wav'),
      });

      var url = proxyUrl.trim();

      // Normalize Hugging Face Space URL to API metadata URL if needed
      if (url.contains('huggingface.co/')) {
        if (url.endsWith('/recognize')) {
          url = url.substring(0, url.length - 10);
        }
        if (url.endsWith('/')) {
          url = url.substring(0, url.length - 1);
        }
        if (url.contains('huggingface.co/spaces/') && !url.contains('/api/spaces/')) {
          url = url.replaceAll('huggingface.co/spaces/', 'huggingface.co/api/spaces/');
        }
      }

      if (url.contains('huggingface.co/api/spaces/')) {
        LogService.log('Detectada URL de API de Hugging Face. Resolviendo host real...');
        try {
          final res = await dio.get(url);
          if (res.statusCode == 200 && res.data != null) {
            final host = res.data['host'] as String?;
            if (host != null && host.isNotEmpty) {
              url = host;
              LogService.log('Host real resuelto: $url');
            }
          }
        } catch (e) {
          LogService.log('Error al resolver host de Hugging Face Space: $e');
        }
      }

      if (!url.endsWith('/recognize')) {
        if (url.endsWith('/')) {
          url = '${url}recognize';
        } else {
          url = '$url/recognize';
        }
      }

      LogService.log('Llamando endpoint de reconocimiento: $url');

      final response = await dio.post(
        url,
        data: formData,
        options: Options(
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        LogService.log('Respuesta de Shazam Proxy recibida exitosamente.');
        if (data != null && data is Map<String, dynamic>) {
          return TrackInfo.fromJson(data);
        } else {
          LogService.log('Error: La respuesta del proxy no es un JSON estructurado de track.');
        }
      } else {
        LogService.log('Error de Shazam Proxy: Status ${response.statusCode}');
      }
    } catch (e) {
      LogService.log('Error llamando a Shazam Proxy: $e');
    }
    return null;
  }

  static Future<String?> _fetchiTunesArtwork(String title, String artist) async {
    try {
      final dio = Dio();
      final term = '$title $artist';
      final url = 'https://itunes.apple.com/search?term=${Uri.encodeComponent(term)}&media=music&limit=1';
      
      final response = await dio.get(
        url,
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        Map<String, dynamic> jsonMap;
        if (data is String) {
          jsonMap = jsonDecode(data);
        } else {
          jsonMap = data;
        }

        final results = jsonMap['results'] as List<dynamic>?;
        if (results != null && results.isNotEmpty) {
          final result = results.first as Map<String, dynamic>;
          final artwork100 = result['artworkUrl100'] as String?;
          if (artwork100 != null) {
            final artwork500 = artwork100.replaceAll('100x100bb', '500x500bb');
            return artwork500;
          }
        }
      }
    } catch (e) {
      LogService.log('Error buscando carátula en iTunes: $e');
    }
    return null;
  }
}
