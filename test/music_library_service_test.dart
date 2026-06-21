import 'package:fake/src/models/track.dart';
import 'package:fake/src/services/music_library_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('creates playlists and returns tracks in playlist order', () async {
    final service = MusicLibraryService();
    await service.init();

    await service.createPlaylist('Road songs');
    await service.addDownloadedTrack(
      title: 'First',
      absolutePath: '/music/first.mp3',
      source: TrackSource.youtubeMp3,
    );
    await service.addDownloadedTrack(
      title: 'Second',
      absolutePath: '/music/second.mp3',
      source: TrackSource.localImport,
    );

    final playlist = service.playlists.single;
    await service.addTrackToPlaylist(playlistId: playlist.id, trackId: service.tracks[1].id);
    await service.addTrackToPlaylist(playlistId: playlist.id, trackId: service.tracks[0].id);

    final tracks = service.tracksForPlaylist(playlist.id);
    expect(tracks.map((track) => track.title), <String>['Second', 'First']);
  });

  test('does not duplicate a track in the same playlist', () async {
    final service = MusicLibraryService();
    await service.init();

    await service.createPlaylist('Favorites');
    await service.addDownloadedTrack(
      title: 'Only once',
      absolutePath: '/music/once.mp3',
      source: TrackSource.youtubeMp3,
    );

    final playlist = service.playlists.single;
    final track = service.tracks.single;
    await service.addTrackToPlaylist(playlistId: playlist.id, trackId: track.id);
    await service.addTrackToPlaylist(playlistId: playlist.id, trackId: track.id);

    expect(service.tracksForPlaylist(playlist.id), hasLength(1));
  });
}