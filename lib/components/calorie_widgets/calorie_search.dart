import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'calorie_log_entry.dart';

class CalorieSearch extends StatefulWidget {
  const CalorieSearch({super.key});

  // Slide-in route helper
  static Route<void> slideRoute() {
    return PageRouteBuilder<void>(
      pageBuilder:
          (context, animation, secondaryAnimation) => const CalorieSearch(),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final tween = Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOutCubic));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 250),
    );
  }

  @override
  State<CalorieSearch> createState() => _CalorieSearchState();
}

class _CalorieSearchState extends State<CalorieSearch> {
  final TextEditingController searchController = TextEditingController();

  // Retain raw API results and a normalized, ranked view for display
  List<Map<String, dynamic>> _searchResults = [];
  List<NormalizedFood> _normalizedResults = [];
  bool isLoading = false;
  bool _hasSearched = false; // track if at least one search attempted

  // NEW: paging state
  static const int _pageSize = 5;
  int _pageNumber = 1;
  bool _hasMore = false;
  bool _isMoreLoading = false;

  // UPDATED: support paging via reset flag and normalize+rank results
  Future<void> searchFood({bool reset = true}) async {
    final query = searchController.text.trim();
    if (query.isEmpty) return;

    if (reset) {
      setState(() {
        isLoading = true;
        _hasSearched = true;
        _pageNumber = 1;
        _hasMore = false;
        _searchResults = [];
        _normalizedResults = [];
      });
    } else {
      if (_isMoreLoading || !_hasMore) return;
      setState(() => _isMoreLoading = true);
    }

    final currentPage = _pageNumber;

    final response = await http.post(
      Uri.parse(
        "https://api.nal.usda.gov/fdc/v1/foods/search?api_key=KGNooTXUxdwG2I77l5AYAyDBLZU8firI8fEoAl5U",
      ),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "query": query,
        "pageSize": _pageSize,
        "pageNumber": currentPage,
        // Keep dataType broad for now; can be filtered in UI later if needed
        // "dataType": ["Foundation", "Branded"],
      }),
    );

    if (!mounted) return;

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final foodsDynamic = (data['foods'] ?? []) as List<dynamic>;
      final foods = foodsDynamic.whereType<Map<String, dynamic>>().toList();

      // Normalize and filter only this batch
      List<NormalizedFood> batch =
          foods
              .map(normalizeFood)
              .where(
                (nf) => (nf.kcalPerServing != null || nf.kcalPer100g != null),
              )
              .toList();
      // Keep batch A→Z for readability, but do not reorder existing items when appending
      batch.sort(
        (a, b) =>
            a.description.toLowerCase().compareTo(b.description.toLowerCase()),
      );

      setState(() {
        // If we got a full page, more may be available
        if (foods.length == _pageSize) {
          _hasMore = true;
          _pageNumber = currentPage + 1;
        } else {
          _hasMore = false;
        }

        if (reset) {
          _searchResults = foods; // keep raw for reference
          _normalizedResults = batch; // replace with first page
        } else {
          _searchResults.addAll(foods);
          // Append new items while preserving already visible order and avoiding duplicates
          final existingIds = _normalizedResults.map((e) => e.fdcId).toSet();
          for (final nf in batch) {
            if (!existingIds.contains(nf.fdcId)) {
              _normalizedResults.add(nf);
            }
          }
        }
      });
    }

    setState(() {
      if (reset) {
        isLoading = false;
      } else {
        _isMoreLoading = false;
      }
    });
  }

  // Function to show feedback Snackbar
  void showFeedback(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: GoogleFonts.poppins())),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Convert dialog to a full-screen page
    return Scaffold(
      appBar: AppBar(
        title: Text("Log Calorie Intake", style: GoogleFonts.poppins()),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Search for a food item:", style: GoogleFonts.poppins()),
            const SizedBox(height: 10),
            TextField(
              controller: searchController,
              decoration: const InputDecoration(
                hintText: "e.g., Cheddar Cheese",
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => searchFood(reset: true),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () => searchFood(reset: true),
              child: Text("Search", style: GoogleFonts.poppins()),
            ),
            if (isLoading) ...[
              const SizedBox(height: 12),
              const Center(child: CircularProgressIndicator()),
            ],
            if (!isLoading && _normalizedResults.isNotEmpty) ...[
              const SizedBox(height: 10),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _normalizedResults.length,
                itemBuilder: (context, index) {
                  final nf = _normalizedResults[index];
                  return ListTile(
                    title: Text(
                      '${nf.description} (${nf.dataType})',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      _formatSubtitle(nf),
                      style: GoogleFonts.poppins(color: Colors.grey),
                    ),
                    onTap: () async {
                      final logged = await Navigator.of(
                        context,
                      ).push<bool>(CalorieLogEntry.slideRoute(nf.raw));
                      if (logged == true && context.mounted) {
                        Navigator.of(context).pop(true);
                      }
                    },
                  );
                },
              ),
              // NEW: "Show more" control
              const SizedBox(height: 8),
              if (_hasMore)
                Center(
                  child:
                      _isMoreLoading
                          ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                          : TextButton.icon(
                            onPressed: () => searchFood(reset: false),
                            icon: const Icon(Icons.expand_more),
                            label: Text(
                              "Show more",
                              style: GoogleFonts.poppins(),
                            ),
                          ),
                ),
            ],
            if (!isLoading && _hasSearched && _normalizedResults.isEmpty) ...[
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No results with calorie info. Try a different keyword or pick a Foundation/SR Legacy/Branded item.',
                      style: GoogleFonts.poppins(),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatSubtitle(NormalizedFood nf) {
    final parts = <String>[];
    if (nf.kcalPerServing != null && nf.servingLabel != null) {
      parts.add(
        '${nf.kcalPerServing!.toStringAsFixed(0)} kcal (${nf.servingLabel})',
      );
    }
    if (nf.kcalPer100g != null) {
      parts.add('${nf.kcalPer100g!.toStringAsFixed(0)} kcal / 100 g');
    }
    if (parts.isEmpty) return 'No kcal info';
    return parts.join(' • ');
  }
}

// ---------------- Normalization / Ranking Helpers ----------------

class NormalizedFood {
  final int fdcId;
  final String description;
  final String dataType;
  final double? kcalPerServing;
  final double? servingSizeG;
  final double? kcalPer100g;
  final String? servingLabel;
  final Map<String, dynamic> raw; // original map for navigation/logging

  NormalizedFood({
    required this.fdcId,
    required this.description,
    required this.dataType,
    required this.raw,
    this.kcalPerServing,
    this.servingSizeG,
    this.kcalPer100g,
    this.servingLabel,
  });
}

double? _extractEnergyKcal(Map<String, dynamic> food) {
  // Try labelNutrients first (Branded)
  final label = food['labelNutrients'];
  if (label is Map && label['calories'] is Map) {
    final v = label['calories']['value'];
    if (v is num) return v.toDouble();
  }
  // Fallback to foodNutrients
  final list = food['foodNutrients'];
  if (list is List) {
    final match = list.firstWhere(
      (n) =>
          n is Map &&
          (n['nutrientId'] == 1008 ||
              (n['nutrientName'] == 'Energy' && n['unitName'] == 'KCAL')),
      orElse: () => null,
    );
    if (match is Map && match['value'] is num) {
      return (match['value'] as num).toDouble();
    }
  }
  return null;
}

NormalizedFood normalizeFood(Map<String, dynamic> food) {
  final dataType = (food['dataType'] as String?) ?? '';
  final desc = (food['description'] as String?) ?? 'Unknown';
  final fdcId = (food['fdcId'] as int?) ?? -1;
  final kcal = _extractEnergyKcal(food);

  double? servingSizeG;
  String? servingLabel;
  double? kcalPerServing = kcal;
  double? kcalPer100g;

  final servingSize = food['servingSize'];
  final servingUnit = food['servingSizeUnit'];

  if (servingSize is num && servingUnit is String) {
    if (servingUnit.toLowerCase() == 'g') {
      servingSizeG = servingSize.toDouble();
      if (kcal != null) {
        kcalPer100g = servingSizeG > 0 ? (kcal / servingSizeG) * 100 : null;
      }
      servingLabel = '${servingSizeG.toStringAsFixed(0)} g';
    } else {
      servingLabel = '${servingSize.toString()} $servingUnit';
    }
  }

  // Assume analytic datasets without serving info are per 100 g
  if (servingSizeG == null &&
      (dataType == 'Foundation' ||
          dataType == 'SR Legacy' ||
          dataType == 'Survey (FNDDS)')) {
    kcalPer100g = kcal;
    kcalPerServing = null;
  }

  return NormalizedFood(
    fdcId: fdcId,
    description: desc,
    dataType: dataType,
    raw: food,
    kcalPerServing: kcalPerServing,
    servingSizeG: servingSizeG,
    kcalPer100g: kcalPer100g,
    servingLabel: servingLabel,
  );
}

int _rankForQuery(NormalizedFood f, String query) {
  final q = query.toLowerCase();
  final d = f.description.toLowerCase();
  int score = 0;

  // DataType weighting
  switch (f.dataType) {
    case 'Foundation':
      score += 500;
      break;
    case 'SR Legacy':
      score += 400;
      break;
    case 'Survey (FNDDS)':
      score += 300;
      break;
    case 'Branded':
      score += 200;
      break;
    case 'Experimental':
      score += 100;
      break;
  }

  // Query word presence
  if (d.contains(q)) score += 100;

  // Egg-specific heuristics when query includes 'egg'
  if (q.contains('egg')) {
    if (d.contains('whole')) score += 80;
    if (d.contains('raw')) score += 60;
    if (d.contains('fresh')) score += 40;
    if (d.contains('powder') ||
        d.contains('white only') ||
        d.contains('yolk only')) {
      score -= 120;
    }
    if (d.contains('scrambled') ||
        d.contains('omelet') ||
        d.contains('omelette')) {
      score -= 60;
    }
    if (f.kcalPer100g != null) {
      final diff = (f.kcalPer100g! - 147).abs();
      score += (80 - diff).round().clamp(0, 80);
    }
  }

  return score;
}

void rankNormalizedFoods(List<NormalizedFood> list, String query) {
  list.sort(
    (a, b) => _rankForQuery(b, query).compareTo(_rankForQuery(a, query)),
  );
}

// (Previous calorie-based sort helper removed after switching to name-based sort.)
