"""
services/currency_service.py — RiseUp Currency Service (Production · Universe Edition)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Live exchange rates · Multi-provider failover · 180+ ISO 4217 currencies · No hardcoding

Provider failover chain (tries in order):
  1. Open Exchange Rates   OPENEXCHANGERATES_APP_ID   (free: 1 000 req/month)
  2. ExchangeRate-API      EXCHANGERATE_API_KEY        (free: 1 500 req/month)
  3. Fixer.io              FIXER_API_KEY               (free: 100 req/month)
  4. open.er-api.com       no key required             (last resort)

Cache TTL: CURRENCY_CACHE_TTL_MINUTES (default 60)
On total failure: HTTPException(503) — never returns stale/wrong data.

Render environment variables to add:
  OPENEXCHANGERATES_APP_ID   = <key>
  EXCHANGERATE_API_KEY       = <key>
  FIXER_API_KEY              = <key>
  CURRENCY_CACHE_TTL_MINUTES = 60
"""

import logging
import asyncio
from typing import Dict, Optional, Tuple
from datetime import datetime, timezone, timedelta

import httpx
from fastapi import HTTPException

from config import settings

logger = logging.getLogger(__name__)

CACHE_TTL_MINUTES = int(getattr(settings, "CURRENCY_CACHE_TTL_MINUTES", 60))
REQUEST_TIMEOUT   = float(getattr(settings, "CURRENCY_REQUEST_TIMEOUT", 6.0))

_cache: Dict[str, Tuple[Dict[str, float], datetime]] = {}
_cache_lock = asyncio.Lock()


# ═════════════════════════════════════════════════════════════════════════════
# PROVIDER IMPLEMENTATIONS
# ═════════════════════════════════════════════════════════════════════════════

async def _fetch_open_exchange_rates(client: httpx.AsyncClient) -> Dict[str, float]:
    app_id = getattr(settings, "OPENEXCHANGERATES_APP_ID", None)
    if not app_id:
        raise ValueError("OPENEXCHANGERATES_APP_ID not configured")
    resp = await client.get(
        "https://openexchangerates.org/api/latest.json",
        params={"app_id": app_id, "base": "USD"},
        timeout=REQUEST_TIMEOUT,
    )
    resp.raise_for_status()
    rates = resp.json().get("rates")
    if not rates:
        raise ValueError("Empty rates from Open Exchange Rates")
    logger.info(f"✅ Open Exchange Rates → {len(rates)} pairs")
    return rates


async def _fetch_exchangerate_api(client: httpx.AsyncClient) -> Dict[str, float]:
    api_key = getattr(settings, "EXCHANGERATE_API_KEY", None)
    if not api_key:
        raise ValueError("EXCHANGERATE_API_KEY not configured")
    resp = await client.get(
        f"https://v6.exchangerate-api.com/v6/{api_key}/latest/USD",
        timeout=REQUEST_TIMEOUT,
    )
    resp.raise_for_status()
    data = resp.json()
    if data.get("result") != "success":
        raise ValueError(f"ExchangeRate-API: {data.get('error-type', 'unknown')}")
    rates = data.get("conversion_rates")
    if not rates:
        raise ValueError("Empty rates from ExchangeRate-API")
    logger.info(f"✅ ExchangeRate-API → {len(rates)} pairs")
    return rates


async def _fetch_fixer(client: httpx.AsyncClient) -> Dict[str, float]:
    api_key = getattr(settings, "FIXER_API_KEY", None)
    if not api_key:
        raise ValueError("FIXER_API_KEY not configured")
    resp = await client.get(
        "https://data.fixer.io/api/latest",
        params={"access_key": api_key},
        timeout=REQUEST_TIMEOUT,
    )
    resp.raise_for_status()
    data = resp.json()
    if not data.get("success"):
        raise ValueError(f"Fixer: {data.get('error', {}).get('info', 'unknown')}")
    rates_eur = data.get("rates", {})
    if not rates_eur:
        raise ValueError("Empty rates from Fixer")
    usd_per_eur = rates_eur.get("USD")
    if not usd_per_eur:
        raise ValueError("USD missing from Fixer — cannot rebase")
    rates_usd = {k: v / usd_per_eur for k, v in rates_eur.items()}
    rates_usd["USD"] = 1.0
    logger.info(f"✅ Fixer → {len(rates_usd)} pairs (rebased EUR→USD)")
    return rates_usd


async def _fetch_open_er_api_free(client: httpx.AsyncClient) -> Dict[str, float]:
    resp = await client.get(
        "https://open.er-api.com/v6/latest/USD",
        timeout=REQUEST_TIMEOUT,
    )
    resp.raise_for_status()
    data = resp.json()
    if data.get("result") != "success":
        raise ValueError(f"open.er-api: {data.get('error-type', 'unknown')}")
    rates = data.get("rates")
    if not rates:
        raise ValueError("Empty rates from open.er-api")
    logger.info(f"✅ open.er-api (free) → {len(rates)} pairs")
    return rates


_PROVIDERS = [
    ("Open Exchange Rates", _fetch_open_exchange_rates),
    ("ExchangeRate-API",    _fetch_exchangerate_api),
    ("Fixer.io",            _fetch_fixer),
    ("open.er-api (free)",  _fetch_open_er_api_free),
]


# ═════════════════════════════════════════════════════════════════════════════
# FAILOVER + CACHE
# ═════════════════════════════════════════════════════════════════════════════

async def _fetch_live_rates_usd() -> Dict[str, float]:
    errors = []
    async with httpx.AsyncClient() as client:
        for name, fn in _PROVIDERS:
            try:
                return await fn(client)
            except Exception as e:
                logger.warning(f"⚠️  Provider '{name}' failed: {e}")
                errors.append(f"{name}: {e}")
    logger.error("🔥 ALL providers failed:\n" + "\n".join(errors))
    raise HTTPException(
        status_code=503,
        detail="Currency service temporarily unavailable. All providers failed. Please retry shortly.",
    )


async def _get_usd_rates() -> Dict[str, float]:
    global _cache
    async with _cache_lock:
        cached = _cache.get("USD")
        if cached:
            rates, fetched_at = cached
            if datetime.now(timezone.utc) - fetched_at < timedelta(minutes=CACHE_TTL_MINUTES):
                return rates
        rates = await _fetch_live_rates_usd()
        _cache["USD"] = (rates, datetime.now(timezone.utc))
        return rates


# ═════════════════════════════════════════════════════════════════════════════
# UNIVERSE CURRENCY → REGION MAP  (all 180+ ISO 4217 currencies)
# ═════════════════════════════════════════════════════════════════════════════

# Every currency in the world mapped to a RiseUp region.
# Groups follow the UN geoscheme + RiseUp's own regional taxonomy.

CURRENCY_REGION_MAP: Dict[str, str] = {

    # ── WEST AFRICA ───────────────────────────────────────────────────────
    "NGN": "africa_west",   # Nigeria — Naira
    "GHS": "africa_west",   # Ghana — Cedi
    "XOF": "africa_west",   # CFA Franc BCEAO (Benin, Burkina Faso, Côte d'Ivoire,
                             #   Guinea-Bissau, Mali, Niger, Senegal, Togo)
    "GMD": "africa_west",   # Gambia — Dalasi
    "GNF": "africa_west",   # Guinea — Franc
    "LRD": "africa_west",   # Liberia — Dollar
    "MRU": "africa_west",   # Mauritania — Ouguiya
    "SLL": "africa_west",   # Sierra Leone — Leone
    "SLE": "africa_west",   # Sierra Leone — Leone (new)
    "CVE": "africa_west",   # Cape Verde — Escudo

    # ── CENTRAL AFRICA ────────────────────────────────────────────────────
    "XAF": "africa_central",  # CFA Franc BEAC (Cameroon, CAR, Chad, Congo,
                               #   Equatorial Guinea, Gabon)
    "CDF": "africa_central",  # DR Congo — Franc
    "STN": "africa_central",  # São Tomé & Príncipe — Dobra
    "AOA": "africa_central",  # Angola — Kwanza

    # ── EAST AFRICA ───────────────────────────────────────────────────────
    "KES": "africa_east",   # Kenya — Shilling
    "TZS": "africa_east",   # Tanzania — Shilling
    "UGX": "africa_east",   # Uganda — Shilling
    "RWF": "africa_east",   # Rwanda — Franc
    "ETB": "africa_east",   # Ethiopia — Birr
    "BIF": "africa_east",   # Burundi — Franc
    "DJF": "africa_east",   # Djibouti — Franc
    "ERN": "africa_east",   # Eritrea — Nakfa
    "SOS": "africa_east",   # Somalia — Shilling
    "SDG": "africa_east",   # Sudan — Pound
    "SSP": "africa_east",   # South Sudan — Pound
    "MGA": "africa_east",   # Madagascar — Ariary
    "SCR": "africa_east",   # Seychelles — Rupee
    "KMF": "africa_east",   # Comoros — Franc
    "MUR": "africa_east",   # Mauritius — Rupee

    # ── SOUTHERN AFRICA ───────────────────────────────────────────────────
    "ZAR": "africa_south",  # South Africa — Rand
    "ZWL": "africa_south",  # Zimbabwe — Dollar (old)
    "ZWG": "africa_south",  # Zimbabwe — Gold (new)
    "BWP": "africa_south",  # Botswana — Pula
    "MWK": "africa_south",  # Malawi — Kwacha
    "MZN": "africa_south",  # Mozambique — Metical
    "NAD": "africa_south",  # Namibia — Dollar
    "SZL": "africa_south",  # Eswatini — Lilangeni
    "LSL": "africa_south",  # Lesotho — Loti
    "ZMW": "africa_south",  # Zambia — Kwacha

    # ── NORTH AFRICA ──────────────────────────────────────────────────────
    "EGP": "africa_north",  # Egypt — Pound
    "MAD": "africa_north",  # Morocco — Dirham
    "TND": "africa_north",  # Tunisia — Dinar
    "DZD": "africa_north",  # Algeria — Dinar
    "LYD": "africa_north",  # Libya — Dinar

    # ── MIDDLE EAST ───────────────────────────────────────────────────────
    "SAR": "middle_east",   # Saudi Arabia — Riyal
    "AED": "middle_east",   # UAE — Dirham
    "QAR": "middle_east",   # Qatar — Riyal
    "KWD": "middle_east",   # Kuwait — Dinar
    "BHD": "middle_east",   # Bahrain — Dinar
    "OMR": "middle_east",   # Oman — Rial
    "JOD": "middle_east",   # Jordan — Dinar
    "IQD": "middle_east",   # Iraq — Dinar
    "SYP": "middle_east",   # Syria — Pound
    "LBP": "middle_east",   # Lebanon — Pound
    "YER": "middle_east",   # Yemen — Rial
    "ILS": "middle_east",   # Israel — Shekel
    "IRR": "middle_east",   # Iran — Rial
    "TRY": "middle_east",   # Turkey — Lira

    # ── SOUTH ASIA ────────────────────────────────────────────────────────
    "INR": "south_asia",    # India — Rupee
    "PKR": "south_asia",    # Pakistan — Rupee
    "BDT": "south_asia",    # Bangladesh — Taka
    "LKR": "south_asia",    # Sri Lanka — Rupee
    "NPR": "south_asia",    # Nepal — Rupee
    "MVR": "south_asia",    # Maldives — Rufiyaa
    "BTN": "south_asia",    # Bhutan — Ngultrum
    "AFN": "south_asia",    # Afghanistan — Afghani

    # ── SOUTHEAST ASIA ────────────────────────────────────────────────────
    "PHP": "southeast_asia",  # Philippines — Peso
    "IDR": "southeast_asia",  # Indonesia — Rupiah
    "MYR": "southeast_asia",  # Malaysia — Ringgit
    "THB": "southeast_asia",  # Thailand — Baht
    "VND": "southeast_asia",  # Vietnam — Dong
    "SGD": "southeast_asia",  # Singapore — Dollar
    "MMK": "southeast_asia",  # Myanmar — Kyat
    "KHR": "southeast_asia",  # Cambodia — Riel
    "LAK": "southeast_asia",  # Laos — Kip
    "BND": "southeast_asia",  # Brunei — Dollar
    "MOP": "southeast_asia",  # Macao — Pataca
    "TWD": "southeast_asia",  # Taiwan — Dollar
    "TLS": "southeast_asia",  # Timor-Leste — Dollar (uses USD, alias)

    # ── EAST ASIA ─────────────────────────────────────────────────────────
    "CNY": "east_asia",     # China — Yuan Renminbi
    "JPY": "east_asia",     # Japan — Yen
    "KRW": "east_asia",     # South Korea — Won
    "HKD": "east_asia",     # Hong Kong — Dollar
    "MNT": "east_asia",     # Mongolia — Tögrög
    "KPW": "east_asia",     # North Korea — Won

    # ── CENTRAL ASIA ──────────────────────────────────────────────────────
    "KZT": "central_asia",  # Kazakhstan — Tenge
    "UZS": "central_asia",  # Uzbekistan — Som
    "TJS": "central_asia",  # Tajikistan — Somoni
    "TMT": "central_asia",  # Turkmenistan — Manat
    "KGS": "central_asia",  # Kyrgyzstan — Som
    "AZN": "central_asia",  # Azerbaijan — Manat
    "GEL": "central_asia",  # Georgia — Lari
    "AMD": "central_asia",  # Armenia — Dram

    # ── NORTH AMERICA ─────────────────────────────────────────────────────
    "USD": "north_america",  # United States — Dollar
    "CAD": "north_america",  # Canada — Dollar
    "MXN": "north_america",  # Mexico — Peso

    # ── CARIBBEAN ─────────────────────────────────────────────────────────
    "JMD": "caribbean",     # Jamaica — Dollar
    "TTD": "caribbean",     # Trinidad & Tobago — Dollar
    "BBD": "caribbean",     # Barbados — Dollar
    "BSD": "caribbean",     # Bahamas — Dollar
    "HTG": "caribbean",     # Haiti — Gourde
    "CUP": "caribbean",     # Cuba — Peso
    "CUC": "caribbean",     # Cuba — Convertible Peso
    "DOP": "caribbean",     # Dominican Republic — Peso
    "XCD": "caribbean",     # Eastern Caribbean Dollar (Antigua, Dominica,
                             #   Grenada, St Kitts, St Lucia, St Vincent)
    "AWG": "caribbean",     # Aruba — Florin
    "ANG": "caribbean",     # Netherlands Antilles — Guilder
    "KYD": "caribbean",     # Cayman Islands — Dollar
    "BMD": "caribbean",     # Bermuda — Dollar
    "BZD": "caribbean",     # Belize — Dollar

    # ── LATIN AMERICA (CENTRAL) ───────────────────────────────────────────
    "GTQ": "latin_america",  # Guatemala — Quetzal
    "HNL": "latin_america",  # Honduras — Lempira
    "NIO": "latin_america",  # Nicaragua — Córdoba
    "CRC": "latin_america",  # Costa Rica — Colón
    "PAB": "latin_america",  # Panama — Balboa (pegged to USD)

    # ── LATIN AMERICA (SOUTH) ─────────────────────────────────────────────
    "BRL": "latin_america",  # Brazil — Real
    "COP": "latin_america",  # Colombia — Peso
    "ARS": "latin_america",  # Argentina — Peso
    "PEN": "latin_america",  # Peru — Sol
    "CLP": "latin_america",  # Chile — Peso
    "VES": "latin_america",  # Venezuela — Bolívar Soberano
    "BOB": "latin_america",  # Bolivia — Boliviano
    "PYG": "latin_america",  # Paraguay — Guaraní
    "UYU": "latin_america",  # Uruguay — Peso
    "GYD": "latin_america",  # Guyana — Dollar
    "SRD": "latin_america",  # Suriname — Dollar
    "FKP": "latin_america",  # Falkland Islands — Pound
    "SVC": "latin_america",  # El Salvador — Colón (now uses USD)

    # ── EUROPE (EUROZONE) ─────────────────────────────────────────────────
    "EUR": "europe",        # Euro (19 EU states + others)

    # ── EUROPE (NON-EURO) ─────────────────────────────────────────────────
    "GBP": "europe",        # United Kingdom — Pound Sterling
    "CHF": "europe",        # Switzerland — Franc
    "SEK": "europe",        # Sweden — Krona
    "NOK": "europe",        # Norway — Krone
    "DKK": "europe",        # Denmark — Krone
    "PLN": "europe",        # Poland — Złoty
    "CZK": "europe",        # Czech Republic — Koruna
    "HUF": "europe",        # Hungary — Forint
    "RON": "europe",        # Romania — Leu
    "BGN": "europe",        # Bulgaria — Lev
    "HRK": "europe",        # Croatia — Kuna (now EUR)
    "RSD": "europe",        # Serbia — Dinar
    "BAM": "europe",        # Bosnia & Herzegovina — Mark
    "MKD": "europe",        # North Macedonia — Denar
    "ALL": "europe",        # Albania — Lek
    "MDL": "europe",        # Moldova — Leu
    "UAH": "europe",        # Ukraine — Hryvnia
    "RUB": "europe",        # Russia — Ruble
    "BYN": "europe",        # Belarus — Ruble
    "ISK": "europe",        # Iceland — Króna
    "GIP": "europe",        # Gibraltar — Pound
    "FJD": "europe",        # (mapped below under Oceania)
    "JEP": "europe",        # Jersey — Pound
    "GGP": "europe",        # Guernsey — Pound
    "IMP": "europe",        # Isle of Man — Pound
    "SMF": "europe",        # San Marino (uses EUR)
    "MTL": "europe",        # Malta (now EUR, legacy)
    "SKK": "europe",        # Slovakia (now EUR, legacy)
    "SIT": "europe",        # Slovenia (now EUR, legacy)
    "CYP": "europe",        # Cyprus (now EUR, legacy)
    "EEK": "europe",        # Estonia (now EUR, legacy)
    "LTL": "europe",        # Lithuania (now EUR, legacy)
    "LVL": "europe",        # Latvia (now EUR, legacy)

    # ── OCEANIA ───────────────────────────────────────────────────────────
    "AUD": "oceania",       # Australia — Dollar
    "NZD": "oceania",       # New Zealand — Dollar
    "FJD": "oceania",       # Fiji — Dollar
    "PGK": "oceania",       # Papua New Guinea — Kina
    "SBD": "oceania",       # Solomon Islands — Dollar
    "VUV": "oceania",       # Vanuatu — Vatu
    "WST": "oceania",       # Samoa — Tālā
    "TOP": "oceania",       # Tonga — Paʻanga
    "TVD": "oceania",       # Tuvalu — Dollar
    "KID": "oceania",       # Kiribati — Dollar (uses AUD)
    "NRD": "oceania",       # Nauru — Dollar (uses AUD)
    "CKD": "oceania",       # Cook Islands — Dollar
    "XPF": "oceania",       # CFP Franc (French Polynesia, New Caledonia, Wallis & Futuna)

    # ── CRYPTO / DIGITAL ──────────────────────────────────────────────────
    "BTC":  "global",       # Bitcoin
    "ETH":  "global",       # Ethereum
    "USDT": "global",       # Tether
    "USDC": "global",       # USD Coin
    "BNB":  "global",       # Binance Coin
    "XRP":  "global",       # Ripple
    "SOL":  "global",       # Solana
    "ADA":  "global",       # Cardano
    "MATIC":"global",       # Polygon
    "LTC":  "global",       # Litecoin

    # ── SPECIAL / SUPRANATIONAL ───────────────────────────────────────────
    "XDR":  "global",       # IMF Special Drawing Rights
    "XAU":  "global",       # Gold (troy ounce)
    "XAG":  "global",       # Silver (troy ounce)
    "XPT":  "global",       # Platinum
    "XPD":  "global",       # Palladium
}


# ═════════════════════════════════════════════════════════════════════════════
# PUBLIC SERVICE CLASS
# ═════════════════════════════════════════════════════════════════════════════

class CurrencyService:
    """
    Production currency service — Universe Edition.
    Live rates · Multi-provider failover · 180+ currencies · No hardcoded values.
    Raises HTTPException(503) on total failure. Never returns stale/wrong data.
    """

    async def get_rates(self, base: str = "USD") -> Dict[str, float]:
        """Return all live rates relative to `base` currency."""
        usd_rates = await _get_usd_rates()
        if base.upper() == "USD":
            return usd_rates
        base_rate = usd_rates.get(base.upper())
        if not base_rate:
            raise HTTPException(400, f"Unsupported base currency: {base}")
        return {k: v / base_rate for k, v in usd_rates.items()}

    async def convert(self, amount: float, from_currency: str, to_currency: str) -> float:
        """Convert `amount` between any two currencies using live rates."""
        from_currency = from_currency.upper()
        to_currency   = to_currency.upper()
        if from_currency == to_currency:
            return amount
        usd_rates = await _get_usd_rates()
        from_rate = usd_rates.get(from_currency)
        to_rate   = usd_rates.get(to_currency)
        if not from_rate:
            raise HTTPException(400, f"Unknown currency: {from_currency}")
        if not to_rate:
            raise HTTPException(400, f"Unknown currency: {to_currency}")
        return round((amount / from_rate) * to_rate, 6)

    async def get_rate(self, from_currency: str, to_currency: str) -> float:
        """Return the live rate for 1 unit of from_currency → to_currency."""
        return await self.convert(1.0, from_currency, to_currency)

    async def format_amount(self, amount: float, currency: str, locale_str: str = "en") -> str:
        """Format a monetary amount with Babel locale-aware formatting."""
        try:
            from babel import numbers as babel_numbers
            from babel.core import Locale
            return babel_numbers.format_currency(
                amount, currency.upper(), locale=Locale.parse(locale_str)
            )
        except Exception as e:
            logger.warning(f"Babel format failed ({currency}/{locale_str}): {e}")
            symbol = await self.get_currency_symbol(currency)
            return f"{symbol}{amount:,.2f}"

    async def get_currency_symbol(self, currency: str) -> str:
        """Return the display symbol for any currency via Babel."""
        try:
            from babel import numbers as babel_numbers
            from babel.core import Locale
            return babel_numbers.get_currency_symbol(
                currency.upper(), locale=Locale.parse("en")
            )
        except Exception:
            return currency.upper()

    async def get_supported_currencies(self) -> Dict[str, str]:
        """
        Return {code: symbol} for every currency the live provider returns.
        Dynamic — matches whatever the current provider supports.
        """
        usd_rates = await _get_usd_rates()
        result = {}
        for code in usd_rates:
            result[code] = await self.get_currency_symbol(code)
        return result

    def get_region_for_currency(self, currency: str) -> str:
        """
        Map any world currency to a RiseUp region string.
        Covers all 180+ ISO 4217 currencies + major crypto.
        Returns 'global' for unknown currencies.
        """
        return CURRENCY_REGION_MAP.get(currency.upper(), "global")

    def get_currencies_for_region(self, region: str) -> list:
        """Return all currency codes that belong to a given region."""
        return [code for code, r in CURRENCY_REGION_MAP.items() if r == region]

    def get_all_regions(self) -> list:
        """Return all unique region strings in the map."""
        return sorted(set(CURRENCY_REGION_MAP.values()))

    async def get_cache_status(self) -> dict:
        """Health-check helper — returns cache state and provider info."""
        cached = _cache.get("USD")
        if cached:
            _, fetched_at = cached
            age = int((datetime.now(timezone.utc) - fetched_at).total_seconds())
            return {
                "cached":         True,
                "age_seconds":    age,
                "ttl_seconds":    CACHE_TTL_MINUTES * 60,
                "expires_in":     max(0, CACHE_TTL_MINUTES * 60 - age),
                "providers":      [p[0] for p in _PROVIDERS],
                "currencies_mapped": len(CURRENCY_REGION_MAP),
            }
        return {
            "cached":            False,
            "providers":         [p[0] for p in _PROVIDERS],
            "currencies_mapped": len(CURRENCY_REGION_MAP),
        }


# ── Singleton ─────────────────────────────────────────────────────────────────
currency_service = CurrencyService()

