import 'package:flutter/material.dart';
import '/components/appbar.dart';
import 'package:google_fonts/google_fonts.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const Header(showBackButton: true, backButtonColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Text('''
Privacy Policy

This privacy policy explains how we collect, use, and protect your information when using our app.

1. Data Collection
We collect:
- User information (email, UID) via Firebase Authentication
- Calorie intake logs you manually input
- Food search data (sent to USDA API for results)

2. Data Use
We use your data to:
- Provide personalized calorie tracking
- Store your logs securely in Firebase Firestore

3. Third-Party Services
We use:
- Firebase for authentication and database
- USDA FoodData Central API for food nutrition data

4. Data Security
Your data is protected using Firebase security rules. We do not share your data with third parties.

5. Your Rights
You may delete your account or contact us to remove your data at any time.

6. Changes
We may update this policy. Continued use of the app means you accept the updated policy.

Contact us at fitpose@gmail.com for questions or concerns.
          ''', style: GoogleFonts.poppins(fontSize: 14)),
      ),
    );
  }
}
