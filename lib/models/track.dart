class Track {
  final String filename;
  final String title;
  final String artist;
  final String album;
  final String genre;
  final String year;
  final String? coverUrl;
  final String? shazamUrl;
  final String playlist; // empty string = root library
  final String downloaded;
  final double sizeMb;

  const Track({
    required this.filename,
    required this.title,
    required this.artist,
    this.album = '',
    this.genre = '',
    this.year = '',
    this.coverUrl,
    this.shazamUrl,
    this.playlist = '',
    this.downloaded = '',
    this.sizeMb = 0,
  });

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        filename: json['filename'] as String? ?? '',
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String? ?? '',
        album: json['album'] as String? ?? '',
        genre: json['genre'] as String? ?? '',
        year: json['year'] as String? ?? '',
        coverUrl: json['cover_url'] as String?,
        shazamUrl: json['shazam_url'] as String?,
        playlist: json['playlist'] as String? ?? '',
        downloaded: json['downloaded'] as String? ?? '',
        sizeMb: (json['size_mb'] as num?)?.toDouble() ?? 0,
      );

  factory Track.fromApiFile(Map<String, dynamic> json, {String playlist = ''}) => Track(
        filename: json['filename'] as String? ?? '',
        title: _titleFromFilename(json['filename'] as String? ?? ''),
        artist: '',
        sizeMb: (json['size_mb'] as num?)?.toDouble() ?? 0,
        playlist: playlist,
      );

  static String _titleFromFilename(String filename) {
    // "Ariis - GOZALO.mp3" → "Ariis - GOZALO"
    return filename.replaceAll(RegExp(r'\.mp3$', caseSensitive: false), '');
  }

  Track copyWith({String? playlist}) => Track(
        filename: filename,
        title: title,
        artist: artist,
        album: album,
        genre: genre,
        year: year,
        coverUrl: coverUrl,
        shazamUrl: shazamUrl,
        playlist: playlist ?? this.playlist,
        downloaded: downloaded,
        sizeMb: sizeMb,
      );
}
