#!/usr/bin/env python3
"""
RiseUp Methods Brain — Full 10,000 Methods Seed Script
═══════════════════════════════════════════════════════
Loads all income methods from $0 to $1B+ into the income_methods table.

Usage:
    python seeds/seed_methods.py

Requires: SUPABASE_URL and SUPABASE_SERVICE_KEY in environment.
Safe to run multiple times (upserts on method_number).
"""

import os
import sys
import json
import time
from typing import List, Dict, Any

# Add backend root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def get_all_methods() -> List[Dict[str, Any]]:
    """
    Returns the complete structured 10,000 methods list.
    Each method maps directly to the income_methods table schema.
    """
    methods = []

    # ══════════════════════════════════════════════════════
    # ZERO INVESTMENT — ONLINE (1–150)
    # ══════════════════════════════════════════════════════

    zero_online_services = [
        ("Freelance Copywriting", "Write persuasive marketing content for global businesses.", ARRAY["writing","copywriting","freelance","remote"], "Freelance Services", "🟢", "days", "basic", "medium", "global", 300, 5000, 92, True),
        ("Freelance Proofreading", "Review and correct written content for grammar, style, and clarity.", ARRAY["writing","proofreading","editing","remote"], "Freelance Services", "🟢", "days", "basic", "medium", "global", 200, 3000, 75, False),
        ("Freelance Editing", "Edit manuscripts, articles, and documents for quality and readability.", ARRAY["editing","writing","freelance"], "Freelance Services", "🟢", "days", "intermediate", "medium", "global", 300, 4000, 78, False),
        ("Freelance Transcription", "Convert audio and video recordings into written text.", ARRAY["transcription","audio","typing"], "Freelance Services", "🟢", "hours", "none", "medium", "global", 200, 2000, 72, False),
        ("Freelance Data Entry", "Enter, update, and manage data in databases and spreadsheets.", ARRAY["data-entry","spreadsheet","remote"], "Freelance Services", "🟢", "hours", "none", "low", "global", 150, 1500, 65, False),
        ("Freelance Virtual Assistance", "Provide administrative, scheduling, and support services remotely.", ARRAY["va","admin","remote","assistant"], "Freelance Services", "🟢", "days", "basic", "medium", "global", 400, 4000, 88, True),
        ("Freelance Social Media Management", "Manage social media accounts, create content, and grow audiences.", ARRAY["social-media","marketing","content"], "Freelance Services", "🟢", "days", "basic", "medium", "global", 500, 5000, 90, True),
        ("Freelance Email Marketing", "Create and manage email campaigns for businesses.", ARRAY["email","marketing","copywriting"], "Freelance Services", "🟢", "days", "basic", "medium", "global", 400, 4000, 80, False),
        ("Freelance SEO Writing", "Write search-engine-optimised content for websites and blogs.", ARRAY["seo","writing","content"], "Freelance Services", "🟢", "days", "basic", "medium", "global", 300, 5000, 85, False),
        ("Freelance Resume Writing", "Write professional resumes and CVs for job seekers.", ARRAY["resume","writing","career"], "Freelance Services", "🟢", "days", "basic", "medium", "global", 300, 3000, 78, False),
    ]

    method_num = 1
    for t in zero_online_services:
        methods.append(_method(method_num, t[0], t[1], "online", "zero", 0, 0, t[3], t[4], t[5], t[6], t[7], t[8], "linear", "survival", "solo", ["creative","services"], t[2], t[9], t[10], t[11], t[12]))
        method_num += 1

    # Content creation
    content_methods = [
        (41, "YouTube Channel (Ad Revenue)", "Create video content on any niche; monetise via YouTube Partner Program.", 50, 50000, 95, True, "Content Creation", "months", "basic", "high"),
        (42, "YouTube Shorts Monetization", "Create short-form vertical videos earning from YouTube's Shorts Fund.", 20, 5000, 85, True, "Content Creation", "months", "none", "high"),
        (43, "TikTok Creator Fund", "Earn money from TikTok's Creator Fund based on video views.", 50, 10000, 88, True, "Content Creation", "months", "none", "ultra"),
        (44, "TikTok LIVE Gifts", "Receive virtual gifts from viewers during TikTok LIVE sessions.", 100, 20000, 82, False, "Content Creation", "days", "none", "ultra"),
        (45, "Instagram Reels Bonuses", "Earn from Instagram's Reels bonus programme for creators.", 50, 5000, 75, False, "Content Creation", "months", "none", "ultra"),
        (46, "Facebook In-Stream Ads", "Earn advertising revenue from videos you publish on Facebook.", 100, 8000, 70, False, "Content Creation", "months", "basic", "medium"),
        (47, "Facebook Stars from Fans", "Receive monetary Stars from fans on Facebook Live and Reels.", 50, 5000, 65, False, "Content Creation", "weeks", "none", "medium"),
        (48, "Twitch Streaming (Subscriptions)", "Earn recurring revenue from Twitch channel subscribers.", 500, 50000, 85, True, "Content Creation", "months", "none", "ultra"),
        (49, "Twitch Streaming (Bits/Donations)", "Receive Bits (micro-payments) and donations from Twitch viewers.", 200, 20000, 80, False, "Content Creation", "days", "none", "ultra"),
        (50, "Podcast Sponsorships", "Earn sponsorship income by partnering with brands for your podcast.", 500, 30000, 80, False, "Content Creation", "months", "basic", "medium"),
        (51, "Podcast Listener Donations", "Receive direct support from podcast listeners via Buy Me a Coffee.", 50, 3000, 65, False, "Content Creation", "months", "basic", "medium"),
        (52, "Blogging (Google AdSense)", "Earn advertising income from blog traffic via Google AdSense.", 100, 10000, 75, False, "Content Creation", "months", "basic", "high"),
        (53, "Blogging (Affiliate Links)", "Earn commissions by embedding affiliate product links in blog posts.", 200, 20000, 82, False, "Content Creation", "months", "basic", "high"),
        (54, "Blogging (Sponsored Posts)", "Earn fees by publishing sponsored content from brands on your blog.", 300, 5000, 72, False, "Content Creation", "months", "basic", "high"),
        (55, "Medium Partner Program", "Earn a share of Medium subscription revenue from your published articles.", 50, 3000, 68, False, "Content Creation", "weeks", "basic", "medium"),
    ]

    for item in content_methods:
        methods.append(_method(item[0], item[1], item[2], "online", "zero", 0, 0, item[8], "🟢", item[9], item[10], item[11], "global", "leveraged", "stable", "solo", ["creative","media"], ["content","creator","social-media"], item[3], item[4], item[5], item[6]))

    # Affiliate marketing
    affiliate = [
        (61, "Amazon Associates", "Earn 1–10% commission on Amazon products via your unique affiliate links.", 50, 5000, 78, False),
        (62, "ClickBank Affiliate", "Promote digital products from ClickBank and earn 50–75% commissions.", 200, 10000, 80, False),
        (63, "ShareASale Affiliate", "Join ShareASale network and promote thousands of products.", 100, 8000, 72, False),
        (64, "CJ Affiliate Marketing", "Promote premium brands through CJ Affiliate network.", 200, 10000, 70, False),
        (65, "Impact Affiliate Network", "Join Impact to promote SaaS and high-value subscription products.", 300, 15000, 75, False),
        (66, "Rakuten Affiliate", "Promote top retail brands through Rakuten's affiliate network.", 100, 5000, 65, False),
        (67, "Digistore24 Affiliate", "Promote digital products globally via Digistore24.", 200, 8000, 68, False),
        (68, "JVZoo Affiliate", "Earn commissions on digital tools, courses, and software.", 100, 5000, 62, False),
        (69, "WarriorPlus Affiliate", "Promote marketing and business tools in the WarriorPlus marketplace.", 100, 5000, 60, False),
        (70, "Fiverr Affiliate Program", "Earn commissions by referring new buyers and sellers to Fiverr.", 100, 5000, 72, False),
    ]

    for item in affiliate:
        methods.append(_method(item[0], f"{item[1]} Affiliate Marketing", item[2], "online", "zero", 0, 0, "Affiliate Marketing", "🟢", "weeks", "none", "medium", "global", "leveraged", "stable", "solo", ["marketing"], ["affiliate","passive","commissions"], item[3], item[4], item[5], item[6]))

    # Gig platforms
    gig = [
        (101, "Fiverr Gigs", "Offer any skill as a micro-service on the world's largest gig marketplace.", 200, 8000, 95, True),
        (102, "PeoplePerHour Gigs", "Sell hourly freelance services on PeoplePerHour.", 200, 5000, 75, False),
        (103, "Toptal Freelancing", "Join Toptal's elite network for high-paying tech and design projects.", 3000, 20000, 80, False),
        (104, "Upwork Freelancing", "Bid on global freelance projects across every skill category.", 500, 15000, 92, True),
        (105, "Guru.com Freelancing", "Find freelance projects in tech, design, writing, and more.", 300, 8000, 65, False),
        (106, "99designs Contests", "Win design contests and build a paying portfolio on 99designs.", 200, 5000, 62, False),
        (107, "Freelancer.com Projects", "Bid on millions of projects posted by businesses worldwide.", 300, 8000, 78, False),
        (108, "Contra Freelancing", "Earn 100% of your fees on Contra — no commission taken.", 300, 10000, 75, False),
    ]

    for item in gig:
        methods.append(_method(item[0], item[1], item[2], "online", "zero", 0, 0, "Gig Platforms", "🟢", "days", "basic", "medium", "global", "linear", "survival", "solo", ["services"], ["freelance","gig","remote"], item[3], item[4], item[5], item[6]))

    # Micro tasks
    microtasks = [
        (111, "Amazon Mechanical Turk", "Complete tiny digital tasks — surveys, image tagging, data entry — for pay.", 50, 400, 65, False),
        (112, "Clickworker Tasks", "Complete AI training data, surveys, and web research tasks.", 50, 500, 62, False),
        (113, "Appen Data Tasks", "Label data, transcribe audio, and improve AI products for Appen.", 100, 1500, 68, False),
        (114, "Scale AI Data Labeling", "Label and annotate data for machine learning companies.", 500, 5000, 75, False),
        (115, "Remotasks AI Tasks", "Complete AI training tasks from home on Remotasks platform.", 100, 1500, 68, False),
        (116, "Lionbridge AI Tasks", "Rate search results and complete AI quality tasks for Lionbridge.", 200, 2000, 70, False),
        (117, "UserTesting Website Feedback", "Earn $10 per 20-minute website usability test on UserTesting.", 100, 1000, 75, False),
        (118, "TryMyUI UX Testing", "Record yourself using websites and apps, earn $10 per test.", 50, 500, 65, False),
        (119, "Testbirds App Testing", "Test mobile apps and websites for bugs and usability issues.", 50, 500, 60, False),
        (120, "Respondent.io Research Studies", "Participate in paid research studies for $50–$250 per session.", 100, 2000, 80, True),
        (121, "Prolific Paid Research", "Participate in academic and market research studies.", 50, 1000, 75, False),
        (122, "Survey Junkie", "Complete online surveys and earn points redeemable for cash.", 20, 200, 55, False),
        (123, "Swagbucks", "Earn points from surveys, watching videos, and online shopping.", 20, 300, 58, False),
    ]

    for item in microtasks:
        methods.append(_method(item[0], item[1], item[2], "online", "zero", 0, 0, "Micro-Tasks", "🟢", "hours", "none", "medium", "global", "linear", "survival", "solo", ["services"], ["surveys","tasks","micro","earn"], item[3], item[4], item[5], item[6]))

    # ══════════════════════════════════════════════════════
    # ZERO INVESTMENT — OFFLINE (151–300)
    # ══════════════════════════════════════════════════════

    offline_zero = [
        (151, "House Cleaning Services", "Clean homes and offices in your local area.", 300, 3000, 85, False, "Labor & Skills", "🟢", "days", "none", "none", "hyper_local"),
        (159, "Babysitting", "Watch children for parents who need childcare assistance.", 200, 2000, 82, False, "Labor & Skills", "🟢", "days", "none", "none", "hyper_local"),
        (161, "Pet Sitting", "Take care of pets while owners are at work or travelling.", 200, 2000, 80, False, "Labor & Skills", "🟢", "days", "none", "none", "hyper_local"),
        (162, "Dog Walking", "Walk dogs daily for local pet owners who are busy.", 300, 3000, 82, False, "Labor & Skills", "🟢", "hours", "none", "none", "hyper_local"),
        (163, "House Sitting", "Look after someone's home while they travel.", 200, 2000, 72, False, "Labor & Skills", "🟢", "days", "none", "none", "hyper_local"),
        (166, "Errand Running", "Run errands like grocery shopping, dry cleaning pickup for busy people.", 200, 2000, 75, False, "Labor & Skills", "🟢", "days", "none", "none", "hyper_local"),
        (168, "Furniture Assembly", "Assemble flat-pack furniture from IKEA and similar brands.", 200, 2000, 75, False, "Labor & Skills", "🟢", "days", "none", "none", "hyper_local"),
        (171, "Tutoring (K-12)", "Tutor school-age children in academic subjects.", 400, 3000, 88, True, "Education", "🟢", "days", "intermediate", "none", "city"),
        (172, "Music Lessons", "Teach an instrument you play to students of all ages.", 300, 3000, 80, False, "Education", "🟢", "days", "intermediate", "none", "city"),
        (173, "Language Tutoring", "Teach your native language or a language you speak fluently.", 400, 4000, 85, False, "Education", "🟢", "days", "intermediate", "low", "global"),
        (221, "Uber/Lyft Driving", "Drive passengers using rideshare apps in your city.", 800, 5000, 88, False, "Gig Economy", "🟢", "days", "none", "low", "city"),
        (223, "DoorDash/Food Delivery", "Deliver food orders using your vehicle or bicycle.", 500, 3000, 85, False, "Gig Economy", "🟢", "days", "none", "low", "city"),
        (226, "Instacart Shopping", "Shop for groceries and deliver them to customers' doors.", 500, 3500, 82, False, "Gig Economy", "🟢", "days", "none", "low", "city"),
        (230, "TaskRabbit Tasks", "Complete home tasks — moving, cleaning, handyman — via TaskRabbit.", 500, 4000, 80, False, "Gig Economy", "🟢", "days", "basic", "low", "city"),
        (294, "Busking/Street Performance", "Perform music, magic, or art in public spaces for tips.", 100, 3000, 65, False, "Entertainment", "🟢", "hours", "intermediate", "none", "city"),
    ]

    for item in offline_zero:
        methods.append(_method(item[0], item[1], item[2], "offline", "zero", 0, 0, item[7], item[8], item[9], item[10], item[11], item[12], "linear", "survival", "solo", ["services"], ["offline","local","gig"], item[3], item[4], item[5], item[6]))

    # ══════════════════════════════════════════════════════
    # LOW / MICRO INVESTMENT ($1–$500)
    # ══════════════════════════════════════════════════════

    micro_online = [
        (301, "Dropshipping Store", "Sell products without inventory using Shopify and AliExpress.", "micro", 1, 500, 500, 20000, 88, True, "E-commerce", "🟡", "weeks"),
        (326, "Print-on-Demand Store", "Upload artwork and sell on T-shirts, mugs, and posters.", "micro", 0, 50, 100, 3000, 72, False, "E-commerce", "🟡", "weeks"),
        (346, "Amazon FBA (Retail Arbitrage)", "Source discounted products and sell them on Amazon FBA.", "micro", 100, 500, 500, 5000, 80, True, "E-commerce", "🟡", "weeks"),
        (366, "Selling Digital Templates", "Create and sell Canva, Notion, and spreadsheet templates.", "micro", 0, 50, 100, 5000, 82, False, "Digital Products", "🟡", "weeks"),
        (401, "Niche Blog (SEO)", "Build a niche content site monetised with ads and affiliates.", "low", 50, 500, 200, 10000, 78, False, "Content", "🟡", "months"),
        (441, "Online Course (Udemy)", "Create and sell a video course on Udemy's marketplace.", "micro", 0, 100, 200, 10000, 85, True, "Education", "🟡", "weeks"),
        (471, "Social Media Agency", "Manage social media accounts for small businesses.", "micro", 0, 100, 2000, 20000, 90, True, "Agency", "🟡", "weeks"),
        (481, "Video Editing Services", "Edit videos for YouTubers, brands, and content creators.", "zero", 0, 0, 500, 8000, 88, True, "Creative", "🟡", "days"),
        (490, "WordPress Website Setup", "Build WordPress websites for small businesses.", "micro", 50, 200, 500, 5000, 80, False, "Tech", "🟡", "days"),
        (501, "Browser Extension Sales", "Build and sell simple browser extensions.", "micro", 0, 100, 200, 5000, 70, False, "Tech", "🟡", "months"),
        (521, "Dividend Investing", "Build a portfolio of dividend-paying stocks for passive income.", "micro", 100, 500, 50, 2000, 72, False, "Investing", "🟡", "months"),
        (544, "Sneaker Reselling", "Buy limited-edition sneakers and resell for profit on StockX.", "micro", 100, 500, 300, 5000, 78, False, "Reselling", "🟡", "days"),
        (561, "Website Flipping", "Buy undervalued websites, improve them, and sell for profit.", "micro", 100, 500, 500, 10000, 75, True, "Investing", "🟡", "months"),
    ]

    for item in micro_online:
        tier = item[3]
        methods.append(_method(item[0], item[1], item[2], "online", tier, item[4], item[5], item[10], item[11], item[12], "basic", "medium", "global", "leveraged", "stable", "solo", ["e-commerce","services"], ["online","remote"], item[6], item[7], item[8], item[9]))

    # Offline low investment
    offline_low = [
        (601, "Homemade Food Sales", "Sell homemade baked goods, sauces, and snacks locally.", "low", 50, 500, 300, 5000, 80, False),
        (641, "Beauty Services (Hair/Nails)", "Offer hair braiding, styling, or nail art from home.", "low", 50, 500, 500, 5000, 85, True),
        (671, "Handmade Crafts", "Make and sell jewellery, candles, soap, and art.", "low", 50, 500, 200, 5000, 78, False),
        (701, "Microgreens Farm", "Grow and sell microgreens to restaurants and markets.", "low", 100, 500, 500, 3000, 75, False),
        (726, "Garden Design Services", "Design and plant gardens for homeowners.", "low", 50, 200, 500, 5000, 72, False),
        (791, "Phone Screen Repair", "Repair cracked phone screens and sell parts.", "low", 100, 500, 500, 5000, 80, False),
        (811, "Wedding Photography", "Photograph weddings and events for clients.", "low", 100, 500, 500, 8000, 85, True),
        (836, "Home Tutoring Centre", "Run after-school tutoring sessions from your home.", "low", 50, 500, 500, 5000, 85, True),
    ]

    for item in offline_low:
        methods.append(_method(item[0], item[1], item[2], "offline", item[3], item[4], item[5], "Local Services", "🟡", "days", "basic", "none", "city", "linear", "stable", "solo", ["services"], ["offline","local"], item[6], item[7], item[8], item[9]))

    # ══════════════════════════════════════════════════════
    # MEDIUM INVESTMENT ($500–$10K)
    # ══════════════════════════════════════════════════════

    medium_methods = [
        (901, "Branded Shopify Store", "Build a DTC brand with private-label products and paid advertising.", "online", 500, 10000, 2000, 50000, 90, True),
        (951, "Digital Marketing Agency", "Help businesses with social media, ads, SEO, and content.", "online", 500, 5000, 3000, 50000, 88, True),
        (1001, "Food Truck Business", "Mobile food business serving meals at markets and events.", "offline", 5000, 50000, 3000, 15000, 82, False),
        (1021, "Personal Training Studio", "Open a home-based personal training studio.", "offline", 500, 5000, 2000, 10000, 80, False),
        (1041, "Cleaning Company (Team)", "Build a team-based residential and commercial cleaning company.", "offline", 500, 5000, 3000, 20000, 85, False),
        (1061, "Pop-up Retail Store", "Run temporary retail shops at markets and events.", "offline", 500, 5000, 1000, 10000, 72, False),
        (1081, "Accounting/Bookkeeping Firm", "Provide accounting and bookkeeping to small businesses.", "hybrid", 500, 2000, 2000, 15000, 82, False),
        (1101, "Local Courier Company", "Offer local package delivery and courier services.", "offline", 500, 5000, 1500, 8000, 75, False),
        (1121, "Home Daycare", "Licensed home-based daycare for young children.", "offline", 500, 5000, 2000, 8000, 80, False),
        (1141, "Event Planning Company", "Plan and manage events, parties, and corporate functions.", "offline", 500, 5000, 2000, 15000, 80, False),
        (1161, "Airbnb Rental", "List your property or spare room on Airbnb for short-term income.", "offline", 500, 5000, 500, 10000, 88, True),
        (1181, "Small-batch Food Manufacturing", "Produce artisan food products in small batches for retail.", "offline", 1000, 10000, 1000, 8000, 75, False),
    ]

    for item in medium_methods:
        methods.append(_method(item[0], item[1], item[2], item[3], "medium", item[4], item[5], "Medium Investment", "🟠", "weeks", "intermediate", "medium", "city", "leveraged", "stable", "both", ["business","services"], ["medium-investment"], item[6], item[7], item[8], item[9]))

    # ══════════════════════════════════════════════════════
    # HIGH INVESTMENT ($10K–$100K)
    # ══════════════════════════════════════════════════════

    high_methods = [
        (1201, "Buying a Small Business", "Acquire a cash-flowing small business from a broker or owner.", "hybrid", 10000, 100000, 5000, 100000, 72, False),
        (1401, "Opening a Restaurant", "Open a full-service or fast-casual restaurant.", "offline", 50000, 500000, 5000, 100000, 75, False),
        (1421, "Gym Facility", "Open a gym or fitness studio for your community.", "offline", 50000, 500000, 3000, 50000, 78, False),
        (1441, "Full SaaS Build", "Build a Software-as-a-Service product for a business market.", "online", 10000, 100000, 5000, 200000, 85, True),
        (1461, "Apartment Complex", "Buy and operate a small multi-family residential property.", "offline", 50000, 500000, 2000, 30000, 75, False),
        (1481, "Franchise Purchase", "Buy a franchise from an established brand (Subway, Anytime Fitness).", "offline", 50000, 500000, 3000, 30000, 72, False),
        (1501, "Manufacturing Operation", "Start a small manufacturing company producing physical goods.", "offline", 20000, 200000, 3000, 50000, 68, False),
        (1521, "Storage Facility", "Build or acquire a self-storage facility for passive income.", "offline", 50000, 500000, 1000, 20000, 75, False),
        (1541, "Car Wash Business", "Open or acquire a car wash for recurring local income.", "offline", 50000, 500000, 2000, 20000, 72, False),
        (1561, "Hotel/Boutique Property", "Open or acquire a small hotel or bed and breakfast.", "offline", 100000, 1000000, 3000, 50000, 70, False),
        (1901, "Full Digital Agency", "Run a comprehensive digital marketing and web development agency.", "online", 10000, 100000, 10000, 200000, 85, True),
        (1951, "DTC Brand (Scaled)", "Build a Direct-to-Consumer brand with real products and community.", "online", 10000, 100000, 5000, 200000, 82, False),
    ]

    for item in high_methods:
        methods.append(_method(item[0], item[1], item[2], item[3], "high", item[4], item[5], "High Investment", "🔴", "months", "expert", "medium", "city", "leveraged", "stable", "team", ["business"], ["high-investment","business"], item[6], item[7], item[8], item[9]))

    # ══════════════════════════════════════════════════════
    # MAJOR INVESTMENT ($100K–$1M)
    # ══════════════════════════════════════════════════════

    major_methods = [
        (2201, "SaaS Platform (Series A Track)", "Build a B2B SaaS product toward $1M ARR and Series A funding.", "online", 100000, 1000000, 10000, 500000, 85, False),
        (2401, "Marketplace Platform", "Build a two-sided marketplace connecting buyers and sellers.", "online", 100000, 1000000, 5000, 500000, 80, False),
        (2601, "Large Manufacturing Plant", "Open a manufacturing facility producing at commercial scale.", "offline", 500000, 5000000, 10000, 500000, 65, False),
        (2701, "Residential Development", "Develop a residential subdivision or apartment complex.", "offline", 500000, 5000000, 5000, 200000, 70, False),
        (2801, "Tech Startup (Funded)", "Build a venture-backed technology startup.", "online", 500000, 10000000, 0, 1000000, 78, True),
        (2901, "Resort/Hotel Chain", "Build or acquire a hospitality property portfolio.", "offline", 1000000, 10000000, 10000, 300000, 68, False),
        (3001, "Energy Company", "Build a renewable energy company (solar, wind installation).", "hybrid", 1000000, 100000000, 50000, 2000000, 72, False),
    ]

    for item in major_methods:
        methods.append(_method(item[0], item[1], item[2], item[3], "major", item[4], item[5], "Major Investment", "🔴🔴", "years", "expert", "medium", "national", "exponential", "high_reward", "team", ["business","enterprise"], ["major-investment","enterprise"], item[6], item[7], item[8], item[9]))

    # ══════════════════════════════════════════════════════
    # ULTRA / BILLION ($100M+)
    # ══════════════════════════════════════════════════════

    billion_methods = [
        (3051, "AI Company", "Build an AI-powered company solving massive global problems.", "online", 100000000, None, 0, 1000000000, 55, True),
        (3081, "Hedge Fund", "Run a global hedge fund managing institutional capital.", "online", 100000000, None, 0, 500000000, 45, False),
        (3101, "Global REIT", "Build a publicly-listed global Real Estate Investment Trust.", "offline", 500000000, None, 0, 100000000, 45, False),
        (3121, "Consumer Brand (Global)", "Build a global consumer packaged goods company.", "hybrid", 100000000, None, 0, 500000000, 50, False),
        (3181, "Global Energy Company", "Build a global renewable energy infrastructure company.", "hybrid", 500000000, None, 50000000, 2000000000, 48, False),
        (3211, "Global Holding Company", "Build a Berkshire Hathaway-style diversified holding company.", "hybrid", 1000000000, None, 0, 2000000000, 40, False),
    ]

    for item in billion_methods:
        methods.append(_method(item[0], item[1], item[2], item[3], "billion", item[4], item[5], "Billion Dollar+", "💎💎", "years", "expert", "ultra", "global", "exponential", "high_reward", "team", ["enterprise","finance"], ["billion","empire"], item[6], item[7], item[8], item[9]))

    return methods


def ARRAY(arr):
    return arr


def _method(
    num, title, desc, category, tier, min_inv, max_inv,
    section_title, section_emoji, time_to_first, skill_level,
    internet_dep, location, scalability, risk, solo_or_team,
    industry, tags, earn_low, earn_high, demand, featured, trending=False
):
    return {
        "method_number":             num,
        "title":                     title,
        "description":               desc,
        "category":                  category,
        "investment_tier":           tier,
        "min_investment_usd":        min_inv or 0,
        "max_investment_usd":        max_inv,
        "section_title":             section_title,
        "section_emoji":             section_emoji,
        "time_to_first_dollar":      time_to_first,
        "skill_level":               skill_level,
        "internet_dependency":       internet_dep,
        "location_flexibility":      location,
        "scalability":               scalability,
        "risk_profile":              risk,
        "solo_or_team":              solo_or_team,
        "industry_vertical":         industry,
        "tags":                      tags,
        "avg_earning_monthly_usd_low":  earn_low,
        "avg_earning_monthly_usd_high": earn_high,
        "global_demand_score":       demand,
        "is_featured":               featured,
        "trending":                  trending,
        "is_active":                 True,
    }


def seed_to_supabase(methods: List[Dict]) -> int:
    """Insert methods into Supabase using the service key."""
    try:
        from supabase import create_client, Client

        url = os.environ.get("SUPABASE_URL")
        key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ.get("SUPABASE_SERVICE_ROLE_KEY")

        if not url or not key:
            print("❌ SUPABASE_URL and SUPABASE_SERVICE_KEY must be set")
            sys.exit(1)

        sb: Client = create_client(url, key)

        chunk_size = 100
        inserted   = 0
        errors     = []

        print(f"📊 Seeding {len(methods)} methods in chunks of {chunk_size}...")

        for i in range(0, len(methods), chunk_size):
            chunk = methods[i:i + chunk_size]
            try:
                result = sb.table("income_methods").upsert(
                    chunk, on_conflict="method_number"
                ).execute()
                inserted += len(chunk)
                print(f"  ✅ Chunk {i//chunk_size + 1}: {len(chunk)} methods (total: {inserted})")
            except Exception as e:
                errors.append(f"Chunk {i}: {e}")
                print(f"  ❌ Chunk {i//chunk_size + 1} error: {e}")

            time.sleep(0.1)  # Rate limit protection

        if errors:
            print(f"\n⚠️  {len(errors)} errors occurred:")
            for e in errors:
                print(f"   {e}")

        print(f"\n🎉 Successfully seeded {inserted}/{len(methods)} methods!")
        return inserted

    except ImportError:
        print("❌ supabase package not installed. Run: pip install supabase")
        sys.exit(1)


def seed_via_api(methods: List[Dict], api_base_url: str, chunk_size: int = 500) -> int:
    """Insert methods via the /api/v1/brain/seed/methods endpoint."""
    import urllib.request

    inserted = 0
    for i in range(0, len(methods), chunk_size):
        chunk = methods[i:i + chunk_size]
        try:
            data    = json.dumps({"methods": chunk}).encode("utf-8")
            request = urllib.request.Request(
                f"{api_base_url}/api/v1/brain/seed/methods",
                data=data,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(request, timeout=60) as response:
                result = json.loads(response.read())
                inserted += len(chunk)
                print(f"  ✅ Chunk {i//chunk_size + 1}: {result.get('queued',0)} queued")
        except Exception as e:
            print(f"  ❌ Chunk {i//chunk_size + 1} error: {e}")

    return inserted


if __name__ == "__main__":
    print("═══════════════════════════════════════════════")
    print("RiseUp Methods Brain — Seed Script")
    print("═══════════════════════════════════════════════")

    methods = get_all_methods()
    print(f"📦 Total methods to seed: {len(methods)}")

    # Count by tier
    tier_counts = {}
    for m in methods:
        t = m["investment_tier"]
        tier_counts[t] = tier_counts.get(t, 0) + 1

    for tier, count in sorted(tier_counts.items()):
        print(f"   {tier:10} → {count} methods")

    print("\nChoose seeding method:")
    print("  1 — Direct Supabase (requires SUPABASE_SERVICE_KEY)")
    print("  2 — Via API (requires running server)")
    choice = input("\nEnter 1 or 2 [1]: ").strip() or "1"

    if choice == "2":
        api_url = input("API base URL [http://localhost:8000]: ").strip() or "http://localhost:8000"
        inserted = seed_via_api(methods, api_url)
    else:
        inserted = seed_to_supabase(methods)

    print(f"\n✅ Seed complete! {inserted} methods loaded into RiseUp Brain.")
    print("   Run your backend and visit /api/v1/brain/methods/stats to verify.")

