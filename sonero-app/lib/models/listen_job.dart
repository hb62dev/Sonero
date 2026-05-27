enum ListenJobStatus { pending, listening, recognizing, searching, downloading, done, failed }

class ListenJob {
  final String jobId;
  final ListenJobStatus status;
  final String step;
  final int progress;
  final TrackResult? track;
  final String? filePath;
  final String? error;

  const ListenJob({
    required this.jobId,
    required this.status,
    this.step = '',
    this.progress = 0,
    this.track,
    this.filePath,
    this.error,
  });

  factory ListenJob.fromJson(Map<String, dynamic> json) {
    final statusStr = json['status'] as String? ?? 'pending';
    final status = ListenJobStatus.values.firstWhere(
      (e) => e.name == statusStr,
      orElse: () => ListenJobStatus.pending,
    );
    final trackJson = json['track'] as Map<String, dynamic>?;
    return ListenJob(
      jobId: json['job_id'] as String? ?? '',
      status: status,
      step: json['step'] as String? ?? '',
      progress: json['progress'] as int? ?? 0,
      track: trackJson != null ? TrackResult.fromJson(trackJson) : null,
      filePath: json['file_path'] as String?,
      error: json['error'] as String?,
    );
  }

  bool get isActive =>
      status == ListenJobStatus.pending ||
      status == ListenJobStatus.listening ||
      status == ListenJobStatus.recognizing ||
      status == ListenJobStatus.searching ||
      status == ListenJobStatus.downloading;

  bool get isDone => status == ListenJobStatus.done;
  bool get isFailed => status == ListenJobStatus.failed;
}

class TrackResult {
  final String title;
  final String artist;
  final String album;
  final String? coverUrl;
  final String genre;
  final String year;

  const TrackResult({
    required this.title,
    required this.artist,
    this.album = '',
    this.coverUrl,
    this.genre = '',
    this.year = '',
  });

  factory TrackResult.fromJson(Map<String, dynamic> json) => TrackResult(
        title: json['title'] as String? ?? '',
        artist: json['subtitle'] as String? ?? json['artist'] as String? ?? '',
        album: json['album'] as String? ?? '',
        coverUrl: json['cover_url'] as String?,
        genre: json['genre'] as String? ?? '',
        year: json['year'] as String? ?? '',
      );
}
