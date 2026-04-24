import 'package:flutter/material.dart';

import 'screens/main_shell.dart';
import 'services/music_library_service.dart';
import 'services/player_service.dart';
import 'services/youtube_service.dart';
import 'theme/app_theme.dart';

class RedBlackPlayerApp extends StatefulWidget {
  const RedBlackPlayerApp({super.key});

  @override
  State<RedBlackPlayerApp> createState() => _RedBlackPlayerAppState();
}

class _RedBlackPlayerAppState extends State<RedBlackPlayerApp> {
  final MusicLibraryService _libraryService = MusicLibraryService();
  final PlayerService _playerService = PlayerService();
  final YoutubeService _youtubeService = YoutubeService();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _libraryService.init();
    setState(() => _initialized = true);
  }

  @override
  void dispose() {
    _playerService.dispose();
    _libraryService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Red Black Player',
      theme: AppTheme.darkRed,
      home: _initialized
          ? MainShell(
              libraryService: _libraryService,
              playerService: _playerService,
              youtubeService: _youtubeService,
            )
          : const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
    );
  }
}
