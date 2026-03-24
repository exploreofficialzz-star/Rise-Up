// frontend/lib/services/currency_service.dart
//
// Global dynamic currency system.
// • Reads the user's currency from their profile (set during onboarding)
// • Shows amounts in BOTH USD and local currency when they differ
// • Never hardcodes NGN, $, or any specific currency
// • Works for any of the 50+ supported currencies

class CurrencyService {
  // ── Singleton ────────────────────────────────────────
  static final CurrencyService _i = CurrencyService._();
  factory CurrencyService() => _i;
  CurrencyService._();

  String _code   = 'USD';
  String _symbol = '\$';

  /// Call this once after loading the user profile
  void init(String currencyCode) {
    _code   = currencyCode.toUpperCase();
    _symbol = _symbolFor(_code);
  }

  String get code   => _code;
  String get symbol => _symbol;

  // ── Format a single amount ────────────────────────────
  /// Returns "₦ 50,000" or "$ 500" depending on the user's currency
  String format(num amount, {String? currency, bool compact = false}) {
    final code   = (currency ?? _code).toUpperCase();
    final symbol = _symbolFor(code);
    final val    = compact ? _compact(amount) : _commify(amount);
    return '$symbol $val';
  }

  /// Returns "$ 500 / ₦ 750,000" when currencies differ
  String dual(num usdAmount, {double rate = 1, String? localCode}) {
    final local = (localCode ?? _code).toUpperCase();
    if (local == 'USD') return format(usdAmount, currency: 'USD');
    final localAmount = usdAmount * rate;
    return '\$ ${_compact(usdAmount)}  ·  ${_symbolFor(local)} ${_compact(localAmount)}';
  }

  // ── Format a range ────────────────────────────────────
  /// e.g. "₦ 50K – ₦ 200K/mo"
  String range(num min, num max, {String? currency, String suffix = '/mo'}) {
    final sym = _symbolFor((currency ?? _code).toUpperCase());
    return '$sym ${_compact(min)} – $sym ${_compact(max)}$suffix';
  }

  // ── Budget label ──────────────────────────────────────
  String budgetLabel(double amount) {
    if (amount <= 0) return '${_symbol}0 Free';
    return '${_symbol}${_compact(amount)}';
  }

  // ── Compact formatter ────────────────────────────────
  String _compact(num v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000)    return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  // ── Comma formatter ──────────────────────────────────
  String _commify(num v) {
    final parts = v.toStringAsFixed(0).split('');
    final buf   = StringBuffer();
    for (int i = 0; i < parts.length; i++) {
      if (i > 0 && (parts.length - i) % 3 == 0) buf.write(',');
      buf.write(parts[i]);
    }
    return buf.toString();
  }

  // ── Symbol lookup (50+ currencies) ───────────────────
  static String _symbolFor(String code) {
    const map = {
      'USD': '\$',   'EUR': '€',   'GBP': '£',   'JPY': '¥',
      'CNY': '¥',   'INR': '₹',   'NGN': '₦',   'KES': 'KSh',
      'GHS': '₵',   'ZAR': 'R',   'EGP': 'E£',  'MAD': 'DH',
      'TZS': 'TSh', 'UGX': 'USh', 'RWF': 'RF',  'ETB': 'Br',
      'XOF': 'CFA', 'XAF': 'FCFA','CAD': 'C\$', 'AUD': 'A\$',
      'NZD': 'NZ\$','CHF': 'Fr',  'SEK': 'kr',  'NOK': 'kr',
      'DKK': 'kr',  'BRL': 'R\$', 'MXN': 'MX\$','ARS': '\$',
      'COP': '\$',  'CLP': '\$',  'PEN': 'S/',  'VES': 'Bs',
      'SGD': 'S\$', 'HKD': 'HK\$','KRW': '₩',  'IDR': 'Rp',
      'PHP': '₱',   'THB': '฿',   'MYR': 'RM',  'PKR': '₨',
      'BDT': '৳',   'VND': '₫',   'AED': 'د.إ', 'SAR': '﷼',
      'QAR': 'QR',  'KWD': 'KD',  'BHD': 'BD',  'ILS': '₪',
      'TRY': '₺',   'RUB': '₽',   'UAH': '₴',   'PLN': 'zł',
      'CZK': 'Kč',  'HUF': 'Ft',  'RON': 'lei', 'HRK': 'kn',
    };
    return map[code] ?? code;
  }

  // ── Currency display name ─────────────────────────────
  static String nameFor(String code) {
    const names = {
      'USD': 'US Dollar',     'EUR': 'Euro',
      'GBP': 'British Pound', 'JPY': 'Japanese Yen',
      'NGN': 'Nigerian Naira','KES': 'Kenyan Shilling',
      'GHS': 'Ghanaian Cedi', 'ZAR': 'South African Rand',
      'EGP': 'Egyptian Pound','INR': 'Indian Rupee',
      'CAD': 'Canadian Dollar','AUD': 'Australian Dollar',
      'BRL': 'Brazilian Real', 'MXN': 'Mexican Peso',
      'CNY': 'Chinese Yuan',   'SGD': 'Singapore Dollar',
      'AED': 'UAE Dirham',     'SAR': 'Saudi Riyal',
    };
    return names[code] ?? code;
  }

  // ── All supported currencies (for picker) ─────────────
  static const List<Map<String, String>> allCurrencies = [
    {'code': 'USD', 'name': 'US Dollar',            'symbol': '\$'},
    {'code': 'EUR', 'name': 'Euro',                 'symbol': '€'},
    {'code': 'GBP', 'name': 'British Pound',        'symbol': '£'},
    {'code': 'NGN', 'name': 'Nigerian Naira',       'symbol': '₦'},
    {'code': 'KES', 'name': 'Kenyan Shilling',      'symbol': 'KSh'},
    {'code': 'GHS', 'name': 'Ghanaian Cedi',        'symbol': '₵'},
    {'code': 'ZAR', 'name': 'South African Rand',   'symbol': 'R'},
    {'code': 'EGP', 'name': 'Egyptian Pound',       'symbol': 'E£'},
    {'code': 'INR', 'name': 'Indian Rupee',         'symbol': '₹'},
    {'code': 'PKR', 'name': 'Pakistani Rupee',      'symbol': '₨'},
    {'code': 'BDT', 'name': 'Bangladeshi Taka',     'symbol': '৳'},
    {'code': 'PHP', 'name': 'Philippine Peso',      'symbol': '₱'},
    {'code': 'IDR', 'name': 'Indonesian Rupiah',    'symbol': 'Rp'},
    {'code': 'MYR', 'name': 'Malaysian Ringgit',    'symbol': 'RM'},
    {'code': 'SGD', 'name': 'Singapore Dollar',     'symbol': 'S\$'},
    {'code': 'THB', 'name': 'Thai Baht',            'symbol': '฿'},
    {'code': 'VND', 'name': 'Vietnamese Dong',      'symbol': '₫'},
    {'code': 'KRW', 'name': 'South Korean Won',     'symbol': '₩'},
    {'code': 'JPY', 'name': 'Japanese Yen',         'symbol': '¥'},
    {'code': 'CNY', 'name': 'Chinese Yuan',         'symbol': '¥'},
    {'code': 'HKD', 'name': 'Hong Kong Dollar',     'symbol': 'HK\$'},
    {'code': 'AUD', 'name': 'Australian Dollar',    'symbol': 'A\$'},
    {'code': 'NZD', 'name': 'New Zealand Dollar',   'symbol': 'NZ\$'},
    {'code': 'CAD', 'name': 'Canadian Dollar',      'symbol': 'C\$'},
    {'code': 'BRL', 'name': 'Brazilian Real',       'symbol': 'R\$'},
    {'code': 'MXN', 'name': 'Mexican Peso',         'symbol': 'MX\$'},
    {'code': 'ARS', 'name': 'Argentine Peso',       'symbol': '\$'},
    {'code': 'COP', 'name': 'Colombian Peso',       'symbol': '\$'},
    {'code': 'AED', 'name': 'UAE Dirham',           'symbol': 'د.إ'},
    {'code': 'SAR', 'name': 'Saudi Riyal',          'symbol': '﷼'},
    {'code': 'QAR', 'name': 'Qatari Riyal',         'symbol': 'QR'},
    {'code': 'KWD', 'name': 'Kuwaiti Dinar',        'symbol': 'KD'},
    {'code': 'ILS', 'name': 'Israeli Shekel',       'symbol': '₪'},
    {'code': 'TRY', 'name': 'Turkish Lira',         'symbol': '₺'},
    {'code': 'RUB', 'name': 'Russian Ruble',        'symbol': '₽'},
    {'code': 'PLN', 'name': 'Polish Zloty',         'symbol': 'zł'},
    {'code': 'SEK', 'name': 'Swedish Krona',        'symbol': 'kr'},
    {'code': 'CHF', 'name': 'Swiss Franc',          'symbol': 'Fr'},
    {'code': 'XOF', 'name': 'West African CFA',     'symbol': 'CFA'},
    {'code': 'XAF', 'name': 'Central African CFA',  'symbol': 'FCFA'},
    {'code': 'TZS', 'name': 'Tanzanian Shilling',   'symbol': 'TSh'},
    {'code': 'UGX', 'name': 'Ugandan Shilling',     'symbol': 'USh'},
    {'code': 'ETB', 'name': 'Ethiopian Birr',       'symbol': 'Br'},
    {'code': 'MAD', 'name': 'Moroccan Dirham',      'symbol': 'DH'},
    {'code': 'RWF', 'name': 'Rwandan Franc',        'symbol': 'RF'},
  ];
}

/// Global singleton shortcut
final currency = CurrencyService();
