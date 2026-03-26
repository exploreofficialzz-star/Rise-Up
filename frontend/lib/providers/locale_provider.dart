// frontend/lib/providers/locale_provider.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global provider for app locale/language
final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>((ref) {
  return LocaleNotifier();
});

/// Provider to access current locale string code (e.g., 'en', 'es')
final localeCodeProvider = Provider<String>((ref) {
  return ref.watch(localeProvider).languageCode;
});

class LocaleNotifier extends StateNotifier<Locale> {
  static const _prefsKey = 'app_locale';
  
  LocaleNotifier() : super(const Locale('en')) {
    _loadSavedLocale();
  }

  /// Load saved locale from SharedPreferences
  Future<void> _loadSavedLocale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLocale = prefs.getString(_prefsKey);
      if (savedLocale != null && savedLocale.isNotEmpty) {
        state = Locale(savedLocale);
      }
    } catch (e) {
      debugPrint('Error loading locale: $e');
    }
  }

  /// Set locale explicitly
  Future<void> setLocale(Locale locale) async {
    state = locale;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, locale.languageCode);
    } catch (e) {
      debugPrint('Error saving locale: $e');
    }
  }

  /// Set locale from region code (e.g., 'africa_west' -> 'en')
  void setLocaleFromRegion(String region) {
    final regionLocales = {
      'africa_west': const Locale('en'),
      'africa_east': const Locale('sw'), // Swahili
      'africa_south': const Locale('en'),
      'south_asia': const Locale('hi'), // Hindi
      'southeast_asia': const Locale('en'),
      'latin_america': const Locale('es'), // Spanish
      'middle_east': const Locale('ar'), // Arabic
      'east_asia': const Locale('zh'), // Chinese
      'europe': const Locale('en'),
      'north_america': const Locale('en'),
      'oceania': const Locale('en'),
      'global': const Locale('en'),
    };
    
    final newLocale = regionLocales[region] ?? const Locale('en');
    setLocale(newLocale);
  }

  /// Get supported locales for the app
  List<Locale> get supportedLocales => const [
    Locale('en'), // English
    Locale('es'), // Spanish
    Locale('fr'), // French
    Locale('de'), // German
    Locale('pt'), // Portuguese
    Locale('hi'), // Hindi
    Locale('ar'), // Arabic
    Locale('zh'), // Chinese
    Locale('ja'), // Japanese
    Locale('ru'), // Russian
    Locale('sw'), // Swahili
    Locale('yo'), // Yoruba
    Locale('ig'), // Igbo
    Locale('ha'), // Hausa
  ];

  /// Check if locale is RTL
  bool get isRtl => ['ar', 'he', 'fa', 'ur'].contains(state.languageCode);
}

