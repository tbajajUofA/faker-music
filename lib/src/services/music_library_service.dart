import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/playlist.dart';
import '../models/track.dart';

class MusicLibraryService extends ChangeNotifier {
  MusicLibraryService();

  static const _tracksKey = 'tracks';
  static const _playlistsKey = 'playlists';

  final List<Track> _tracks = <Track>[];
  final List<Playlist> _playlists = <Playlist>[];
  final Uuid _uuid = const Uuid();

  List<Track> get tracks => List<Track>.unmodifiable(_tracks);
  List<Playlist> get playlists => List<Playlist>.unmodifiable(_playlists);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final trackRaw = prefs.getString(_tracksKey);
    final playlistRaw = prefs.getString(_playlistsKey);

    if (trackRaw != null) {
      final decoded = jsonDecode(trackRaw) as List<dynamic>;
      _tracks
        ..clear()
        ..addAll(decoded.cast<Map<String, dynamic>>().map(Track.fromJson));
    }
    if (playlistRaw != null) {
      final decoded = jsonDecode(playlistRaw) as List<dynamic>;
      _playlists
        ..clear()
        ..addAll(decoded.cast<Map<String, dynamic>>().map(Playlist.fromJson));
    }
    notifyListeners();
  }

  Future<void> importLocalMp3s() async {
    await _requestImportPermission();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3'],
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;

    final appDocDir = await getApplicationDocumentsDirectory();
    final importDir = Directory(p.join(appDocDir.path, 'imports'));
    if (!importDir.existsSync()) importDir.createSync(recursive: true);

    for (final file in result.files) {
      final sourcePath = file.path;
      if (sourcePath == null) continue;
      final fileName = p.basename(sourcePath);
      final destination = p.join(importDir.path, fileName);
      await File(sourcePath).copy(destination);

      final alreadyAdded = _tracks.any((track) => track.path == destination);
      if (alreadyAdded) continue;

      final parsed = _parseTrackName(fileName);
      _tracks.add(
        Track(
          id: _uuid.v4(),
          title: parsed.$2,
          artist: parsed.$1,
          path: destination,
        ),
      );
    }

    await _saveAll();
    notifyListeners();
  }

  Future<void> addDownloadedTrack({
    required String title,
    required String absolutePath,
    required TrackSource source,
    String? artworkUrl,
  }) async {
    _tracks.add(
      Track(
        id: _uuid.v4(),
        title: title,
        path: absolutePath,
        source: source,
        artworkUrl: artworkUrl,
      ),
    );
    await _saveAll();
    notifyListeners();
  }

  Future<void> createPlaylist(String name) async {
    if (name.trim().isEmpty) return;
    _playlists.add(
      Playlist(
        id: _uuid.v4(),
        name: name.trim(),
        trackIds: <String>[],
      ),
    );
    await _saveAll();
    notifyListeners();
  }

  Future<void> deletePlaylist(String playlistId) async {
    _playlists.removeWhere((playlist) => playlist.id == playlistId);
    await _saveAll();
    notifyListeners();
  }

  Future<void> addTrackToPlaylist({
    required String playlistId,
    required String trackId,
  }) async {
    final index = _playlists.indexWhere((playlist) => playlist.id == playlistId);
    if (index == -1) return;

    final playlist = _playlists[index];
    if (playlist.trackIds.contains(trackId)) return;
    _playlists[index] = playlist.copyWith(
      trackIds: <String>[...playlist.trackIds, trackId],
    );
    await _saveAll();
    notifyListeners();
  }

  Future<void> removeTrackFromPlaylist({
    required String playlistId,
    required String trackId,
  }) async {
    final index = _playlists.indexWhere((playlist) => playlist.id == playlistId);
    if (index == -1) return;

    final playlist = _playlists[index];
    _playlists[index] = playlist.copyWith(
      trackIds: playlist.trackIds.where((id) => id != trackId).toList(),
    );
    await _saveAll();
    notifyListeners();
  }

  List<Track> tracksForPlaylist(String playlistId) {
    final playlist = _playlists.firstWhere(
      (value) => value.id == playlistId,
      orElse: () => const Playlist(id: '', name: '', trackIds: <String>[]),
    );
    if (playlist.id.isEmpty) return const <Track>[];
    final trackMap = <String, Track>{for (final track in _tracks) track.id: track};
    return playlist.trackIds.map((id) => trackMap[id]).whereType<Track>().toList();
  }

  Future<void> _saveAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _tracksKey,
      jsonEncode(_tracks.map((value) => value.toJson()).toList()),
    );
    await prefs.setString(
      _playlistsKey,
      jsonEncode(_playlists.map((value) => value.toJson()).toList()),
    );
  }

  Future<void> _requestImportPermission() async {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      return;
    }
    final status = await Permission.audio.request();
    if (!status.isGranted) {
      throw PlatformException(
        code: 'permission_denied',
        message: 'Audio/media permission is required to import songs.',
      );
    }
  }

  (String, String) _parseTrackName(String fileName) {
    final withoutExt = p.basenameWithoutExtension(fileName);
    final parts = withoutExt.split(' - ');
    if (parts.length >= 2) {
      return (parts.first.trim(), parts.sublist(1).join(' - ').trim());
    }
    return ('Unknown Artist', withoutExt);
  }
}
