import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── API ─────────────────────────────────────────────
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://riseup-api.onrender.com/api/v1',
);
const String kSupabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
const String kSupabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

// AdMob
const String kAdMobAppId = String.fromEnvironment(
  'ADMOB_APP_ID',
  defaultValue: 'ca-app-pub-3940256099942544~3347511713', // test id
);
const String kRewardedAdUnit = String.fromEnvironment(
  'ADMOB_REWARDED_UNIT',
  defaultValue: 'ca-app-pub-3940256099942544/5224354917', // test rewarded
);
// Banner ad — shown on Dashboard & Skills screens
const String kBannerAdUnit = String.fromEnvironment(
  'ADMOB_BANNER_UNIT',
  defaultValue: 'ca-app-pub-3940256099942544/6300978111', // test banner
);
// Interstitial ad — shown after task completion
const String kInterstitialAdUnit = String.fromEnvironment(
  'ADMOB_INTERSTITIAL_UNIT',
  defaultValue: 'ca-app-pub-3940256099942544/1033173712', // test interstitial
);
// App Open ad — shown when app is brought to foreground
const String kAppOpenAdUnit = String.fromEnvironment(
  'ADMOB_APP_OPEN_UNIT',
  defaultValue: 'ca-app-pub-3940256099942544/9257395921', // test app-open
);

// ── Colors ───────────────────────────────────────────
class AppColors {
  // Primary brand
  static const Color primary = Color(0xFF6C5CE7);      // Purple
  static const Color primaryLight = Color(0xFF9B8CF0);
  static const Color primaryDark = Color(0xFF4A3ABF);

  // Accent
  static const Color accent = Color(0xFF00CEC9);        // Teal
  static const Color accentLight = Color(0xFF81ECEC);
  static const Color gold = Color(0xFFFFD700);
  static const Color goldDark = Color(0xFFE5B800);

  // Status
  static const Color success = Color(0xFF00B894);
  static const Color warning = Color(0xFFFDCB6E);
  static const Color error = Color(0xFFE17055);
  static const Color info = Color(0xFF74B9FF);

  // Stages
  static const Color survival = Color(0xFFE17055);
  static const Color earning = Color(0xFFFDCB6E);
  static const Color growing = Color(0xFF00B894);
  static const Color wealth = Color(0xFF6C5CE7);

  // Backgrounds
  static const Color bgDark = Color(0xFF0F0E17);
  static const Color bgCard = Color(0xFF1A1A2E);
  static const Color bgCardLight = Color(0xFF16213E);
  static const Color bgSurface = Color(0xFF1F1F3A);

  // Text
  static const Color textPrimary = Color(0xFFF8F8FF);
  static const Color textSecondary = Color(0xFFB2B2CC);
  static const Color textMuted = Color(0xFF6B6B8A);

  // Chat
  static const Color userBubble = Color(0xFF6C5CE7);
  static const Color aiBubble = Color(0xFF1F1F3A);

  static Color stageColor(String stage) {
    switch (stage.toLowerCase()) {
      case 'survival': return survival;
      case 'earning': return earning;
      case 'growing': return growing;
      case 'wealth': return wealth;
      default: return primary;
    }
  }
}

// ── Typography ───────────────────────────────────────
class AppTextStyles {
  static TextStyle get h1 => GoogleFonts.poppins(
    fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.5,
  );
  static TextStyle get h2 => GoogleFonts.poppins(
    fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
  );
  static TextStyle get h3 => GoogleFonts.poppins(
    fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
  );
  static TextStyle get h4 => GoogleFonts.poppins(
    fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
  );
  static TextStyle get body => GoogleFonts.inter(
    fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textPrimary, height: 1.6,
  );
  static TextStyle get bodySmall => GoogleFonts.inter(
    fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textSecondary,
  );
  static TextStyle get label => GoogleFonts.inter(
    fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textSecondary,
  );
  static TextStyle get caption => GoogleFonts.inter(
    fontSize: 11, color: AppColors.textMuted,
  );
  static TextStyle get money => GoogleFonts.poppins(
    fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.success,
  );
  static TextStyle get chatUser => GoogleFonts.inter(
    fontSize: 14, color: Colors.white, height: 1.5,
  );
  static TextStyle get chatAI => GoogleFonts.inter(
    fontSize: 14, color: AppColors.textPrimary, height: 1.6,
  );
}

// ── Theme ────────────────────────────────────────────
class AppTheme {
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bgDark,
    colorScheme: ColorScheme.dark(
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: AppColors.bgCard,
      error: AppColors.error,
      onPrimary: Colors.white,
      onSurface: AppColors.textPrimary,
    ),
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).copyWith(
      bodyLarge: AppTextStyles.body,
      bodyMedium: AppTextStyles.body,
      bodySmall: AppTextStyles.bodySmall,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.bgDark,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: AppTextStyles.h4,
      iconTheme: const IconThemeData(color: AppColors.textPrimary),
    ),
    cardTheme: CardTheme(
      color: AppColors.bgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.bgSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      hintStyle: AppTextStyles.label,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.bgCard,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textMuted,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
  );
}

// ── Spacing ──────────────────────────────────────────
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

// ── Radius ────────────────────────────────────────────
class AppRadius {
  static BorderRadius get sm => BorderRadius.circular(8);
  static BorderRadius get md => BorderRadius.circular(12);
  static BorderRadius get lg => BorderRadius.circular(16);
  static BorderRadius get xl => BorderRadius.circular(24);
  static BorderRadius get pill => BorderRadius.circular(50);
}

// ── Shadows ───────────────────────────────────────────
class AppShadows {
  static List<BoxShadow> get card => [
    BoxShadow(
      color: Colors.black.withOpacity(0.3),
      blurRadius: 20,
      offset: const Offset(0, 4),
    )
  ];
  static List<BoxShadow> get glow => [
    BoxShadow(
      color: AppColors.primary.withOpacity(0.3),
      blurRadius: 20,
      spreadRadius: -4,
    )
  ];
}

// ── Features ─────────────────────────────────────────
class FeatureKeys {
  static const String aiRoadmap = 'ai_roadmap';
  static const String taskBooster = 'task_booster';
  static const String skillBoost = 'skill_boost';
  static const String premiumSkills = 'premium_skills';
  static const String investmentTools = 'investment_tools';
  static const String mentorship = 'mentorship';
  static const String advancedAnalytics = 'advanced_analytics';
}

// ── Stage Info ────────────────────────────────────────
class StageInfo {
  static Map<String, dynamic> get(String stage) {
    switch (stage.toLowerCase()) {
      case 'survival':
        return {
          'label': 'Survival Mode',
          'emoji': '🆘',
          'color': AppColors.survival,
          'description': 'Focus on immediate income',
          'target': '₦50,000/month',
        };
      case 'earning':
        return {
          'label': 'Earning',
          'emoji': '💪',
          'color': AppColors.earning,
          'description': 'Building consistent income',
          'target': '₦200,000/month',
        };
      case 'growing':
        return {
          'label': 'Growing',
          'emoji': '🚀',
          'color': AppColors.growing,
          'description': 'Scaling skills & income',
          'target': '₦500,000/month',
        };
      case 'wealth':
        return {
          'label': 'Building Wealth',
          'emoji': '💎',
          'color': AppColors.wealth,
          'description': 'Assets & passive income',
          'target': '₦1,000,000+/month',
        };
      default:
        return {
          'label': 'Getting Started',
          'emoji': '🌱',
          'color': AppColors.primary,
          'description': 'Begin your journey',
          'target': 'Set your first goal',
        };
    }
  }
}
