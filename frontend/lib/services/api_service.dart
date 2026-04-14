// frontend/lib/services/api_service.dart
//
// Changes vs original:
//  • _addAuthInterceptor: when refresh fails → authService.onAuthenticationFailed()
//  • signIn now calls authService.onLoginSuccess()
//  • signOut now calls authService.onLogout()
//  • registerFcmToken updated to named parameters    ← NEW (matches notification_service.dart)
//  • unregisterFcmToken added                        ← NEW
//
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import '../config/app_constants.dart';
import '../utils/storage_service.dart';
import 'auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Custom exception
// ─────────────────────────────────────────────────────────────────────────────
class ApiException implements Exception {
  final int? statusCode;
  final String message;
  const ApiException(this.message, {this.statusCode});

  @override
  String toString() =>
      statusCode != null ? '[$statusCode] $message' : message;
}

// ─────────────────────────────────────────────────────────────────────────────
// MIME helpers
// ─────────────────────────────────────────────────────────────────────────────
Map<String, String> _mimeFromPath(String filePath) {
  final ext = p.extension(filePath).toLowerCase().replaceFirst('.', '');
  const map = <String, String>{
    'jpg':  'jpeg',
    'jpeg': 'jpeg',
    'png':  'png',
    'webp': 'webp',
    'gif':  'gif',
    'heic': 'heic',
    'heif': 'heif',
    'avif': 'avif',
    'bmp':  'bmp',
    'tiff': 'tiff',
    'tif':  'tiff',
    'svg':  'svg+xml',
    'ico':  'x-icon',
    'mp4':  'mp4',
    'mov':  'quicktime',
    'avi':  'x-msvideo',
    'mkv':  'x-matroska',
    'webm': 'webm',
    '3gp':  '3gpp',
  };
  final subtype = map[ext] ?? 'jpeg';
  final isVideo = ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'].contains(ext);
  return {
    'type':    isVideo ? 'video' : 'image',
    'subtype': subtype,
    'ext':     ext.isEmpty ? 'jpg' : ext,
    'mime':    '${isVideo ? "video" : "image"}/$subtype',
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// ApiService
// ─────────────────────────────────────────────────────────────────────────────
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late final Dio _dio;
  late final Dio _uploadDio;

  bool _isRefreshing = false;

  ApiService._internal() {
    _dio = Dio(BaseOptions(
      baseUrl:        kApiBaseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 90),
      sendTimeout:    const Duration(seconds: 120),
      headers: {'Content-Type': 'application/json'},
    ));

    _uploadDio = Dio(BaseOptions(
      baseUrl:        kApiBaseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout:    const Duration(minutes: 10),
      headers: {'Content-Type': 'multipart/form-data'},
    ));

    _addAuthInterceptor(_dio);
    _addAuthInterceptor(_uploadDio);
  }

  void _addAuthInterceptor(Dio dio) {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await storageService.read(key: 'access_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onResponse: (response, handler) => handler.next(response),
      onError: (error, handler) async {
        if (error.response?.statusCode == 401 && !_isRefreshing) {
          _isRefreshing = true;
          final refreshed = await _refreshToken();
          _isRefreshing = false;

          if (refreshed) {
            final token = await storageService.read(key: 'access_token');
            error.requestOptions.headers['Authorization'] = 'Bearer $token';
            try {
              final retry = await dio.fetch(error.requestOptions);
              return handler.resolve(retry);
            } catch (_) {
              return handler.next(error);
            }
          } else {
           await authService.onLogout();
            return handler.next(error);
          }
        }
        return handler.next(error);
      },
    ));
  }

  Future<bool> _refreshToken() async {
    try {
      final refresh = await storageService.read(key: 'refresh_token');
      if (refresh == null) return false;
      final res = await _dio.post('/auth/refresh',
          data: {'refresh_token': refresh});
      await storageService.write(
          key: 'access_token', value: res.data['access_token'] as String);
      await storageService.write(
          key: 'refresh_token', value: res.data['refresh_token'] as String);
      return true;
    } catch (_) {
      return false;
    }
  }

  ApiException _handleError(dynamic e) {
    if (e is DioException) {
      final data = e.response?.data;
      final msg  =
          (data is Map ? data['detail'] ?? data['message'] : null) ??
              e.message ??
              'Something went wrong';
      return ApiException(msg.toString(), statusCode: e.response?.statusCode);
    }
    return ApiException(e.toString());
  }

  // ── Generic HTTP helpers ─────────────────────────────────────────────────

  Future<dynamic> get(String path, {Map<String, dynamic>? queryParams}) async {
    try {
      final res = await _dio.get(path, queryParameters: queryParams);
      return res.data;
    } catch (e) { throw _handleError(e); }
  }

  Future<dynamic> post(String path, Map<String, dynamic> data,
      {Map<String, dynamic>? queryParams}) async {
    try {
      final res = await _dio.post(path,
          data: data, queryParameters: queryParams);
      return res.data;
    } catch (e) { throw _handleError(e); }
  }

  Future<dynamic> patch(String path, Map<String, dynamic> data,
      {Map<String, dynamic>? queryParams}) async {
    try {
      final res = await _dio.patch(path,
          data: data, queryParameters: queryParams);
      return res.data;
    } catch (e) { throw _handleError(e); }
  }

  Future<dynamic> put(String path, Map<String, dynamic> data,
      {Map<String, dynamic>? queryParams}) async {
    try {
      final res = await _dio.put(path,
          data: data, queryParameters: queryParams);
      return res.data;
    } catch (e) { throw _handleError(e); }
  }

  Future<dynamic> delete(String path,
      {Map<String, dynamic>? queryParams}) async {
    try {
      final res = await _dio.delete(path, queryParameters: queryParams);
      return res.data;
    } catch (e) { throw _handleError(e); }
  }

  // ── Auth ─────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> signUp(
      String email, String password, String? name) async {
    try {
      final res = await _dio.post('/auth/signup', data: {
        'email': email, 'password': password, 'full_name': name,
      });
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> signIn(String email, String password) async {
    try {
      final res = await _dio.post('/auth/signin',
          data: {'email': email, 'password': password});
      final data = res.data as Map<String, dynamic>;
      await storageService.write(
          key: 'access_token', value: data['access_token'] as String);
      await storageService.write(
          key: 'refresh_token', value: data['refresh_token'] as String);
      await storageService.write(
          key: 'user_id', value: data['user_id'] as String);
      authService.onLoginSuccess();
      return data;
    } catch (e) { throw _handleError(e); }
  }

  Future<void> signOut() async {
    try { await _dio.post('/auth/signout', data: {}); } catch (_) {}
    await authService.onLogout();
  }

  Future<Map<String, dynamic>> forgotPassword(String email) async {
    try {
      final res = await _dio.post('/auth/forgot-password',
          data: {'email': email});
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> resendVerification(String email) async {
    try {
      final res = await _dio.post('/auth/resend-verification',
          data: {'email': email});
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> checkVersion(String appVersion) async {
    try {
      final res = await _dio.get('/auth/version',
          queryParameters: {'app_version': appVersion});
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<String?> getToken()  => storageService.read(key: 'access_token');
  Future<String?> getUserId() => storageService.read(key: 'user_id');

  Future<bool> isAuthenticated() async {
    try { return (await getToken()) != null; } catch (_) { return false; }
  }

  // ── AI Chat ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> chat({
    required String message,
    String? conversationId,
    String mode = 'general',
    String? preferredModel,
  }) async {
    try {
      final res = await _dio.post('/ai/chat', data: {
        'message': message,
        if (conversationId != null) 'conversation_id': conversationId,
        'mode': mode,
        if (preferredModel != null) 'preferred_model': preferredModel,
      });
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> generateTasks(
      {int count = 5, String? category}) async {
    try {
      final res = await _dio.post('/ai/generate-tasks', data: {
        'count': count,
        if (category != null) 'category': category,
      });
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> generateRoadmap() async {
    try {
      final res = await _dio.post('/ai/generate-roadmap', data: {});
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<List<dynamic>> getAiConversations() async {
    try {
      final res = await _dio.get('/ai/conversations');
      return (res.data['conversations'] as List?) ?? [];
    } catch (e) { throw _handleError(e); }
  }

  Future<List<dynamic>> getMessages(String conversationId) async {
    try {
      final res = await _dio.get('/ai/conversations/$conversationId/messages');
      return (res.data['messages'] as List?) ?? [];
    } catch (e) { throw _handleError(e); }
  }

  Future<List<dynamic>> getAvailableModels() async {
    try {
      final res = await _dio.get('/ai/models');
      return (res.data['models'] as List?) ?? [];
    } catch (e) { throw _handleError(e); }
  }

  // ── Tasks ────────────────────────────────────────────────────────────────

  Future<List<dynamic>> getTasks({String? status}) async {
    try {
      final res = await _dio.get('/tasks/',
          queryParameters: {if (status != null) 'status': status});
      return (res.data['tasks'] as List?) ?? [];
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> updateTask(String taskId,
      {String? status, double? earnings}) async {
    try {
      final res = await _dio.patch('/tasks/$taskId', data: {
        if (status   != null) 'status': status,
        if (earnings != null) 'actual_earnings': earnings,
      });
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> skipTask(String taskId) async {
    try {
      final res = await _dio.delete('/tasks/$taskId');
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  // ── Skills ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getSkillModules() async {
    try {
      final res = await _dio.get('/skills/modules');
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> enrollSkill(String moduleId) async {
    try {
      final res = await _dio.post('/skills/enroll',
          data: {'module_id': moduleId});
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<List<dynamic>> getMyCourses() async {
    try {
      final res = await _dio.get('/skills/my-courses');
      return (res.data['enrollments'] as List?) ?? [];
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> updateSkillProgress({
    required String enrollmentId,
    required int progressPercent,
    required int currentLesson,
    double? earnings,
  }) async {
    try {
      final res = await _dio.patch('/skills/progress', data: {
        'enrollment_id':    enrollmentId,
        'progress_percent': progressPercent,
        'current_lesson':   currentLesson,
        if (earnings != null) 'earnings_from_skill': earnings,
      });
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  // ── Payments ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> initiatePayment(
      {String plan = 'monthly', String currency = 'NGN'}) async {
    try {
      final res = await _dio.post('/payments/initiate',
          data: {'plan': plan, 'currency': currency});
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> verifyPayment(
      {required String txRef, String? transactionId}) async {
    try {
      final res = await _dio.post('/payments/verify', data: {
        'tx_ref': txRef,
        if (transactionId != null) 'transaction_id': transactionId,
      });
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> unlockViaAd({
    required String featureKey,
    required String adUnitId,
    int hours = 1,
  }) async {
    try {
      final res = await _dio.post('/payments/ad-unlock', data: {
        'feature_key':    featureKey,
        'ad_unit_id':     adUnitId,
        'duration_hours': hours,
      });
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> checkFeatureAccess(String featureKey) async {
    try {
      final res = await _dio.get('/payments/check-access/$featureKey');
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getSubscriptionStatus() async {
    try {
      final res = await _dio.get('/payments/subscription-status');
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  // ── Progress ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getStats() async {
    try {
      final res = await _dio.get('/progress/stats');
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getEarnings() async {
    try {
      final res = await _dio.get('/progress/earnings');
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getRoadmap() async {
    try {
      final res = await _dio.get('/progress/roadmap');
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getProfile() async {
    try {
      final res = await _dio.get('/progress/profile');
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> updateProfile(
      Map<String, dynamic> data) async {
    try {
      final res = await _dio.patch('/progress/profile', data: data);
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> logEarning({
    required double amount,
    required String sourceType,
    String? sourceId,
    String? description,
    String currency = 'NGN',
  }) async {
    try {
      final res = await _dio.post('/progress/log-earning', data: {
        'amount':      amount,
        'source_type': sourceType,
        if (sourceId    != null) 'source_id':   sourceId,
        if (description != null) 'description': description,
        'currency': currency,
      });
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  // ── Avatar Upload ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> uploadAvatar(String filePath) async {
    try {
      final mime     = _mimeFromPath(filePath);
      final mimeType = mime['type']!;
      final subtype  = mime['subtype']!;
      final ext      = mime['ext']!;

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          filePath,
          filename:    'avatar.$ext',
          contentType: DioMediaType(mimeType, subtype),
        ),
      });

      final res = await _uploadDio.post(
        '/progress/avatar',
        data: formData,
        options: Options(headers: {'Content-Type': 'multipart/form-data'}),
      );
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> uploadAvatarBytes({
    required List<int> bytes,
    required String filename,
    String mimeType = 'image/jpeg',
  }) async {
    try {
      final parts    = mimeType.split('/');
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename:    filename,
          contentType: DioMediaType(
              parts[0], parts.length > 1 ? parts[1] : 'jpeg'),
        ),
      });
      final res = await _uploadDio.post(
        '/progress/avatar',
        data: formData,
        options: Options(headers: {'Content-Type': 'multipart/form-data'}),
      );
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  // ── Link Preview ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getLinkPreview(String url) async {
    try {
      final r = await _dio.get('/posts/link-preview',
          queryParameters: {'url': url});
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  // ── Post / Status Media Upload ────────────────────────────────────────────

  Future<Map<String, dynamic>> uploadPostMedia(String filePath) async {
    try {
      final mime     = _mimeFromPath(filePath);
      final mimeType = mime['type']!;
      final subtype  = mime['subtype']!;
      final ext      = mime['ext']!;
      final fileName =
          'post_media_${DateTime.now().millisecondsSinceEpoch}.$ext';

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          filePath,
          filename:    fileName,
          contentType: DioMediaType(mimeType, subtype),
        ),
      });

      final res = await _uploadDio.post(
        '/posts/status/upload-media',
        data: formData,
        options: Options(headers: {'Content-Type': 'multipart/form-data'}),
      );
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> uploadPostMediaBytes({
    required List<int> bytes,
    required String filename,
    required String mimeType,
  }) async {
    try {
      final parts    = mimeType.split('/');
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename:    filename,
          contentType: DioMediaType(
              parts[0], parts.length > 1 ? parts[1] : 'jpeg'),
        ),
      });
      final res = await _uploadDio.post(
        '/posts/status/upload-media',
        data: formData,
        options: Options(headers: {'Content-Type': 'multipart/form-data'}),
      );
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  // ── Social / Posts ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getFeed(
      {String tab = 'for_you', int limit = 20, int offset = 0}) async {
    try {
      final r = await _dio.get('/posts/feed', queryParameters: {
        'tab': tab, 'limit': limit, 'offset': offset,
      });
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> createPost({
  required String content,
  required String tag,
  String? mediaUrl,
  String? mediaType,
  String? linkUrl,
  String? linkTitle,
  String? backgroundColor,   // ← NEW PARAMETER
}) async {
  try {
    final r = await _dio.post('/posts', data: {
      'content': content,
      'tag':     tag,
      if (mediaUrl  != null && mediaUrl.isNotEmpty)  'media_url':  mediaUrl,
      if (mediaType != null && mediaType.isNotEmpty) 'media_type': mediaType,
      if (linkUrl   != null && linkUrl.isNotEmpty)   'link_url':   linkUrl,
      if (linkTitle != null && linkTitle.isNotEmpty) 'link_title': linkTitle,
      if (backgroundColor != null) 'background_color': backgroundColor, // ← NEW FIELD
    });
    return r.data as Map<String, dynamic>;
  } catch (e) { throw _handleError(e); }
  }
  
  Future<Map<String, dynamic>> updatePost(
    String postId, {
    String? content,
    String? tag,
    String? linkUrl,
    String? linkTitle,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (content   != null) body['content']   = content;
      if (tag       != null) body['tag']        = tag;
      if (linkUrl   != null) body['link_url']   = linkUrl;
      if (linkTitle != null) body['link_title'] = linkTitle;

      final r = await _dio.patch('/posts/$postId', data: body);
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> toggleLike(String postId) async {
    try {
      final r = await _dio.post('/posts/$postId/like', data: {});
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> toggleSave(String postId) async {
    try {
      final r = await _dio.post('/posts/$postId/save', data: {});
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> sharePost(String postId) async {
    try {
      final r = await _dio.post('/posts/$postId/share', data: {});
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> deletePost(String postId) async {
    try {
      final r = await _dio.delete('/posts/$postId');
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getPostComments(String postId) async {
    try {
      final r = await _dio.get('/posts/$postId/comments');
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> addComment(String postId, String content,
      {String? parentId, bool isAI = false, bool isPinned = false}) async {
    try {
      final r = await _dio.post('/posts/$postId/comments', data: {
        'content': content,
        if (parentId  != null) 'parent_id': parentId,
        if (isAI)              'is_ai':     true,
        if (isPinned)          'is_pinned': true,
      });
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> likeComment(String commentId) async {
    try {
      final r = await _dio.post('/posts/comments/$commentId/like', data: {});
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> toggleFollow(String targetUserId) async {
    try {
      final r = await _dio.post('/posts/users/$targetUserId/follow', data: {});
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getUserProfile(String userId) async {
    try {
      final r = await _dio.get('/posts/users/$userId/profile');
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getUserPosts(String userId) async {
    try {
      final r = await _dio.get('/posts/users/$userId/posts');
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getLikedPosts(String userId) async {
    try {
      final r = await _dio.get('/posts/users/$userId/liked');
      return r.data as Map<String, dynamic>;
    } catch (_) { return {'posts': []}; }
  }

  Future<Map<String, dynamic>> logShare(
      String shareType, String platform) async {
    try {
      final res = await _dio.post('/community/share',
          data: {'share_type': shareType, 'platform': platform});
      return res.data as Map<String, dynamic>;
    } catch (_) { return {}; }
  }

  // ── Status ────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getStatusFeed() async {
    try {
      final r = await _dio.get('/posts/status/feed');
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> createStatus(Map<String, dynamic> data) async {
    try {
      final r = await _dio.post('/posts/status', data: data);
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> viewStatus(String statusId) async {
    try {
      final r = await _dio.post('/posts/status/$statusId/view', data: {});
      return r.data as Map<String, dynamic>;
    } catch (_) { return {'viewed': true}; }
  }

  Future<Map<String, dynamic>> deleteStatus(String statusId) async {
    try {
      final r = await _dio.delete('/posts/status/$statusId');
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  // ── Streaks ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> checkIn() async {
    try {
      final res = await _dio.post('/streaks/check-in', data: {});
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getStreak() async {
    try {
      final res = await _dio.get('/streaks/');
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  // ── Goals ─────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getGoals({String? status}) async {
    try {
      final res = await _dio.get('/goals/',
          queryParameters: {if (status != null) 'status': status});
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> createGoal(Map<String, dynamic> data) async {
    try {
      final res = await _dio.post('/goals/', data: data);
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> updateGoal(
      String goalId, Map<String, dynamic> data) async {
    try {
      final res = await _dio.patch('/goals/$goalId', data: data);
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> contributeToGoal(
      String goalId, double amount, {String? description}) async {
    try {
      final res = await _dio.post('/goals/$goalId/contribute', data: {
        'amount': amount,
        if (description != null) 'description': description,
      });
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> deleteGoal(String goalId) async {
    try {
      final res = await _dio.delete('/goals/$goalId');
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> suggestGoals() async {
    try {
      final res = await _dio.post('/goals/ai-suggest', data: {});
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  // ── Expenses ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getExpenses(
      {String? month, String? category}) async {
    try {
      final res = await _dio.get('/expenses/', queryParameters: {
        if (month    != null) 'month':    month,
        if (category != null) 'category': category,
      });
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> logExpense(Map<String, dynamic> data) async {
    try {
      final res = await _dio.post('/expenses/', data: data);
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> deleteExpense(String expenseId) async {
    try {
      final res = await _dio.delete('/expenses/$expenseId');
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getBudgets({String? month}) async {
    try {
      final res = await _dio.get('/expenses/budgets',
          queryParameters: {if (month != null) 'month': month});
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> setBudget(Map<String, dynamic> data) async {
    try {
      final res = await _dio.post('/expenses/budgets', data: data);
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getMonthlySummary({String? month}) async {
    try {
      final res = await _dio.get('/expenses/summary',
          queryParameters: {if (month != null) 'month': month});
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  // ── Achievements ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getAchievements() async {
    try {
      final res = await _dio.get('/achievements/');
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getMyAchievements() async {
    try {
      final res = await _dio.get('/achievements/my');
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> checkAchievements() async {
    try {
      final res = await _dio.post('/achievements/check', data: {});
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  // ── Referrals ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getMyReferralCode() async {
    try {
      final res = await _dio.get('/referrals/my-code');
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> applyReferralCode(String code) async {
    try {
      final res = await _dio.post('/referrals/apply',
          data: {'referral_code': code});
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  // ── Notifications ─────────────────────────────────────────────────────────

  // ← UPDATED: changed to named parameters to match notification_service.dart
  Future<void> registerFcmToken({
    required String token,
    required String platform,
  }) async {
    try {
      await _dio.post('/notifications/register-token',
          data: {'token': token, 'platform': platform});
    } catch (_) {
      // Non-fatal — app works without push if registration fails
    }
  }

  // ← NEW: called by notification_service.dart on logout
  Future<void> unregisterFcmToken(String token) async {
    try {
      await _dio.delete('/notifications/unregister-token',
          queryParameters: {'token': token});
    } catch (_) {}
  }

  Future<Map<String, dynamic>> getNotifications({int limit = 30}) async {
    try {
      final res = await _dio.get('/notifications/',
          queryParameters: {'limit': limit});
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> markNotificationsRead(
      {List<String>? ids}) async {
    try {
      final res = await _dio.post('/notifications/mark-read', data: {
        if (ids != null) 'notification_ids': ids,
      });
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  // ── Agentic AI ────────────────────────────────────────────────────────────

  Future<dynamic> runAgent({
    required String task,
    double budget = 0,
    double hoursPerDay = 2,
    String currency = 'NGN',
    String? context,
    String? workflowId,
  }) async {
    return post('/agent/run', {
      'task': task, 'budget': budget, 'hours_per_day': hoursPerDay,
      'currency': currency,
      if (context    != null) 'context':     context,
      if (workflowId != null) 'workflow_id': workflowId,
    });
  }

  Future<dynamic> agentChat(String message,
      {String? sessionId, String? workflowId}) async {
    return post('/agent/chat', {
      'message': message,
      if (sessionId  != null) 'session_id':  sessionId,
      if (workflowId != null) 'workflow_id': workflowId,
    });
  }

  Future<dynamic> executeTool(String tool, Map<String, dynamic> input,
      {String? workflowId}) async {
    return post('/agent/execute-tool', {
      'tool': tool, 'input': input,
      if (workflowId != null) 'workflow_id': workflowId,
    });
  }

  Future<dynamic> quickAgent(String task,
      {String outputType = 'any'}) async {
    return post('/agent/quick', {'task': task, 'output_type': outputType});
  }

  Future<dynamic> analyzeAndImprove(String content,
      {String goal = 'improve'}) async {
    return post('/agent/analyze', {'content': content, 'goal': goal});
  }

  // ── Messages ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getConversations() async {
    try {
      final r = await _dio.get('/messages/conversations');
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getOrCreateConversation(
      String otherUserId) async {
    try {
      final r = await _dio.post(
          '/messages/conversations/with/$otherUserId', data: {});
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<List<dynamic>> getDMConversations() async {
    try {
      final r = await _dio.get('/messages/conversations');
      return (r.data['conversations'] as List?) ?? [];
    } catch (e) { throw _handleError(e); }
  }

  Future<List<dynamic>> searchUsers(String q) async {
    try {
      final r = await _dio.get('/messages/users/search',
          queryParameters: {'q': q});
      return (r.data['users'] as List?) ?? [];
    } catch (e) { throw _handleError(e); }
  }

  Future<String> getOrCreateDM(String otherUserId) async {
    try {
      final r = await _dio.post(
          '/messages/conversations/with/$otherUserId', data: {});
      return (r.data['conversation_id'] as String?) ?? '';
    } catch (e) { throw _handleError(e); }
  }

  Future<List<Map<String, dynamic>>> getDMMessages(
    String conversationId, {
    int limit = 50,
    String? since,
  }) async {
    try {
      final r = await _dio.get(
        '/messages/conversations/$conversationId/messages',
        queryParameters: {
          'limit': limit,
          if (since != null) 'since': since,
        },
      );
      final data = r.data;
      if (data is List) {
        return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      if (data is Map) {
        final list = data['messages'] as List?;
        if (list != null) {
          return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
      return [];
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> sendDMMessage(
      String conversationId, String content) async {
    try {
      final r = await _dio.post(
          '/messages/conversations/$conversationId/send',
          data: {'content': content});
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> sendAIMessageInDM(
    String conversationId,
    String content, {
    bool adUnlocked = false,
    List<Map<String, String>> contextHistory = const [],
  }) async {
    try {
      final r = await _dio.post(
        '/messages/conversations/$conversationId/ai-message',
        data: {
          'content':     content,
          'ad_unlocked': adUnlocked,
          if (contextHistory.isNotEmpty) 'context_history': contextHistory,
        },
      );
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getAIQuota() async {
    try {
      final r = await _dio.get('/messages/ai-quota');
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<String> getOrCreateAIConversation() async {
    try {
      final r = await _dio.get('/messages/ai-conversation');
      final id = (r.data['conversation_id'] as String?) ?? '';
      if (id.isNotEmpty) return id;
      throw ApiException('Empty conversation_id');
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        try {
          final r = await _dio.post('/messages/ai-conversation', data: {});
          return (r.data['conversation_id'] as String?) ?? '';
        } catch (inner) { throw _handleError(inner); }
      }
      throw _handleError(e);
    } catch (e) { throw _handleError(e); }
  }

  Future<void> updatePresence() async {
    try { await _dio.post('/messages/presence', data: {}); } catch (_) {}
  }

  Future<void> setOffline() async {
    try { await _dio.delete('/messages/presence', data: {}); } catch (_) {}
  }

  Future<Map<String, dynamic>> inviteAIToConversation(
      String conversationId) async {
    try {
      final r = await _dio.post(
          '/messages/conversations/$conversationId/invite-ai', data: {});
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> removeAIFromConversation(
      String conversationId) async {
    try {
      final r = await _dio.delete(
          '/messages/conversations/$conversationId/remove-ai');
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> checkAIInConversation(
      String conversationId) async {
    try {
      final r = await _dio.get(
          '/messages/conversations/$conversationId/ai-status');
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  // ── Groups ────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getGroups() async {
    try {
      final r = await _dio.get('/messages/groups');
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> toggleGroup(String groupId) async {
    try {
      final r = await _dio.post('/messages/groups/$groupId/join', data: {});
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  // ── Live Sessions ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getLiveSessions() async {
    try {
      final r = await _dio.get('/live/sessions');
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> startLive({
    required String title,
    required String topic,
    bool isPremium = false,
  }) async {
    try {
      final r = await _dio.post('/live/start',
          data: {'title': title, 'topic': topic, 'is_premium': isPremium});
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> endLive() async {
    try {
      final r = await _dio.post('/live/end', data: {});
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> joinLive(String sessionId) async {
    try {
      final r = await _dio.post('/live/sessions/$sessionId/join', data: {});
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> leaveLive(String sessionId) async {
    try {
      final r = await _dio.post('/live/sessions/$sessionId/leave', data: {});
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> sendCoins(String sessionId, int amount) async {
    try {
      final r = await _dio.post('/live/sessions/$sessionId/coins',
          data: {'amount': amount});
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  // ── Income Memory ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> logMemoryEvent({
    required String eventType,
    required String title,
    double amountUsd = 0,
    String? platform,
    String? skillUsed,
    String? outcome,
  }) async {
    try {
      final res = await _dio.post('/memory/event', data: {
        'event_type': eventType,
        'title':      title,
        'amount_usd': amountUsd,
        if (platform  != null) 'platform':   platform,
        if (skillUsed != null) 'skill_used': skillUsed,
        'outcome': outcome ?? 'success',
      });
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getMemoryProfile() async {
    try {
      final res = await _dio.get('/memory/profile');
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getMemoryInsights() async {
    try {
      final res = await _dio.get('/memory/insights');
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getIncomePatterns() async {
    try {
      final res = await _dio.get('/memory/streak-patterns');
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  // ── Market Pulse ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getTodaysPulse() async {
    try {
      final res = await _dio.get('/pulse/today');
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getArbitrageData() async {
    try {
      final res = await _dio.get('/pulse/arbitrage');
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> scanSkillDemand(String skill) async {
    try {
      final res = await _dio.get('/pulse/opportunity-scan',
          queryParameters: {'skill': skill});
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  // ── Contracts & Invoices ──────────────────────────────────────────────────

  Future<Map<String, dynamic>> generateContract(
      Map<String, dynamic> data) async {
    try {
      final res = await _dio.post('/contracts/generate', data: data);
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> generateInvoice(
      Map<String, dynamic> data) async {
    try {
      final res = await _dio.post('/contracts/invoice/generate', data: data);
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> listContracts() async {
    try {
      final res = await _dio.get('/contracts/');
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> markInvoicePaid(String invoiceId) async {
    try {
      final res = await _dio.patch('/contracts/invoice/$invoiceId/paid',
          data: {});
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  // ── Client CRM ────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> addCrmClient(
      Map<String, dynamic> data) async {
    try {
      final res = await _dio.post('/crm/clients', data: data);
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getCrmClients({String? status}) async {
    try {
      final res = await _dio.get('/crm/clients',
          queryParameters: {if (status != null) 'status': status});
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getDueFollowUps() async {
    try {
      final res = await _dio.get('/crm/follow-ups/due');
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> generateFollowUpMessage(
      String clientId) async {
    try {
      final res = await _dio.post('/crm/clients/$clientId/ai-followup',
          data: {});
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getCrmAnalytics() async {
    try {
      final res = await _dio.get('/crm/analytics');
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> updateCrmClient(
      String clientId, Map<String, dynamic> data) async {
    try {
      final res = await _dio.patch('/crm/clients/$clientId', data: data);
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  // ── Income Challenges ─────────────────────────────────────────────────────

  Future<Map<String, dynamic>> createChallenge(String type,
      {String? customGoal, double? targetUsd}) async {
    try {
      final res = await _dio.post('/challenges/create', data: {
        'challenge_type': type,
        if (customGoal != null) 'custom_goal':       customGoal,
        if (targetUsd  != null) 'custom_target_usd': targetUsd,
      });
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> challengeCheckIn(
      String challengeId, String action,
      {double amountUsd = 0, String? note}) async {
    try {
      final res = await _dio.post('/challenges/check-in', data: {
        'challenge_id':      challengeId,
        'action_taken':      action,
        'amount_earned_usd': amountUsd,
        if (note != null) 'note': note,
      });
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> listChallenges() async {
    try {
      final res = await _dio.get('/challenges/');
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getChallenge(String id) async {
    try {
      final res = await _dio.get('/challenges/$id');
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getChallengeIntervention(String id) async {
    try {
      final res = await _dio.post('/challenges/$id/ai-intervention', data: {});
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  // ── Portfolio ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getPortfolio() async {
    try {
      final res = await _dio.get('/portfolio/');
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> addPortfolioProject(
      Map<String, dynamic> data) async {
    try {
      final res = await _dio.post('/portfolio/projects', data: data);
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> generatePortfolioFromWorkflow(
      String workflowId) async {
    try {
      final res = await _dio.post(
          '/portfolio/generate-from-workflow/$workflowId', data: {});
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> generateProfessionalBio() async {
    try {
      final res = await _dio.post('/portfolio/ai-bio', data: {});
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getPublicPortfolio(String userId) async {
    try {
      final res = await _dio.get('/portfolio/public/$userId');
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  // ── Methods Brain ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> brainMentorChat({
    required String message,
    String?  sessionId,
    String   language = 'en',
    List<Map<String, String>> history = const [],
  }) async {
    try {
      final r = await _dio.post('/brain/mentor/chat', data: {
        'message':    message,
        if (sessionId != null) 'session_id': sessionId,
        'language':   language,
        'history':    history,
      });
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> brainInternalSearch(
      String query, {int limit = 5}) async {
    try {
      final r = await _dio.post('/brain/search/internal',
          data: {'query': query, 'limit': limit});
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getBrainMethods({
    String? investmentTier,
    String? category,
    String? skillLevel,
    String? timeToFirst,
    String? search,
    bool?   featured,
    bool?   trending,
    int     limit  = 20,
    int     offset = 0,
  }) async {
    try {
      final r = await _dio.get('/brain/methods', queryParameters: {
        if (investmentTier != null) 'investment_tier': investmentTier,
        if (category       != null) 'category':        category,
        if (skillLevel     != null) 'skill_level':     skillLevel,
        if (timeToFirst    != null) 'time_to_first':   timeToFirst,
        if (search         != null) 'search':          search,
        if (featured       != null) 'featured':        featured,
        if (trending       != null) 'trending':        trending,
        'limit':  limit,
        'offset': offset,
      });
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> searchBrainMethods(
      String query, {int limit = 20}) async {
    try {
      final r = await _dio.get('/brain/methods/search',
          queryParameters: {'q': query, 'limit': limit});
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getBrainMethod(String methodId) async {
    try {
      final r = await _dio.get('/brain/methods/$methodId');
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getFeaturedMethods({int limit = 10}) async {
    try {
      final r = await _dio.get('/brain/methods/featured',
          queryParameters: {'limit': limit});
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getMethodsStats() async {
    try {
      final r = await _dio.get('/brain/methods/stats');
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getMethodTiers() async {
    try {
      final r = await _dio.get('/brain/methods/tiers');
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> trackMethod(
      String methodId, {String status = 'exploring', String? notes}) async {
    try {
      final r = await _dio.post('/brain/methods/$methodId/track',
          data: {'status': status, if (notes != null) 'notes': notes});
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getTrackedMethods({String? status}) async {
    try {
      final r = await _dio.get('/brain/methods/my/tracked',
          queryParameters: {if (status != null) 'status': status});
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> savePositioning(
      Map<String, dynamic> data) async {
    try {
      final r = await _dio.post('/brain/methods/position', data: data);
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getMyPositioning() async {
    try {
      final r = await _dio.get('/brain/methods/positioning/me');
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  // ── Marketplace ───────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getMarketplaceListings({
    String? listingType,
    String? country,
    bool?   isGlobal,
    String? tags,
    String? search,
    int     limit  = 20,
    int     offset = 0,
  }) async {
    try {
      final r = await _dio.get('/brain/marketplace', queryParameters: {
        if (listingType != null) 'listing_type': listingType,
        if (country     != null) 'country':      country,
        if (isGlobal    != null) 'is_global':    isGlobal,
        if (tags        != null) 'tags':         tags,
        if (search      != null) 'search':       search,
        'limit':  limit,
        'offset': offset,
      });
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> createMarketplaceListing(
      Map<String, dynamic> data) async {
    try {
      final r = await _dio.post('/brain/marketplace', data: data);
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> inquireMarketplaceListing(
      String listingId, String message,
      {Map<String, dynamic>? contactInfo}) async {
    try {
      final r = await _dio.post('/brain/marketplace/$listingId/inquire',
          data: {'message': message, 'contact_info': contactInfo ?? {}});
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getMyMarketplaceListings(
      {String? status}) async {
    try {
      final r = await _dio.get('/brain/marketplace/my',
          queryParameters: {if (status != null) 'status': status});
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> deleteMarketplaceListing(
      String listingId) async {
    try {
      final r = await _dio.delete('/brain/marketplace/$listingId');
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  // ── Agentic Tasks ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> createAgenticTask({
    required String title,
    required String description,
    String  taskType = 'custom',
    String  priority = 'normal',
    Map<String, dynamic> inputData = const {},
  }) async {
    try {
      final r = await _dio.post('/brain/task/create', data: {
        'task_type':   taskType,
        'title':       title,
        'description': description,
        'priority':    priority,
        'input_data':  inputData,
      });
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getAgenticTask(String taskId) async {
    try {
      final r = await _dio.get('/brain/task/$taskId');
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> listAgenticTasks(
      {String? status, String? taskType, int limit = 20}) async {
    try {
      final r = await _dio.get('/brain/task', queryParameters: {
        if (status   != null) 'status':    status,
        if (taskType != null) 'task_type': taskType,
        'limit': limit,
      });
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> approveExternalSearch(String taskId) async {
    try {
      final r = await _dio.post(
          '/brain/task/$taskId/approve-external', data: {});
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> approveAgenticExecution(String taskId) async {
    try {
      final r = await _dio.post(
          '/brain/task/$taskId/approve-execute', data: {});
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> cancelAgenticTask(String taskId) async {
    try {
      final r = await _dio.delete('/brain/task/$taskId');
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> getTaskContacts(
      String taskId, {String? contactType, int minScore = 0}) async {
    try {
      final r = await _dio.get('/brain/contacts/$taskId', queryParameters: {
        if (contactType != null) 'contact_type': contactType,
        'min_score': minScore,
      });
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  Future<Map<String, dynamic>> updateAgenticContact(
      String contactId, Map<String, dynamic> data) async {
    try {
      final r = await _dio.patch('/brain/contacts/$contactId', data: data);
      return r.data as Map<String, dynamic>;
    } catch (e) { throw _handleError(e); }
  }

  // ── Adaptive Brain Signals ────────────────────────────────────────────────

  Future<Map<String, dynamic>?> recordPostSignal({
    required String postId,
    required String content,
    String? tag,
  }) async {
    try {
      final r = await _dio.post('/ai/signal/post', data: {
        'post_id': postId,
        'content': content,
        if (tag != null) 'tag': tag,
      });
      return r.data as Map<String, dynamic>?;
    } catch (_) { return null; }
  }

  Future<void> recordInteractionSignal({
    required String action,
    required String postId,
    required String postContent,
  }) async {
    try {
      await _dio.post('/ai/signal/interaction', data: {
        'action':       action,
        'post_id':      postId,
        'post_content': postContent.length > 200
            ? postContent.substring(0, 200)
            : postContent,
      });
    } catch (_) {}
  }

  Future<Map<String, dynamic>> getAdaptiveProfile() async {
    try {
      final r = await _dio.get('/ai/adaptive-profile');
      return (r.data as Map<String, dynamic>?)?['profile']
          as Map<String, dynamic>? ?? {};
    } catch (e) { throw _handleError(e); }
  }

  Future<List<dynamic>> getComplementaryUsers({int limit = 5}) async {
    try {
      final r = await _dio.get('/ai/complementary-users',
          queryParameters: {'limit': limit});
      return (r.data as Map?)?['matches'] as List? ?? [];
    } catch (_) { return []; }
  }

} // end ApiService

// ─────────────────────────────────────────────────────────────────────────────
// Global singleton
// ─────────────────────────────────────────────────────────────────────────────
final api = ApiService();
