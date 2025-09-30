import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '/analytics/presentation/app_resources.dart';

class ChartLegend extends StatefulWidget {
  final Function(List<int>) onFiltersChanged;
  final List<int> initialActiveIndices;

  const ChartLegend({
    super.key,
    required this.onFiltersChanged,
    this.initialActiveIndices = const [0, 1, 2, 3, 4, 5],
  });

  @override
  State<ChartLegend> createState() => _ChartLegendState();
}

class _ChartLegendState extends State<ChartLegend> {
  late List<bool> _activeFilters;

  final List<String> _workoutNames = [
    'Squat',
    'Plank',
    'Push Up',
    'Shoulder Press',
    'Bicep Curl',
    'Lunges',
  ];

  final List<Color> _workoutColors = [
    AppColors.contentColorGreen,
    AppColors.contentColorPink,
    AppColors.contentColorCyan,
    Colors.orange,
    Colors.purple,
    Colors.amber,
  ];

  @override
  void initState() {
    super.initState();
    // Initialize active filters based on initial indices
    _activeFilters = List.generate(
      _workoutNames.length,
      (index) => widget.initialActiveIndices.contains(index),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      // Replace Wrap with SingleChildScrollView for horizontal scrolling
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: List.generate(
            _workoutNames.length,
            (index) => Padding(
              padding: EdgeInsets.only(
                right: index < _workoutNames.length - 1 ? 16.0 : 0.0,
              ),
              child: _legendItem(
                _workoutNames[index],
                _workoutColors[index],
                _activeFilters[index],
                index,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _legendItem(String title, Color color, bool isActive, int index) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _toggleFilter(index),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: isActive ? color : Colors.grey.shade300,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isActive ? Colors.transparent : color,
                    width: 1,
                  ),
                  boxShadow:
                      isActive
                          ? [
                            BoxShadow(
                              color: color.withAlpha((0.3 * 255).round()),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ]
                          : null,
                ),
              ),
              const SizedBox(width: 6),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 300),
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  color: isActive ? Colors.black87 : Colors.grey,
                ),
                child: Text(title),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleFilter(int index) {
    setState(() {
      _activeFilters[index] = !_activeFilters[index];

      // Notify parent about filter changes
      final List<int> activeIndices = [];
      for (int i = 0; i < _activeFilters.length; i++) {
        if (_activeFilters[i]) {
          activeIndices.add(i);
        }
      }

      widget.onFiltersChanged(activeIndices);
    });
  }
}
