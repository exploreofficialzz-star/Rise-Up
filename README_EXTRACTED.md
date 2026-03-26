# RiseUp — All New Screens Package

## Files — copy each to your repo:

| File in zip | Destination |
|---|---|
| `lib/screens/explore/explore_screen.dart` | `frontend/lib/screens/explore/explore_screen.dart` |
| `lib/screens/create/create_post_screen.dart` | `frontend/lib/screens/create/create_post_screen.dart` |
| `lib/screens/profile/profile_screen.dart` | `frontend/lib/screens/profile/profile_screen.dart` |
| `lib/screens/notifications/notifications_screen.dart` | `frontend/lib/screens/notifications/notifications_screen.dart` |
| `lib/screens/comments/comments_screen.dart` | `frontend/lib/screens/comments/comments_screen.dart` |
| `lib/screens/premium/premium_screen.dart` | `frontend/lib/screens/premium/premium_screen.dart` |
| `lib/screens/settings/settings_screen.dart` | `frontend/lib/screens/settings/settings_screen.dart` |
| `lib/config/router.dart` | `frontend/lib/config/router.dart` |

## What each screen does:

### Explore Screen
- Search bar for creators and topics
- 3 tabs: Trending posts, Creators, Topics/Categories
- Follow button on creators
- Topic grid with emoji categories

### Create Post Screen
- Text post with character counter (500 max)
- Topic tag selector (8 categories)
- Photo, Video, Poll buttons (ready for implementation)
- Gradient Post button

### Profile Screen
- Avatar with first letter of name
- Posts, Followers, Following stats
- Stage badge (Survival/Earning/Growing/Wealth)
- Edit Profile + Share buttons
- Posts tab + Liked posts tab

### Notifications Screen
- Like, Comment, Follow, Mention, AI notification types
- Unread blue dot indicator
- Mark all read button
- Color-coded notification icons

### Comments Screen
- Original post preview at top
- Full comment thread
- Like comments
- Add comment input with send button

### Premium Screen
- Monthly/Yearly toggle with 33% savings
- Full feature list with icons
- Gradient CTA button
- "Cancel anytime" note

### Settings Screen
- Account (Edit, Password, Email, Premium)
- Notifications toggles
- Privacy toggles
- Support links
- Sign out with confirmation

### Router
- All new routes connected
- /premium, /comments/:postId, /explore, /create, /profile, /settings, /notifications
