// frontend/lib/services/api_service_additions.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// NOTE: All methods previously in this file have been consolidated into
// api_service.dart directly on the ApiService class.
//
// This file is intentionally empty to avoid:
//   1. `part of` + `extension` conflict (Dart disallows both together)
//   2. Duplicate member errors (same methods defined twice)
//
// DO NOT add methods here. Add them directly to ApiService in api_service.dart.
// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
// ADD THIS METHOD to api_service.dart
// Place it right below the existing checkAIInConversation() method
// inside the ApiService class (around line where Messages section ends).
// ─────────────────────────────────────────────────────────────────────────────

  /// Gets (or creates) the dedicated user↔AI conversation in the messages
  /// system. Returns the conversation UUID. Idempotent — safe to call on
  /// every AI chat screen open.
  Future<String> getOrCreateAIConversation() async {
    try {
      final r = await _dio.get('/messages/ai-conversation');
      return (r.data['conversation_id'] as String?) ?? '';
    } catch (e) {
      throw _handleError(e);
    }
  }
