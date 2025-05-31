import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../model/progressmodel.dart';
import '../util/time_util.dart';

class ProgressBox extends StatelessWidget {
  final String title;
  final WorkoutProgress progress;
  final Color color;

  const ProgressBox({
    super.key,
    required this.title,
    required this.progress,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 20.0),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withAlpha((0.4 * 255).toInt())),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                StatItem(
                  icon: Icons.repeat,
                  value: '${progress.reps}',
                  label: 'Reps',
                  color: color,
                ),
                StatItem(
                  icon: Icons.fitness_center,
                  value: '${progress.sets}',
                  label: 'Sets',
                  color: color,
                ),
                StatItem(
                  icon: Icons.timer,
                  value: DurationFormatter.format(progress.duration),
                  label: 'Duration',
                  color: color,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const StatItem({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 1),
        Text(
          value,
          style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }
}
