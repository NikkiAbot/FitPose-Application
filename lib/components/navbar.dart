import 'package:flutter/material.dart';
import '/pages/main_pages/home_page.dart';
import '/pages/main_pages/workout_page.dart';
import '/pages/main_pages/calories_page.dart';
import '/pages/main_pages/settings.dart';

class NavBar extends StatelessWidget {
  final int currentIndex;

  const NavBar({super.key, required this.currentIndex});

  // Function to navigate to a new page without animation
  void _navigate(BuildContext context, Widget page) {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => page,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          backgroundColor: Colors.black,
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.grey[400],
          type: BottomNavigationBarType.fixed,
          onTap: (index) {
            if (index == currentIndex) return; // Avoid reloading current page
            switch (index) {
              case 0:
                _navigate(context, const HomePage());
                break;
              case 1:
                _navigate(context, WorkoutPage());
                break;
              case 2:
                _navigate(context, Calories());
                break;
              case 3:
                _navigate(context, const SettingsPage());
                break;
            }
          },
          items: [
            BottomNavigationBarItem(
              icon: _Animation(icon: Icons.home, isSelected: currentIndex == 0),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: _Animation(
                icon: Icons.fitness_center,
                isSelected: currentIndex == 1,
              ),
              label: 'Workout',
            ),
            BottomNavigationBarItem(
              icon: _Animation(
                icon: Icons.local_fire_department,
                isSelected: currentIndex == 2,
              ),
              label: 'Calories',
            ),
            BottomNavigationBarItem(
              icon: _Animation(
                icon: Icons.settings,
                isSelected: currentIndex == 3,
              ),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}

// Animation for the BottomNavigationBar items
class _Animation extends StatelessWidget {
  final IconData icon;
  final bool isSelected;

  const _Animation({required this.icon, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: isSelected ? 1.3 : 1.0,
      duration: const Duration(milliseconds: 1000),
      curve: Curves.easeInOut,
      child: Icon(icon, color: isSelected ? Colors.white : Colors.grey[400]),
    );
  }
}
