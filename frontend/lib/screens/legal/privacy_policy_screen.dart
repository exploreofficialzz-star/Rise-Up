import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_constants.dart';

const _privacyContent = r"""
# Privacy Policy

**RiseUp — Global AI Wealth & Income Platform**
**ChAs Technologies LLC**
**Last updated: January 2026**

---

## 1. Who We Are

RiseUp is a global AI-powered wealth-building, income-generation, and financial empowerment platform developed and operated by **ChAs Technologies LLC**. RiseUp combines social community features, autonomous AI agents, income tools, skill-building, marketplace access, and personalised mentorship to help users worldwide build sustainable financial freedom.

This Privacy Policy explains how we collect, use, store, and protect your personal information when you use RiseUp across any platform — mobile (iOS/Android), web, or any future RiseUp product.

📧 Contact us: **riseup.customer.carez@gmail.com**

---

## 2. Information We Collect

### 2.1 Information You Provide

- **Account data**: Full name, email address, password (AES-256 encrypted), profile photo
- **Financial profile**: Monthly income, expenses, savings goals, skills, target income — used exclusively to personalise your AI mentor experience
- **Conversation history**: Your chats with the RiseUp AI Mentor and APEX Agent
- **Workflow & task data**: Plans, goals, and tasks you create or complete inside RiseUp
- **Community content**: Posts, comments, reactions, and messages you share on the platform
- **Payment information**: Processed securely by third-party payment processors (we do not store raw card data)
- **Identity verification** (where required): Government ID, phone number, country of residence

### 2.2 Information Collected Automatically

- **Usage data**: Screens visited, features used, time spent, button taps, session duration
- **Device information**: Device type, operating system, app version, unique device identifiers
- **Location data**: Country/region (derived from IP address for content localisation — no precise GPS tracking without consent)
- **Network data**: IP address, connection type
- **Crash reports & error logs**: Used solely for bug diagnosis and service improvement
- **Performance metrics**: Page load times, API response times, feature usage frequency

### 2.3 Advertising Data

- **Google AdMob (Android/iOS)**: Google's advertising SDK collects device identifiers (e.g., IDFA/GAID) to serve relevant ads. You can opt out via your device's advertising settings.
- **Google AdSense (Web)**: Uses cookies and browsing behaviour for ad personalisation.
- **Rewarded Video Ads**: When you watch a rewarded ad to unlock AI messages or APEX tokens, we record that the reward was granted — no additional data is collected beyond what AdMob tracks.

---

## 3. How We Use Your Information

| Purpose | Legal Basis |
|---|---|
| Providing the RiseUp AI Mentor & APEX Agent service | Contract performance |
| Personalising income tasks, roadmaps & workflows | Contract performance |
| Powering the RiseUp social community features | Contract performance |
| Sending account verification, security, and reset emails | Contract performance |
| Processing payments and subscriptions | Contract performance |
| Matching users with complementary skills (RiseUp Brain) | Contract performance |
| Showing relevant advertisements to free-tier users | Consent (opt-out available) |
| Improving our AI models, features, and platform | Legitimate interest |
| Detecting fraud, abuse, and security threats | Legitimate interest |
| Complying with applicable laws and regulations | Legal obligation |
| Sending product updates and announcements (opt-in) | Consent |

---

## 4. AI, APEX Agent & Data Processing

RiseUp uses multiple AI systems to power your experience:

### AI Mentor
Your conversations with the RiseUp AI Mentor are:
- Sent to third-party AI providers — including **Groq, Google Gemini, Cohere, OpenAI, and Anthropic** — for real-time response generation
- **Not used to train those providers' models** — we access their APIs under terms that prohibit training use
- Stored in our secure Supabase database to maintain conversation context and history
- Accessible only to you, with anonymised versions used solely for internal bug diagnosis

### APEX Autonomous Agent
When you activate APEX:
- APEX uses AI reasoning to browse the web, execute tasks, fill forms, and interact with third-party platforms on your behalf
- Screenshots and action logs are stored temporarily (24 hours) to power the live browser stream
- You remain in full control and can pause, stop, or override APEX at any time
- APEX actions are performed only with your explicit instruction

### RiseUp Brain (Internal Knowledge Search)
- RiseUp maintains an internal knowledge base of income methods, opportunities, and resources
- Searches of this database are tied to your session and used only to personalise responses
- No personally identifiable data is exposed to other users through Brain searches

---

## 5. Data Sharing

We **do not sell, rent, or trade your personal data**. We share data only with trusted partners as necessary to operate RiseUp:

| Recipient | Purpose | Data Shared |
|---|---|---|
| **Supabase** | Secure cloud database hosting (EU servers) | Encrypted user data |
| **Groq / Google / Cohere / OpenAI / Anthropic** | AI response generation | Conversation messages only |
| **Google AdMob / AdSense** | Advertising on free tier | Device identifiers, ad interactions |
| **Flutterwave / Payment Processors** | Subscription & payment processing | Payment details (not stored by us) |
| **Playwright / Browser Automation** | APEX agent browser tasks | Session-only, no retention |
| **Law enforcement / Regulators** | Legal compliance only | Minimum required by law |

We require all third-party providers to handle your data in compliance with applicable privacy laws.

---

## 6. International Data Transfers

RiseUp serves users globally. Your data may be processed in countries outside your own, including the United States and European Union. Where required, we ensure adequate protections are in place through standard contractual clauses or equivalent safeguards.

---

## 7. Data Retention

| Data Type | Retention Period |
|---|---|
| Account data | Active + 30 days after account deletion |
| Conversation history (AI Mentor) | 12 months, then anonymised |
| APEX browser session screenshots | 24 hours maximum |
| Workflow and task data | Active + 30 days after deletion |
| Payment records | 7 years (legal / tax requirement) |
| Crash logs and error reports | 90 days |
| Advertising interaction data | Controlled by Google AdMob policy |

---

## 8. Your Rights

Regardless of where you live, you have the following rights:

- **Access**: Request a copy of all personal data we hold about you
- **Correction**: Fix inaccurate data via Profile Settings in the app
- **Deletion**: Delete your account and all associated data via Settings → Delete Account
- **Portability**: Request your data in a machine-readable format
- **Opt-out of ads**: Adjust personalised advertising via your device advertising settings
- **Withdraw consent**: Opt out of optional data uses at any time

**EU / UK users (GDPR / UK GDPR):** You additionally have the right to object to processing, restrict processing, and lodge a complaint with your local supervisory authority.

**California users (CCPA):** You have the right to know what data we collect, the right to delete, and the right to opt-out of sale (we do not sell data).

To exercise any of these rights, email: **riseup.customer.carez@gmail.com** with subject **"PRIVACY REQUEST"**. We respond within 30 days.

---

## 9. Children's Privacy

RiseUp is intended for users **13 years and older** (or 16 in certain EU countries). We do not knowingly collect personal data from children below this age. If you believe a child has created a RiseUp account, contact us immediately at **riseup.customer.carez@gmail.com** and we will delete the account promptly.

---

## 10. Security

We implement industry-standard security measures to protect your data:

- **AES-256 encryption** for passwords, tokens, and sensitive fields at rest
- **TLS 1.3 / HTTPS** for all data in transit
- **Supabase Row Level Security (RLS)** — each user can only access their own data, enforced at the database level
- **Rate limiting** on all API endpoints to prevent brute-force and abuse attacks
- **JWT authentication** with short expiry tokens and refresh rotation
- **Zero-trust architecture** — internal services authenticate each request
- Regular security audits and dependency updates

Despite these measures, no system is 100% secure. We encourage you to use a strong, unique password and enable any available 2FA.

---

## 11. Cookies & Tracking

On the RiseUp web platform, we use:

- **Essential cookies**: Required for login sessions and security
- **Analytics cookies**: Understand how users navigate the app (opt-out available)
- **Advertising cookies**: Google AdSense personalisation (opt-out via browser or AdSense controls)

You can manage cookie preferences in your browser settings at any time.

---

## 12. Changes to This Policy

We will notify you of significant changes via email and an in-app notification at least 14 days before they take effect. Continued use of RiseUp after changes take effect means you accept the updated policy. The "Last updated" date at the top of this page will always reflect the most recent version.

---

## 13. Contact & Data Requests

**ChAs Technologies LLC**
🌍 Global Operations
📧 **riseup.customer.carez@gmail.com**

For all privacy requests, data deletion requests, or complaints, email us with subject line **"PRIVACY REQUEST"**. We aim to respond within 30 days.
""";

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.bgDark : Colors.white,
      appBar: AppBar(
        title: Text('Privacy Policy', style: AppTextStyles.h3),
        backgroundColor: isDark ? AppColors.bgDark : Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: Markdown(
        data: _privacyContent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        styleSheet: MarkdownStyleSheet(
          h1: AppTextStyles.h2.copyWith(color: AppColors.primary),
          h2: AppTextStyles.h3,
          h3: AppTextStyles.h4,
          p: AppTextStyles.body,
          tableBody: AppTextStyles.bodySmall,
          tableBorder: TableBorder.all(color: AppColors.bgSurface),
          tableColumnWidth: const FlexColumnWidth(),
          tableHead: AppTextStyles.bodySmall.copyWith(
              color: AppColors.primary, fontWeight: FontWeight.w700),
          blockquoteDecoration: BoxDecoration(
            color: AppColors.bgCard,
            border: Border(
                left: BorderSide(color: AppColors.primary, width: 3)),
          ),
          code: AppTextStyles.caption.copyWith(
            backgroundColor: AppColors.bgCard,
            fontFamily: 'monospace',
          ),
          codeblockDecoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: AppRadius.md,
          ),
          horizontalRuleDecoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(color: AppColors.bgSurface)),
          ),
          listBullet: AppTextStyles.body.copyWith(color: AppColors.primary),
          strong: AppTextStyles.body
              .copyWith(fontWeight: FontWeight.w700),
        ),
        onTapLink: (text, href, title) async {
          if (href != null) {
            final uri = Uri.parse(href);
            if (await canLaunchUrl(uri)) {
              launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          }
        },
      ),
    );
  }
}
