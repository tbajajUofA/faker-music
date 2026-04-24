class Track {
  const Track({
    required this.id,
    required this.title,
    required this.path,
    this.artist = 'Unknown Artist',
    this.artworkUrl,
    this.source = TrackSource.localImport,
  });

  final String id;
  final String title;
  final String path;
  final String artist;
  final String? artworkUrl;
  final TrackSource source;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'path': path,
      'artist': artist,
      'artworkUrl': artworkUrl,
      'source': source.name,
    };
  }

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'] as String,
      title: json['title'] as String,
      path: json['path'] as String,
      artist: json['artist'] as String? ?? 'Unknown Artist',
      artworkUrl: json['artworkUrl'] as String?,
      source: TrackSource.values.firstWhere(
        (value) => value.name == json['source'],
        orElse: () => TrackSource.localImport,
      ),
    );
  }
}

enum TrackSource { localImport, youtubeMp3, youtubeMp4 }
