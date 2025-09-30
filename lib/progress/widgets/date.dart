import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DatePicker extends StatelessWidget {
  final DateTime selectedDate;
  final Function(DateTime) onDateSelected;

  const DatePicker({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
    required DateTime initialDate,
    required Null Function(dynamic selectedDate) onDateSelection,
    required bool disableFutureDates,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 1),
      child: Row(
        children: [
          const Text("Select Date:"),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () async {
              final DateTime? picked = await showDatePicker(
                context: context,
                initialDate: selectedDate,
                firstDate: DateTime(2024),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                onDateSelected(picked);
              }
            },
            child: Text(DateFormat('yMMMd').format(selectedDate)),
          ),
        ],
      ),
    );
  }
}
