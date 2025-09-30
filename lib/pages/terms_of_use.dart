import 'package:flutter/material.dart';
import '/components/appbar.dart';
import 'package:google_fonts/google_fonts.dart';

class TermsOfUsePage extends StatelessWidget {
  const TermsOfUsePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const Header(showBackButton: true, backButtonColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Text('''
Terms of Use

Welcome to Fitpose, a pose correction app for exercises. By using this app, you agree to the following terms:

1. Acceptance of Terms
By accessing or using this app, you agree to be bound by these Terms of Use.

2. Usage
This app is provided for personal use only. You agree not to misuse the app or attempt unauthorized access.

3. Data Accuracy
While we strive for accurate information, we are not responsible for any inaccuracies in calorie data retrieved from the USDA API.

4. Account
You are responsible for maintaining the confidentiality of your login credentials and any activity under your account.

5. Changes
We reserve the right to update these Terms of Use at any time. Continued use of the app after changes constitutes acceptance.

6. Termination
We reserve the right to suspend or terminate accounts for violations of these terms.

If you have any questions, contact us at fitpose@gmail.com.
          ''', style: GoogleFonts.poppins(fontSize: 14)),
      ),
    );
  }
}
