class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.trackIds,
  });

  final String id;
  final String name;
  final List<String> trackIds;

  Playlist copyWith({
    String? id,
    String? name,
    List<String>? trackIds,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      trackIds: trackIds ?? this.trackIds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'trackIds': trackIds,
    };
  }

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] as String,
      name: json['name'] as String,
      trackIds: (json['trackIds'] as List<dynamic>).cast<String>(),
    );
  }
}
