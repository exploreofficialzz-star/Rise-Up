import 'package:dio/dio.dart';
import '../config/app_constants.dart';
import '../utils/storage_service.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late Dio _dio;
  // uses global storageService

  ApiService._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: kApiBaseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      headers: {'Content-Type': 'application/json'},
    ));

    // Auth interceptor
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await storageService.read(key: 'access_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          // Try token refresh
          final refreshed = await _refreshToken();
          if (refreshed) {
            final token = await storageService.read(key: 'access_token');
            error.requestOptions.headers['Authorization'] = 'Bearer $token';
            final retryRes = await _dio.fetch(error.requestOptions);
            return handler.resolve(retryRes);
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
      final res = await _dio.post('/auth/refresh', data: {'refresh_token': refresh});
      await storageService.write(key: 'access_token', value: res.data['access_token']);
      await storageService.write(key: 'refresh_token', value: res.data['refresh_token']);
      return true;
    } catch (_) { return false; }
  }

  // ── Auth ────────────────────────────────────────────
  Future<Map> signUp(String email, String password, String? name) async {
    final res = await _dio.post('/auth/signup', data: {
      'email': email, 'password': password, 'full_name': name
    });
    return res.data;
  }

  Future<Map> signIn(String email, String password) async {
    final res = await _dio.post('/auth/signin', data: {
      'email': email, 'password': password
    });
    final data = res.data;
    await storageService.write(key: 'access_token', value: data['access_token']);
    await storageService.write(key: 'refresh_token', value: data['refresh_token']);
    await storageService.write(key: 'user_id', value: data['user_id']);
    return data;
  }

  Future<void> signOut() async {
    await storageService.deleteAll();
  }

  Future<String?> getToken() => storageService.read(key: 'access_token');
  Future<String?> getUserId() => storageService.read(key: 'user_id');
  Future<bool> isAuthenticated() async => (await getToken()) != null;

  // ── AI Chat ──────────────────────────────────────────
  Future<Map> chat({
    required String message,
    String? conversationId,
    String mode = 'general',
    String? preferredModel,
  }) async {
    final res = await _dio.post('/ai/chat', data: {
      'message': message,
      if (conversationId != null) 'conversation_id': conversationId,
      'mode': mode,
      if (preferredModel != null) 'preferred_model': preferredModel,
    });
    return res.data;
  }

  Future<Map> generateTasks({int count = 5, String? category}) async {
    final res = await _dio.post('/ai/generate-tasks', data: {
      'count': count,
      if (category != null) 'category': category,
    });
    return res.data;
  }

  Future<Map> generateRoadmap() async {
    final res = await _dio.post('/ai/generate-roadmap');
    return res.data;
  }

  Future<List> getConversations() async {
    final res = await _dio.get('/ai/conversations');
    return res.data['conversations'] as List;
  }

  Future<List> getMessages(String conversationId) async {
    final res = await _dio.get('/ai/conversations/$conversationId/messages');
    return res.data['messages'] as List;
  }

  Future<List> getAvailableModels() async {
    final res = await _dio.get('/ai/models');
    return res.data['models'] as List;
  }

  // ── Tasks ────────────────────────────────────────────
  Future<List> getTasks({String? status}) async {
    final res = await _dio.get('/tasks/', queryParameters: {
      if (status != null) 'status': status
    });
    return res.data['tasks'] as List;
  }

  Future<Map> updateTask(String taskId, {String? status, double? earnings}) async {
    final res = await _dio.patch('/tasks/$taskId', data: {
      if (status != null) 'status': status,
      if (earnings != null) 'actual_earnings': earnings,
    });
    return res.data;
  }

  Future<Map> skipTask(String taskId) async {
    final res = await _dio.delete('/tasks/$taskId');
    return res.data;
  }

  // ── Skills ────────────────────────────────────────────
  Future<Map> getSkillModules() async {
    final res = await _dio.get('/skills/modules');
    return res.data;
  }

  Future<Map> enrollSkill(String moduleId) async {
    final res = await _dio.post('/skills/enroll', data: {'module_id': moduleId});
    return res.data;
  }

  Future<List> getMyCourses() async {
    final res = await _dio.get('/skills/my-courses');
    return res.data['enrollments'] as List;
  }

  Future<Map> updateSkillProgress({
    required String enrollmentId,
    required int progressPercent,
    required int currentLesson,
    double? earnings,
  }) async {
    final res = await _dio.patch('/skills/progress', data: {
      'enrollment_id': enrollmentId,
      'progress_percent': progressPercent,
      'current_lesson': currentLesson,
      if (earnings != null) 'earnings_from_skill': earnings,
    });
    return res.data;
  }

  // ── Payments ──────────────────────────────────────────
  Future<Map> initiatePayment({String plan = 'monthly', String currency = 'NGN'}) async {
    final res = await _dio.post('/payments/initiate', data: {
      'plan': plan, 'currency': currency
    });
    return res.data;
  }

  Future<Map> verifyPayment({required String txRef, String? transactionId}) async {
    final res = await _dio.post('/payments/verify', data: {
      'tx_ref': txRef,
      if (transactionId != null) 'transaction_id': transactionId,
    });
    return res.data;
  }

  Future<Map> unlockViaAd({required String featureKey, required String adUnitId, int hours = 1}) async {
    final res = await _dio.post('/payments/ad-unlock', data: {
      'feature_key': featureKey, 'ad_unit_id': adUnitId, 'duration_hours': hours,
    });
    return res.data;
  }

  Future<Map> checkFeatureAccess(String featureKey) async {
    final res = await _dio.get('/payments/check-access/$featureKey');
    return res.data;
  }

  Future<Map> getSubscriptionStatus() async {
    final res = await _dio.get('/payments/subscription-status');
    return res.data;
  }

  // ── Progress ──────────────────────────────────────────
  Future<Map> getStats() async {
    final res = await _dio.get('/progress/stats');
    return res.data;
  }

  Future<Map> getEarnings() async {
    final res = await _dio.get('/progress/earnings');
    return res.data;
  }

  Future<Map> getRoadmap() async {
    final res = await _dio.get('/progress/roadmap');
    return res.data;
  }

  Future<Map> getProfile() async {
    final res = await _dio.get('/progress/profile');
    return res.data;
  }

  Future<Map> updateProfile(Map<String, dynamic> data) async {
    final res = await _dio.patch('/progress/profile', data: data);
    return res.data;
  }

  Future<Map> logEarning({
    required double amount,
    required String sourceType,
    String? sourceId,
    String? description,
    String currency = 'NGN',
  }) async {
    final res = await _dio.post('/progress/log-earning', data: {
      'amount': amount, 'source_type': sourceType,
      if (sourceId != null) 'source_id': sourceId,
      if (description != null) 'description': description,
      'currency': currency,
    });
    return res.data;
  }
}

  // ── Password Reset ───────────────────────────────────────
  Future<Map> forgotPassword(String email) async {
    final res = await _dio.post('/auth/forgot-password', data: {'email': email});
    return res.data;
  }

  Future<Map> resendVerification(String email) async {
    final res = await _dio.post('/auth/resend-verification', data: {'email': email});
    return res.data;
  }

  // ── Version Check ────────────────────────────────────────
  Future<Map> checkVersion(String appVersion) async {
    final res = await _dio.get('/auth/version', queryParameters: {'app_version': appVersion});
    return res.data;
  }

// Global instance
final api = ApiService();
