import 'package:dio/dio.dart';
import '../config/app_constants.dart';
import '../utils/storage_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Custom exception so every screen can handle errors uniformly
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
// ApiService — singleton, Dio-based, JWT + refresh token aware
// ─────────────────────────────────────────────────────────────────────────────
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late final Dio _dio;

  /// Guards against infinite refresh loops
  bool _isRefreshing = false;

  ApiService._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: kApiBaseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      headers: {'Content-Type': 'application/json'},
    ));

    // ── Request interceptor: inject auth token ──────────────────
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await storageService.read(key: 'access_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },

      onResponse: (response, handler) {
        return handler.next(response);
      },

      // ── Error interceptor: 401 refresh + unified errors ───────
      onError: (error, handler) async {
        if (error.response?.statusCode == 401 && !_isRefreshing) {
          _isRefreshing = true;
          final refreshed = await _refreshToken();
          _isRefreshing = false;

          if (refreshed) {
            final token = await storageService.read(key: 'access_token');
            error.requestOptions.headers['Authorization'] = 'Bearer $token';
            try {
              final retry = await _dio.fetch(error.requestOptions);
              return handler.resolve(retry);
            } catch (_) {
              return handler.next(error);
            }
          }
        }

        return handler.next(error);
      },
    ));
  }

  // ── Internal: silent token refresh ───────────────────────────
  Future<bool> _refreshToken() async {
    try {
      final refresh = await storageService.read(key: 'refresh_token');
      if (refresh == null) return false;
      final res =
          await _dio.post('/auth/refresh', data: {'refresh_token': refresh});
      await storageService.write(
          key: 'access_token', value: res.data['access_token'] as String);
      await storageService.write(
          key: 'refresh_token', value: res.data['refresh_token'] as String);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Centralized error parser ──────────────────────────────────
  ApiException _handleError(dynamic e) {
    if (e is DioException) {
      final data = e.response?.data;
      final msg = (data is Map ? data['detail'] ?? data['message'] : null) ??
          e.message ??
          'Something went wrong';
      return ApiException(msg.toString(),
          statusCode: e.response?.statusCode);
    }
    return ApiException(e.toString());
  }

  // ─────────────────────────────────────────────────────────────
  // ── Generic HTTP helpers ─────────────────────────────────────
  // ─────────────────────────────────────────────────────────────

  Future<dynamic> get(String path,
      {Map<String, dynamic>? queryParams}) async {
    try {
      final res = await _dio.get(path, queryParameters: queryParams);
      return res.data;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<dynamic> post(String path, Map<String, dynamic> data,
      {Map<String, dynamic>? queryParams}) async {
    try {
      final res =
          await _dio.post(path, data: data, queryParameters: queryParams);
      return res.data;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<dynamic> patch(String path, Map<String, dynamic> data,
      {Map<String, dynamic>? queryParams}) async {
    try {
      final res =
          await _dio.patch(path, data: data, queryParameters: queryParams);
      return res.data;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<dynamic> put(String path, Map<String, dynamic> data,
      {Map<String, dynamic>? queryParams}) async {
    try {
      final res =
          await _dio.put(path, data: data, queryParameters: queryParams);
      return res.data;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<dynamic> delete(String path,
      {Map<String, dynamic>? queryParams}) async {
    try {
      final res = await _dio.delete(path, queryParameters: queryParams);
      return res.data;
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ── Auth ─────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> signUp(
      String email, String password, String? name) async {
    try {
      final res = await _dio.post('/auth/signup', data: {
        'email': email,
        'password': password,
        'full_name': name,
      });
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> signIn(
      String email, String password) async {
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
      return data;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> signOut() async {
    try {
      await _dio.post('/auth/signout');
    } catch (_) {}
    await storageService.deleteAll();
  }

  Future<Map<String, dynamic>> forgotPassword(String email) async {
    try {
      final res = await _dio
          .post('/auth/forgot-password', data: {'email': email});
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> resendVerification(String email) async {
    try {
      final res = await _dio
          .post('/auth/resend-verification', data: {'email': email});
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> checkVersion(String appVersion) async {
    try {
      final res = await _dio.get('/auth/version',
          queryParameters: {'app_version': appVersion});
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<String?> getToken() => storageService.read(key: 'access_token');
  Future<String?> getUserId() => storageService.read(key: 'user_id');

  Future<bool> isAuthenticated() async {
    try {
      return (await getToken()) != null;
    } catch (_) {
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ── AI Chat ──────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────

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
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> generateTasks(
      {int count = 5, String? category}) async {
    try {
      final res = await _dio.post('/ai/generate-tasks', data: {
        'count': count,
        if (category != null) 'category': category,
      });
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> generateRoadmap() async {
    try {
      final res = await _dio.post('/ai/generate-roadmap');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<List<dynamic>> getAiConversations() async {
    try {
      final res = await _dio.get('/ai/conversations');
      return (res.data['conversations'] as List?) ?? [];
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<List<dynamic>> getMessages(String conversationId) async {
    try {
      final res =
          await _dio.get('/ai/conversations/$conversationId/messages');
      return (res.data['messages'] as List?) ?? [];
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<List<dynamic>> getAvailableModels() async {
    try {
      final res = await _dio.get('/ai/models');
      return (res.data['models'] as List?) ?? [];
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ── Tasks ────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────

  Future<List<dynamic>> getTasks({String? status}) async {
    try {
      final res = await _dio.get('/tasks/',
          queryParameters: {if (status != null) 'status': status});
      return (res.data['tasks'] as List?) ?? [];
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> updateTask(String taskId,
      {String? status, double? earnings}) async {
    try {
      final res = await _dio.patch('/tasks/$taskId', data: {
        if (status != null) 'status': status,
        if (earnings != null) 'actual_earnings': earnings,
      });
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> skipTask(String taskId) async {
    try {
      final res = await _dio.delete('/tasks/$taskId');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ── Skills ───────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getSkillModules() async {
    try {
      final res = await _dio.get('/skills/modules');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> enrollSkill(String moduleId) async {
    try {
      final res = await _dio
          .post('/skills/enroll', data: {'module_id': moduleId});
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<List<dynamic>> getMyCourses() async {
    try {
      final res = await _dio.get('/skills/my-courses');
      return (res.data['enrollments'] as List?) ?? [];
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> updateSkillProgress({
    required String enrollmentId,
    required int progressPercent,
    required int currentLesson,
    double? earnings,
  }) async {
    try {
      final res = await _dio.patch('/skills/progress', data: {
        'enrollment_id': enrollmentId,
        'progress_percent': progressPercent,
        'current_lesson': currentLesson,
        if (earnings != null) 'earnings_from_skill': earnings,
      });
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ── Payments ─────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> initiatePayment(
      {String plan = 'monthly', String currency = 'NGN'}) async {
    try {
      final res = await _dio.post('/payments/initiate',
          data: {'plan': plan, 'currency': currency});
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> verifyPayment(
      {required String txRef, String? transactionId}) async {
    try {
      final res = await _dio.post('/payments/verify', data: {
        'tx_ref': txRef,
        if (transactionId != null) 'transaction_id': transactionId,
      });
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> unlockViaAd({
    required String featureKey,
    required String adUnitId,
    int hours = 1,
  }) async {
    try {
      final res = await _dio.post('/payments/ad-unlock', data: {
        'feature_key': featureKey,
        'ad_unit_id': adUnitId,
        'duration_hours': hours,
      });
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> checkFeatureAccess(
      String featureKey) async {
    try {
      final res =
          await _dio.get('/payments/check-access/$featureKey');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> getSubscriptionStatus() async {
    try {
      final res = await _dio.get('/payments/subscription-status');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ── Progress ─────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getStats() async {
    try {
      final res = await _dio.get('/progress/stats');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> getEarnings() async {
    try {
      final res = await _dio.get('/progress/earnings');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> getRoadmap() async {
    try {
      final res = await _dio.get('/progress/roadmap');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> getProfile() async {
    try {
      final res = await _dio.get('/progress/profile');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> updateProfile(
      Map<String, dynamic> data) async {
    try {
      final res = await _dio.patch('/progress/profile', data: data);
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
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
        'amount': amount,
        'source_type': sourceType,
        if (sourceId != null) 'source_id': sourceId,
        if (description != null) 'description': description,
        'currency': currency,
      });
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ── Streaks ──────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> checkIn() async {
    try {
      final res = await _dio.post('/streaks/check-in');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> getStreak() async {
    try {
      final res = await _dio.get('/streaks/');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ── Goals ────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getGoals({String? status}) async {
    try {
      final res = await _dio.get('/goals/', queryParameters: {
        if (status != null) 'status': status,
      });
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> createGoal(
      Map<String, dynamic> data) async {
    try {
      final res = await _dio.post('/goals/', data: data);
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> updateGoal(
      String goalId, Map<String, dynamic> data) async {
    try {
      final res = await _dio.patch('/goals/$goalId', data: data);
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> contributeToGoal(
      String goalId, double amount,
      {String? description}) async {
    try {
      final res = await _dio.post('/goals/$goalId/contribute', data: {
        'amount': amount,
        if (description != null) 'description': description,
      });
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> deleteGoal(String goalId) async {
    try {
      final res = await _dio.delete('/goals/$goalId');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> suggestGoals() async {
    try {
      final res = await _dio.post('/goals/ai-suggest');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ── Expenses ─────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getExpenses(
      {String? month, String? category}) async {
    try {
      final res = await _dio.get('/expenses/', queryParameters: {
        if (month != null) 'month': month,
        if (category != null) 'category': category,
      });
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> logExpense(
      Map<String, dynamic> data) async {
    try {
      final res = await _dio.post('/expenses/', data: data);
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> deleteExpense(
      String expenseId) async {
    try {
      final res = await _dio.delete('/expenses/$expenseId');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> getBudgets({String? month}) async {
    try {
      final res = await _dio.get('/expenses/budgets',
          queryParameters: {if (month != null) 'month': month});
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> setBudget(
      Map<String, dynamic> data) async {
    try {
      final res = await _dio.post('/expenses/budgets', data: data);
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> getMonthlySummary(
      {String? month}) async {
    try {
      final res = await _dio.get('/expenses/summary',
          queryParameters: {if (month != null) 'month': month});
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ── Achievements ─────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getAchievements() async {
    try {
      final res = await _dio.get('/achievements/');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> getMyAchievements() async {
    try {
      final res = await _dio.get('/achievements/my');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> checkAchievements() async {
    try {
      final res = await _dio.post('/achievements/check');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ── Referrals ────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getMyReferralCode() async {
    try {
      final res = await _dio.get('/referrals/my-code');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> applyReferralCode(String code) async {
    try {
      final res = await _dio
          .post('/referrals/apply', data: {'referral_code': code});
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ── Notifications ────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> registerFcmToken(
      String token, String platform) async {
    try {
      final res = await _dio.post('/notifications/register-token',
          data: {'token': token, 'platform': platform});
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> getNotifications(
      {int limit = 30}) async {
    try {
      final res = await _dio.get('/notifications/',
          queryParameters: {'limit': limit});
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> markNotificationsRead(
      {List<String>? ids}) async {
    try {
      final res = await _dio.post('/notifications/mark-read', data: {
        if (ids != null) 'notification_ids': ids,
      });
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ── Agentic AI ───────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────

  Future<dynamic> runAgent({
    required String task,
    double budget = 0,
    double hoursPerDay = 2,
    String currency = 'NGN',
    String? context,
    String? workflowId,
  }) async {
    return post('/agent/run', {
      'task': task,
      'budget': budget,
      'hours_per_day': hoursPerDay,
      'currency': currency,
      if (context != null) 'context': context,
      if (workflowId != null) 'workflow_id': workflowId,
    });
  }

  Future<dynamic> agentChat(String message,
      {String? sessionId, String? workflowId}) async {
    return post('/agent/chat', {
      'message': message,
      if (sessionId != null) 'session_id': sessionId,
      if (workflowId != null) 'workflow_id': workflowId,
    });
  }

  Future<dynamic> executeTool(
      String tool, Map<String, dynamic> input,
      {String? workflowId}) async {
    return post('/agent/execute-tool', {
      'tool': tool,
      'input': input,
      if (workflowId != null) 'workflow_id': workflowId,
    });
  }

  /// FIX: was POST with empty body + query params — now sends proper body
  Future<dynamic> quickAgent(String task,
      {String outputType = 'any'}) async {
    return post('/agent/quick', {
      'task': task,
      'output_type': outputType,
    });
  }

  /// FIX: was POST with empty body + query params — now sends proper body
  Future<dynamic> analyzeAndImprove(String content,
      {String goal = 'improve'}) async {
    return post('/agent/analyze', {
      'content': content,
      'goal': goal,
    });
  }

  // ─────────────────────────────────────────────────────────────
  // ── Profile Avatar Upload ─────────────────────────────────────
  // ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> uploadAvatar(String filePath) async {
    try {
      final token = await getToken();
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          filePath,
          filename: 'avatar.jpg',
          contentType: DioMediaType('image', 'jpeg'),
        ),
      });
      final res = await _dio.post(
        '/progress/avatar',
        data: formData,
        options:
            Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ── Social / Posts ───────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getFeed(
      {String tab = 'for_you',
      int limit = 20,
      int offset = 0}) async {
    try {
      final r = await _dio.get('/posts/feed', queryParameters: {
        'tab': tab,
        'limit': limit,
        'offset': offset,
      });
      return r.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> createPost({
    required String content,
    required String tag,
    String? mediaUrl,
    String? mediaType,
  }) async {
    try {
      final r = await _dio.post('/posts', data: {
        'content': content,
        'tag': tag,
        if (mediaUrl != null) 'media_url': mediaUrl,
        if (mediaType != null) 'media_type': mediaType,
      });
      return r.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> toggleLike(String postId) async {
    try {
      final r = await _dio.post('/posts/$postId/like');
      return r.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> toggleSave(String postId) async {
    try {
      final r = await _dio.post('/posts/$postId/save');
      return r.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> sharePost(String postId) async {
    try {
      final r = await _dio.post('/posts/$postId/share');
      return r.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> deletePost(String postId) async {
    try {
      final r = await _dio.delete('/posts/$postId');
      return r.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> getPostComments(
      String postId) async {
    try {
      final r = await _dio.get('/posts/$postId/comments');
      return r.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> addComment(
      String postId, String content,
      {String? parentId}) async {
    try {
      final r = await _dio.post('/posts/$postId/comments', data: {
        'content': content,
        if (parentId != null) 'parent_id': parentId,
      });
      return r.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> likeComment(
      String commentId) async {
    try {
      final r =
          await _dio.post('/posts/comments/$commentId/like');
      return r.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> toggleFollow(
      String targetUserId) async {
    try {
      final r =
          await _dio.post('/posts/users/$targetUserId/follow');
      return r.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> getUserProfile(
      String userId) async {
    try {
      final r =
          await _dio.get('/posts/users/$userId/profile');
      return r.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> getUserPosts(String userId) async {
    try {
      final r = await _dio.get('/posts/users/$userId/posts');
      return r.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> getLikedPosts(
      String userId) async {
    try {
      final r = await _dio.get('/posts/users/$userId/liked');
      return r.data as Map<String, dynamic>;
    } catch (e) {
      return {'posts': []};
    }
  }

  Future<Map<String, dynamic>> logShare(
      String shareType, String platform) async {
    try {
      final res = await _dio.post('/community/share',
          data: {'share_type': shareType, 'platform': platform});
      return res.data as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ── Messages ─────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getConversations() async {
    try {
      final r = await _dio.get('/messages/conversations');
      return r.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> getOrCreateConversation(
      String otherUserId) async {
    try {
      final r = await _dio
          .post('/messages/conversations/with/$otherUserId');
      return r.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> getConversationMessages(
      String conversationId,
      {int limit = 50}) async {
    try {
      final r = await _dio.get(
        '/messages/conversations/$conversationId/messages',
        queryParameters: {'limit': limit},
      );
      return r.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> sendMessage(
      String conversationId, String content) async {
    try {
      final r = await _dio.post(
        '/messages/conversations/$conversationId/send',
        data: {'content': content},
      );
      return r.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ── Groups ───────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getGroups() async {
    try {
      final r = await _dio.get('/messages/groups');
      return r.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> toggleGroup(String groupId) async {
    try {
      final r =
          await _dio.post('/messages/groups/$groupId/join');
      return r.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ── Live Sessions ────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getLiveSessions() async {
    try {
      final r = await _dio.get('/live/sessions');
      return r.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> startLive({
    required String title,
    required String topic,
    bool isPremium = false,
  }) async {
    try {
      final r = await _dio.post('/live/start', data: {
        'title': title,
        'topic': topic,
        'is_premium': isPremium,
      });
      return r.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> endLive() async {
    try {
      final r = await _dio.post('/live/end');
      return r.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> joinLive(String sessionId) async {
    try {
      final r =
          await _dio.post('/live/sessions/$sessionId/join');
      return r.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> leaveLive(String sessionId) async {
    try {
      final r =
          await _dio.post('/live/sessions/$sessionId/leave');
      return r.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> sendCoins(
      String sessionId, int amount) async {
    try {
      final r = await _dio.post(
          '/live/sessions/$sessionId/coins',
          data: {'amount': amount});
      return r.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ── Income Memory ─────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────

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
        'title': title,
        'amount_usd': amountUsd,
        if (platform != null) 'platform': platform,
        if (skillUsed != null) 'skill_used': skillUsed,
        'outcome': outcome ?? 'success',
      });
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> getMemoryProfile() async {
    try {
      final res = await _dio.get('/memory/profile');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> getMemoryInsights() async {
    try {
      final res = await _dio.get('/memory/insights');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> getIncomePatterns() async {
    try {
      final res = await _dio.get('/memory/streak-patterns');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ── Market Pulse ─────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getTodaysPulse() async {
    try {
      final res = await _dio.get('/pulse/today');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> getArbitrageData() async {
    try {
      final res = await _dio.get('/pulse/arbitrage');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> scanSkillDemand(
      String skill) async {
    try {
      final res = await _dio.get('/pulse/opportunity-scan',
          queryParameters: {'skill': skill});
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ── Contracts & Invoices ─────────────────────────────────────
  // ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> generateContract(
      Map<String, dynamic> data) async {
    try {
      final res =
          await _dio.post('/contracts/generate', data: data);
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> generateInvoice(
      Map<String, dynamic> data) async {
    try {
      final res =
          await _dio.post('/contracts/invoice/generate', data: data);
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> listContracts() async {
    try {
      final res = await _dio.get('/contracts/');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> markInvoicePaid(
      String invoiceId) async {
    try {
      final res = await _dio
          .patch('/contracts/invoice/$invoiceId/paid');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ── Client CRM ───────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> addCrmClient(
      Map<String, dynamic> data) async {
    try {
      final res = await _dio.post('/crm/clients', data: data);
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> getCrmClients(
      {String? status}) async {
    try {
      final res = await _dio.get('/crm/clients',
          queryParameters: {if (status != null) 'status': status});
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> getDueFollowUps() async {
    try {
      final res = await _dio.get('/crm/follow-ups/due');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> generateFollowUpMessage(
      String clientId) async {
    try {
      final res =
          await _dio.post('/crm/clients/$clientId/ai-followup');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> getCrmAnalytics() async {
    try {
      final res = await _dio.get('/crm/analytics');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> updateCrmClient(
      String clientId, Map<String, dynamic> data) async {
    try {
      final res =
          await _dio.patch('/crm/clients/$clientId', data: data);
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ── Income Challenges ─────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> createChallenge(String type,
      {String? customGoal, double? targetUsd}) async {
    try {
      final res = await _dio.post('/challenges/create', data: {
        'challenge_type': type,
        if (customGoal != null) 'custom_goal': customGoal,
        if (targetUsd != null) 'custom_target_usd': targetUsd,
      });
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> challengeCheckIn(
      String challengeId, String action,
      {double amountUsd = 0, String? note}) async {
    try {
      final res = await _dio.post('/challenges/check-in', data: {
        'challenge_id': challengeId,
        'action_taken': action,
        'amount_earned_usd': amountUsd,
        if (note != null) 'note': note,
      });
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> listChallenges() async {
    try {
      final res = await _dio.get('/challenges/');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> getChallenge(String id) async {
    try {
      final res = await _dio.get('/challenges/$id');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> getChallengeIntervention(
      String id) async {
    try {
      final res =
          await _dio.post('/challenges/$id/ai-intervention');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ── Portfolio ─────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getPortfolio() async {
    try {
      final res = await _dio.get('/portfolio/');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> addPortfolioProject(
      Map<String, dynamic> data) async {
    try {
      final res =
          await _dio.post('/portfolio/projects', data: data);
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> generatePortfolioFromWorkflow(
      String workflowId) async {
    try {
      final res = await _dio.post(
          '/portfolio/generate-from-workflow/$workflowId');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> generateProfessionalBio() async {
    try {
      final res = await _dio.post('/portfolio/ai-bio');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> getPublicPortfolio(
      String userId) async {
    try {
      final res = await _dio.get('/portfolio/public/$userId');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }
} // end ApiService

// ─────────────────────────────────────────────────────────────────────────────
// Global singleton — import this in every screen: import '../services/api_service.dart';
// ─────────────────────────────────────────────────────────────────────────────
final api = ApiService();
