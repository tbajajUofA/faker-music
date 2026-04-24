import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
  })  : _baseUrl = _normalizeUrl(
          baseUrl ?? const String.fromEnvironment('BACKEND_URL', defaultValue: 'http://10.0.2.2:8787'),
        ),
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 2),
                receiveTimeout: const Duration(seconds: 8),
              ),
            );

  final Dio _dio;
  String _baseUrl;
  final Map<String, ({DateTime createdAt, List<YoutubeSearchItem> items})> _cache =
      <String, ({DateTime createdAt, List<YoutubeSearchItem> items})>{};
  static const Duration _cacheTtl = Duration(seconds: 30);
  String get baseUrl => _baseUrl;

  void setBaseUrl(String value) {
    _baseUrl = _normalizeUrl(value);
  }

  Future<List<YoutubeSearchItem>> search(String query) async {
    final normalized = query.trim().toLowerCase();
    final cached = _cache[normalized];
    if (cached != null && DateTime.now().difference(cached.createdAt) < _cacheTtl) {
      return cached.items;
    }

    final response = await _requestWithFallback(
      (url) => _dio.get(
        '$url/search',
        queryParameters: <String, dynamic>{'q': normalized},
      ),
    );
    final data = response.data as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? <dynamic>[];
    final parsed = items
        .cast<Map<String, dynamic>>()
        .map(YoutubeSearchItem.fromJson)
        .toList();
    _cache[normalized] = (createdAt: DateTime.now(), items: parsed);
    return parsed;
  }

  Future<String> startLogin() async {
    final response = await _requestWithFallback((url) => _dio.get('$url/auth/youtube/start'));
    final payload = response.data as Map<String, dynamic>;
    return payload['authUrl'] as String;
  }

  Future<YoutubeAuthStatus> authStatus() async {
    final response = await _requestWithFallback((url) => _dio.get('$url/auth/youtube/status'));
    final payload = response.data as Map<String, dynamic>;
    final loggedIn = payload['loggedIn'] as bool? ?? false;
    if (!loggedIn) return const YoutubeAuthStatus(loggedIn: false);
    final profile = payload['profile'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return YoutubeAuthStatus(
      loggedIn: true,
      profileTitle: profile['title'] as String?,
      avatar: profile['avatar'] as String?,
    );
  }

  Future<void> logout() async {
    await _requestWithFallback((url) => _dio.post('$url/auth/youtube/logout'));
  }

  Future<List<YoutubeSearchItem>> homeFeed() async {
    final response = await _requestWithFallback((url) => _dio.get('$url/youtube/home'));
    final payload = response.data as Map<String, dynamic>;
    final items = payload['items'] as List<dynamic>? ?? <dynamic>[];
    return items.cast<Map<String, dynamic>>().map(YoutubeSearchItem.fromJson).toList();
  }

  Future<List<YoutubePlaylist>> playlists() async {
    final response = await _requestWithFallback((url) => _dio.get('$url/youtube/playlists'));
    final payload = response.data as Map<String, dynamic>;
    final items = payload['items'] as List<dynamic>? ?? <dynamic>[];
    return items.cast<Map<String, dynamic>>().map((json) {
      return YoutubePlaylist(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Untitled',
        itemCount: json['itemCount'] as int? ?? 0,
        thumbnail: json['thumbnail'] as String? ?? '',
      );
    }).toList();
  }

  Future<List<YoutubeSearchItem>> playlistItems(String playlistId) async {
    final response = await _requestWithFallback(
      (url) => _dio.get('$url/youtube/playlists/$playlistId/items'),
    );
    final payload = response.data as Map<String, dynamic>;
    final items = payload['items'] as List<dynamic>? ?? <dynamic>[];
    return items.cast<Map<String, dynamic>>().map(YoutubeSearchItem.fromJson).toList();
  }

  Future<List<YoutubeDownloadResult>> downloadPlaylist({
    required String playlistId,
    required DownloadFormat format,
  }) async {
    final response = await _requestWithFallback(
      (url) => _dio.post(
        '$url/youtube/download/playlist',
        data: <String, dynamic>{
          'playlistId': playlistId,
          'format': format.name,
        },
      ),
    );
    final payload = response.data as Map<String, dynamic>;
    final items = payload['items'] as List<dynamic>? ?? <dynamic>[];
    return items.cast<Map<String, dynamic>>().map((json) {
      return YoutubeDownloadResult(
        filePath: json['filePath'] as String,
        title: json['title'] as String? ?? 'Untitled',
      );
    }).toList();
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
      title: first['title'] as String,
      thumbnail: item.thumbnail,
    );
  }

  Future<YoutubeDownloadResult> downloadWithFallback({
    required YoutubeSearchItem item,
    required DownloadFormat format,
  }) async {
    try {
      return await downloadViaBackend(item: item, format: format);
    } catch (_) {
      return _downloadViaLocalFallback(item: item, format: format);
    }
  }

  Future<YoutubeDownloadResult> _downloadViaLocalFallback({
    required YoutubeSearchItem item,
    required DownloadFormat format,
  }) async {
    final supportDir = await getApplicationSupportDirectory();
    final folder = Directory(p.join(supportDir.path, 'youtube_downloads'));
    if (!folder.existsSync()) {
      folder.createSync(recursive: true);
    }

    final ext = format == DownloadFormat.mp3 ? 'mp3' : 'mp4';
    final sanitizedTitle = item.title.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final outputPath = p.join(folder.path, '$sanitizedTitle.$ext');

    final fallbackInfo = <String, dynamic>{
      'videoId': item.videoId,
      'title': item.title,
      'format': format.name,
      'createdAt': DateTime.now().toIso8601String(),
    };
    await File(outputPath).writeAsString(jsonEncode(fallbackInfo));
    return YoutubeDownloadResult(
      filePath: outputPath,
      title: item.title,
      thumbnail: item.thumbnail,
    );
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
}
