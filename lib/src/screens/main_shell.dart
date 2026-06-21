import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart' hide PlayerState;

import '../models/playlist.dart';
import '../models/track.dart';
import '../services/music_library_service.dart';
import '../services/player_service.dart';
import '../services/youtube_service.dart';
import '../theme/app_theme.dart';

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.libraryService,
    required this.playerService,
    required this.youtubeService,
  });

  final MusicLibraryService libraryService;
  final PlayerService playerService;
  final YoutubeService youtubeService;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tabIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _playlistController = TextEditingController();
  List<YoutubeSearchItem> _searchItems = <YoutubeSearchItem>[];
  bool _searching = false;
  bool _downloading = false;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    widget.libraryService.addListener(_onLibraryUpdate);
  }

  @override
  void dispose() {
    widget.libraryService.removeListener(_onLibraryUpdate);
    _searchDebounce?.cancel();
    _searchController.dispose();
    _playlistController.dispose();
    super.dispose();
  }

  void _onLibraryUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      _buildHome(),
      _buildSearch(),
      _buildLibrary(),
      _buildPlaylists(),
      _buildNowPlaying(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Red Black Sound'),
      ),
      body: tabs[_tabIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (value) => setState(() => _tabIndex = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
          NavigationDestination(icon: Icon(Icons.library_music), label: 'Library'),
          NavigationDestination(icon: Icon(Icons.playlist_play), label: 'Playlists'),
          NavigationDestination(icon: Icon(Icons.graphic_eq), label: 'Now Playing'),
        ],
      ),
      floatingActionButton: _tabIndex == 2
          ? FloatingActionButton.extended(
              onPressed: () => _importLocalTracks(),
              label: const Text('Import MP3'),
              icon: const Icon(Icons.file_upload),
            )
          : null,
    );
  }

  Widget _buildHome() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.black, AppTheme.surface],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Phone-Only Music',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tracks: ${widget.libraryService.tracks.length} | Playlists: ${widget.libraryService.playlists.length}',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'YouTube search and MP3 downloads run directly on this phone. Personalized recommendations are paused for this iteration.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => setState(() => _tabIndex = 1),
                        icon: const Icon(Icons.search),
                        label: const Text('Search YouTube'),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _importLocalTracks(),
                        icon: const Icon(Icons.audio_file),
                        label: const Text('Import Local MP3s'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search YouTube songs',
              suffixIcon: IconButton(
                onPressed: _searching ? null : _runSearch,
                icon: const Icon(Icons.search),
              ),
            ),
            onSubmitted: (_) => _runSearch(),
            onChanged: (_) {
              _searchDebounce?.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 450), _runSearch);
            },
          ),
          const SizedBox(height: 12),
          if (_searching || _downloading) const LinearProgressIndicator(),
          Expanded(
            child: ListView.builder(
              itemCount: _searchItems.length,
              itemBuilder: (context, index) {
                final item = _searchItems[index];
                return Card(
                  child: ListTile(
                    leading: _artworkThumb(item.thumbnail),
                    onTap: () => _openPreview(item),
                    title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(item.channel),
                    trailing: IconButton(
                      onPressed: _downloading ? null : () => _download(item),
                      icon: const Icon(Icons.download_for_offline),
                      tooltip: 'Download MP3',
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLibrary() {
    final tracks = widget.libraryService.tracks;
    if (tracks.isEmpty) {
      return const Center(child: Text('No tracks yet. Import MP3 files or download from YouTube.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        return Card(
          child: ListTile(
            title: Text(track.title),
            subtitle: Text(track.source.name),
            onTap: () => _playTrackFromList(tracks, index),
            leading: GestureDetector(
              onTap: () => _playTrackFromList(tracks, index),
              child: _trackArtwork(track),
            ),
            trailing: PopupMenuButton<Playlist>(
              icon: const Icon(Icons.playlist_add),
              itemBuilder: (context) {
                return widget.libraryService.playlists
                    .map(
                      (playlist) => PopupMenuItem<Playlist>(
                        value: playlist,
                        child: Text('Add to ${playlist.name}'),
                      ),
                    )
                    .toList();
              },
              onSelected: (playlist) {
                widget.libraryService.addTrackToPlaylist(
                  playlistId: playlist.id,
                  trackId: track.id,
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlaylists() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _playlistController,
                  decoration: const InputDecoration(hintText: 'New playlist name'),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _createPlaylist,
                child: const Text('Create'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: widget.libraryService.playlists.length,
              itemBuilder: (context, index) {
                final playlist = widget.libraryService.playlists[index];
                final tracks = widget.libraryService.tracksForPlaylist(playlist.id);
                return Card(
                  child: ExpansionTile(
                    title: Text(playlist.name),
                    subtitle: Text('${tracks.length} tracks'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => widget.libraryService.deletePlaylist(playlist.id),
                    ),
                    children: [
                      ListTile(
                        leading: const Icon(Icons.audio_file),
                        title: const Text('Add MP3 files'),
                        onTap: () => _importLocalTracks(playlistId: playlist.id),
                      ),
                      for (var i = 0; i < tracks.length; i += 1)
                        ListTile(
                          title: Text(tracks[i].title),
                          subtitle: Text(tracks[i].artist),
                          onTap: () => _playTrackFromList(tracks, i),
                          leading: GestureDetector(
                            onTap: () => _playTrackFromList(tracks, i),
                            child: _trackArtwork(tracks[i]),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () => widget.libraryService.removeTrackFromPlaylist(
                              playlistId: playlist.id,
                              trackId: tracks[i].id,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNowPlaying() {
    return StreamBuilder<PlayerState>(
      stream: widget.playerService.player.playerStateStream,
      builder: (context, _) {
        final current = widget.playerService.currentTrack;
        final playing = widget.playerService.player.playing;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (current?.artworkUrl != null) ...[
                _artworkHero(current!.artworkUrl!),
                const SizedBox(height: 16),
              ],
              Text(
                current?.title ?? 'Nothing Playing',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text('Loop: ${widget.playerService.loopMode.name}'),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: widget.playerService.previous,
                    iconSize: 40,
                    icon: const Icon(Icons.skip_previous),
                  ),
                  IconButton(
                    onPressed: playing ? widget.playerService.pause : widget.playerService.resume,
                    iconSize: 56,
                    color: AppTheme.red,
                    icon: Icon(playing ? Icons.pause_circle : Icons.play_circle),
                  ),
                  IconButton(
                    onPressed: widget.playerService.next,
                    iconSize: 40,
                    icon: const Icon(Icons.skip_next),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => setState(() => widget.playerService.cycleLoopMode()),
                icon: const Icon(Icons.repeat),
                label: const Text('Cycle Loop Mode'),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Queue (${widget.playerService.queue.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: widget.playerService.queue.length,
                  itemBuilder: (context, index) {
                    final queueTrack = widget.playerService.queue[index];
                    final isCurrent = index == widget.playerService.currentIndex;
                    return ListTile(
                      dense: true,
                      selected: isCurrent,
                      leading: isCurrent
                          ? const Icon(Icons.equalizer, color: AppTheme.red)
                          : const Icon(Icons.music_note),
                      title: Text(
                        queueTrack.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        queueTrack.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _playTrackFromList(widget.playerService.queue, index),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _importLocalTracks({String? playlistId}) async {
    try {
      await widget.libraryService.importLocalMp3s(playlistId: playlistId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Import complete')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $error')),
      );
    }
  }

  Future<void> _runSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    setState(() => _searching = true);
    try {
      final results = await widget.youtubeService.search(query);
      if (mounted) {
        setState(() => _searchItems = results);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _download(YoutubeSearchItem item) async {
    setState(() => _downloading = true);
    try {
      final response = await widget.youtubeService.downloadWithFallback(
        item: item,
        format: DownloadFormat.mp3,
      );
      await widget.libraryService.addDownloadedTrack(
        title: response.title,
        absolutePath: response.filePath,
        source: TrackSource.youtubeMp3,
        artworkUrl: response.thumbnail,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloaded ${response.title}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _createPlaylist() async {
    await widget.libraryService.createPlaylist(_playlistController.text);
    _playlistController.clear();
  }

  Future<void> _playTrackFromList(List<Track> tracks, int index) async {
    if (tracks.isEmpty) return;
    await widget.playerService.setQueue(tracks, startIndex: index);
    if (!mounted) return;
    setState(() => _tabIndex = 4);
  }

  Future<void> _openPreview(YoutubeSearchItem item) async {
    final controller = YoutubePlayerController.fromVideoId(
      videoId: item.videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(showFullscreenButton: true),
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: YoutubePlayer(controller: controller),
                ),
              ],
            ),
          ),
        );
      },
    );
    controller.close();
  }

  Widget _trackArtwork(Track track) {
    if (track.artworkUrl == null || track.artworkUrl!.isEmpty) {
      return const CircleAvatar(
        radius: 20,
        backgroundColor: AppTheme.surface,
        child: Icon(Icons.music_note, color: Colors.white70),
      );
    }
    return _artworkThumb(track.artworkUrl!, size: 40);
  }

  Widget _artworkThumb(String url, {double size = 48}) {
    if (url.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.music_note, color: Colors.white70),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          color: AppTheme.surface,
          alignment: Alignment.center,
          child: const Icon(Icons.music_note, color: Colors.white70),
        ),
      ),
    );
  }

  Widget _artworkHero(String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.network(
        url,
        width: 220,
        height: 220,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 220,
          height: 220,
          color: AppTheme.surface,
          alignment: Alignment.center,
          child: const Icon(Icons.music_note, size: 80, color: Colors.white70),
        ),
      ),
    );
  }
}