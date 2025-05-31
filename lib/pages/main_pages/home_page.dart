import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitpose/pages/workouts/bicepcurl.dart';
import 'package:fitpose/pages/workouts/lunges.dart';
import 'package:fitpose/pages/workouts/plank.dart';
import 'package:fitpose/pages/workouts/shoulderpress.dart';
import 'package:fitpose/pages/workouts/situp.dart';
import 'package:fitpose/pages/workouts/squats.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '/components/navbar.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? username;

  @override
  void initState() {
    super.initState();
    fetchUsername();
  }

  Future<void> fetchUsername() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc =
          await FirebaseFirestore.instance
              .collection(
                'users',
              ) // Make sure this matches your Firestore collection name
              .doc(user.uid)
              .get();

      if (doc.exists) {
        setState(() {
          username = doc.data()?['username'] ?? 'User';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 1,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'lib/images/Logo1.png',
              height: 60,
              errorBuilder:
                  (context, error, stackTrace) =>
                      const Icon(Icons.image_not_supported),
            ),
            Text(
              "Fitpose",
              style: GoogleFonts.poppins(
                fontSize: 30,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(115),
          child: Padding(
            padding: const EdgeInsets.only(left: 25, bottom: 5),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Welcome!!',
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w400,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    username ?? 'Loading...',
                    style: GoogleFonts.poppins(
                      fontSize: 50,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ready to work out?\nSelect a workout you’d like to do.',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  color: const Color.fromARGB(255, 48, 48, 48),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 5),
              const Divider(thickness: 1, color: Colors.grey),
              Text(
                'Non-Equipment Workouts:',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 10),
              WorkoutCard(
                title: 'Squat',
                icon: 'lib/images/squat_icon.png',
                backgroundImage: 'lib/images/squat.png',
                onTap:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const Squats()),
                    ),
              ),
              WorkoutCard(
                title: 'Plank',
                icon: 'lib/images/plank_icon.png',
                backgroundImage: 'lib/images/plank.png',
                onTap:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const Plank()),
                    ),
              ),
              WorkoutCard(
                title: 'Push Up',
                icon: 'lib/images/push_up_icon.png',
                backgroundImage: 'lib/images/push_up.png',
                onTap:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const SitUp()),
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                'Equipment Workouts:',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 10),
              WorkoutCard(
                title: 'Shoulder Press',
                icon: 'lib/images/shoulder_press_icon.png',
                backgroundImage: 'lib/images/shoulder_press.png',
                onTap:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ShoulderPress(),
                      ),
                    ),
              ),
              WorkoutCard(
                title: 'Bicep Curl',
                icon: 'lib/images/bicep_curl_icon.png',
                backgroundImage: 'lib/images/bicep_curl.png',
                onTap:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const BicepCurl(),
                      ),
                    ),
              ),
              WorkoutCard(
                title: 'Lunges',
                icon: 'lib/images/lunges_icon.png',
                backgroundImage: 'lib/images/lunges.png',
                onTap:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const Lunges()),
                    ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const NavBar(currentIndex: 0),
    );
  }
}

class WorkoutCard extends StatelessWidget {
  final String title;
  final String icon;
  final String? routeName;
  final VoidCallback? onTap;
  final String backgroundImage;

  const WorkoutCard({
    super.key,
    required this.title,
    required this.icon,
    this.routeName,
    this.onTap,
    required this.backgroundImage,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap:
          onTap ??
          (routeName != null
              ? () => Navigator.pushNamed(context, routeName!)
              : null),
      child: Container(
        height: 100, // Increased height
        margin: const EdgeInsets.only(bottom: 15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha((0.1 * 255).toInt()),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
          image: DecorationImage(
            image: AssetImage(backgroundImage),
            fit: BoxFit.cover,
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.black.withOpacity(0.7),
                Colors.black.withOpacity(0.5),
              ],
            ),
          ),
          child: Row(
            children: [
              Image.asset(
                icon,
                height: 40, // Larger icon
                width: 40,
                errorBuilder:
                    (context, error, stackTrace) => const Icon(
                      Icons.image_not_supported,
                      color: Colors.white,
                      size: 40,
                    ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 18, // Larger text
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                color: Colors.white,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
