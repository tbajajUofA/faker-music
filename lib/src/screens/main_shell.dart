import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

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
  final TextEditingController _backendUrlController = TextEditingController();
  List<YoutubeSearchItem> _searchItems = <YoutubeSearchItem>[];
  List<YoutubeSearchItem> _homeItems = <YoutubeSearchItem>[];
  List<YoutubePlaylist> _youtubePlaylists = <YoutubePlaylist>[];
  bool _searching = false;
  bool _downloading = false;
  bool _authLoading = false;
  bool _feedLoading = false;
  YoutubeAuthStatus _authStatus = const YoutubeAuthStatus(loggedIn: false);
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    widget.libraryService.addListener(_onLibraryUpdate);
    _backendUrlController.text = widget.youtubeService.baseUrl;
    _loadBackendUrl();
    _refreshAuthAndFeed();
  }

  @override
  void dispose() {
    widget.libraryService.removeListener(_onLibraryUpdate);
    _searchDebounce?.cancel();
    _searchController.dispose();
    _playlistController.dispose();
    _backendUrlController.dispose();
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
              onPressed: _importLocalTracks,
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
                    'Spotify Style Controls',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tracks: ${widget.libraryService.tracks.length} | Playlists: ${widget.libraryService.playlists.length}',
                  ),
                  const SizedBox(height: 12),
                  if (_authLoading) const LinearProgressIndicator(),
                  _buildAuthCard(),
                  const SizedBox(height: 12),
                  if (_authStatus.loggedIn) _buildPersonalizedHome(),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _importLocalTracks,
                    icon: const Icon(Icons.audio_file),
                    label: const Text('Import Local MP3s'),
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
            controller: _backendUrlController,
            decoration: InputDecoration(
              hintText: 'Backend URL (e.g. http://192.168.1.10:8787)',
              suffixIcon: IconButton(
                icon: const Icon(Icons.save),
                onPressed: _saveBackendUrl,
                tooltip: 'Save backend URL',
              ),
            ),
            onSubmitted: (_) => _saveBackendUrl(),
          ),
          const SizedBox(height: 8),
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
            onChanged: (value) {
              _searchDebounce?.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 450), _runSearch);
            },
          ),
          const SizedBox(height: 12),
          if (_searching) const LinearProgressIndicator(),
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
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        IconButton(
                          onPressed: _downloading
                              ? null
                              : () => _download(item, DownloadFormat.mp3),
                          icon: const Icon(Icons.download_for_offline),
                          tooltip: 'Download MP3',
                        ),
                        IconButton(
                          onPressed: _downloading
                              ? null
                              : () => _download(item, DownloadFormat.mp4),
                          icon: const Icon(Icons.movie),
                          tooltip: 'Download MP4',
                        ),
                      ],
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
      return const Center(child: Text('No tracks yet. Import MP3 files to begin.'));
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
          if (_authStatus.loggedIn) ...[
            _buildYoutubePlaylistPanel(),
            const SizedBox(height: 12),
          ],
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
                      for (final track in tracks)
                        ListTile(
                          title: Text(track.title),
                          onTap: () => _playTrackFromList(tracks, tracks.indexOf(track)),
                          leading: GestureDetector(
                            onTap: () => _playTrackFromList(tracks, tracks.indexOf(track)),
                            child: _trackArtwork(track),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () => widget.libraryService.removeTrackFromPlaylist(
                              playlistId: playlist.id,
                              trackId: track.id,
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
      builder: (context, snapshot) {
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

  Future<void> _importLocalTracks() async {
    await widget.libraryService.importLocalMp3s();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Import complete')),
    );
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

  Future<void> _download(YoutubeSearchItem item, DownloadFormat format) async {
    setState(() => _downloading = true);
    try {
      final response = await widget.youtubeService.downloadWithFallback(
        item: item,
        format: format,
      );
      await widget.libraryService.addDownloadedTrack(
        title: response.title,
        absolutePath: response.filePath,
        source: format == DownloadFormat.mp3 ? TrackSource.youtubeMp3 : TrackSource.youtubeMp4,
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

  Widget _buildAuthCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            if (_authStatus.avatar != null && _authStatus.avatar!.isNotEmpty)
              CircleAvatar(backgroundImage: NetworkImage(_authStatus.avatar!))
            else
              const CircleAvatar(child: Icon(Icons.person)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _authStatus.loggedIn
                    ? 'Signed in as ${_authStatus.profileTitle ?? 'YouTube User'}'
                    : 'Not signed in to YouTube',
              ),
            ),
            if (_authStatus.loggedIn)
              OutlinedButton(onPressed: _logoutYoutube, child: const Text('Logout'))
            else
              ElevatedButton(onPressed: _loginYoutube, child: const Text('Login')),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonalizedHome() {
    if (_feedLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_homeItems.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No recent personalized items found yet.'),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('YouTube Recent Feed', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final item in _homeItems.take(8))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: _artworkThumb(item.thumbnail, size: 38),
                title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(item.channel, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => _openPreview(item),
                trailing: IconButton(
                  icon: const Icon(Icons.download_for_offline),
                  onPressed: _downloading ? null : () => _download(item, DownloadFormat.mp3),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildYoutubePlaylistPanel() {
    return Card(
      child: ExpansionTile(
        title: const Text('YouTube Playlists'),
        subtitle: Text('${_youtubePlaylists.length} playlists'),
        children: [
          for (final playlist in _youtubePlaylists)
            ListTile(
              leading: playlist.thumbnail.isEmpty
                  ? const Icon(Icons.playlist_play)
                  : _artworkThumb(playlist.thumbnail, size: 40),
              title: Text(playlist.title),
              subtitle: Text('${playlist.itemCount} items'),
              trailing: Wrap(
                spacing: 8,
                children: [
                  IconButton(
                    icon: const Icon(Icons.library_music),
                    tooltip: 'View items',
                    onPressed: () => _viewYoutubePlaylistItems(playlist),
                  ),
                  IconButton(
                    icon: const Icon(Icons.download_for_offline),
                    tooltip: 'Download playlist MP3',
                    onPressed: () => _downloadYoutubePlaylist(playlist, DownloadFormat.mp3),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _loginYoutube() async {
    setState(() => _authLoading = true);
    try {
      final url = await widget.youtubeService.startLogin();
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      await Future<void>.delayed(const Duration(seconds: 2));
      await _refreshAuthAndFeed();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Login failed: $error')));
    } finally {
      if (mounted) setState(() => _authLoading = false);
    }
  }

  Future<void> _logoutYoutube() async {
    await widget.youtubeService.logout();
    await _refreshAuthAndFeed();
  }

  Future<void> _refreshAuthAndFeed() async {
    setState(() {
      _feedLoading = true;
      _authLoading = true;
    });
    try {
      final status = await widget.youtubeService.authStatus();
      final playlists = status.loggedIn ? await widget.youtubeService.playlists() : <YoutubePlaylist>[];
      final home = status.loggedIn ? await widget.youtubeService.homeFeed() : <YoutubeSearchItem>[];
      if (!mounted) return;
      setState(() {
        _authStatus = status;
        _youtubePlaylists = playlists;
        _homeItems = home;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _authStatus = const YoutubeAuthStatus(loggedIn: false);
        _youtubePlaylists = <YoutubePlaylist>[];
        _homeItems = <YoutubeSearchItem>[];
      });
    } finally {
      if (mounted) {
        setState(() {
          _feedLoading = false;
          _authLoading = false;
        });
      }
    }
  }

  Future<void> _downloadYoutubePlaylist(YoutubePlaylist playlist, DownloadFormat format) async {
    setState(() => _downloading = true);
    try {
      final items = await widget.youtubeService.downloadPlaylist(
        playlistId: playlist.id,
        format: format,
      );
      for (final result in items) {
        await widget.libraryService.addDownloadedTrack(
          title: result.title,
          absolutePath: result.filePath,
          source: format == DownloadFormat.mp3 ? TrackSource.youtubeMp3 : TrackSource.youtubeMp4,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloaded ${items.length} tracks from ${playlist.title}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Playlist download failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _viewYoutubePlaylistItems(YoutubePlaylist playlist) async {
    try {
      final items = await widget.youtubeService.playlistItems(playlist.id);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.75,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Text(playlist.title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  for (final item in items)
                    ListTile(
                      leading: _artworkThumb(item.thumbnail, size: 40),
                      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(item.channel),
                      onTap: () => _openPreview(item),
                      trailing: IconButton(
                        icon: const Icon(Icons.download_for_offline),
                        onPressed: () => _download(item, DownloadFormat.mp3),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load playlist items: $error')),
      );
    }
  }

  Future<void> _openPreview(YoutubeSearchItem item) async {
    bool audioOnly = false;
    final controller = YoutubePlayerController.fromVideoId(
      videoId: item.videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(showFullscreenButton: true),
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                        Switch(
                          value: audioOnly,
                          onChanged: (value) {
                            setModalState(() => audioOnly = value);
                            controller.setVolume(value ? 100 : 100);
                          },
                        ),
                        const Text('Audio only'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (audioOnly)
                      const SizedBox(
                        height: 120,
                        child: Center(
                          child: Text('Audio-only preview enabled'),
                        ),
                      )
                    else
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
      },
    );
    controller.close();
  }

  Future<void> _loadBackendUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('backend_url');
    if (saved == null || saved.trim().isEmpty) return;
    widget.youtubeService.setBaseUrl(saved);
    if (!mounted) return;
    setState(() => _backendUrlController.text = saved);
  }

  Future<void> _saveBackendUrl() async {
    final value = _backendUrlController.text.trim();
    if (value.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('backend_url', value);
    widget.youtubeService.setBaseUrl(value);
    await _refreshAuthAndFeed();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Backend URL saved: $value')),
    );
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
