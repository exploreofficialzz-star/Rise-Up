// ─────────────────────────────────────────────────────────────────────────────
// api_service_additions.dart  — MESSAGES section
// Drop these methods into the existing ApiService class.
// File: frontend/lib/services/api_service_additions.dart
// ─────────────────────────────────────────────────────────────────────────────
// (This file uses part/extension pattern — add the methods below to ApiService)

part of 'api_service.dart';   // ← remove this line if file is standalone

extension MessagesApi on ApiService {

  // ── Conversations ─────────────────────────────────────────────────────────

  /// All DM conversations for current user, newest first.
  Future<List<dynamic>> getDMConversations() async {
    try {
      final res = await get('/messages/conversations');
      return (res as Map?)?['conversations'] as List? ?? [];
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Get or create a DM conversation with [otherUserId].
  /// Returns the conversation ID string.
  Future<String> getOrCreateDM(String otherUserId) async {
    try {
      final res = await post(
        '/messages/conversations/with/$otherUserId', {},
      );
      return (res as Map)['conversation_id'] as String;
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ── Messages ──────────────────────────────────────────────────────────────

  /// Fetch messages in a DM conversation.
  /// Pass [since] (ISO timestamp) for incremental polling.
  Future<List<dynamic>> getDMMessages(
    String conversationId, {
    int limit = 50,
    String? since,
  }) async {
    try {
      final res = await get(
        '/messages/conversations/$conversationId/messages',
        queryParams: {
          'limit': limit,
          if (since != null) 'since': since,
        },
      );
      return (res as Map?)?['messages'] as List? ?? [];
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Send a text (or media) DM.
  Future<Map<String, dynamic>> sendDMMessage(
    String conversationId,
    String content, {
    String? mediaUrl,
  }) async {
    try {
      final res = await post(
        '/messages/conversations/$conversationId/send',
        {
          'content': content,
          if (mediaUrl != null) 'media_url': mediaUrl,
        },
      );
      return (res as Map)['message'] as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ── AI inside a DM ────────────────────────────────────────────────────────

  /// Send a message to the AI mentor inside a DM conversation.
  /// [adUnlocked] = true after the user watches a rewarded ad.
  ///
  /// Throws [ApiException] with statusCode 402 when quota is exceeded
  /// (client should show the ad gate).
  /// Throws [ApiException] with statusCode 429 when the daily ad limit is
  /// reached (client should show the daily-limit countdown).
  Future<Map<String, dynamic>> sendAIMessageInDM(
    String conversationId,
    String content, {
    bool adUnlocked = false,
  }) async {
    try {
      final res = await post(
        '/messages/conversations/$conversationId/ai-message',
        {'content': content, 'ad_unlocked': adUnlocked},
      );
      return res as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Fetch the current user's AI message quota status.
  Future<Map<String, dynamic>> getAIQuota() async {
    try {
      final res = await get('/messages/ai-quota');
      return res as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ── User search ───────────────────────────────────────────────────────────

  /// Search for users to start a new DM.
  Future<List<dynamic>> searchUsers(String query) async {
    try {
      if (query.trim().length < 2) return [];
      final res = await get(
        '/messages/users/search',
        queryParams: {'q': query.trim(), 'limit': 20},
      );
      return (res as Map?)?['users'] as List? ?? [];
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ── Notifications (used in main_shell.dart) ───────────────────────────────

  Future<Map<String, dynamic>> getNotifications({int limit = 50}) async {
    try {
      final res = await get(
        '/notifications/',
        queryParams: {'limit': limit},
      );
      return res as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }
}
