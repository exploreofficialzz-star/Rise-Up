# RiseUp Social Platform — New Files

## Files in this package

### 1. `frontend/lib/main_shell.dart`
Facebook-style bottom navigation:
- Home, Explore, Create (gradient button), AI, Profile
- Adapts to system dark/light theme
- Haptic feedback on tab switch

### 2. `frontend/lib/screens/home/home_screen.dart`
Social media feed screen:
- RiseUp gradient header (like Facebook's branding)
- Stories row
- For You / Following / Trending tabs
- Post cards with Like, Comment, Share, Save
- **"Ask RiseUp AI"** button on every post (public)
- **"Chat Privately"** button on every post (private)
- Daily free AI limit (3/day) with rewarded ads after
- Premium users get unlimited AI access

### 3. `frontend/lib/screens/ai/post_ai_sheet.dart`
Public AI bottom sheet:
- Opens when user taps "Ask RiseUp AI"
- Auto-reads and responds to the post
- Shows response as public-style comment
- Follow-up questions with quick suggestion chips
- Rewarded ad gate for free users

### 4. `frontend/lib/screens/chat/chat_screen.dart`
Updated AI chat screen:
- Now supports `postContext` and `postAuthor` params
- When opened from a post → shows private context banner
- Private conversation with full history
- Same beautiful UI adapted to system theme

### 5. `frontend/lib/config/router.dart`
Updated router:
- `/home` → HomeScreen (social feed)
- `/chat` → ChatScreen (now accepts postContext & postAuthor)
- `/explore` → CommunityScreen
- `/create` → (placeholder — build CreatePostScreen next)
- `/profile` → ProfileScreen
- All existing routes preserved

## How to use
Copy each file to the corresponding path in your repo and push.

## AI Monetization Flow
- Free users: 3 free AI responses/day on posts
- After 3: Must watch 30s rewarded ad
- Premium users: Unlimited, no ads
- All users can READ AI responses for free
