import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:fftea/fftea.dart';
import 'package:uuid/uuid.dart';

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
      artist: track['subtitle'] ?? 'Unknown',
      album: album,
      coverUrl: coverUrl,
      genre: genre,
      year: year,
      shazamUrl: track['url'],
      trackKey: track['key'],
    );
  }
}

class RecognizerService {
  static const String _shazamEndpoint = "https://amp.shazam.com/discovery/v5/en/GB/android/-/tag";

  static final Map<String, String> _headers = {
    "X-Shazam-Platform": "ANDROID",
    "X-Shazam-AppVersion": "9.25.0",
    "Accept": "*/*",
    "Accept-Language": "en",
    "Accept-Encoding": "gzip, deflate",
    "User-Agent": "Shazam/3685 CFNetwork/1197 Darwin/20.0.0",
    "Content-Type": "application/json",
  };

  /// Main recognition method
  static Future<TrackInfo?> recognize(String audioPath) async {
    try {
      final samplesData = await _readWavSamples(audioPath);
      final samples = samplesData.samples;
      final sampleRate = samplesData.sampleRate;

      final resampled = _resampleTo16k(samples, sampleRate);
      final signature = _computeSignature(resampled, 16000);

      if (signature == null) return null;

      final data = await _callShazamApi(signature);
      if (data != null && data.containsKey('track')) {
        return TrackInfo.fromJson(data['track']);
      }
    } catch (e) {
      print("[RecognizerService] Error: $e");
    }
    return null;
  }

  static Future<Map<String, dynamic>?> _callShazamApi(Map<String, dynamic> signature) async {
    final uuid = const Uuid();
    final url = "$_shazamEndpoint/${uuid.v4().toUpperCase()}/${uuid.v4().toUpperCase()}"
        "?sync=true&webv3=true&sampling=true&connected=&shazamapiversion=v3"
        "&sharehub=true&video=v3";

    final payload = {
      "timezone": "America/Caracas",
      "signature": {
        "uri": signature["uri"],
        "samplems": (signature["samples"] / 16000 * 1000).toInt(),
      },
      "timestamp": signature["timestamp"],
      "context": {},
      "geolocation": {},
    };

    try {
      final dio = Dio();
      final response = await dio.post(
        url,
        data: payload,
        options: Options(headers: _headers, sendTimeout: const Duration(seconds: 30)),
      );
      return response.data;
    } catch (e) {
      print("[RecognizerService] API error: $e");
      return null;
    }
  }

  static Map<String, dynamic>? _computeSignature(List<double> samples, int sampleRate) {
    const int fftSize = 2048;
    const int hop = 512;
    
    List<Map<String, dynamic>> peaks = [];
    final fft = FFT(fftSize);

    for (int start = 0; start <= samples.length - fftSize; start += hop) {
      List<double> frame = samples.sublist(start, start + fftSize);
      
      // Apply Hann window
      for (int i = 0; i < fftSize; i++) {
        frame[i] = frame[i] * (0.5 - 0.5 * math.cos(2 * math.pi * i / (fftSize - 1)));
      }

      // Compute FFT
      final complexArray = fft.realFft(frame);
      final maxBin = fftSize ~/ 4; // up to 4000 Hz approx

      int peakBin = -1;
      double maxMag = -1;

      for (int k = 0; k < maxBin; k++) {
        final re = complexArray[k].x;
        final im = complexArray[k].y;
        final mag = math.sqrt(re * re + im * im);
        
        if (mag > maxMag) {
          maxMag = mag;
          peakBin = k;
        }
      }

      if (peakBin != -1) {
        final peakFreq = peakBin * sampleRate / fftSize;
        if (peakFreq > 100) {
          peaks.add({
            'time': start ~/ hop,
            'bin': peakBin,
            'mag': maxMag,
          });
        }
      }
    }

    if (peaks.isEmpty) return null;

    // Take top 50 peaks to build signature
    final sigData = peaks.take(50).map((p) => "${p['time']}:${p['bin']}").join('|');
    final uri = "data:audio/vnd.shazam.sig;base64,$sigData";

    return {
      "uri": uri,
      "samples": samples.length,
      "timestamp": DateTime.now().millisecondsSinceEpoch,
    };
  }

  static Future<_WavData> _readWavSamples(String path) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    final byteData = ByteData.view(bytes.buffer);

    // Simplistic WAV parsing
    int offset = 12; // skip RIFF header
    int sampleRate = 44100;
    int numChannels = 1;
    int bitsPerSample = 16;
    Uint8List rawData = Uint8List(0);

    while (offset < bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = byteData.getUint32(offset + 4, Endian.little);
      offset += 8;

      if (chunkId == "fmt ") {
        numChannels = byteData.getUint16(offset + 2, Endian.little);
        sampleRate = byteData.getUint32(offset + 4, Endian.little);
        bitsPerSample = byteData.getUint16(offset + 14, Endian.little);
        offset += chunkSize;
      } else if (chunkId == "data") {
        rawData = bytes.sublist(offset, offset + chunkSize);
        break;
      } else {
        offset += chunkSize;
      }
    }

    List<double> samples = [];
    final rawDataView = ByteData.view(rawData.buffer);

    if (bitsPerSample == 16) {
      int count = rawData.length ~/ 2;
      for (int i = 0; i < count; i++) {
        samples.add(rawDataView.getInt16(i * 2, Endian.little) / 32768.0);
      }
    } else {
      // 8-bit or unhandled
      for (int i = 0; i < rawData.length; i++) {
        samples.add(rawData[i] / 128.0 - 1.0);
      }
    }

    if (numChannels == 2) {
      List<double> mono = [];
      for (int i = 0; i < samples.length - 1; i += 2) {
        mono.add((samples[i] + samples[i + 1]) / 2);
      }
      samples = mono;
    }

    return _WavData(samples, sampleRate);
  }

  static List<double> _resampleTo16k(List<double> samples, int srcRate) {
    const int targetRate = 16000;
    if (srcRate == targetRate) return samples;

    final ratio = srcRate / targetRate;
    final int outLen = (samples.length / ratio).floor();
    List<double> out = List.filled(outLen, 0.0);

    for (int i = 0; i < outLen; i++) {
      final double srcPos = i * ratio;
      final int idx = srcPos.floor();
      final double frac = srcPos - idx;

      if (idx + 1 < samples.length) {
        out[i] = samples[idx] * (1 - frac) + samples[idx + 1] * frac;
      } else if (idx < samples.length) {
        out[i] = samples[idx];
      }
    }

    return out;
  }
}

class _WavData {
  final List<double> samples;
  final int sampleRate;
  _WavData(this.samples, this.sampleRate);
}
