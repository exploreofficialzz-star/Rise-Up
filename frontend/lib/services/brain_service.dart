// frontend/lib/services/brain_service.dart
//
// RiseUp Brain Service — Flutter client for the Methods Brain API
// Handles: brain chat, escalation signals, agentic task creation,
//          post signal recording, adaptive profile reading

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'api_service.dart';

// ─────────────────────────────────────────────────────────────────
// Brain Chat Response model
// ─────────────────────────────────────────────────────────────────

class BrainChatResponse {
  final String  reply;
  final String  intent;
  final bool    internalFound;
  final int     internalCount;
  final bool    needsExternal;
  final String? escalationReason;
  final String? suggestedTaskType;
  final List    methods;
  final List    marketplace;
  final List    serviceProviders;
  final List    complementaryUsers;

  BrainChatResponse.fromJson(Map j)
      : reply             = j['reply']              ?? j['content'] ?? '',
        intent            = j['intent']             ?? 'explore',
        internalFound     = j['internal_found']     == true,
        internalCount     = (j['internal_count'] as num?)?.toInt() ?? 0,
        needsExternal     = j['needs_external']     == true
                         || j['brain_needs_external'] == true,
        escalationReason  = j['escalation_reason']
                         ?? j['brain_escalation_reason'],
        suggestedTaskType = j['suggested_task_type']
                         ?? j['brain_suggested_task_type'],
        methods           = (j['methods'] as List?)
                         ?? (j['brain_methods'] as List?)           ?? [],
        marketplace       = (j['marketplace'] as List?)
                         ?? (j['brain_marketplace'] as List?)       ?? [],
        serviceProviders  = (j['service_providers'] as List?)
                         ?? (j['brain_service_providers'] as List?) ?? [],
        complementaryUsers= (j['complementary_users'] as List?)     ?? [];

  bool get hasInternalResults =>
      methods.isNotEmpty || marketplace.isNotEmpty || serviceProviders.isNotEmpty;
}

// ─────────────────────────────────────────────────────────────────
// Brain Service singleton
// ─────────────────────────────────────────────────────────────────

class BrainService {
  static final BrainService _instance = BrainService._();
  factory BrainService() => _instance;
  BrainService._();

  // ── Chat with the brain-aware AI mentor ──────────────────────────
  Future<BrainChatResponse> mentorChat({
    required String message,
    String?  sessionId,
    String   language = 'en',
    List<Map<String, String>> history = const [],
  }) async {
    final res = await api.post('/brain/mentor/chat', {
      'message':    message,
      'session_id': sessionId,
      'language':   language,
      'history':    history,
    });
    return BrainChatResponse.fromJson(res as Map);
  }

  // ── Record a post creation signal ────────────────────────────────
  Future<Map?> recordPostSignal({
    required String postId,
    required String content,
    String?  tag,
  }) async {
    try {
      final res = await api.post('/ai/signal/post', {
        'post_id': postId,
        'content': content,
        'tag':     tag,
      });
      return res as Map?;
    } catch (_) {
      return null; // Silent — signal collection is best-effort
    }
  }

  // ── Record a like/save/share interaction ─────────────────────────
  Future<void> recordInteraction({
    required String action,  // 'like', 'save', 'share'
    required String postId,
    required String postContent,
  }) async {
    try {
      await api.post('/ai/signal/interaction', {
        'action':       action,
        'post_id':      postId,
        'post_content': postContent.substring(0, postContent.length.clamp(0, 200)),
      });
    } catch (_) {
      // Silent
    }
  }

  // ── Create agentic task from escalation ──────────────────────────
  Future<Map?> createAgenticTask({
    required String description,
    required String taskType,
    bool    approveExternal  = false,
    bool    approveExecution = false,
  }) async {
    try {
      final res = await api.post('/brain/task/create', {
        'task_type':   taskType,
        'title':       description.substring(0, description.length.clamp(0, 60)),
        'description': description,
        'input_data': {
          'description':               description,
          'user_approved_external':    approveExternal,
          'user_approved_execution':   approveExecution,
        },
        'priority': 'high',
      });
      return res as Map?;
    } catch (e) {
      return null;
    }
  }

  // ── Get adaptive profile ─────────────────────────────────────────
  Future<Map?> getAdaptiveProfile() async {
    try {
      final res = await api.get('/ai/adaptive-profile');
      return (res as Map?)?['profile'] as Map?;
    } catch (_) {
      return null;
    }
  }

  // ── Get complementary users ──────────────────────────────────────
  Future<List> getComplementaryUsers({int limit = 5}) async {
    try {
      final res = await api.get('/ai/complementary-users',
          queryParams: {'limit': limit});
      return (res as Map?)?['matches'] as List? ?? [];
    } catch (_) {
      return [];
    }
  }

  // ── Internal search ──────────────────────────────────────────────
  Future<Map?> internalSearch(String query, {int limit = 5}) async {
    try {
      final res = await api.post('/brain/search/internal',
          {'query': query, 'limit': limit});
      return res as Map?;
    } catch (_) {
      return null;
    }
  }
}

final brainService = BrainService();

// ─────────────────────────────────────────────────────────────────
// Escalation Bottom Sheet — shown when AI says needs_external = true
// ─────────────────────────────────────────────────────────────────

class EscalationSheet extends StatefulWidget {
  final BrainChatResponse brainResponse;
  final String            originalQuery;
  final VoidCallback?     onDismiss;

  const EscalationSheet({
    super.key,
    required this.brainResponse,
    required this.originalQuery,
    this.onDismiss,
  });

  static Future<void> show(
    BuildContext context, {
    required BrainChatResponse brainResponse,
    required String            originalQuery,
  }) {
    return showModalBottomSheet(
      context:             context,
      isScrollControlled:  true,
      backgroundColor:     Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => EscalationSheet(
        brainResponse: brainResponse,
        originalQuery: originalQuery,
      ),
    );
  }

  @override
  State<EscalationSheet> createState() => _EscalationSheetState();
}

class _EscalationSheetState extends State<EscalationSheet> {
  bool _loading  = false;
  String? _status;

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final br   = widget.brainResponse;
    final q    = widget.originalQuery;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.search_rounded,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Search Beyond RiseUp',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: cs.onSurface)),
                    Text(
                      br.escalationReason ?? 'Limited internal results',
                      style: TextStyle(
                          fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Internal results summary
          if (br.hasInternalResults)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline,
                      color: Colors.green, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Found ${br.methods.length} methods, '
                      '${br.marketplace.length} listings, '
                      '${br.serviceProviders.length} providers on RiseUp.',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.green),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 12),

          // Status indicator
          if (_status != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_status!,
                  style: TextStyle(fontSize: 13, color: cs.onSurface)),
            ),

          // Option 1: Search web via Workflow
          _OptionCard(
            icon:    Icons.travel_explore_rounded,
            color:   Colors.orange,
            title:   'Search Internet (Workflow Engine)',
            desc:    'I\'ll search the web for buyers, sellers, '
                     'contacts, and opportunities related to:\n"$q"',
            loading: _loading,
            onTap:   () => _handleWorkflow(context, q),
          ),

          const SizedBox(height: 10),

          // Option 2: Handle everything (Agentic)
          _OptionCard(
            icon:    Icons.flash_on_rounded,
            color:   const Color(0xFF6C63FF),
            title:   'Handle Everything (Agentic)',
            desc:    'I\'ll search the web, find contacts, draft '
                     'messages, and manage the whole process for you.',
            loading: _loading,
            badge:   'END-TO-END',
            onTap:   () => _handleAgentic(context, q),
          ),

          const SizedBox(height: 10),

          // Option 3: Post in marketplace
          _OptionCard(
            icon:    Icons.store_rounded,
            color:   Colors.green,
            title:   'Post in RiseUp Marketplace',
            desc:    'List what you\'re selling/looking for so '
                     'other RiseUp members can find you.',
            loading: false,
            onTap:   () {
              Navigator.pop(context);
              context.push('/marketplace');
            },
          ),

          // Complementary users
          if (br.complementaryUsers.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('👥 RiseUp users who might help:',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: cs.onSurface)),
            const SizedBox(height: 8),
            ...br.complementaryUsers.take(3).map((u) => _UserChip(u)),
          ],
        ],
      ),
    );
  }

  Future<void> _handleWorkflow(BuildContext ctx, String q) async {
    setState(() {_loading = true; _status = 'Opening Workflow Engine...\nSearching the web for you 🔍';});
    try {
      await brainService.createAgenticTask(
        description:     q,
        taskType:        widget.brainResponse.suggestedTaskType ?? 'custom',
        approveExternal: true,
      );
      if (mounted) {
        Navigator.pop(ctx);
        ctx.push('/workflow');
      }
    } catch (e) {
      setState(() {_loading = false; _status = 'Error: $e';});
    }
  }

  Future<void> _handleAgentic(BuildContext ctx, String q) async {
    setState(() {_loading = true; _status = 'Activating Agentic AI...\nHandling everything end-to-end 🤖';});
    try {
      await brainService.createAgenticTask(
        description:      q,
        taskType:         widget.brainResponse.suggestedTaskType ?? 'custom',
        approveExternal:  true,
        approveExecution: true,
      );
      if (mounted) {
        Navigator.pop(ctx);
        ctx.push('/agent');
      }
    } catch (e) {
      setState(() {_loading = false; _status = 'Error: $e';});
    }
  }
}

class _OptionCard extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final String   title;
  final String   desc;
  final bool     loading;
  final String?  badge;
  final VoidCallback onTap;

  const _OptionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.desc,
    required this.loading,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: loading
                  ? SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: color))
                  : Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: cs.onSurface)),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(badge!,
                              style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: color)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(desc,
                      style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                          height: 1.4)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: color.withOpacity(0.6), size: 18),
          ],
        ),
      ),
    );
  }
}

class _UserChip extends StatelessWidget {
  final Map user;
  const _UserChip(this.user);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: cs.primary.withOpacity(0.1),
            backgroundImage: user['avatar_url'] != null
                ? NetworkImage(user['avatar_url'].toString())
                : null,
            child: user['avatar_url'] == null
                ? Icon(Icons.person, size: 16, color: cs.primary)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user['full_name']?.toString() ?? 'RiseUp User',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: cs.onSurface),
                ),
                if (user['service'] != null || user['overlap'] != null)
                  Text(
                    (user['overlap'] as List?)?.take(2).join(', ') ??
                    user['service']?.toString() ?? '',
                    style: TextStyle(
                        fontSize: 10, color: cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              user['match_type']?.toString().toUpperCase() ?? 'MATCH',
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: cs.primary),
            ),
          ),
        ],
      ),
    );
  }
}

