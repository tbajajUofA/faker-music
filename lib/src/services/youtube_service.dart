import 'dart:io';

import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

/// Only MP3 is active in the phone-only flow. MP4 is kept so existing persisted
/// source values and future video support do not need another model change.
enum DownloadFormat { mp3, mp4 }

class YoutubeSearchItem {
  const YoutubeSearchItem({
    required this.videoId,
    required this.title,
    required this.channel,
    required this.thumbnail,
  });

  final String videoId;
  final String title;
  final String channel;
  final String thumbnail;

  factory YoutubeSearchItem.fromJson(Map<String, dynamic> json) {
    return YoutubeSearchItem(
      videoId: json['videoId'] as String,
      title: json['title'] as String,
      channel: json['channel'] as String? ?? '',
      thumbnail: json['thumbnail'] as String? ?? '',
    );
  }
}

class YoutubeDownloadResult {
  const YoutubeDownloadResult({
    required this.filePath,
    required this.title,
    this.thumbnail,
  });

  final String filePath;
  final String title;
  final String? thumbnail;
}

class YoutubeAuthStatus {
  const YoutubeAuthStatus({
    required this.loggedIn,
    this.profileTitle,
    this.avatar,
  });

  final bool loggedIn;
  final String? profileTitle;
  final String? avatar;
}

class YoutubePlaylist {
  const YoutubePlaylist({
    required this.id,
    required this.title,
    required this.itemCount,
    required this.thumbnail,
  });

  final String id;
  final String title;
  final int itemCount;
  final String thumbnail;
}

class YoutubeService {
  YoutubeService({
    Dio? dio,
    String? baseUrl,
    yt.YoutubeExplode? youtube,
  })  : _baseUrl = _normalizeUrl(
          baseUrl ?? const String.fromEnvironment('BACKEND_URL', defaultValue: 'http://10.0.2.2:8787'),
        ),
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 2),
                receiveTimeout: const Duration(seconds: 8),
              ),
            ),
        _youtube = youtube ?? yt.YoutubeExplode();

  final Dio _dio;
  final yt.YoutubeExplode _youtube;
  String _baseUrl;
  final Map<String, ({DateTime createdAt, List<YoutubeSearchItem> items})> _cache =
      <String, ({DateTime createdAt, List<YoutubeSearchItem> items})>{};
  static const Duration _cacheTtl = Duration(seconds: 30);
  String get baseUrl => _baseUrl;

  void setBaseUrl(String value) {
    _baseUrl = _normalizeUrl(value);
  }

  Future<List<YoutubeSearchItem>> search(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return const <YoutubeSearchItem>[];

    final cacheKey = normalized.toLowerCase();
    final cached = _cache[cacheKey];
    if (cached != null && DateTime.now().difference(cached.createdAt) < _cacheTtl) {
      return cached.items;
    }

    final videos = await _youtube.search.search(normalized);
    final parsed = videos.take(25).map((video) {
      return YoutubeSearchItem(
        videoId: video.id.value,
        title: video.title,
        channel: video.author,
        thumbnail: _thumbnailFor(video),
      );
    }).toList();
    _cache[cacheKey] = (createdAt: DateTime.now(), items: parsed);
    return parsed;
  }

  Future<YoutubeDownloadResult> downloadWithFallback({
    required YoutubeSearchItem item,
    required DownloadFormat format,
  }) {
    return downloadOnDevice(item: item, format: format);
  }

  Future<YoutubeDownloadResult> downloadOnDevice({
    required YoutubeSearchItem item,
    required DownloadFormat format,
  }) async {
    if (format != DownloadFormat.mp3) {
      throw UnsupportedError('Phone-only downloads currently support MP3 audio only.');
    }

    final supportDir = await getApplicationSupportDirectory();
    final downloadDir = Directory(p.join(supportDir.path, 'youtube_mp3'));
    final tempDir = Directory(p.join(supportDir.path, 'youtube_temp'));
    if (!downloadDir.existsSync()) downloadDir.createSync(recursive: true);
    if (!tempDir.existsSync()) tempDir.createSync(recursive: true);

    final manifest = await _youtube.videos.streamsClient.getManifest(item.videoId);
    final audio = manifest.audioOnly.withHighestBitrate();
    final baseName = _safeFileName(item.title, fallback: item.videoId);
    final sourceExt = audio.container.name;
    final sourcePath = p.join(tempDir.path, '$baseName.$sourceExt');
    final outputPath = await _uniqueOutputPath(downloadDir.path, baseName, 'mp3');

    final stream = _youtube.videos.streamsClient.get(audio);
    final output = File(sourcePath).openWrite();
    await stream.pipe(output);

    try {
      await _transcodeToMp3(sourcePath: sourcePath, outputPath: outputPath);
    } finally {
      final sourceFile = File(sourcePath);
      if (await sourceFile.exists()) {
        await sourceFile.delete();
      }
    }

    return YoutubeDownloadResult(
      filePath: outputPath,
      title: item.title,
      thumbnail: item.thumbnail,
    );
  }

  // Dormant backend/OAuth hooks retained for the future personalized feed work.
  Future<String> startLogin() async {
    final response = await _requestWithFallback((url) => _dio.get('$url/auth/youtube/start'));
    final payload = response.data as Map<String, dynamic>;
    return payload['authUrl'] as String;
  }

  Future<YoutubeAuthStatus> authStatus() async {
    return const YoutubeAuthStatus(loggedIn: false);
  }

  Future<void> logout() async {}

  Future<List<YoutubeSearchItem>> homeFeed() async {
    return const <YoutubeSearchItem>[];
  }

  Future<List<YoutubePlaylist>> playlists() async {
    return const <YoutubePlaylist>[];
  }

  Future<List<YoutubeSearchItem>> playlistItems(String playlistId) async {
    return const <YoutubeSearchItem>[];
  }

  Future<List<YoutubeDownloadResult>> downloadPlaylist({
    required String playlistId,
    required DownloadFormat format,
  }) async {
    return const <YoutubeDownloadResult>[];
  }

  Future<YoutubeDownloadResult> downloadViaBackend({
    required YoutubeSearchItem item,
    required DownloadFormat format,
  }) async {
    final response = await _requestWithFallback(
      (url) => _dio.post(
        '$url/youtube/download/video',
        data: <String, dynamic>{
          'videoId': item.videoId,
          'title': item.title,
          'format': format.name,
        },
      ),
    );
    final payload = response.data as Map<String, dynamic>;
    final resultList = payload['items'] as List<dynamic>? ?? <dynamic>[];
    final first = resultList.isNotEmpty ? resultList.first as Map<String, dynamic> : payload;
    return YoutubeDownloadResult(
      filePath: first['filePath'] as String,
      title: first['title'] as String? ?? 'Untitled',
      thumbnail: item.thumbnail,
    );
  }

  Future<void> _transcodeToMp3({
    required String sourcePath,
    required String outputPath,
  }) async {
    final session = await FFmpegKit.executeWithArguments(<String>[
      '-y',
      '-i',
      sourcePath,
      '-vn',
      '-codec:a',
      'libmp3lame',
      '-b:a',
      '192k',
      outputPath,
    ]);
    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getAllLogsAsString();
      throw Exception('MP3 conversion failed: $logs');
    }
  }

  Future<String> _uniqueOutputPath(String directory, String baseName, String extension) async {
    var candidate = p.join(directory, '$baseName.$extension');
    var counter = 2;
    while (await File(candidate).exists()) {
      candidate = p.join(directory, '$baseName-$counter.$extension');
      counter += 1;
    }
    return candidate;
  }

  String _safeFileName(String value, {required String fallback}) {
    final sanitized = value
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (sanitized.isEmpty) return fallback;
    return sanitized.length > 80 ? sanitized.substring(0, 80).trim() : sanitized;
  }

  String _thumbnailFor(yt.Video video) {
    final thumbnails = video.thumbnails;
    return thumbnails.mediumResUrl.isNotEmpty
        ? thumbnails.mediumResUrl
        : thumbnails.standardResUrl;
  }

  Future<Response<dynamic>> _requestWithFallback(
    Future<Response<dynamic>> Function(String baseUrl) call,
  ) async {
    final candidates = _candidateBaseUrls();
    Object? lastError;
    for (final candidate in candidates) {
      try {
        return await call(candidate);
      } catch (error) {
        lastError = error;
      }
    }
    throw Exception(
      'Unable to reach backend. Tried: ${candidates.join(', ')}. Last error: $lastError',
    );
  }

  List<String> _candidateBaseUrls() {
    final set = <String>{_baseUrl};
    if (Platform.isAndroid) {
      set.add('http://10.0.2.2:8787');
    }
    set.add('http://127.0.0.1:8787');
    set.add('http://localhost:8787');
    return set.toList();
  }

  static String _normalizeUrl(String value) {
    return value.trim().replaceAll(RegExp(r'/$'), '');
  }

  void close() {
    _youtube.close();
  }
}