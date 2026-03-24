# RiseUp — API Wiring Package

## Files — copy each to your repo:

### Backend (3 new files):
| File | Destination |
|---|---|
| `backend/routers/posts.py` | `backend/routers/posts.py` |
| `backend/routers/messages.py` | `backend/routers/messages.py` |
| `backend/routers/live.py` | `backend/routers/live.py` |
| `backend/main.py` | `backend/main.py` (replace) |
| `backend/migration_social.sql` | Run in Supabase SQL Editor |

### Frontend (2 files):
| File | Destination |
|---|---|
| `frontend/lib/screens/home/home_screen.dart` | Replace existing |
| `frontend/lib/services/api_service_additions.dart` | See instructions below |

---

## IMPORTANT — api_service_additions.dart

Do NOT replace your api_service.dart. Instead:

1. Open `frontend/lib/services/api_service.dart`
2. Find the last method in the class (before closing `}`)
3. Copy all methods from `api_service_additions.dart`
4. Paste them before the closing `}`

---

## IMPORTANT — Run SQL Migration

1. Go to: https://supabase.com/dashboard/project/pbjvrlrmrffengjidtka/sql/new
2. Open `backend/migration_social.sql`
3. Copy and paste the entire content
4. Click Run

This creates:
- posts, post_likes, post_saves, post_comments, comment_likes
- follows
- conversations, conversation_members, messages
- groups, group_members, group_posts
- live_sessions, live_viewers, coin_gifts
- All RPC functions
- Seeded 15 default groups

---

## What's now live:

### Home Feed
- Real posts from Supabase
- Pull to refresh
- Load more pagination
- Real like/save toggles
- Real comment navigation
- Per-tab feed (For You, Following, Trending)

### Posts API
- GET /api/v1/posts/feed — paginated feed
- POST /api/v1/posts — create post
- POST /api/v1/posts/:id/like — toggle like
- POST /api/v1/posts/:id/save — toggle save
- GET /api/v1/posts/:id/comments — get comments
- POST /api/v1/posts/:id/comments — add comment
- POST /api/v1/posts/users/:id/follow — toggle follow

### Messages API
- GET /api/v1/messages/conversations — all DMs
- POST /api/v1/messages/conversations/with/:id — start DM
- GET /api/v1/messages/conversations/:id/messages — load messages
- POST /api/v1/messages/conversations/:id/send — send message
- GET /api/v1/messages/groups — all groups
- POST /api/v1/messages/groups/:id/join — join/leave

### Live API
- GET /api/v1/live/sessions — active lives
- POST /api/v1/live/start — go live
- POST /api/v1/live/end — end session
- POST /api/v1/live/sessions/:id/join — join live
- POST /api/v1/live/sessions/:id/coins — send coins
