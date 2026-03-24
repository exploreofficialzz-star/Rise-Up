import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_constants.dart';

const _privacyContent = r"""
# Privacy Policy

**RiseUp — AI Wealth Mentor**
**ChAs Tech Group**
**Last updated: January 2025**

---

## 1. Who We Are

RiseUp is an AI-powered wealth-building application developed by **ChAs Tech Group**, based in Lagos, Nigeria. This Privacy Policy explains how we collect, use, and protect your personal information.

Contact us at: **privacy@chastech.ng**

---

## 2. Information We Collect

### Information You Provide
- **Account data**: Name, email address, password (encrypted)
- **Financial profile**: Monthly income, expenses, goals, skills (used to personalise AI advice)
- **Conversation history**: Your chats with the RiseUp AI mentor

### Information Collected Automatically
- **Usage data**: Screens visited, features used, time spent
- **Device information**: Device type, operating system, app version
- **Crash reports**: Error logs to help us fix bugs

### Advertising Data
- **AdMob (Android/iOS)**: Google's advertising SDK collects device identifiers to show relevant ads. You can opt out via your device's advertising settings.
- **Google AdSense (Web)**: Collects cookies and browsing data for ad personalisation.

---

## 3. How We Use Your Information

| Purpose | Legal Basis |
|---------|-------------|
| Providing the RiseUp AI mentoring service | Contract |
| Personalising income tasks and roadmaps | Contract |
| Sending account verification and reset emails | Contract |
| Improving our AI models and features | Legitimate interest |
| Showing relevant advertisements | Consent (opt-out available) |
| Complying with legal obligations | Legal requirement |

---

## 4. AI & Data Processing

Your conversations with the RiseUp AI are:
- Sent to third-party AI providers (Groq, Google Gemini, Cohere, OpenAI, Anthropic) for processing
- **Not used to train those providers' models** — we use API access only
- Stored in our secure Supabase database to maintain conversation context
- Accessible only to you (and anonymised for bug diagnosis)

---

## 5. Data Sharing

We **do not sell your personal data**. We share data only with:
- **Supabase** (database hosting, EU servers)
- **AI providers** (Groq, Google, Cohere, OpenAI, Anthropic) — for processing your requests
- **Flutterwave** — for payment processing (they have their own privacy policy)
- **Google AdMob / AdSense** — for advertising
- **Law enforcement** — only when legally required

---

## 6. Data Retention

- Account data: Retained while your account is active + 30 days after deletion
- Conversation history: 12 months, then anonymised
- Payment records: 7 years (legal requirement)

---

## 7. Your Rights

You have the right to:
- **Access** your data (request a copy via the app)
- **Correct** inaccurate data (via Profile settings)
- **Delete** your account and data (Settings → Delete Account)
- **Opt out** of personalised ads (device advertising settings)
- **Data portability** (contact us at privacy@chastech.ng)

For users in the EU/UK, additional GDPR rights apply.

---

## 8. Children's Privacy

RiseUp is intended for users **13 years and older**. We do not knowingly collect data from children under 13. If you believe a child has created an account, contact us immediately.

---

## 9. Security

We protect your data using:
- AES-256 encryption for passwords and tokens
- TLS/HTTPS for all data in transit
- Supabase Row Level Security (RLS) — each user can only access their own data
- Rate limiting to prevent unauthorised access attempts

---

## 10. Changes to This Policy

We will notify you of significant changes via email and an in-app notification. Continued use after changes means you accept the updated policy.

---

## 11. Contact

**ChAs Tech Group**
Lagos, Nigeria
📧 privacy@chastech.ng

For data requests or complaints, email us with subject "PRIVACY REQUEST".
""";

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: Text('Privacy Policy', style: AppTextStyles.h3),
        backgroundColor: AppColors.bgDark,
      ),
      body: Markdown(
        data: _privacyContent,
        styleSheet: MarkdownStyleSheet(
          h1: AppTextStyles.h2.copyWith(color: AppColors.primary),
          h2: AppTextStyles.h3,
          h3: AppTextStyles.h4,
          p: AppTextStyles.body,
          tableBody: AppTextStyles.bodySmall,
          tableBorder: TableBorder.all(color: AppColors.bgSurface),
          tableColumnWidth: const FlexColumnWidth(),
          blockquoteDecoration: BoxDecoration(
            color: AppColors.bgCard,
            border: Border(left: BorderSide(color: AppColors.primary, width: 3)),
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
            border: Border(bottom: BorderSide(color: AppColors.bgSurface)),
          ),
        ),
        onTapLink: (text, href, title) async {
          if (href != null) {
            final uri = Uri.parse(href);
            if (await canLaunchUrl(uri)) launchUrl(uri);
          }
        },
      ),
    );
  }
}
