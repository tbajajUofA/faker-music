import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../models/track.dart';

class PlayerService {
  PlayerService() {
    _player.playerStateStream.listen((_) {
      if (_queue.isEmpty) return;
      if (_player.processingState == ProcessingState.completed &&
          _loopMode == MusicLoopMode.track) {
        unawaited(playTrack(_queue[_currentIndex]));
      }
    });
  }

  final AudioPlayer _player = AudioPlayer();
  final List<Track> _queue = <Track>[];
  int _currentIndex = 0;
  MusicLoopMode _loopMode = MusicLoopMode.off;

  AudioPlayer get player => _player;
  List<Track> get queue => List<Track>.unmodifiable(_queue);
  int get currentIndex => _currentIndex;
  MusicLoopMode get loopMode => _loopMode;
  Track? get currentTrack => _queue.isEmpty ? null : _queue[_currentIndex];

  Future<void> setQueue(List<Track> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;
    _queue
      ..clear()
      ..addAll(tracks);
    _currentIndex = startIndex.clamp(0, _queue.length - 1).toInt();
    await playTrack(_queue[_currentIndex]);
  }

  Future<void> playTrack(Track track) async {
    await _player.setFilePath(track.path);
    await _player.play();
  }

  Future<void> pause() => _player.pause();
  Future<void> resume() => _player.play();

  Future<void> next() async {
    if (_queue.isEmpty) return;
    if (_loopMode == MusicLoopMode.playlist) {
      _currentIndex = (_currentIndex + 1) % _queue.length;
    } else {
      if (_currentIndex >= _queue.length - 1) return;
      _currentIndex += 1;
    }
    await playTrack(_queue[_currentIndex]);
  }

  Future<void> previous() async {
    if (_queue.isEmpty) return;
    if (_currentIndex == 0) return;
    _currentIndex -= 1;
    await playTrack(_queue[_currentIndex]);
  }

  void cycleLoopMode() {
    _loopMode = switch (_loopMode) {
      MusicLoopMode.off => MusicLoopMode.track,
      MusicLoopMode.track => MusicLoopMode.playlist,
      MusicLoopMode.playlist => MusicLoopMode.off,
    };
  }

  Future<void> dispose() => _player.dispose();
}

enum MusicLoopMode { off, track, playlist }
