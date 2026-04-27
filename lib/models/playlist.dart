class Playlist {
  final String name;
  final String path;
  final int trackCount;

  const Playlist({
    required this.name,
    required this.path,
    this.trackCount = 0,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
        name: json['name'] as String,
        path: json['path'] as String,
        trackCount: json['track_count'] as int? ?? 0,
      );

  static const Playlist library = Playlist(
    name: 'Biblioteca',
    path: '',
    trackCount: 0,
  );

  bool get isLibrary => name == 'Biblioteca';
}
