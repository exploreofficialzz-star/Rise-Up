// api_service.dart — Add these methods to your existing ApiService class
// Find the end of your existing ApiService class and add all methods below
// before the closing } of the class

// ══════════════════════════════════════════════════════
// PASTE THESE METHODS INTO YOUR EXISTING ApiService CLASS
// ══════════════════════════════════════════════════════

  // ── Feed / Posts ──────────────────────────────────
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
