import '/pages/privacy_policy.dart';
import '/pages/terms_of_use.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '/pages/auth_page.dart';
import '/components/appbar.dart';
import '/components/navbar.dart';
import 'package:google_fonts/google_fonts.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  void signUserOut(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const AuthPage()),
        (Route<dynamic> route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: const Header(), // Custom App Bar
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            CircleAvatar(
              radius: 35,
              backgroundColor: const Color.fromARGB(
                255,
                137,
                137,
                137,
              ), // Added background color
              child: Icon(Icons.person, size: 50, color: Colors.white),
            ),

            const SizedBox(height: 10),
            // User Information
            StreamBuilder<DocumentSnapshot>(
              stream:
                  FirebaseFirestore.instance
                      .collection('users')
                      .doc(user?.uid)
                      .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const CircularProgressIndicator();
                }
                if (snapshot.hasError) {
                  return Text('Error: ${snapshot.error}');
                }
                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const Text('No user data found');
                }
                final userData = snapshot.data!.data() as Map<String, dynamic>?;

                // Display user information
                return Column(
                  children: [
                    // Email container
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      padding: const EdgeInsets.all(15),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 5,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.email, size: 20, color: Colors.black),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              'Email: ${userData?['email'] ?? user?.email ?? 'No Email'}',
                              style: GoogleFonts.poppins(fontSize: 16),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Username container
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(15),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 5,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.verified_user,
                            size: 20,
                            color: Colors.black,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              'Username: ${userData?['username'] ?? user?.displayName ?? 'No Username'}',
                              style: GoogleFonts.poppins(fontSize: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 20),

            // Terms of Use and Privacy Policy buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Terms of Use
                GestureDetector(
                  onTap: () {
                    // Navigate to Terms of Use page
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => TermsOfUsePage()),
                    );
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 5,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(10),
                    child: Text('Terms of Use', style: GoogleFonts.poppins()),
                  ),
                ),

                // Privacy Policy
                GestureDetector(
                  onTap: () {
                    // Navigate to Privacy Policy page
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => PrivacyPolicyPage(),
                      ),
                    );
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 5,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(10),
                    child: Text('Privacy Policy', style: GoogleFonts.poppins()),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => signUserOut(context),
              icon: const Icon(Icons.logout),
              label: Text("Sign Out", style: GoogleFonts.poppins()),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const NavBar(currentIndex: 3),
    );
  }
}
