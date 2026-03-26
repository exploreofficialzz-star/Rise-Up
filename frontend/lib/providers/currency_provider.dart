// frontend/lib/providers/currency_provider.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global provider for user's preferred currency
final currencyProvider = StateNotifierProvider<CurrencyNotifier, String>((ref) {
  return CurrencyNotifier();
});

/// Provider for currency symbol (e.g., '$', '₦', '€')
final currencySymbolProvider = Provider<String>((ref) {
  final code = ref.watch(currencyProvider);
  return _getCurrencySymbol(code);
});

/// Provider for currency name
final currencyNameProvider = Provider<String>((ref) {
  final code = ref.watch(currencyProvider);
  return _getCurrencyName(code);
});

class CurrencyNotifier extends StateNotifier<String> {
  static const _prefsKey = 'app_currency';
  
  CurrencyNotifier() : super('USD') {
    _loadSavedCurrency();
  }

  /// Load saved currency from SharedPreferences
  Future<void> _loadSavedCurrency() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCurrency = prefs.getString(_prefsKey);
      if (savedCurrency != null && savedCurrency.isNotEmpty) {
        state = savedCurrency;
      }
    } catch (e) {
      debugPrint('Error loading currency: $e');
    }
  }

  /// Set currency explicitly
  Future<void> setCurrency(String currencyCode) async {
    state = currencyCode.toUpperCase();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, state);
    } catch (e) {
      debugPrint('Error saving currency: $e');
    }
  }

  /// Get currency from country/region code
  void setCurrencyFromRegion(String region) {
    final regionCurrencies = {
      'africa_west': 'NGN', // Nigeria
      'africa_east': 'KES', // Kenya
      'africa_south': 'ZAR', // South Africa
      'south_asia': 'INR', // India
      'southeast_asia': 'IDR', // Indonesia
      'latin_america': 'BRL', // Brazil
      'middle_east': 'EGP', // Egypt
      'east_asia': 'CNY', // China
      'europe': 'EUR', // Euro
      'north_america': 'USD', // US Dollar
      'oceania': 'AUD', // Australian Dollar
      'global': 'USD',
    };
    
    final currency = regionCurrencies[region] ?? 'USD';
    setCurrency(currency);
  }

  /// Detect currency from locale
  void setCurrencyFromLocale(Locale locale) {
    final localeCurrencies = {
      'en': 'USD',
      'es': 'EUR',
      'fr': 'EUR',
      'de': 'EUR',
      'pt': 'BRL',
      'hi': 'INR',
      'ar': 'AED',
      'zh': 'CNY',
      'ja': 'JPY',
      'ru': 'RUB',
      'sw': 'KES',
      'yo': 'NGN',
      'ig': 'NGN',
      'ha': 'NGN',
    };
    
    final currency = localeCurrencies[locale.languageCode] ?? 'USD';
    setCurrency(currency);
  }
}

/// Get currency symbol
String _getCurrencySymbol(String code) {
  final symbols = {
    'USD': '\$',
    'EUR': '€',
    'GBP': '£',
    'JPY': '¥',
    'CNY': '¥',
    'NGN': '₦',
    'GHS': '₵',
    'KES': 'KSh',
    'ZAR': 'R',
    'INR': '₹',
    'PKR': '₨',
    'BDT': '৳',
    'BRL': 'R\$',
    'MXN': '\$',
    'PHP': '₱',
    'IDR': 'Rp',
    'MYR': 'RM',
    'SGD': 'S\$',
    'AED': 'د.إ',
    'SAR': '﷼',
    'TRY': '₺',
    'QAR': '﷼',
    'EGP': 'E£',
    'RUB': '₽',
    'AUD': 'A\$',
    'CAD': 'C\$',
    'CHF': 'Fr',
    'SEK': 'kr',
    'NOK': 'kr',
    'DKK': 'kr',
    'PLN': 'zł',
    'THB': '฿',
    'VND': '₫',
    'KRW': '₩',
    'TWD': 'NT\$',
    'HKD': 'HK\$',
    'NZD': 'NZ\$',
    'BTC': '₿',
    'ETH': 'Ξ',
    'USDT': '₮',
  };
  return symbols[code.toUpperCase()] ?? code;
}

/// Get currency full name
String _getCurrencyName(String code) {
  final names = {
    'USD': 'US Dollar',
    'EUR': 'Euro',
    'GBP': 'British Pound',
    'JPY': 'Japanese Yen',
    'CNY': 'Chinese Yuan',
    'NGN': 'Nigerian Naira',
    'GHS': 'Ghana Cedi',
    'KES': 'Kenyan Shilling',
    'ZAR': 'South African Rand',
    'INR': 'Indian Rupee',
    'PKR': 'Pakistani Rupee',
    'BDT': 'Bangladeshi Taka',
    'BRL': 'Brazilian Real',
    'MXN': 'Mexican Peso',
    'PHP': 'Philippine Peso',
    'IDR': 'Indonesian Rupiah',
    'MYR': 'Malaysian Ringgit',
    'SGD': 'Singapore Dollar',
    'AED': 'UAE Dirham',
    'SAR': 'Saudi Riyal',
    'TRY': 'Turkish Lira',
    'QAR': 'Qatari Riyal',
    'EGP': 'Egyptian Pound',
    'RUB': 'Russian Ruble',
    'AUD': 'Australian Dollar',
    'CAD': 'Canadian Dollar',
    'CHF': 'Swiss Franc',
    'SEK': 'Swedish Krona',
    'NOK': 'Norwegian Krone',
    'DKK': 'Danish Krone',
    'PLN': 'Polish Zloty',
    'THB': 'Thai Baht',
    'VND': 'Vietnamese Dong',
    'KRW': 'South Korean Won',
    'TWD': 'Taiwan Dollar',
    'HKD': 'Hong Kong Dollar',
    'NZD': 'New Zealand Dollar',
    'BTC': 'Bitcoin',
    'ETH': 'Ethereum',
    'USDT': 'Tether',
  };
  return names[code.toUpperCase()] ?? code;
}

/// List of all supported currencies
final supportedCurrenciesProvider = Provider<List<Map<String, String>>>((ref) {
  return [
    {'code': 'USD', 'name': 'US Dollar', 'symbol': '\$'},
    {'code': 'EUR', 'name': 'Euro', 'symbol': '€'},
    {'code': 'GBP', 'name': 'British Pound', 'symbol': '£'},
    {'code': 'JPY', 'name': 'Japanese Yen', 'symbol': '¥'},
    {'code': 'CNY', 'name': 'Chinese Yuan', 'symbol': '¥'},
    {'code': 'NGN', 'name': 'Nigerian Naira', 'symbol': '₦'},
    {'code': 'GHS', 'name': 'Ghana Cedi', 'symbol': '₵'},
    {'code': 'KES', 'name': 'Kenyan Shilling', 'symbol': 'KSh'},
    {'code': 'ZAR', 'name': 'South African Rand', 'symbol': 'R'},
    {'code': 'INR', 'name': 'Indian Rupee', 'symbol': '₹'},
    {'code': 'PKR', 'name': 'Pakistani Rupee', 'symbol': '₨'},
    {'code': 'BDT', 'name': 'Bangladeshi Taka', 'symbol': '৳'},
    {'code': 'BRL', 'name': 'Brazilian Real', 'symbol': 'R\$'},
    {'code': 'MXN', 'name': 'Mexican Peso', 'symbol': '\$'},
    {'code': 'PHP', 'name': 'Philippine Peso', 'symbol': '₱'},
    {'code': 'IDR', 'name': 'Indonesian Rupiah', 'symbol': 'Rp'},
    {'code': 'MYR', 'name': 'Malaysian Ringgit', 'symbol': 'RM'},
    {'code': 'SGD', 'name': 'Singapore Dollar', 'symbol': 'S\$'},
    {'code': 'AED', 'name': 'UAE Dirham', 'symbol': 'د.إ'},
    {'code': 'SAR', 'name': 'Saudi Riyal', 'symbol': '﷼'},
    {'code': 'TRY', 'name': 'Turkish Lira', 'symbol': '₺'},
    {'code': 'EGP', 'name': 'Egyptian Pound', 'symbol': 'E£'},
    {'code': 'RUB', 'name': 'Russian Ruble', 'symbol': '₽'},
    {'code': 'AUD', 'name': 'Australian Dollar', 'symbol': 'A\$'},
    {'code': 'CAD', 'name': 'Canadian Dollar', 'symbol': 'C\$'},
    {'code': 'CHF', 'name': 'Swiss Franc', 'symbol': 'Fr'},
    {'code': 'BTC', 'name': 'Bitcoin', 'symbol': '₿'},
    {'code': 'ETH', 'name': 'Ethereum', 'symbol': 'Ξ'},
    {'code': 'USDT', 'name': 'Tether', 'symbol': '₮'},
  ];
});
