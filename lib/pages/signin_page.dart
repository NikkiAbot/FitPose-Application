// ignore_for_file: use_build_context_synchronously

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/gestures.dart';
import '/components/text_field.dart';
import '/components/login_button.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '/pages/terms_of_use.dart';
import '/pages/privacy_policy.dart';

class SignInPage extends StatefulWidget {
  final Function()? onTap;
  const SignInPage({super.key, required this.onTap});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final usernameController = TextEditingController();
  bool isChecked = false;
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmpasswordController = TextEditingController();

  void signUserUp() async {
    if (!isChecked) {
      showErrorMessage(
        "Please agree to the Terms of Service and Privacy Policy",
      );
      return;
    }
    showDialog(
      context: context,
      builder: (context) {
        return const Center(
          child: CircularProgressIndicator(
            color: Color.fromARGB(255, 66, 164, 244),
          ),
        );
      },
    );

    try {
      if (passwordController.text == confirmpasswordController.text) {
        // Create user
        UserCredential userCredential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
              email: emailController.text.trim(),
              password: passwordController.text.trim(),
            );

        // Get user UID
        String uid = userCredential.user!.uid;

        // Store additional info in Firestore
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'username': usernameController.text.trim(),
          'email': emailController.text.trim(),
          'password': passwordController.text.trim(),
          'createdAt': Timestamp.now(),
        });

        Navigator.pop(context); // Close loading dialog
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        Navigator.pop(context);
        showErrorMessage("Passwords do not match");
      }
    } on FirebaseAuthException catch (e) {
      Navigator.pop(context);
      showErrorMessage(e.message ?? "An error occurred");
    }
  }

  void showErrorMessage(String message) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color.fromARGB(255, 140, 140, 140),
          title: Center(
            child: Text(
              message,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('lib/images/Fitpose-LogIn.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: Center(
          child: Column(
            children: [
              const SizedBox(height: 50),
              Image.asset('lib/images/Logo2.png', width: 100, height: 100),
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  'FitPose',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 60,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                'Sign in to continue',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 20),

              // Username
              TextWidget(
                controller: usernameController,
                hintText: 'Username',
                obscureText: false,
              ),

              const SizedBox(height: 20),

              // Email
              TextWidget(
                controller: emailController,
                hintText: 'Email',
                obscureText: false,
              ),

              const SizedBox(height: 20),

              // Password
              TextWidget(
                controller: passwordController,
                hintText: 'Password',
                obscureText: true,
              ),

              const SizedBox(height: 20),

              // Confirm Password
              TextWidget(
                controller: confirmpasswordController,
                hintText: 'Confirm Password',
                obscureText: true,
              ),

              const SizedBox(height: 20),

              // Terms of Service and Privacy Policy
              Padding(
                padding: const EdgeInsets.only(left: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Checkbox(
                      value: isChecked,
                      onChanged: (value) {
                        setState(() {
                          isChecked = value!;
                        });
                      },
                      activeColor: const Color.fromARGB(255, 66, 164, 244),
                    ),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(
                            text: TextSpan(
                              text: 'By signing up, you agree to Fitpose\'s ',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w300,
                              ),
                              children: [
                                TextSpan(
                                  text: 'Terms of Service',
                                  style: GoogleFonts.poppins(
                                    color: const Color.fromARGB(
                                      255,
                                      66,
                                      164,
                                      244,
                                    ),
                                    fontSize: 14,
                                    decoration: TextDecoration.underline,
                                  ),
                                  recognizer:
                                      TapGestureRecognizer()
                                        ..onTap = () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder:
                                                  (_) => const TermsOfUsePage(),
                                            ),
                                          );
                                        },
                                ),
                                TextSpan(
                                  text: ' and ',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                                TextSpan(
                                  text: 'Privacy Policy',
                                  style: GoogleFonts.poppins(
                                    color: const Color.fromARGB(
                                      255,
                                      66,
                                      164,
                                      244,
                                    ),
                                    fontSize: 14,
                                    decoration: TextDecoration.underline,
                                  ),
                                  recognizer:
                                      TapGestureRecognizer()
                                        ..onTap = () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder:
                                                  (_) =>
                                                      const PrivacyPolicyPage(),
                                            ),
                                          );
                                        },
                                ),
                                TextSpan(
                                  text: '.',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // End of Terms of Service and Privacy Policy
              const SizedBox(height: 10),

              // Sign Up Button
              LoginButton(text: "Sign In", onTap: signUserUp),

              const SizedBox(height: 10),

              Text(
                'Already have an account?',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w300,
                ),
              ),

              GestureDetector(
                onTap: widget.onTap,
                child: Text(
                  'Sign Up',
                  style: GoogleFonts.poppins(
                    color: const Color.fromARGB(255, 66, 164, 244),
                    fontSize: 14,
                    decoration: TextDecoration.underline,
                    decorationColor: Color.fromARGB(255, 66, 164, 244),
                  ),
                ),
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
