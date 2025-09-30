import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '/components/text_field.dart';
import '/components/login_button.dart';

class LoginPage extends StatefulWidget {
  final Function()? onTap;
  const LoginPage({super.key, required this.onTap});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  void signUserIn() async {
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
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text,
        password: passwordController.text,
      );
      if (!mounted) return;
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      Navigator.pop(context);
      showErrorMessage(e.code);
    }
  }

  void showErrorMessage(String message) {
    showDialog(
      context: context,
      barrierDismissible: true, // Allows tapping outside to dismiss
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
                'Log in to continue',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 20),

              // Email field
              TextWidget(
                controller: emailController,
                hintText: 'Email',
                obscureText: false,
              ),

              const SizedBox(height: 20),

              // Password field
              TextWidget(
                controller: passwordController,
                hintText: 'Password',
                obscureText: true,
              ),

              const SizedBox(height: 20),

              // Login button
              LoginButton(text: "Log In", onTap: signUserIn),

              SizedBox(height: 10),

              Text(
                'Don\'t have an account?',
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
