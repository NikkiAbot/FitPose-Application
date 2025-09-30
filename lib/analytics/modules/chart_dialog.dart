import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '/analytics/presentation/app_resources.dart';

class WorkoutDialog {
  static void showWorkoutDetailsDialog(
    BuildContext context,
    String workoutType,
    int accuracy,
    String date,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            workoutType,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.calendar_today, size: 18, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    date,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      'Posture Accuracy',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$accuracy%',
                      style: GoogleFonts.poppins(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: _getAccuracyColor(accuracy),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildAccuracyFeedback(accuracy),
            ],
          ),
          actions: [
            TextButton(
              child: Text(
                'Close',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  static Color _getAccuracyColor(int accuracy) {
    if (accuracy >= 80) return Colors.green;
    if (accuracy >= 60) return Colors.amber;
    return Colors.redAccent;
  }

  static Widget _buildAccuracyFeedback(int accuracy) {
    String message;
    IconData icon;
    Color color;

    if (accuracy >= 80) {
      message = 'Excellent form! Keep it up!';
      icon = Icons.thumb_up;
      color = Colors.green;
    } else if (accuracy >= 60) {
      message = 'Good effort! Room for improvement.';
      icon = Icons.thumbs_up_down;
      color = Colors.amber;
    } else {
      message = 'Focus on improving your form.';
      icon = Icons.warning_amber;
      color = Colors.redAccent;
    }

    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
