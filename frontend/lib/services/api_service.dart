import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:dio/dio.dart';
import '../config/app_constants.dart';
import '../utils/storage_service.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late Dio _dio;

  ApiService._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: kApiBaseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      headers: {'Content-Type': 'application/json'},
    ));

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
          final refreshed = await _refreshToken();
          if (refreshed) {
            final token = await storageService.read(key: 'access_token');
            error.requestOptions.headers['Authorization'] = 'Bearer $token';
            try {
              final retryRes = await _dio.fetch(error.requestOptions);
              return handler.resolve(retryRes);
            } catch (_) {
              return handler.next(error);
            }
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
          key: 'access_token', value: res.data['access_token']);
      await storageService.write(
          key: 'refresh_token', value: res.data['refresh_token']);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Auth ─────────────────────────────────────────────────────
  Future<Map> signUp(String email, String password, String? name) async {
    final res = await _dio.post('/auth/signup',
        data: {'email': email, 'password': password, 'full_name': name});
    return res.data;
  }

  Future<Map> signIn(String email, String password) async {
    final res = await _dio.post('/auth/signin',
        data: {'email': email, 'password': password});
    final data = res.data;
    await storageService.write(
        key: 'access_token', value: data['access_token']);
    await storageService.write(
        key: 'refresh_token', value: data['refresh_token']);
    await storageService.write(key: 'user_id', value: data['user_id']);
    return data;
  }

  Future<void> signOut() async {
    try {
      await _dio.post('/auth/signout');
    } catch (_) {}
    await storageService.deleteAll();
  }

  Future<Map> forgotPassword(String email) async {
    final res = await _dio.post('/auth/forgot-password',
        data: {'email': email});
    return res.data;
  }

  Future<Map> resendVerification(String email) async {
    final res = await _dio.post('/auth/resend-verification',
        data: {'email': email});
    return res.data;
  }

  Future<Map> checkVersion(String appVersion) async {
    final res = await _dio.get('/auth/version',
        queryParameters: {'app_version': appVersion});
    return res.data;
  }

  Future<String?> getToken() => storageService.read(key: 'access_token');
  Future<String?> getUserId() => storageService.read(key: 'user_id');

  // ← Fixed: wrapped in try/catch — prevents silent crash on Android release
  Future<bool> isAuthenticated() async {
    try {
      return (await getToken()) != null;
    } catch (_) {
      return false;
    }
  }

  // ── Generic HTTP helpers (used by Workflow Engine + new screens) ──
  Future<dynamic> get(String path, {Map<String, dynamic>? queryParams}) async {
    final res = await _dio.get(path, queryParameters: queryParams);
    return res.data;
  }

  Future<dynamic> post(String path, Map<String, dynamic> data,
      {Map<String, dynamic>? queryParams}) async {
    final res = await _dio.post(
      path,
      data: data,
      queryParameters: queryParams,
    );
    return res.data;
  }

  Future<dynamic> patch(String path, Map<String, dynamic> data,
      {Map<String, dynamic>? queryParams}) async {
    final res = await _dio.patch(path, data: data, queryParameters: queryParams);
    return res.data;
  }

  Future<dynamic> delete(String path) async {
    final res = await _dio.delete(path);
    return res.data;
  }

  // ── AI Chat ──────────────────────────────────────────────────
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

  Future<List> getAiConversations() async {
    final res = await _dio.get('/ai/conversations');
    return res.data['conversations'] as List;
  }

  Future<List> getMessages(String conversationId) async {
    final res =
        await _dio.get('/ai/conversations/$conversationId/messages');
    return res.data['messages'] as List;
  }

  Future<List> getAvailableModels() async {
    final res = await _dio.get('/ai/models');
    return res.data['models'] as List;
  }

  // ── Tasks ────────────────────────────────────────────────────
  Future<List> getTasks({String? status}) async {
    final res = await _dio.get('/tasks/',
        queryParameters: {if (status != null) 'status': status});
    return res.data['tasks'] as List;
  }

  Future<Map> updateTask(String taskId,
      {String? status, double? earnings}) async {
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

  // ── Skills ───────────────────────────────────────────────────
  Future<Map> getSkillModules() async {
    final res = await _dio.get('/skills/modules');
    return res.data;
  }

  Future<Map> enrollSkill(String moduleId) async {
    final res = await _dio.post('/skills/enroll',
        data: {'module_id': moduleId});
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

  // ── Payments ─────────────────────────────────────────────────
  Future<Map> initiatePayment(
      {String plan = 'monthly', String currency = 'NGN'}) async {
    final res = await _dio.post('/payments/initiate',
        data: {'plan': plan, 'currency': currency});
    return res.data;
  }

  Future<Map> verifyPayment(
      {required String txRef, String? transactionId}) async {
    final res = await _dio.post('/payments/verify', data: {
      'tx_ref': txRef,
      if (transactionId != null) 'transaction_id': transactionId,
    });
    return res.data;
  }

  Future<Map> unlockViaAd({
    required String featureKey,
    required String adUnitId,
    int hours = 1,
  }) async {
    final res = await _dio.post('/payments/ad-unlock', data: {
      'feature_key': featureKey,
      'ad_unit_id': adUnitId,
      'duration_hours': hours,
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

  // ── Progress ─────────────────────────────────────────────────
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
      'amount': amount,
      'source_type': sourceType,
      if (sourceId != null) 'source_id': sourceId,
      if (description != null) 'description': description,
      'currency': currency,
    });
    return res.data;
  }

  // ── Streaks ──────────────────────────────────────────────────
  Future<Map> checkIn() async {
    final res = await _dio.post('/streaks/check-in');
    return res.data;
  }

  Future<Map> getStreak() async {
    final res = await _dio.get('/streaks/');
    return res.data;
  }

  // ── Goals ────────────────────────────────────────────────────
  Future<Map> getGoals({String? status}) async {
    final res = await _dio.get('/goals/', queryParameters: {
      if (status != null) 'status': status,
    });
    return res.data;
  }

  Future<Map> createGoal(Map<String, dynamic> data) async {
    final res = await _dio.post('/goals/', data: data);
    return res.data;
  }

  Future<Map> updateGoal(String goalId, Map<String, dynamic> data) async {
    final res = await _dio.patch('/goals/$goalId', data: data);
    return res.data;
  }

  Future<Map> contributeToGoal(String goalId, double amount,
      {String? description}) async {
    final res = await _dio.post('/goals/$goalId/contribute', data: {
      'amount': amount,
      if (description != null) 'description': description,
    });
    return res.data;
  }

  Future<Map> deleteGoal(String goalId) async {
    final res = await _dio.delete('/goals/$goalId');
    return res.data;
  }

  Future<Map> suggestGoals() async {
    final res = await _dio.post('/goals/ai-suggest');
    return res.data;
  }

  // ── Expenses ─────────────────────────────────────────────────
  Future<Map> getExpenses({String? month, String? category}) async {
    final res = await _dio.get('/expenses/', queryParameters: {
      if (month != null) 'month': month,
      if (category != null) 'category': category,
    });
    return res.data;
  }

  Future<Map> logExpense(Map<String, dynamic> data) async {
    final res = await _dio.post('/expenses/', data: data);
    return res.data;
  }

  Future<Map> deleteExpense(String expenseId) async {
    final res = await _dio.delete('/expenses/$expenseId');
    return res.data;
  }

  Future<Map> getBudgets({String? month}) async {
    final res = await _dio.get('/expenses/budgets', queryParameters: {
      if (month != null) 'month': month,
    });
    return res.data;
  }

  Future<Map> setBudget(Map<String, dynamic> data) async {
    final res = await _dio.post('/expenses/budgets', data: data);
    return res.data;
  }

  Future<Map> getMonthlySummary({String? month}) async {
    final res = await _dio.get('/expenses/summary', queryParameters: {
      if (month != null) 'month': month,
    });
    return res.data;
  }

  // ── Achievements ─────────────────────────────────────────────
  Future<Map> getAchievements() async {
    final res = await _dio.get('/achievements/');
    return res.data;
  }

  Future<Map> getMyAchievements() async {
    final res = await _dio.get('/achievements/my');
    return res.data;
  }

  Future<Map> checkAchievements() async {
    final res = await _dio.post('/achievements/check');
    return res.data;
  }

  // ── Referrals ─────────────────────────────────────────────────
  Future<Map> getMyReferralCode() async {
    final res = await _dio.get('/referrals/my-code');
    return res.data;
  }

  Future<Map> applyReferralCode(String code) async {
    final res = await _dio.post('/referrals/apply',
        data: {'referral_code': code});
    return res.data;
  }

  // ── Notifications ─────────────────────────────────────────────
  Future<Map> registerFcmToken(String token, String platform) async {
    final res = await _dio.post('/notifications/register-token',
        data: {'token': token, 'platform': platform});
    return res.data;
  }

  Future<Map> getNotifications({int limit = 30}) async {
    final res = await _dio.get('/notifications/',
        queryParameters: {'limit': limit});
    return res.data;
  }

  Future<Map> markNotificationsRead({List<String>? ids}) async {
    final res = await _dio.post('/notifications/mark-read', data: {
      if (ids != null) 'notification_ids': ids,
    });
    return res.data;
  }

  Future<Map> logShare(String shareType, String platform) async {
    try {
      final res = await _dio.post('/community/share',
          data: {'share_type': shareType, 'platform': platform});
      return res.data;
    } catch (_) {
      return {};
    }
  }

  // ── Agentic AI ────────────────────────────────────────────────
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

  Future<dynamic> agentChat(String message, {String? sessionId, String? workflowId}) async {
    return post('/agent/chat', {
      'message': message,
      if (sessionId != null) 'session_id': sessionId,
      if (workflowId != null) 'workflow_id': workflowId,
    });
  }

  Future<dynamic> executeTool(String tool, Map<String, dynamic> input, {String? workflowId}) async {
    return post('/agent/execute-tool', {
      'tool': tool,
      'input': input,
      if (workflowId != null) 'workflow_id': workflowId,
    });
  }

  Future<dynamic> quickAgent(String task, {String outputType = 'any'}) async {
    return post('/agent/quick', {}, queryParams: {
      'task': task,
      'output_type': outputType,
    });
  }

  Future<dynamic> analyzeAndImprove(String content, {String goal = 'improve'}) async {
    return post('/agent/analyze', {}, queryParams: {
      'content': content,
      'goal': goal,
    });
  }

  // ── Profile Avatar Upload ─────────────────────────────────────
  Future<Map> uploadAvatar(String filePath) async {
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
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return res.data;
    } catch (e) {
      throw Exception('Avatar upload failed: $e');
    }
  }

  // ── Liked Posts ───────────────────────────────────────────────
  Future<Map> getLikedPosts(String userId) async {
    try {
      final res = await _dio.get('/posts/users/$userId/liked');
      return res.data;
    } catch (_) {
      return {'posts': []};
    }
  }


  // ── Social, Messages, Live (from api_service_additions) ─────
  Future<Map> getFeed({String tab = 'for_you', int limit = 20, int offset = 0}) async {
    final r = await _dio.get('/posts/feed', queryParameters: {'tab': tab, 'limit': limit, 'offset': offset});
    return r.data as Map;
  }

  Future<Map> createPost({required String content, required String tag, String? mediaUrl, String? mediaType}) async {
    final r = await _dio.post('/posts', data: {
      'content': content,
      'tag': tag,
      if (mediaUrl != null) 'media_url': mediaUrl,
      if (mediaType != null) 'media_type': mediaType,
    });
    return r.data as Map;
  }

  Future<Map> toggleLike(String postId) async {
    final r = await _dio.post('/posts/$postId/like');
    return r.data as Map;
  }

  Future<Map> toggleSave(String postId) async {
    final r = await _dio.post('/posts/$postId/save');
    return r.data as Map;
  }

  Future<Map> sharePost(String postId) async {
    final r = await _dio.post('/posts/$postId/share');
    return r.data as Map;
  }

  Future<Map> deletePost(String postId) async {
    final r = await _dio.delete('/posts/$postId');
    return r.data as Map;
  }

  Future<Map> getPostComments(String postId) async {
    final r = await _dio.get('/posts/$postId/comments');
    return r.data as Map;
  }

  Future<Map> addComment(String postId, String content, {String? parentId}) async {
    final r = await _dio.post('/posts/$postId/comments', data: {
      'content': content,
      if (parentId != null) 'parent_id': parentId,
    });
    return r.data as Map;
  }

  Future<Map> likeComment(String commentId) async {
    final r = await _dio.post('/posts/comments/$commentId/like');
    return r.data as Map;
  }

  Future<Map> toggleFollow(String targetUserId) async {
    final r = await _dio.post('/posts/users/$targetUserId/follow');
    return r.data as Map;
  }

  Future<Map> getUserProfile(String userId) async {
    final r = await _dio.get('/posts/users/$userId/profile');
    return r.data as Map;
  }

  Future<Map> getUserPosts(String userId) async {
    final r = await _dio.get('/posts/users/$userId/posts');
    return r.data as Map;
  }

  // ── Messages ───────────────────────────────────────
  Future<Map> getConversations() async {
    final r = await _dio.get('/messages/conversations');
    return r.data as Map;
  }

  Future<Map> getOrCreateConversation(String otherUserId) async {
    final r = await _dio.post('/messages/conversations/with/$otherUserId');
    return r.data as Map;
  }

  Future<Map> getConversationMessages(String conversationId, {int limit = 50}) async {
    final r = await _dio.get(
      '/messages/conversations/$conversationId/messages',
      queryParameters: {'limit': limit},
    );
    return r.data as Map;
  }

  Future<Map> sendMessage(String conversationId, String content) async {
    final r = await _dio.post(
      '/messages/conversations/$conversationId/send',
      data: {'content': content},
    );
    return r.data as Map;
  }

  // ── Groups ─────────────────────────────────────────
  Future<Map> getGroups() async {
    final r = await _dio.get('/messages/groups');
    return r.data as Map;
  }

  Future<Map> toggleGroup(String groupId) async {
    final r = await _dio.post('/messages/groups/$groupId/join');
    return r.data as Map;
  }

  // ── Live ───────────────────────────────────────────
  Future<Map> getLiveSessions() async {
    final r = await _dio.get('/live/sessions');
    return r.data as Map;
  }

  Future<Map> startLive({required String title, required String topic, bool isPremium = false}) async {
    final r = await _dio.post('/live/start', data: {
      'title': title, 'topic': topic, 'is_premium': isPremium,
    });
    return r.data as Map;
  }

  Future<Map> endLive() async {
    final r = await _dio.post('/live/end');
    return r.data as Map;
  }

  Future<Map> joinLive(String sessionId) async {
    final r = await _dio.post('/live/sessions/$sessionId/join');
    return r.data as Map;
  }

  Future<Map> leaveLive(String sessionId) async {
    final r = await _dio.post('/live/sessions/$sessionId/leave');
    return r.data as Map;
  }

  Future<Map> sendCoins(String sessionId, int amount) async {
    final r = await _dio.post('/live/sessions/$sessionId/coins', data: {'amount': amount});
    return r.data as Map;
  }

} // end ApiService

// Global singleton instance
final api = ApiService();
