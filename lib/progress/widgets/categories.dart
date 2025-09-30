import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class WorkoutCategorySelector extends StatelessWidget {
  final List<String> workoutNames;
  final List<Color> workoutColors;
  final int selectedWorkoutIndex;
  final Function(int) onWorkoutSelected;

  const WorkoutCategorySelector({
    super.key,
    required this.workoutNames,
    required this.workoutColors,
    required this.selectedWorkoutIndex,
    required this.onWorkoutSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: List.generate(workoutNames.length, (index) {
          final isSelected = index == selectedWorkoutIndex;
          return GestureDetector(
            onTap: () => onWorkoutSelected(index),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8.0),
              padding: const EdgeInsets.all(10.0),
              decoration: BoxDecoration(
                color:
                    isSelected
                        ? workoutColors[index].withAlpha(51) // 0.2 * 255 = 51
                        : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    backgroundColor: workoutColors[index],
                    child: Image.asset(
                      'lib/images/${workoutNames[index].toLowerCase().replaceAll(' ', '_')}_icon.png',
                      fit: BoxFit.cover,
                      width: 30,
                      height: 30,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    workoutNames[index],
                    style: GoogleFonts.poppins(fontSize: 12),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
