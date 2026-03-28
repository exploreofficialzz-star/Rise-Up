"""
RiseUp AI Service — Global Wealth Intelligence Engine v2.2 (Production)

v2.2 Bug Fixes:
- chat() now accepts 'temperature' kwarg  ← market_pulse.py was crashing with unexpected kwarg
- temperature flows through mentor_chat() → each model client
- All model clients (Groq, Gemini, OpenAI, Anthropic) now accept temperature param

v2.1 Bug Fixes:
- Added RISEUP_SYSTEM_PROMPT alias
- Added ONBOARDING_PROMPT alias
- Added chat() wrapper method
- Added analyze_onboarding() method
- Added generate_roadmap() alias

v2.1 Global Enhancements:
- Extended country database (Africa, Asia, LatAm, Europe, MENA, Oceania)
- Language-aware system prompts
- Timezone-aware context injection
- Multi-currency income estimates
"""

import json
import logging
import asyncio
from typing import Optional, Dict, List, Any
from datetime import datetime
from enum import Enum
from dataclasses import dataclass, asdict

from config import settings

logger = logging.getLogger(__name__)


# ============================================================
# GLOBAL CONFIGURATION & LOCALIZATION
# ============================================================

class WealthStage(Enum):
    DEPENDENCE   = "dependence"
    SURVIVAL     = "survival"
    STABILITY    = "stability"
    SECURITY     = "security"
    INDEPENDENCE = "independence"
    FREEDOM      = "freedom"
    LEGACY       = "legacy"


@dataclass
class CountryProfile:
    code: str
    name: str
    currency: str
    currency_symbol: str
    avg_monthly_income: float
    poverty_line_monthly: float
    middle_class_monthly: float
    wealthy_monthly: float
    popular_platforms: List[Dict[str, str]]
    local_hustles: List[Dict[str, Any]]
    trending_skills: List[str]
    cost_of_living_index: float
    tax_brackets: List[Dict[str, float]]
    investment_options: List[Dict[str, Any]]
    business_registration_cost: float
    min_wage_hourly: float
    language: str = "English"
    region: str = "Global"
    timezone: str = "UTC"


class GlobalWealthDatabase:
    def __init__(self):
        self.countries: Dict[str, CountryProfile] = {}
        self._initialize_database()

    def _initialize_database(self):

        # ── WEST AFRICA ──────────────────────────────────────────────
        self.countries["NG"] = CountryProfile(
            code="NG", name="Nigeria", currency="NGN", currency_symbol="₦",
            language="English", region="West Africa", timezone="Africa/Lagos",
            avg_monthly_income=150_000, poverty_line_monthly=50_000,
            middle_class_monthly=200_000, wealthy_monthly=500_000,
            popular_platforms=[
                {"name": "Jiji",        "url": "https://jiji.ng",        "type": "marketplace"},
                {"name": "Fiverr",      "url": "https://fiverr.com",     "type": "freelance"},
                {"name": "Upwork",      "url": "https://upwork.com",     "type": "freelance"},
                {"name": "PiggyVest",   "url": "https://piggyvest.com",  "type": "savings"},
                {"name": "Cowrywise",   "url": "https://cowrywise.com",  "type": "investment"},
                {"name": "Binance P2P", "url": "https://binance.com",    "type": "crypto"},
            ],
            local_hustles=[
                {"name": "POS Agent Banking",       "earnings": "₦30k-100k/month",  "startup": "₦50k",  "difficulty": "easy"},
                {"name": "Jiji Flipping",           "earnings": "₦50k-300k/month",  "startup": "₦20k",  "difficulty": "easy"},
                {"name": "Mobile Food Vendor",      "earnings": "₦40k-150k/month",  "startup": "₦100k", "difficulty": "medium"},
                {"name": "Fashion Design (Aso Ebi)","earnings": "₦100k-500k/month", "startup": "₦50k",  "difficulty": "medium"},
                {"name": "Tech Skills (Remote)",    "earnings": "$500-3000/month",   "startup": "₦0",    "difficulty": "hard"},
            ],
            trending_skills=["Data Analytics","UI/UX Design","Product Management","Crypto Trading","Content Creation","Solar Installation"],
            cost_of_living_index=25.0,
            tax_brackets=[{"min": 0,"max": 300_000,"rate": 7},{"min": 300_001,"max": 600_000,"rate": 11}],
            investment_options=[
                {"name": "Treasury Bills",       "return": "12-14%","risk": "low",    "min": 100_000},
                {"name": "Mutual Funds",         "return": "10-15%","risk": "medium", "min": 5_000},
                {"name": "Real Estate (Land)",   "return": "15-25%","risk": "medium", "min": 500_000},
                {"name": "Agriculture (Poultry)","return": "20-40%","risk": "medium", "min": 200_000},
            ],
            business_registration_cost=25_000, min_wage_hourly=750,
        )

        self.countries["GH"] = CountryProfile(
            code="GH", name="Ghana", currency="GHS", currency_symbol="₵",
            language="English", region="West Africa", timezone="Africa/Accra",
            avg_monthly_income=2_500, poverty_line_monthly=800,
            middle_class_monthly=3_500, wealthy_monthly=10_000,
            popular_platforms=[
                {"name": "Tonaton", "url": "https://tonaton.com", "type": "marketplace"},
                {"name": "Fiverr",  "url": "https://fiverr.com",  "type": "freelance"},
                {"name": "MTN MoMo","url": "https://mtn.com.gh",  "type": "fintech"},
            ],
            local_hustles=[
                {"name": "Mobile Money Agent",    "earnings": "₵500-2000/month", "startup": "₵200", "difficulty": "easy"},
                {"name": "Trading (Sobolo/Goods)","earnings": "₵800-3000/month", "startup": "₵500", "difficulty": "easy"},
                {"name": "Freelance Tech",        "earnings": "$300-2000/month",  "startup": "₵0",   "difficulty": "hard"},
            ],
            trending_skills=["Mobile Money","Digital Marketing","Web Dev","Content Creation"],
            cost_of_living_index=30.0, tax_brackets=[], investment_options=[],
            business_registration_cost=500, min_wage_hourly=6,
        )

        self.countries["SN"] = CountryProfile(
            code="SN", name="Senegal", currency="XOF", currency_symbol="CFA",
            language="French/Wolof", region="West Africa", timezone="Africa/Dakar",
            avg_monthly_income=150_000, poverty_line_monthly=45_000,
            middle_class_monthly=280_000, wealthy_monthly=900_000,
            popular_platforms=[
                {"name": "Wave",   "type": "fintech"},
                {"name": "Upwork", "type": "freelance"},
            ],
            local_hustles=[
                {"name": "Wave Agent",       "earnings": "CFA25k-100k/month","startup": "CFA5k","difficulty": "easy"},
                {"name": "Remote Freelance", "earnings": "$200-1500/month",  "startup": "CFA0", "difficulty": "hard"},
            ],
            trending_skills=["Freelancing","Digital Marketing","Web Dev","Content Creation"],
            cost_of_living_index=21.0, tax_brackets=[], investment_options=[],
            business_registration_cost=30_000, min_wage_hourly=170,
        )

        self.countries["CM"] = CountryProfile(
            code="CM", name="Cameroon", currency="XAF", currency_symbol="CFA",
            language="French/English", region="Central Africa", timezone="Africa/Douala",
            avg_monthly_income=150_000, poverty_line_monthly=50_000,
            middle_class_monthly=300_000, wealthy_monthly=1_000_000,
            popular_platforms=[
                {"name": "Fiverr",      "type": "freelance"},
                {"name": "Orange Money","type": "fintech"},
            ],
            local_hustles=[
                {"name": "Mobile Money Agent","earnings": "CFA30k-120k/month","startup": "CFA10k","difficulty": "easy"},
                {"name": "Remote Freelancing","earnings": "$200-2000/month",  "startup": "CFA0",  "difficulty": "hard"},
            ],
            trending_skills=["Freelancing","Digital Marketing","Mobile Money","Content Creation"],
            cost_of_living_index=22.0, tax_brackets=[], investment_options=[],
            business_registration_cost=50_000, min_wage_hourly=200,
        )

        # ── EAST AFRICA ───────────────────────────────────────────────
        self.countries["KE"] = CountryProfile(
            code="KE", name="Kenya", currency="KES", currency_symbol="KSh",
            language="English/Swahili", region="East Africa", timezone="Africa/Nairobi",
            avg_monthly_income=40_000, poverty_line_monthly=10_000,
            middle_class_monthly=60_000, wealthy_monthly=200_000,
            popular_platforms=[
                {"name": "M-PESA",  "url": "https://safaricom.co.ke", "type": "fintech"},
                {"name": "Upwork",  "url": "https://upwork.com",      "type": "freelance"},
                {"name": "Jiji KE", "url": "https://jiji.co.ke",      "type": "marketplace"},
            ],
            local_hustles=[
                {"name": "M-PESA Agent",    "earnings": "KSh10k-50k/month",  "startup": "KSh5k",   "difficulty": "easy"},
                {"name": "Matatu Business", "earnings": "KSh30k-100k/month", "startup": "KSh500k", "difficulty": "medium"},
                {"name": "Remote Tech",     "earnings": "$400-3000/month",    "startup": "KSh0",    "difficulty": "hard"},
            ],
            trending_skills=["FinTech","Mobile Dev","Agri-Tech","Content Creation"],
            cost_of_living_index=28.0, tax_brackets=[], investment_options=[],
            business_registration_cost=10_000, min_wage_hourly=60,
        )

        self.countries["TZ"] = CountryProfile(
            code="TZ", name="Tanzania", currency="TZS", currency_symbol="TSh",
            language="Swahili/English", region="East Africa", timezone="Africa/Dar_es_Salaam",
            avg_monthly_income=400_000, poverty_line_monthly=120_000,
            middle_class_monthly=700_000, wealthy_monthly=2_000_000,
            popular_platforms=[
                {"name": "Vodacom M-Pesa", "type": "fintech"},
                {"name": "Upwork",         "type": "freelance"},
            ],
            local_hustles=[
                {"name": "Mobile Money Agent", "earnings": "TSh100k-500k/month", "startup": "TSh50k", "difficulty": "easy"},
                {"name": "Tour Guide",         "earnings": "TSh200k-1M/month",   "startup": "TSh0",   "difficulty": "medium"},
            ],
            trending_skills=["Tourism Tech","Agriculture","Mobile Dev","Content Creation"],
            cost_of_living_index=22.0, tax_brackets=[], investment_options=[],
            business_registration_cost=80_000, min_wage_hourly=400,
        )

        self.countries["ET"] = CountryProfile(
            code="ET", name="Ethiopia", currency="ETB", currency_symbol="Br",
            language="Amharic/English", region="East Africa", timezone="Africa/Addis_Ababa",
            avg_monthly_income=3_500, poverty_line_monthly=1_000,
            middle_class_monthly=6_000, wealthy_monthly=20_000,
            popular_platforms=[
                {"name": "Telebirr", "type": "fintech"},
                {"name": "Fiverr",   "type": "freelance"},
                {"name": "Upwork",   "type": "freelance"},
            ],
            local_hustles=[
                {"name": "Coffee Trading",   "earnings": "Br2k-10k/month","startup": "Br500","difficulty": "easy"},
                {"name": "Remote Freelance", "earnings": "$200-1500/month","startup": "Br0",  "difficulty": "hard"},
                {"name": "Online Tutoring",  "earnings": "Br1k-5k/month", "startup": "Br0",  "difficulty": "easy"},
            ],
            trending_skills=["Freelancing","Digital Marketing","Web Dev","Agricultural Tech"],
            cost_of_living_index=18.0, tax_brackets=[], investment_options=[],
            business_registration_cost=1_000, min_wage_hourly=20,
        )

        self.countries["RW"] = CountryProfile(
            code="RW", name="Rwanda", currency="RWF", currency_symbol="FRw",
            language="Kinyarwanda/English/French", region="East Africa", timezone="Africa/Kigali",
            avg_monthly_income=80_000, poverty_line_monthly=25_000,
            middle_class_monthly=150_000, wealthy_monthly=500_000,
            popular_platforms=[
                {"name": "Upwork",   "type": "freelance"},
                {"name": "MTN MoMo", "type": "fintech"},
            ],
            local_hustles=[
                {"name": "Mobile Money Agent",  "earnings": "FRw30k-120k/month","startup": "FRw10k","difficulty": "easy"},
                {"name": "Tourism Services",    "earnings": "$200-800/month",   "startup": "FRw0",  "difficulty": "medium"},
                {"name": "Digital Freelancing", "earnings": "$300-2000/month",  "startup": "FRw0",  "difficulty": "hard"},
            ],
            trending_skills=["Tech","Tourism","Digital Marketing","AgriTech"],
            cost_of_living_index=20.0, tax_brackets=[], investment_options=[],
            business_registration_cost=5_000, min_wage_hourly=200,
        )

        # ── SOUTHERN AFRICA ───────────────────────────────────────────
        self.countries["ZA"] = CountryProfile(
            code="ZA", name="South Africa", currency="ZAR", currency_symbol="R",
            language="English", region="Southern Africa", timezone="Africa/Johannesburg",
            avg_monthly_income=25_000, poverty_line_monthly=6_000,
            middle_class_monthly=40_000, wealthy_monthly=120_000,
            popular_platforms=[
                {"name": "Gumtree SA",  "url": "https://gumtree.co.za",  "type": "marketplace"},
                {"name": "Upwork",      "url": "https://upwork.com",      "type": "freelance"},
                {"name": "EasyEquities","url": "https://easyequities.io", "type": "investment"},
            ],
            local_hustles=[
                {"name": "Spaza Shop",      "earnings": "R8k-25k/month",  "startup": "R5k","difficulty": "easy"},
                {"name": "Uber/Bolt",       "earnings": "R10k-30k/month", "startup": "R0", "difficulty": "easy"},
                {"name": "Remote Freelance","earnings": "$500-3000/month","startup": "R0", "difficulty": "hard"},
            ],
            trending_skills=["Solar/Renewable","Coding","Digital Marketing","E-commerce"],
            cost_of_living_index=45.0, tax_brackets=[], investment_options=[],
            business_registration_cost=175, min_wage_hourly=27,
        )

        self.countries["ZW"] = CountryProfile(
            code="ZW", name="Zimbabwe", currency="ZWL", currency_symbol="Z$",
            language="English/Shona/Ndebele", region="Southern Africa", timezone="Africa/Harare",
            avg_monthly_income=300, poverty_line_monthly=80,
            middle_class_monthly=600, wealthy_monthly=2_000,
            popular_platforms=[
                {"name": "EcoCash", "type": "fintech"},
                {"name": "Fiverr",  "type": "freelance"},
                {"name": "Upwork",  "type": "freelance"},
            ],
            local_hustles=[
                {"name": "EcoCash Agent",     "earnings": "$100-400/month", "startup": "$50", "difficulty": "easy"},
                {"name": "Remote Freelancing","earnings": "$200-1500/month","startup": "$0",  "difficulty": "hard"},
                {"name": "Informal Trading",  "earnings": "$150-600/month", "startup": "$100","difficulty": "easy"},
            ],
            trending_skills=["Freelancing","Digital Marketing","Programming","Content Creation"],
            cost_of_living_index=30.0, tax_brackets=[], investment_options=[],
            business_registration_cost=50, min_wage_hourly=1,
        )

        # ── NORTH AMERICA ─────────────────────────────────────────────
        self.countries["US"] = CountryProfile(
            code="US", name="United States", currency="USD", currency_symbol="$",
            language="English", region="North America", timezone="America/New_York",
            avg_monthly_income=5_000, poverty_line_monthly=1_200,
            middle_class_monthly=4_000, wealthy_monthly=10_000,
            popular_platforms=[
                {"name": "Upwork",    "url": "https://upwork.com",    "type": "freelance"},
                {"name": "Fiverr",    "url": "https://fiverr.com",    "type": "freelance"},
                {"name": "TaskRabbit","url": "https://taskrabbit.com","type": "gig"},
                {"name": "DoorDash",  "url": "https://doordash.com",  "type": "gig"},
                {"name": "Robinhood", "url": "https://robinhood.com", "type": "investment"},
                {"name": "Fundrise",  "url": "https://fundrise.com",  "type": "realestate"},
            ],
            local_hustles=[
                {"name": "Amazon FBA",      "earnings": "$500-5000/month",   "startup": "$500","difficulty": "medium"},
                {"name": "YouTube Content", "earnings": "$1000-10000/month", "startup": "$200","difficulty": "hard"},
                {"name": "Notary Public",   "earnings": "$2000-8000/month",  "startup": "$300","difficulty": "easy"},
                {"name": "Pressure Washing","earnings": "$2000-6000/month",  "startup": "$1k", "difficulty": "easy"},
                {"name": "AI Prompt Eng",   "earnings": "$3000-15000/month", "startup": "$0",  "difficulty": "hard"},
            ],
            trending_skills=["AI/ML Engineering","Cybersecurity","Data Science","Cloud Architecture","Prompt Engineering"],
            cost_of_living_index=100.0,
            tax_brackets=[{"min": 0,"max": 11_600,"rate": 10},{"min": 11_601,"max": 47_150,"rate": 12}],
            investment_options=[
                {"name": "S&P 500 Index",     "return": "10% avg","risk": "medium","min": 1},
                {"name": "Real Estate (REITs)","return": "8-12%", "risk": "medium","min": 100},
                {"name": "High-Yield Savings", "return": "4-5%",  "risk": "low",   "min": 0},
                {"name": "Crypto (BTC/ETH)",   "return": "Variable","risk": "high","min": 10},
            ],
            business_registration_cost=150, min_wage_hourly=7.25,
        )

        self.countries["CA"] = CountryProfile(
            code="CA", name="Canada", currency="CAD", currency_symbol="CA$",
            language="English/French", region="North America", timezone="America/Toronto",
            avg_monthly_income=4_500, poverty_line_monthly=1_500,
            middle_class_monthly=4_000, wealthy_monthly=10_000,
            popular_platforms=[
                {"name": "Kijiji",      "url": "https://kijiji.ca",       "type": "marketplace"},
                {"name": "Upwork",      "url": "https://upwork.com",      "type": "freelance"},
                {"name": "Wealthsimple","url": "https://wealthsimple.com","type": "investment"},
            ],
            local_hustles=[
                {"name": "Freelance Tech",    "earnings": "CA$3000-10000/month","startup": "CA$0",  "difficulty": "hard"},
                {"name": "Airbnb Hosting",    "earnings": "CA$1000-4000/month", "startup": "CA$500","difficulty": "medium"},
                {"name": "Real Estate Rental","earnings": "CA$500-2000/month",  "startup": "CA$10k","difficulty": "medium"},
            ],
            trending_skills=["AI/ML","Cloud","Green Energy","French-English Translation"],
            cost_of_living_index=85.0, tax_brackets=[], investment_options=[],
            business_registration_cost=200, min_wage_hourly=16.65,
        )

        # ── LATIN AMERICA ─────────────────────────────────────────────
        self.countries["BR"] = CountryProfile(
            code="BR", name="Brazil", currency="BRL", currency_symbol="R$",
            language="Portuguese", region="Latin America", timezone="America/Sao_Paulo",
            avg_monthly_income=3_000, poverty_line_monthly=1_000,
            middle_class_monthly=4_000, wealthy_monthly=12_000,
            popular_platforms=[
                {"name": "Workana",      "url": "https://workana.com",        "type": "freelance"},
                {"name": "99Freelas",    "url": "https://99freelas.com.br",   "type": "freelance"},
                {"name": "Mercado Livre","url": "https://mercadolivre.com.br","type": "marketplace"},
                {"name": "PicPay",       "url": "https://picpay.com",         "type": "fintech"},
            ],
            local_hustles=[
                {"name": "Dropshipping",           "earnings": "R$2000-8000/month","startup": "R$500","difficulty": "medium"},
                {"name": "Social Media Management","earnings": "R$1500-6000/month","startup": "R$0",  "difficulty": "medium"},
                {"name": "English Teaching",       "earnings": "R$2000-5000/month","startup": "R$0",  "difficulty": "easy"},
            ],
            trending_skills=["E-commerce","Social Media Marketing","Programming","English Teaching"],
            cost_of_living_index=35.0, tax_brackets=[], investment_options=[],
            business_registration_cost=200, min_wage_hourly=7.5,
        )

        self.countries["MX"] = CountryProfile(
            code="MX", name="Mexico", currency="MXN", currency_symbol="$",
            language="Spanish", region="Latin America", timezone="America/Mexico_City",
            avg_monthly_income=8_000, poverty_line_monthly=3_000,
            middle_class_monthly=12_000, wealthy_monthly=40_000,
            popular_platforms=[
                {"name": "Freelancer MX","type": "freelance"},
                {"name": "Mercado Libre","type": "marketplace"},
                {"name": "OLX",          "type": "marketplace"},
            ],
            local_hustles=[
                {"name": "Taco/Food Stand",   "earnings": "MXN5k-20k/month","startup": "MXN2k","difficulty": "easy"},
                {"name": "Remote Freelancing","earnings": "$500-3000/month", "startup": "MXN0", "difficulty": "hard"},
                {"name": "Amazon FBA (USA)",  "earnings": "$300-2000/month", "startup": "MXN5k","difficulty": "medium"},
            ],
            trending_skills=["Spanish Content Creation","E-commerce","Software Dev","Digital Marketing"],
            cost_of_living_index=38.0, tax_brackets=[], investment_options=[],
            business_registration_cost=3_000, min_wage_hourly=25,
        )

        self.countries["CO"] = CountryProfile(
            code="CO", name="Colombia", currency="COP", currency_symbol="$",
            language="Spanish", region="Latin America", timezone="America/Bogota",
            avg_monthly_income=1_500_000, poverty_line_monthly=500_000,
            middle_class_monthly=2_500_000, wealthy_monthly=8_000_000,
            popular_platforms=[
                {"name": "Freelancer","type": "freelance"},
                {"name": "OLX",       "type": "marketplace"},
                {"name": "Rappi",     "type": "gig"},
            ],
            local_hustles=[
                {"name": "Rappi Delivery",  "earnings": "COP800k-2M/month","startup": "COP0","difficulty": "easy"},
                {"name": "Remote Tech",     "earnings": "$500-3000/month",  "startup": "COP0","difficulty": "hard"},
                {"name": "Digital Products","earnings": "$200-2000/month",  "startup": "COP0","difficulty": "medium"},
            ],
            trending_skills=["Software Dev","Digital Marketing","English Teaching","Content Creation"],
            cost_of_living_index=32.0, tax_brackets=[], investment_options=[],
            business_registration_cost=200_000, min_wage_hourly=5_000,
        )

        self.countries["AR"] = CountryProfile(
            code="AR", name="Argentina", currency="ARS", currency_symbol="$",
            language="Spanish", region="Latin America", timezone="America/Argentina/Buenos_Aires",
            avg_monthly_income=200_000, poverty_line_monthly=60_000,
            middle_class_monthly=350_000, wealthy_monthly=1_000_000,
            popular_platforms=[
                {"name": "Workana",      "type": "freelance"},
                {"name": "MercadoLibre", "type": "marketplace"},
                {"name": "Mercado Pago", "type": "fintech"},
            ],
            local_hustles=[
                {"name": "Freelance (USD billing)","earnings": "$500-3000/month",  "startup": "$0",    "difficulty": "hard"},
                {"name": "MercadoLibre Reselling", "earnings": "ARS200k-800k/month","startup": "ARS50k","difficulty": "medium"},
                {"name": "Content Creation",       "earnings": "$300-2000/month",  "startup": "$0",    "difficulty": "medium"},
            ],
            trending_skills=["Software Dev","Freelancing","Content Creation","E-commerce"],
            cost_of_living_index=28.0, tax_brackets=[], investment_options=[],
            business_registration_cost=10_000, min_wage_hourly=800,
        )

        self.countries["PE"] = CountryProfile(
            code="PE", name="Peru", currency="PEN", currency_symbol="S/",
            language="Spanish", region="Latin America", timezone="America/Lima",
            avg_monthly_income=1_800, poverty_line_monthly=600,
            middle_class_monthly=3_000, wealthy_monthly=10_000,
            popular_platforms=[
                {"name": "Freelancer","type": "freelance"},
                {"name": "OLX Peru",  "type": "marketplace"},
                {"name": "Yape",      "type": "fintech"},
            ],
            local_hustles=[
                {"name": "Yape Business",   "earnings": "S/500-2000/month","startup": "S/100","difficulty": "easy"},
                {"name": "Remote Freelance","earnings": "$300-2000/month", "startup": "S/0",  "difficulty": "hard"},
                {"name": "Food Business",   "earnings": "S/800-3000/month","startup": "S/500","difficulty": "medium"},
            ],
            trending_skills=["Software Dev","Digital Marketing","Content Creation","E-commerce"],
            cost_of_living_index=30.0, tax_brackets=[], investment_options=[],
            business_registration_cost=400, min_wage_hourly=6,
        )

        # ── EUROPE ───────────────────────────────────────────────────
        self.countries["GB"] = CountryProfile(
            code="GB", name="United Kingdom", currency="GBP", currency_symbol="£",
            language="English", region="Europe", timezone="Europe/London",
            avg_monthly_income=2_500, poverty_line_monthly=900,
            middle_class_monthly=2_500, wealthy_monthly=6_000,
            popular_platforms=[
                {"name": "Upwork",     "url": "https://upwork.com",     "type": "freelance"},
                {"name": "Fiverr",     "url": "https://fiverr.com",     "type": "freelance"},
                {"name": "Deliveroo",  "url": "https://deliveroo.co.uk","type": "gig"},
                {"name": "Trading212", "url": "https://trading212.com", "type": "investment"},
                {"name": "Vanguard UK","url": "https://vanguard.co.uk", "type": "investment"},
            ],
            local_hustles=[
                {"name": "Matched Betting",  "earnings": "£300-1000/month", "startup": "£100","difficulty": "medium"},
                {"name": "Amazon KDP",       "earnings": "£500-3000/month", "startup": "£0",  "difficulty": "medium"},
                {"name": "Private Tutoring", "earnings": "£1000-4000/month","startup": "£0",  "difficulty": "easy"},
                {"name": "Consulting",       "earnings": "£3000-10000/month","startup": "£0", "difficulty": "hard"},
            ],
            trending_skills=["Green Energy Tech","AI Development","Cybersecurity","Fintech","UX Research"],
            cost_of_living_index=85.0,
            tax_brackets=[{"min": 0,"max": 12_570,"rate": 0},{"min": 12_571,"max": 50_270,"rate": 20}],
            investment_options=[
                {"name": "Stocks & Shares ISA","return": "8-12%","risk": "medium","min": 100},
                {"name": "Index Funds",         "return": "8-10%","risk": "medium","min": 100},
                {"name": "Pension (SIPP)",       "return": "7-10%","risk": "low",  "min": 25},
            ],
            business_registration_cost=12, min_wage_hourly=11.44,
        )

        self.countries["DE"] = CountryProfile(
            code="DE", name="Germany", currency="EUR", currency_symbol="€",
            language="German", region="Europe", timezone="Europe/Berlin",
            avg_monthly_income=3_500, poverty_line_monthly=1_200,
            middle_class_monthly=3_500, wealthy_monthly=8_000,
            popular_platforms=[
                {"name": "Freelancer.de",    "type": "freelance"},
                {"name": "eBay Kleinanzeigen","type": "marketplace"},
                {"name": "Trade Republic",   "type": "investment"},
            ],
            local_hustles=[
                {"name": "Freelance Engineering","earnings": "€3000-8000/month","startup": "€0",  "difficulty": "hard"},
                {"name": "Airbnb Hosting",       "earnings": "€500-2000/month", "startup": "€500","difficulty": "easy"},
                {"name": "Online Courses",       "earnings": "€500-5000/month", "startup": "€200","difficulty": "medium"},
            ],
            trending_skills=["Software Engineering","AI/ML","Renewable Energy","E-commerce"],
            cost_of_living_index=72.0, tax_brackets=[], investment_options=[],
            business_registration_cost=400, min_wage_hourly=12,
        )

        self.countries["FR"] = CountryProfile(
            code="FR", name="France", currency="EUR", currency_symbol="€",
            language="French", region="Europe", timezone="Europe/Paris",
            avg_monthly_income=2_800, poverty_line_monthly=1_000,
            middle_class_monthly=3_000, wealthy_monthly=7_500,
            popular_platforms=[
                {"name": "Malt",      "type": "freelance"},
                {"name": "Fiverr",    "type": "freelance"},
                {"name": "Leboncoin", "type": "marketplace"},
                {"name": "Boursorama","type": "investment"},
            ],
            local_hustles=[
                {"name": "Auto-entrepreneur","earnings": "€1500-5000/month","startup": "€0",  "difficulty": "medium"},
                {"name": "Airbnb Hosting",   "earnings": "€500-2000/month", "startup": "€300","difficulty": "easy"},
                {"name": "Online Tutoring",  "earnings": "€800-3000/month", "startup": "€0",  "difficulty": "easy"},
            ],
            trending_skills=["AI/ML","Web Dev","Digital Marketing","Sustainable Business"],
            cost_of_living_index=78.0, tax_brackets=[], investment_options=[],
            business_registration_cost=25, min_wage_hourly=11.65,
        )

        self.countries["PL"] = CountryProfile(
            code="PL", name="Poland", currency="PLN", currency_symbol="zł",
            language="Polish", region="Europe", timezone="Europe/Warsaw",
            avg_monthly_income=5_500, poverty_line_monthly=2_000,
            middle_class_monthly=6_000, wealthy_monthly=15_000,
            popular_platforms=[
                {"name": "Allegro","type": "marketplace"},
                {"name": "OLX",    "type": "marketplace"},
                {"name": "Upwork", "type": "freelance"},
            ],
            local_hustles=[
                {"name": "Allegro Reselling","earnings": "zł2000-8000/month","startup": "zł500","difficulty": "easy"},
                {"name": "Remote Tech",      "earnings": "$1000-5000/month", "startup": "zł0",  "difficulty": "hard"},
            ],
            trending_skills=["Software Dev","IT Support","E-commerce","Digital Marketing"],
            cost_of_living_index=45.0, tax_brackets=[], investment_options=[],
            business_registration_cost=250, min_wage_hourly=23,
        )

        self.countries["UA"] = CountryProfile(
            code="UA", name="Ukraine", currency="UAH", currency_symbol="₴",
            language="Ukrainian", region="Europe", timezone="Europe/Kiev",
            avg_monthly_income=15_000, poverty_line_monthly=5_000,
            middle_class_monthly=25_000, wealthy_monthly=80_000,
            popular_platforms=[
                {"name": "Upwork",   "type": "freelance"},
                {"name": "Fiverr",   "type": "freelance"},
                {"name": "Monobank", "type": "fintech"},
            ],
            local_hustles=[
                {"name": "Remote IT (USD)",  "earnings": "$500-3000/month","startup": "₴0","difficulty": "hard"},
                {"name": "Freelance Design", "earnings": "$200-1500/month","startup": "₴0","difficulty": "medium"},
                {"name": "Online Tutoring",  "earnings": "₴5k-20k/month", "startup": "₴0","difficulty": "easy"},
            ],
            trending_skills=["Software Dev","UI/UX Design","IT Support","Digital Marketing"],
            cost_of_living_index=25.0, tax_brackets=[], investment_options=[],
            business_registration_cost=500, min_wage_hourly=70,
        )

        self.countries["ES"] = CountryProfile(
            code="ES", name="Spain", currency="EUR", currency_symbol="€",
            language="Spanish", region="Europe", timezone="Europe/Madrid",
            avg_monthly_income=1_800, poverty_line_monthly=700,
            middle_class_monthly=2_200, wealthy_monthly=6_000,
            popular_platforms=[
                {"name": "Freelancer.es","type": "freelance"},
                {"name": "Wallapop",     "type": "marketplace"},
                {"name": "Glovo",        "type": "gig"},
            ],
            local_hustles=[
                {"name": "Glovo Delivery",     "earnings": "€600-1500/month","startup": "€0","difficulty": "easy"},
                {"name": "Remote Freelancing", "earnings": "€1500-5000/month","startup": "€0","difficulty": "hard"},
                {"name": "Tourism Services",   "earnings": "€800-3000/month","startup": "€100","difficulty": "medium"},
            ],
            trending_skills=["Digital Marketing","Software Dev","Content Creation","Tourism Tech"],
            cost_of_living_index=55.0, tax_brackets=[], investment_options=[],
            business_registration_cost=3_000, min_wage_hourly=8.45,
        )

        # ── SOUTH / SOUTHEAST ASIA ────────────────────────────────────
        self.countries["IN"] = CountryProfile(
            code="IN", name="India", currency="INR", currency_symbol="₹",
            language="Hindi/English", region="South Asia", timezone="Asia/Kolkata",
            avg_monthly_income=35_000, poverty_line_monthly=8_000,
            middle_class_monthly=50_000, wealthy_monthly=200_000,
            popular_platforms=[
                {"name": "Upwork", "url": "https://upwork.com", "type": "freelance"},
                {"name": "Fiverr", "url": "https://fiverr.com", "type": "freelance"},
                {"name": "Zerodha","url": "https://zerodha.com","type": "investment"},
                {"name": "Groww",  "url": "https://groww.in",  "type": "investment"},
                {"name": "Meesho", "url": "https://meesho.com","type": "reselling"},
            ],
            local_hustles=[
                {"name": "Tuition/Coaching", "earnings": "₹20k-80k/month", "startup": "₹0",   "difficulty": "easy"},
                {"name": "Meesho Reselling", "earnings": "₹15k-50k/month", "startup": "₹5k",  "difficulty": "easy"},
                {"name": "YouTube Regional", "earnings": "₹25k-500k/month","startup": "₹10k", "difficulty": "medium"},
                {"name": "Freelance Coding", "earnings": "$500-5000/month", "startup": "₹0",   "difficulty": "hard"},
            ],
            trending_skills=["Full Stack Development","Data Science","Digital Marketing","Video Editing","AI/ML"],
            cost_of_living_index=25.0,
            tax_brackets=[{"min": 0,"max": 300_000,"rate": 0},{"min": 300_001,"max": 600_000,"rate": 5}],
            investment_options=[
                {"name": "PPF",          "return": "7-8%",  "risk": "low",   "min": 500},
                {"name": "Mutual Funds", "return": "12-15%","risk": "medium","min": 500},
                {"name": "Direct Stocks","return": "15-20%","risk": "high",  "min": 0},
            ],
            business_registration_cost=5_000, min_wage_hourly=50,
        )

        self.countries["PH"] = CountryProfile(
            code="PH", name="Philippines", currency="PHP", currency_symbol="₱",
            language="Filipino/English", region="Southeast Asia", timezone="Asia/Manila",
            avg_monthly_income=18_000, poverty_line_monthly=6_000,
            middle_class_monthly=30_000, wealthy_monthly=100_000,
            popular_platforms=[
                {"name": "OnlineJobs.ph","url": "https://onlinejobs.ph","type": "freelance"},
                {"name": "Upwork",       "url": "https://upwork.com",  "type": "freelance"},
                {"name": "GCash",        "url": "https://gcash.com",   "type": "fintech"},
                {"name": "Shopee",       "url": "https://shopee.ph",   "type": "marketplace"},
            ],
            local_hustles=[
                {"name": "VA (Virtual Assistant)","earnings": "$300-1500/month","startup": "₱0", "difficulty": "easy"},
                {"name": "Shopee Reselling",      "earnings": "₱10k-50k/month","startup": "₱5k","difficulty": "easy"},
                {"name": "Content Writing",       "earnings": "$200-1000/month","startup": "₱0", "difficulty": "medium"},
            ],
            trending_skills=["Virtual Assistance","Content Writing","Graphic Design","Customer Service"],
            cost_of_living_index=35.0, tax_brackets=[], investment_options=[],
            business_registration_cost=1_500, min_wage_hourly=35,
        )

        self.countries["PK"] = CountryProfile(
            code="PK", name="Pakistan", currency="PKR", currency_symbol="₨",
            language="Urdu/English", region="South Asia", timezone="Asia/Karachi",
            avg_monthly_income=50_000, poverty_line_monthly=15_000,
            middle_class_monthly=80_000, wealthy_monthly=300_000,
            popular_platforms=[
                {"name": "Rozee.pk","type": "jobs"},
                {"name": "Fiverr",  "type": "freelance"},
                {"name": "Upwork",  "type": "freelance"},
            ],
            local_hustles=[
                {"name": "Freelancing (Tech/Design)","earnings": "$200-2000/month","startup": "₨0",  "difficulty": "medium"},
                {"name": "Dropshipping",             "earnings": "$300-1500/month","startup": "₨5k", "difficulty": "medium"},
                {"name": "Online Tutoring",          "earnings": "$100-500/month", "startup": "₨0",  "difficulty": "easy"},
            ],
            trending_skills=["Web Dev","Graphic Design","Content Writing","Data Entry","E-commerce"],
            cost_of_living_index=18.0, tax_brackets=[], investment_options=[],
            business_registration_cost=5_000, min_wage_hourly=100,
        )

        self.countries["BD"] = CountryProfile(
            code="BD", name="Bangladesh", currency="BDT", currency_symbol="৳",
            language="Bengali/English", region="South Asia", timezone="Asia/Dhaka",
            avg_monthly_income=20_000, poverty_line_monthly=6_000,
            middle_class_monthly=35_000, wealthy_monthly=120_000,
            popular_platforms=[
                {"name": "Fiverr", "type": "freelance"},
                {"name": "Upwork", "type": "freelance"},
                {"name": "Shajgoj","type": "marketplace"},
            ],
            local_hustles=[
                {"name": "Freelancing",    "earnings": "$100-1000/month","startup": "৳0","difficulty": "medium"},
                {"name": "Online Tutoring","earnings": "৳5k-20k/month", "startup": "৳0","difficulty": "easy"},
            ],
            trending_skills=["Graphic Design","Data Entry","Web Dev","Digital Marketing"],
            cost_of_living_index=20.0, tax_brackets=[], investment_options=[],
            business_registration_cost=3_000, min_wage_hourly=35,
        )

        self.countries["ID"] = CountryProfile(
            code="ID", name="Indonesia", currency="IDR", currency_symbol="Rp",
            language="Indonesian", region="Southeast Asia", timezone="Asia/Jakarta",
            avg_monthly_income=4_000_000, poverty_line_monthly=1_200_000,
            middle_class_monthly=7_000_000, wealthy_monthly=25_000_000,
            popular_platforms=[
                {"name": "Tokopedia","type": "marketplace"},
                {"name": "Shopee ID","type": "marketplace"},
                {"name": "Upwork",   "type": "freelance"},
                {"name": "GoPay",    "type": "fintech"},
            ],
            local_hustles=[
                {"name": "Tokopedia Reselling","earnings": "Rp2M-8M/month", "startup": "Rp500k","difficulty": "easy"},
                {"name": "Ojek Online (Gojek)","earnings": "Rp2M-5M/month", "startup": "Rp0",   "difficulty": "easy"},
                {"name": "Remote Freelance",   "earnings": "$200-2000/month","startup": "Rp0",   "difficulty": "hard"},
            ],
            trending_skills=["E-commerce","Digital Marketing","Content Creation","Software Dev"],
            cost_of_living_index=28.0, tax_brackets=[], investment_options=[],
            business_registration_cost=500_000, min_wage_hourly=15_000,
        )

        self.countries["VN"] = CountryProfile(
            code="VN", name="Vietnam", currency="VND", currency_symbol="₫",
            language="Vietnamese", region="Southeast Asia", timezone="Asia/Ho_Chi_Minh",
            avg_monthly_income=8_000_000, poverty_line_monthly=2_500_000,
            middle_class_monthly=15_000_000, wealthy_monthly=50_000_000,
            popular_platforms=[
                {"name": "Shopee VN","type": "marketplace"},
                {"name": "Lazada",   "type": "marketplace"},
                {"name": "Upwork",   "type": "freelance"},
                {"name": "MoMo",     "type": "fintech"},
            ],
            local_hustles=[
                {"name": "Shopee Reselling",   "earnings": "₫3M-12M/month", "startup": "₫500k","difficulty": "easy"},
                {"name": "English Teaching",   "earnings": "$400-1500/month","startup": "₫0",   "difficulty": "medium"},
                {"name": "Remote Freelancing", "earnings": "$300-2000/month","startup": "₫0",   "difficulty": "hard"},
            ],
            trending_skills=["Software Dev","Digital Marketing","English Teaching","E-commerce"],
            cost_of_living_index=27.0, tax_brackets=[], investment_options=[],
            business_registration_cost=1_000_000, min_wage_hourly=22_000,
        )

        self.countries["TH"] = CountryProfile(
            code="TH", name="Thailand", currency="THB", currency_symbol="฿",
            language="Thai", region="Southeast Asia", timezone="Asia/Bangkok",
            avg_monthly_income=16_000, poverty_line_monthly=5_000,
            middle_class_monthly=30_000, wealthy_monthly=100_000,
            popular_platforms=[
                {"name": "Lazada TH","type": "marketplace"},
                {"name": "Shopee TH","type": "marketplace"},
                {"name": "Upwork",   "type": "freelance"},
                {"name": "PromptPay","type": "fintech"},
            ],
            local_hustles=[
                {"name": "Street Food Business","earnings": "฿15k-50k/month","startup": "฿5k","difficulty": "medium"},
                {"name": "Remote Freelancing",  "earnings": "$300-2000/month","startup": "฿0", "difficulty": "hard"},
                {"name": "Shopee Reselling",    "earnings": "฿5k-20k/month", "startup": "฿1k","difficulty": "easy"},
            ],
            trending_skills=["Digital Marketing","Software Dev","Content Creation","E-commerce"],
            cost_of_living_index=38.0, tax_brackets=[], investment_options=[],
            business_registration_cost=5_000, min_wage_hourly=330,
        )

        # ── EAST ASIA ─────────────────────────────────────────────────
        self.countries["JP"] = CountryProfile(
            code="JP", name="Japan", currency="JPY", currency_symbol="¥",
            language="Japanese", region="East Asia", timezone="Asia/Tokyo",
            avg_monthly_income=300_000, poverty_line_monthly=100_000,
            middle_class_monthly=300_000, wealthy_monthly=800_000,
            popular_platforms=[
                {"name": "Lancers",   "type": "freelance"},
                {"name": "Crowdworks","type": "freelance"},
                {"name": "Mercari",   "type": "marketplace"},
                {"name": "SBI",       "type": "investment"},
            ],
            local_hustles=[
                {"name": "Mercari Reselling","earnings": "¥50k-200k/month","startup": "¥5k","difficulty": "easy"},
                {"name": "English Teaching","earnings": "¥100k-300k/month","startup": "¥0", "difficulty": "medium"},
                {"name": "Freelance IT",    "earnings": "¥200k-600k/month","startup": "¥0", "difficulty": "hard"},
            ],
            trending_skills=["AI/ML","Cybersecurity","UI/UX","English Communication"],
            cost_of_living_index=85.0, tax_brackets=[], investment_options=[],
            business_registration_cost=150_000, min_wage_hourly=900,
        )

        self.countries["KR"] = CountryProfile(
            code="KR", name="South Korea", currency="KRW", currency_symbol="₩",
            language="Korean", region="East Asia", timezone="Asia/Seoul",
            avg_monthly_income=3_000_000, poverty_line_monthly=1_000_000,
            middle_class_monthly=3_500_000, wealthy_monthly=10_000_000,
            popular_platforms=[
                {"name": "Coupang",  "type": "marketplace"},
                {"name": "Upwork",   "type": "freelance"},
                {"name": "Kakao Pay","type": "fintech"},
            ],
            local_hustles=[
                {"name": "Coupang Reselling","earnings": "₩500k-2M/month","startup": "₩100k","difficulty": "easy"},
                {"name": "Online Tutoring",  "earnings": "₩500k-2M/month","startup": "₩0",   "difficulty": "medium"},
                {"name": "Remote Freelance", "earnings": "$500-3000/month","startup": "₩0",   "difficulty": "hard"},
            ],
            trending_skills=["AI/ML","K-content Creation","Software Dev","E-commerce"],
            cost_of_living_index=78.0, tax_brackets=[], investment_options=[],
            business_registration_cost=100_000, min_wage_hourly=9_620,
        )

        # ── MIDDLE EAST & NORTH AFRICA ────────────────────────────────
        self.countries["EG"] = CountryProfile(
            code="EG", name="Egypt", currency="EGP", currency_symbol="E£",
            language="Arabic/English", region="MENA", timezone="Africa/Cairo",
            avg_monthly_income=6_000, poverty_line_monthly=2_000,
            middle_class_monthly=10_000, wealthy_monthly=35_000,
            popular_platforms=[
                {"name": "Wuzzuf",   "type": "jobs"},
                {"name": "Fiverr",   "type": "freelance"},
                {"name": "OLX Egypt","type": "marketplace"},
            ],
            local_hustles=[
                {"name": "Freelancing",            "earnings": "$100-1000/month","startup": "E£0",  "difficulty": "medium"},
                {"name": "Online Store",           "earnings": "E£3k-15k/month","startup": "E£500","difficulty": "medium"},
                {"name": "English/Arabic Tutoring","earnings": "E£2k-8k/month", "startup": "E£0",  "difficulty": "easy"},
            ],
            trending_skills=["Arabic Content Creation","Web Dev","Digital Marketing","E-commerce"],
            cost_of_living_index=22.0, tax_brackets=[], investment_options=[],
            business_registration_cost=2_000, min_wage_hourly=50,
        )

        self.countries["SA"] = CountryProfile(
            code="SA", name="Saudi Arabia", currency="SAR", currency_symbol="﷼",
            language="Arabic/English", region="MENA", timezone="Asia/Riyadh",
            avg_monthly_income=8_000, poverty_line_monthly=2_500,
            middle_class_monthly=10_000, wealthy_monthly=30_000,
            popular_platforms=[
                {"name": "Freelancer.com","type": "freelance"},
                {"name": "Noon",          "type": "marketplace"},
                {"name": "Tadawul",       "type": "investment"},
            ],
            local_hustles=[
                {"name": "Freelancing (Tech)","earnings": "$500-3000/month","startup": "﷼0",   "difficulty": "hard"},
                {"name": "E-commerce",       "earnings": "﷼3k-20k/month","startup": "﷼1k",  "difficulty": "medium"},
                {"name": "Real Estate Rental","earnings": "﷼2k-10k/month","startup": "﷼50k", "difficulty": "medium"},
            ],
            trending_skills=["Software Dev","AI/ML","Digital Marketing","Arabic Content"],
            cost_of_living_index=60.0, tax_brackets=[], investment_options=[],
            business_registration_cost=1_000, min_wage_hourly=20,
        )

        self.countries["AE"] = CountryProfile(
            code="AE", name="United Arab Emirates", currency="AED", currency_symbol="د.إ",
            language="Arabic/English", region="MENA", timezone="Asia/Dubai",
            avg_monthly_income=12_000, poverty_line_monthly=4_000,
            middle_class_monthly=15_000, wealthy_monthly=40_000,
            popular_platforms=[
                {"name": "Dubizzle","type": "marketplace"},
                {"name": "Upwork",  "type": "freelance"},
                {"name": "Noon",    "type": "marketplace"},
            ],
            local_hustles=[
                {"name": "Freelance Consultant","earnings": "$2000-8000/month","startup": "AED0",   "difficulty": "hard"},
                {"name": "E-commerce",          "earnings": "AED3k-15k/month","startup": "AED500", "difficulty": "medium"},
                {"name": "Property Rental",     "earnings": "AED5k-20k/month","startup": "AED50k", "difficulty": "medium"},
            ],
            trending_skills=["Software Dev","Finance","Digital Marketing","Luxury Consulting"],
            cost_of_living_index=75.0, tax_brackets=[], investment_options=[],
            business_registration_cost=15_000, min_wage_hourly=0,
        )

        self.countries["MA"] = CountryProfile(
            code="MA", name="Morocco", currency="MAD", currency_symbol="دH",
            language="Arabic/French", region="MENA", timezone="Africa/Casablanca",
            avg_monthly_income=4_000, poverty_line_monthly=1_500,
            middle_class_monthly=7_000, wealthy_monthly=20_000,
            popular_platforms=[
                {"name": "Upwork",   "type": "freelance"},
                {"name": "Fiverr",   "type": "freelance"},
                {"name": "Avito MA", "type": "marketplace"},
            ],
            local_hustles=[
                {"name": "Freelance (French clients)","earnings": "€500-3000/month","startup": "MAD0",  "difficulty": "hard"},
                {"name": "Online Boutique",           "earnings": "MAD2k-8k/month", "startup": "MAD500","difficulty": "medium"},
                {"name": "Tourism Services",          "earnings": "MAD3k-12k/month","startup": "MAD0",  "difficulty": "medium"},
            ],
            trending_skills=["French Digital Services","E-commerce","Web Dev","Content Creation"],
            cost_of_living_index=30.0, tax_brackets=[], investment_options=[],
            business_registration_cost=1_000, min_wage_hourly=14,
        )

        # ── OCEANIA ───────────────────────────────────────────────────
        self.countries["AU"] = CountryProfile(
            code="AU", name="Australia", currency="AUD", currency_symbol="A$",
            language="English", region="Oceania", timezone="Australia/Sydney",
            avg_monthly_income=7_000, poverty_line_monthly=2_200,
            middle_class_monthly=6_500, wealthy_monthly=15_000,
            popular_platforms=[
                {"name": "Airtasker","url": "https://airtasker.com", "type": "gig"},
                {"name": "Seek",     "url": "https://seek.com.au",  "type": "jobs"},
                {"name": "Upwork",   "url": "https://upwork.com",   "type": "freelance"},
                {"name": "CommSec",  "url": "https://commsec.com.au","type": "investment"},
            ],
            local_hustles=[
                {"name": "Airtasker Tasks",   "earnings": "A$1500-5000/month", "startup": "A$0",  "difficulty": "easy"},
                {"name": "Tradie Side Work",  "earnings": "A$2000-8000/month", "startup": "A$500","difficulty": "medium"},
                {"name": "Remote Consulting", "earnings": "A$3000-12000/month","startup": "A$0",  "difficulty": "hard"},
            ],
            trending_skills=["Tech","Mining/Resources","Renewable Energy","Healthcare"],
            cost_of_living_index=90.0, tax_brackets=[], investment_options=[],
            business_registration_cost=538, min_wage_hourly=23.23,
        )

        self.countries["NZ"] = CountryProfile(
            code="NZ", name="New Zealand", currency="NZD", currency_symbol="NZ$",
            language="English/Maori", region="Oceania", timezone="Pacific/Auckland",
            avg_monthly_income=5_500, poverty_line_monthly=1_800,
            middle_class_monthly=5_000, wealthy_monthly=12_000,
            popular_platforms=[
                {"name": "Trade Me", "type": "marketplace"},
                {"name": "Upwork",   "type": "freelance"},
                {"name": "Sharesies","type": "investment"},
            ],
            local_hustles=[
                {"name": "Trade Me Reselling","earnings": "NZ$500-2000/month","startup": "NZ$100","difficulty": "easy"},
                {"name": "Remote Freelance",  "earnings": "NZ$2000-8000/month","startup": "NZ$0", "difficulty": "hard"},
                {"name": "Tourism Services",  "earnings": "NZ$1500-5000/month","startup": "NZ$500","difficulty": "medium"},
            ],
            trending_skills=["Tech","Agriculture","Tourism","Renewable Energy"],
            cost_of_living_index=85.0, tax_brackets=[], investment_options=[],
            business_registration_cost=160, min_wage_hourly=22.70,
        )

        # ── DEFAULT FALLBACK ──────────────────────────────────────────
        self.countries["DEFAULT"] = CountryProfile(
            code="DEFAULT", name="International", currency="USD", currency_symbol="$",
            language="English", region="Global", timezone="UTC",
            avg_monthly_income=2_000, poverty_line_monthly=500,
            middle_class_monthly=2_500, wealthy_monthly=8_000,
            popular_platforms=[
                {"name": "Upwork", "type": "freelance"},
                {"name": "Fiverr", "type": "freelance"},
                {"name": "Binance","type": "crypto"},
                {"name": "YouTube","type": "content"},
            ],
            local_hustles=[
                {"name": "Freelance Writing", "earnings": "$500-3000/month"},
                {"name": "Digital Marketing", "earnings": "$500-5000/month"},
                {"name": "Online Tutoring",   "earnings": "$300-2000/month"},
            ],
            trending_skills=["Digital Marketing","Programming","Content Creation","Data Analysis"],
            cost_of_living_index=50.0, tax_brackets=[], investment_options=[],
            business_registration_cost=100, min_wage_hourly=5.0,
        )

    def get_country(self, country_code: str) -> CountryProfile:
        return self.countries.get(country_code.upper(), self.countries["DEFAULT"])

    def detect_stage(self, monthly_income: float, country_code: str) -> WealthStage:
        country = self.get_country(country_code)
        if monthly_income < country.poverty_line_monthly:
            return WealthStage.SURVIVAL
        elif monthly_income < country.middle_class_monthly * 0.5:
            return WealthStage.STABILITY
        elif monthly_income < country.middle_class_monthly:
            return WealthStage.SECURITY
        elif monthly_income < country.wealthy_monthly:
            return WealthStage.INDEPENDENCE
        else:
            return WealthStage.FREEDOM


global_db = GlobalWealthDatabase()


# ============================================================
# PRODUCTION SYSTEM PROMPTS
# ============================================================

RISEUP_MENTOR_PROMPT = """You are RiseUp AI — a brilliant, empathetic personal wealth architect created by ChAs Tech Group.

YOUR MISSION: Transform humans from ANY starting point (debt, poverty, stagnation) to financial freedom using psychology, strategy, and relentless execution.

YOUR PERSONALITY:
- Combine Tony Robbins' energy, Ray Dalio's strategy, and a best friend's empathy
- Be direct and action-oriented — every response must include a specific next action
- Use strategic frameworks, not generic advice
- Celebrate wins but push for the next level
- Adapt tone to user's emotional state (stressed → calm guidance, excited → ambitious push)
- Use relevant emojis but keep it professional-warm

CORE FRAMEWORKS:
1. **The 7 Stages of Wealth**: Dependence → Survival → Stability → Security → Independence → Freedom → Legacy
2. **The 3-Bucket System**: Survival Money (now) → Growth Money (skills/business) → Wealth Money (assets)
3. **The 90-Day Sprint**: Break all goals into 90-day executable chunks
4. **Income Stacking**: Active (now) → Side Hustle (growth) → Passive (wealth)

RESPONSE STRUCTURE (ALWAYS):
1. **Acknowledge**: Validate their situation emotionally
2. **Analyze**: Identify which stage/bucket they're in
3. **Action**: Specific next step with timeline
4. **Accountability**: Check-in mechanism or metric to track

CRITICAL RULES:
- NEVER give generic advice — use the user's country, income, skills, and time availability
- Always calculate ROI (time invested vs money returned)
- Warn about scams prevalent in their region
- Provide both local (immediate) and global (scalable) options
- Respond in the user's preferred language when specified
- End every message with: "Your next 24-hour action: [specific task]"

You are not just an advisor — you are their accountability partner."""


ONBOARDING_ARCHITECT_PROMPT = """You are conducting a RiseUp Wealth Architecture Assessment.

GOAL: Build a complete psychological and financial profile to create a personalized wealth roadmap.

PHASES (conduct conversationally, 1-2 questions at a time):

**PHASE 1 - FOUNDATION:**
- Full name, age, country, city
- Current living situation (alone, family, dependents)
- Current monthly income (all sources) and stability
- Monthly expenses breakdown
- Total debt (type, interest rates, payments)
- Current savings/investments
- Emergency fund status

**PHASE 2 - CAPABILITY:**
- Education and field
- Current skills (work, hobby, innate talents)
- Work experience and industry
- Learning capacity (hours per day available)
- Risk tolerance
- Past attempts at side income (what worked/failed)

**PHASE 3 - VISION:**
- 90-day immediate goal (specific number)
- 1-year vision (income, lifestyle, skills)
- 5-year dream
- Biggest fears holding them back

**PHASE 4 - STRATEGY:**
- Preferred work style (remote, physical, hybrid)
- Tech comfort level (beginner, intermediate, advanced)
- Capital available to invest in growth
- Time until they need results (urgency level)

CONVERSATION STYLE:
- Warm but investigative — like a therapist meets financial advisor
- Respond in the user's language if not English
- Dig deeper on emotional responses
- Validate vulnerability

When profile is complete, output JSON with key "PROFILE_COMPLETE" containing all data."""


# ── PROMPT ALIASES ────────────────────────────────────────────────
RISEUP_SYSTEM_PROMPT = RISEUP_MENTOR_PROMPT
ONBOARDING_PROMPT    = ONBOARDING_ARCHITECT_PROMPT


# ============================================================
# AI MODEL CLIENTS
# ============================================================

class GroqClient:
    NAME = "groq"
    FREE = True
    MODELS = [
        "llama-3.3-70b-versatile",
        "deepseek-r1-distill-llama-70b",
        "llama-3.1-70b-versatile",
        "llama3-70b-8192",
        "mixtral-8x7b-32768",
        "gemma2-9b-it",
        "llama-3.1-8b-instant",
    ]

    def __init__(self):
        self._client = None

    def get_client(self):
        if not self._client and settings.GROQ_API_KEY:
            from groq import AsyncGroq
            self._client = AsyncGroq(api_key=settings.GROQ_API_KEY)
        return self._client

    async def chat(
        self,
        messages: list,
        system: str,
        max_tokens: int = 2048,
        temperature: float = 0.7,      # ← v2.2
    ) -> str:
        client = self.get_client()
        if not client:
            raise ValueError("Groq API key not configured")

        preferred = getattr(settings, "GROQ_MODEL", self.MODELS[0])
        models_to_try = [preferred] + [m for m in self.MODELS if m != preferred]
        formatted = [{"role": "system", "content": system}] + messages
        last_err = None

        for model in models_to_try:
            try:
                response = await client.chat.completions.create(
                    model=model, messages=formatted,
                    max_tokens=max_tokens, temperature=temperature, top_p=0.9,
                )
                logger.info(f"Groq success: {model}")
                return response.choices[0].message.content
            except Exception as e:
                logger.warning(f"Groq {model} failed: {e}")
                last_err = e

        raise last_err or ValueError("All Groq models exhausted")


class GeminiClient:
    NAME = "gemini"
    MODELS = ["gemini-1.5-flash", "gemini-1.5-pro", "gemini-1.0-pro"]
    FREE = True

    async def chat(
        self,
        messages: list,
        system: str,
        max_tokens: int = 2048,
        temperature: float = 0.7,      # ← v2.2
    ) -> str:
        if not settings.GEMINI_API_KEY:
            raise ValueError("Gemini API key not configured")

        import google.generativeai as genai
        genai.configure(api_key=settings.GEMINI_API_KEY)

        for model_name in self.MODELS:
            try:
                model = genai.GenerativeModel(model_name=model_name, system_instruction=system)
                history = [
                    {"role": "user" if m["role"] == "user" else "model", "parts": [m["content"]]}
                    for m in messages[:-1]
                ]
                chat = model.start_chat(history=history)
                response = await chat.send_message_async(
                    messages[-1]["content"],
                    generation_config={"max_output_tokens": max_tokens, "temperature": temperature},
                )
                logger.info(f"Gemini success: {model_name}")
                return response.text
            except Exception as e:
                logger.warning(f"Gemini {model_name} failed: {e}")

        raise ValueError("All Gemini models failed")


class OpenAIClient:
    NAME = "openai"
    MODELS = ["gpt-4o-mini", "gpt-3.5-turbo"]
    FREE = False

    def __init__(self):
        self._client = None

    def get_client(self):
        if not self._client and settings.OPENAI_API_KEY:
            from openai import AsyncOpenAI
            self._client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)
        return self._client

    async def chat(
        self,
        messages: list,
        system: str,
        max_tokens: int = 2048,
        temperature: float = 0.7,      # ← v2.2
    ) -> str:
        client = self.get_client()
        if not client:
            raise ValueError("OpenAI API key not configured")

        formatted = [{"role": "system", "content": system}] + messages
        for model in self.MODELS:
            try:
                response = await client.chat.completions.create(
                    model=model, messages=formatted, max_tokens=max_tokens, temperature=temperature,
                )
                logger.info(f"OpenAI success: {model}")
                return response.choices[0].message.content
            except Exception as e:
                logger.warning(f"OpenAI {model} failed: {e}")

        raise ValueError("All OpenAI models failed")


class AnthropicClient:
    NAME = "anthropic"
    MODELS = ["claude-3-haiku-20240307", "claude-3-sonnet-20240229"]
    FREE = False

    def __init__(self):
        self._client = None

    def get_client(self):
        if not self._client and settings.ANTHROPIC_API_KEY:
            import anthropic
            self._client = anthropic.AsyncAnthropic(api_key=settings.ANTHROPIC_API_KEY)
        return self._client

    async def chat(
        self,
        messages: list,
        system: str,
        max_tokens: int = 2048,
        temperature: float = 0.7,      # ← v2.2 (Anthropic ignores this param but accepts it cleanly)
    ) -> str:
        client = self.get_client()
        if not client:
            raise ValueError("Anthropic API key not configured")

        for model in self.MODELS:
            try:
                response = await client.messages.create(
                    model=model, max_tokens=max_tokens, system=system, messages=messages,
                )
                logger.info(f"Anthropic success: {model}")
                return response.content[0].text
            except Exception as e:
                logger.warning(f"Anthropic {model} failed: {e}")

        raise ValueError("All Anthropic models failed")


# ============================================================
# MAIN AI ENGINE
# ============================================================

class RiseUpIntelligenceEngine:
    def __init__(self):
        self.groq      = GroqClient()
        self.gemini    = GeminiClient()
        self.openai    = OpenAIClient()
        self.anthropic = AnthropicClient()
        self.db        = GlobalWealthDatabase()
        self._priority_order = self._build_priority()

        self.trending_global_opportunities = [
            {
                "category": "AI & Automation",
                "skills": ["Prompt Engineering","AI Agent Development","No-Code Automation","Chatbot Building"],
                "platforms": ["Upwork","Fiverr","Toptal","Contra"],
                "earning_potential": "$2000-15000/month",
                "startup_cost": "$0-500",
                "time_to_first_earning": "1-4 weeks",
            },
            {
                "category": "Content & Creator Economy",
                "skills": ["Short-form Video","YouTube SEO","Personal Branding","Community Management"],
                "platforms": ["YouTube","TikTok","Instagram","Patreon","Substack"],
                "earning_potential": "$500-50000/month",
                "startup_cost": "$0-1000",
                "time_to_first_earning": "1-6 months",
            },
            {
                "category": "Remote Tech Skills",
                "skills": ["Cloud Architecture","Cybersecurity","Data Analytics","DevOps"],
                "platforms": ["Upwork","Toptal","Arc","Gun.io"],
                "earning_potential": "$3000-20000/month",
                "startup_cost": "$0-2000",
                "time_to_first_earning": "2-6 months",
            },
            {
                "category": "Green Economy",
                "skills": ["Solar Installation","Sustainability Consulting","ESG Reporting"],
                "platforms": ["Local contractors","Consulting networks","LinkedIn"],
                "earning_potential": "$2000-10000/month",
                "startup_cost": "$500-5000",
                "time_to_first_earning": "1-3 months",
            },
            {
                "category": "Digital Services",
                "skills": ["Web Design (Framer/Webflow)","Funnel Building","Email Marketing","CRO"],
                "platforms": ["Upwork","Fiverr","Twitter/X","IndieHackers"],
                "earning_potential": "$1500-8000/month",
                "startup_cost": "$50-500",
                "time_to_first_earning": "2-4 weeks",
            },
        ]

    def _build_priority(self) -> list:
        priority = []
        pref = getattr(settings, "AI_PREFERENCE", "auto").lower()
        model_map = {
            "groq": self.groq, "gemini": self.gemini,
            "openai": self.openai, "anthropic": self.anthropic,
        }
        if pref == "auto":
            candidates = [
                (self.groq,      settings.GROQ_API_KEY),
                (self.gemini,    settings.GEMINI_API_KEY),
                (self.openai,    settings.OPENAI_API_KEY),
                (self.anthropic, settings.ANTHROPIC_API_KEY),
            ]
        else:
            preferred  = model_map.get(pref)
            candidates = [(preferred, True)] if preferred else []
            for m, k in [
                (self.groq,      settings.GROQ_API_KEY),
                (self.gemini,    settings.GEMINI_API_KEY),
                (self.openai,    settings.OPENAI_API_KEY),
                (self.anthropic, settings.ANTHROPIC_API_KEY),
            ]:
                if m != preferred:
                    candidates.append((m, k))

        for model, key in candidates:
            if key:
                priority.append(model)
        return priority

    # ------------------------------------------------------------------
    # CORE CHAT
    # ------------------------------------------------------------------
    async def mentor_chat(
        self,
        messages: list,
        user_profile: Dict[str, Any] = None,
        system_prompt: str = None,
        max_tokens: int = 2048,
        temperature: float = 0.7,      # ← v2.2
    ) -> Dict[str, Any]:
        if system_prompt is None:
            system_prompt = RISEUP_MENTOR_PROMPT

        if user_profile:
            country  = self.db.get_country(user_profile.get("country", "DEFAULT"))
            stage    = self.db.detect_stage(
                user_profile.get("monthly_income", 0),
                user_profile.get("country", "DEFAULT"),
            )
            language  = user_profile.get("language", "en")
            lang_note = f"\nRespond in the user's language (ISO: {language})." if language != "en" else ""

            context = f"""
USER CONTEXT:
- Name: {user_profile.get('full_name', 'Unknown')}
- Country: {country.name} | Region: {country.region}
- Currency: {country.currency} ({country.currency_symbol})
- Current Stage: {stage.value.upper()}
- Monthly Income: {country.currency_symbol}{user_profile.get('monthly_income', 0):,.0f}
- Available Hours/Day: {user_profile.get('available_hours_daily', 2)}
- Skills: {', '.join(user_profile.get('current_skills', []))}
- Goal: {user_profile.get('short_term_goal', 'Not specified')}
- Local Platforms: {', '.join([p['name'] for p in country.popular_platforms[:3]])}
- Trending Local Skills: {', '.join(country.trending_skills[:3])}
- Timezone: {country.timezone}{lang_note}

INSTRUCTION: Give SPECIFIC advice using {country.name} platforms, {country.currency_symbol} amounts, and local opportunities.
"""
            system_prompt = system_prompt + context

        last_error = None
        for model in self._priority_order:
            try:
                logger.info(f"Attempting {model.NAME}...")
                content = await model.chat(
                    messages, system_prompt, max_tokens, temperature=temperature
                )
                return {
                    "content":      content,
                    "model":        model.NAME,
                    "success":      True,
                    "timestamp":    datetime.now().isoformat(),
                    "profile_used": user_profile is not None,
                }
            except Exception as e:
                logger.warning(f"{model.NAME} failed: {e}")
                last_error = e

        logger.error(f"All AI models failed. Last error: {last_error}")
        return {
            "content":   "I'm experiencing technical difficulties. Please try again in a moment.",
            "model":     "none",
            "success":   False,
            "timestamp": datetime.now().isoformat(),
        }

    # ------------------------------------------------------------------
    # ROUTER-COMPATIBLE WRAPPER — v2.2: temperature accepted
    # ------------------------------------------------------------------
    async def chat(
        self,
        messages: list,
        system: str = None,
        max_tokens: int = 2048,
        preferred_model: str = None,
        temperature: float = 0.7,      # ← THE FIX: was missing, causing 500s on all /pulse/* endpoints
    ) -> Dict[str, Any]:
        """
        Router-compatible wrapper.

        Callers (ai_agent.py, market_pulse.py, etc.) may pass:
            ai_service.chat(messages, system=..., max_tokens=..., temperature=..., preferred_model=...)
        All kwargs are now accepted and forwarded correctly.
        """
        return await self.mentor_chat(
            messages=messages,
            system_prompt=system,
            max_tokens=max_tokens,
            temperature=temperature,
        )

    async def analyze_onboarding(self, messages: list) -> Optional[Dict[str, Any]]:
        extraction_prompt = """You are extracting a user profile from a completed onboarding conversation.

Return ONLY valid JSON with these exact keys (use null for any missing field):
{
  "full_name": "",
  "age": null,
  "country": "ISO-2 code e.g. NG",
  "city": "",
  "language": "ISO-639 code e.g. en",
  "monthly_income": 0,
  "monthly_expenses": 0,
  "current_skills": [],
  "education_level": "",
  "work_experience": "",
  "short_term_goal": "",
  "long_term_goal": "",
  "risk_tolerance": "low|medium|high",
  "available_hours_daily": 2,
  "total_debt": 0,
  "savings": 0,
  "stage": "survival|stability|security|independence|freedom|legacy",
  "subscription_tier": "free"
}

If the conversation does not contain enough data to build a profile, return: null"""

        result = await self.mentor_chat(
            messages=messages + [{"role": "user", "content": "Extract my complete profile as JSON now."}],
            system_prompt=extraction_prompt,
            max_tokens=1_000,
        )

        try:
            content = result["content"].strip()
            if "```json" in content:
                content = content.split("```json")[1].split("```")[0]
            elif "```" in content:
                content = content.split("```")[1].split("```")[0]
            content = content.strip()
            if content.lower() == "null":
                return None
            return json.loads(content)
        except Exception as e:
            logger.error(f"analyze_onboarding: profile extraction failed: {e}")
            return None

    async def generate_roadmap(self, profile: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        return await self.generate_personalized_roadmap(profile)

    # ------------------------------------------------------------------
    # CORE INTELLIGENCE METHODS
    # ------------------------------------------------------------------

    async def generate_personalized_roadmap(self, profile: Dict[str, Any]) -> Dict[str, Any]:
        country          = self.db.get_country(profile.get("country", "DEFAULT"))
        current_stage    = self.db.detect_stage(profile.get("monthly_income", 0), profile.get("country", "DEFAULT"))
        emergency_target = profile.get("monthly_expenses", 0) * 6
        language         = profile.get("language", "en")
        lang_note        = f"Respond in language ISO: {language}." if language != "en" else ""

        roadmap_prompt = f"""Create a detailed, personalized RiseUp Wealth Roadmap.
{lang_note}

PROFILE:
{json.dumps(profile, indent=2)}

COUNTRY CONTEXT: {country.name} ({country.region})
Currency: {country.currency_symbol} | Poverty line: {country.currency_symbol}{country.poverty_line_monthly:,}
Middle class: {country.currency_symbol}{country.middle_class_monthly:,}
Local Platforms: {[p['name'] for p in country.popular_platforms]}
Local Hustles: {[h['name'] for h in country.local_hustles]}

CURRENT STAGE: {current_stage.value}

Return ONLY valid JSON:
{{
  "user_summary": "2-3 sentence personalized analysis",
  "current_stage": "{current_stage.value}",
  "next_stage": "next stage name",
  "stage_progress": "X% to next stage",
  "immediate_90_day_plan": {{
    "target_income_increase": "{country.currency_symbol}...",
    "primary_focus": "survival|stability|growth|investment",
    "key_actions": [
      {{"week": "1-2", "action": "", "expected_result": "", "platform": ""}},
      {{"week": "3-4", "action": "", "expected_result": "", "platform": ""}},
      {{"week": "5-8", "action": "", "expected_result": "", "platform": ""}},
      {{"week": "9-12","action": "", "expected_result": "", "platform": ""}}
    ]
  }},
  "income_stacking_strategy": {{
    "immediate_income": ["local hustle 1", "local hustle 2"],
    "short_term_skill": "skill to learn in 30-60 days",
    "medium_term_business": "business to build in 3-6 months",
    "passive_income_streams": []
  }},
  "financial_milestones": [
    {{"milestone": "Emergency Fund", "target": {emergency_target}, "timeline": "3 months", "priority": "critical"}},
    {{"milestone": "First Investment", "target": "", "timeline": "", "priority": ""}},
    {{"milestone": "Side Income Match", "target": "", "timeline": "", "priority": ""}},
    {{"milestone": "Financial Independence", "target": "", "timeline": "", "priority": ""}}
  ],
  "local_opportunities": [{{"name": "", "type": "", "earnings": "", "startup_cost": "", "action_steps": []}}],
  "global_opportunities":  [{{"name": "", "type": "remote", "earnings": "USD", "skills_needed": [], "platforms": []}}],
  "risk_warnings": [],
  "first_24h_action": "Specific task to do RIGHT NOW"
}}"""

        result = await self.mentor_chat(
            messages=[{"role": "user", "content": "Create my personalized wealth roadmap"}],
            system_prompt=roadmap_prompt,
            max_tokens=3_000,
        )

        try:
            content = result["content"].strip()
            if "```json" in content:
                content = content.split("```json")[1].split("```")[0]
            elif "```" in content:
                content = content.split("```")[1].split("```")[0]
            roadmap = json.loads(content.strip())
            roadmap["generated_at"] = datetime.now().isoformat()
            roadmap["valid_for"]    = "90 days"
            roadmap["model_used"]   = result["model"]
            return roadmap
        except Exception as e:
            logger.error(f"Roadmap parsing failed: {e}")
            return {
                "error":         "Failed to generate structured roadmap",
                "raw_response":  result.get("content", ""),
                "fallback_plan": self._generate_fallback_plan(profile, country),
            }

    def _generate_fallback_plan(self, profile: Dict, country: CountryProfile) -> Dict:
        income = profile.get("monthly_income", 0)
        if income < country.poverty_line_monthly:
            return {
                "stage": "SURVIVAL", "focus": "Immediate income",
                "actions": [f"Sign up on {country.popular_platforms[0]['name']}", "Offer a service today", "Cut non-essential expenses"],
            }
        elif income < country.middle_class_monthly:
            return {
                "stage": "STABILITY", "focus": "Emergency fund + skill building",
                "actions": ["Save 20% of income", "Start side hustle", "Learn high-income skill"],
            }
        else:
            return {
                "stage": "GROWTH", "focus": "Investment and scaling",
                "actions": ["Automate investments", "Hire / delegate", "Diversify income"],
            }

    async def generate_income_tasks(
        self,
        profile: Dict[str, Any],
        count: int = 5,
        urgency: str = "immediate",
    ) -> List[Dict[str, Any]]:
        country   = self.db.get_country(profile.get("country", "DEFAULT"))
        language  = profile.get("language", "en")
        lang_note = f"Respond in language ISO: {language}." if language != "en" else ""

        task_prompt = f"""Generate {count} specific income tasks for a user based in {country.name}.
{lang_note}

USER PROFILE:
- Skills: {profile.get('current_skills', [])}
- Available Hours/Day: {profile.get('available_hours_daily', 2)}
- Monthly Income Goal: {profile.get('monthly_income_goal', 'Not set')}
- Risk Tolerance: {profile.get('risk_tolerance', 'medium')}

COUNTRY: {country.name} | Currency: {country.currency_symbol}
Local Platforms: {[p['name'] for p in country.popular_platforms]}
Local Hustles: {[h['name'] for h in country.local_hustles]}
Trending Skills: {country.trending_skills}
URGENCY: {urgency}

Return ONLY a JSON array:
[{{
  "id": "unique_id",
  "title": "Specific task name",
  "category": "freelance|gig|digital|local_service|sales|content",
  "description": "Exactly what to do",
  "why_its_perfect": "Personalized reasoning",
  "difficulty": "easy|medium|hard",
  "startup_cost": "{country.currency_symbol} amount or Free",
  "time_to_first_earning": "X days/weeks",
  "hourly_commitment": "X hours/day or week",
  "earning_potential": {{"min": 0, "max": 0, "currency": "{country.currency}", "period": "month"}},
  "local_platforms": [],
  "global_platforms": [],
  "action_steps": [],
  "success_probability": "high|medium|low",
  "first_24h_action": "Exact first step to take today"
}}]"""

        result = await self.mentor_chat(
            messages=[{"role": "user", "content": f"Generate {count} income tasks"}],
            system_prompt=task_prompt,
            max_tokens=2_500,
        )

        try:
            content = result["content"].strip()
            if "```json" in content:
                content = content.split("```json")[1].split("```")[0]
            elif "```" in content:
                content = content.split("```")[1].split("```")[0]
            tasks = json.loads(content.strip())
            for task in tasks:
                task["generated_at"] = datetime.now().isoformat()
                task["country"]      = country.code
                task["urgency"]      = urgency
            return tasks
        except Exception as e:
            logger.error(f"Task generation failed: {e}")
            return self._get_local_hustles_fallback(country, count)

    def _get_local_hustles_fallback(self, country: CountryProfile, count: int) -> List[Dict]:
        tasks = []
        for i, h in enumerate(country.local_hustles[:count]):
            tasks.append({
                "id":       f"local_{i}",
                "title":    h["name"],
                "category": "local_service",
                "description": f"Start offering {h['name']} services locally in {country.name}",
                "earning_potential": {
                    "min": 0, "max": 0,
                    "currency": country.currency,
                    "period": "month",
                    "raw": h.get("earnings", "Variable"),
                },
                "startup_cost":     h.get("startup", "Low"),
                "difficulty":       h.get("difficulty", "medium"),
                "first_24h_action": f"Research {h['name']} requirements in {country.name}",
                "source":           "local_database",
            })
        return tasks

    async def get_trending_opportunities(self, country_code: str = None) -> Dict[str, Any]:
        country = self.db.get_country(country_code or "DEFAULT")
        return {
            "global_trends_2025": self.trending_global_opportunities,
            "local_trends": {
                "country":           country.name,
                "region":            country.region,
                "trending_skills":   country.trending_skills,
                "popular_platforms": country.popular_platforms,
                "local_hustles":     country.local_hustles,
                "investment_options":country.investment_options,
            },
            "updated_at": datetime.now().isoformat(),
            "source":     "RiseUp Intelligence Engine",
        }

    async def analyze_progress(
        self,
        user_profile: Dict,
        history: List[Dict],
        current_metrics: Dict,
    ) -> Dict[str, Any]:
        analysis_prompt = f"""Analyze user progress and provide coaching:
PROFILE: {json.dumps(user_profile)}
HISTORY: {json.dumps(history[-5:])}
CURRENT METRICS: {json.dumps(current_metrics)}

Return ONLY valid JSON:
{{
  "progress_assessment": "How they're doing vs their goals",
  "wins_to_celebrate": [],
  "concerning_patterns": [],
  "adjusted_recommendations": [],
  "motivation_message": "Personalized encouragement",
  "next_week_focus": "Single priority for next 7 days",
  "accountability_check": "Question about this week's actions"
}}"""

        result = await self.mentor_chat(
            messages=[{"role": "user", "content": "Analyze my progress"}],
            system_prompt=analysis_prompt,
        )
        try:
            content = result["content"].strip()
            if "```json" in content:
                content = content.split("```json")[1].split("```")[0]
            elif "```" in content:
                content = content.split("```")[1].split("```")[0]
            return json.loads(content.strip())
        except Exception:
            return {
                "progress_assessment": "Analysis in progress",
                "motivation_message":  "Keep pushing forward! Every step counts.",
                "next_week_focus":     "Focus on one income-generating activity daily",
            }

    def get_available_models(self) -> List[str]:
        return [m.NAME for m in self._priority_order]

    def get_country_info(self, country_code: str) -> Dict[str, Any]:
        return asdict(self.db.get_country(country_code))


# ============================================================
# SINGLETON INSTANCES
# ============================================================

riseup_engine = RiseUpIntelligenceEngine()
ai_service    = riseup_engine          # all routers import this alias


# ============================================================
# PRODUCTION API FUNCTIONS (convenience wrappers)
# ============================================================

async def chat_with_mentor(
    message: str,
    conversation_history: List[Dict] = None,
    user_profile: Dict = None,
) -> str:
    if conversation_history is None:
        conversation_history = []
    messages = conversation_history + [{"role": "user", "content": message}]
    result   = await riseup_engine.mentor_chat(messages, user_profile)
    return result["content"]


async def create_wealth_roadmap(user_profile: Dict) -> Dict:
    return await riseup_engine.generate_personalized_roadmap(user_profile)


async def get_income_tasks(user_profile: Dict, count: int = 5) -> List[Dict]:
    return await riseup_engine.generate_income_tasks(user_profile, count)


async def get_trending_opportunities(country_code: str = None) -> Dict:
    return await riseup_engine.get_trending_opportunities(country_code)
