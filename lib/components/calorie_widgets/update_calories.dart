import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class CalorieUpdate extends StatefulWidget {
  final String docId;
  final String initialFood; // Add this parameter
  final int initialCalories;
  final String initialDate;
  final String initialTime;
  final Map<String, dynamic> existingData;

  const CalorieUpdate({
    super.key,
    required this.docId,
    required this.initialFood, // Add this parameter
    required this.initialCalories,
    required this.initialDate,
    required this.initialTime,
    required this.existingData,
  });

  @override
  State<CalorieUpdate> createState() => _CalorieUpdateState();
}

class _CalorieUpdateState extends State<CalorieUpdate> {
  // General controllers
  final TextEditingController searchController = TextEditingController();
  final TextEditingController dateController = TextEditingController();
  final TextEditingController timeController = TextEditingController();
  final TextEditingController servingsController = TextEditingController(
    text: '1',
  );
  final TextEditingController customQtyController = TextEditingController();

  // Search dialog state
  List<dynamic> searchResults = [];
  bool isSearching = false;

  // Food + portion/calculation state (parity with log entry)
  Map<String, dynamic>? _foodSummary; // holds description, fdcId, etc.
  bool _loadingDetail = true;
  List<_PortionOption> _portionOptions = [];
  _PortionOption? _selectedPortion;
  bool _usingCustom = false;
  String _customUnit = 'g';
  _UnitConverter _unitConverter = _UnitConverter();
  double? _kcalPer100g;
  double? _kcalPerServing;
  double? _totalGrams;
  double? _totalKcal;
  String? _disabledReason;

  // Preselection helpers from existing data
  double? _prefServings;
  double? _prefGramsPerServing;
  bool? _prefUsingCustom;
  String? _prefCustomUnit;
  double? _prefCustomQuantity;

  @override
  void initState() {
    super.initState();
    // Initialize form values from existing data
    searchController.text = widget.existingData['food'] ?? widget.initialFood;
    dateController.text = widget.existingData['date'] ?? widget.initialDate;
    timeController.text = widget.existingData['time'] ?? widget.initialTime;

    // Pre-fill preferred values for selection
    _prefServings =
        (widget.existingData['servings'] is num)
            ? (widget.existingData['servings'] as num).toDouble()
            : 1.0;
    servingsController.text = (_prefServings ?? 1.0).toString();
    _prefGramsPerServing =
        (widget.existingData['gramsPerServing'] is num)
            ? (widget.existingData['gramsPerServing'] as num).toDouble()
            : null;
    _prefUsingCustom = widget.existingData['usingCustom'] as bool?;
    _prefCustomUnit = widget.existingData['customUnit'] as String?;
    _prefCustomQuantity =
        (widget.existingData['customQuantity'] is num)
            ? (widget.existingData['customQuantity'] as num).toDouble()
            : null;

    // Prepare initial food summary
    final fdcId = widget.existingData['fdcId'];
    _foodSummary = {
      'description': searchController.text,
      if (fdcId != null) 'fdcId': fdcId,
      // attempt to carry serving hints if present
      if (widget.existingData['servingSize'] != null)
        'servingSize': widget.existingData['servingSize'],
      if (widget.existingData['servingSizeUnit'] != null)
        'servingSizeUnit': widget.existingData['servingSizeUnit'],
      if (widget.existingData['foodNutrients'] != null)
        'foodNutrients': widget.existingData['foodNutrients'],
    };

    // Try fast baseline from stored fields
    final baseline = widget.existingData['kcalPer100gBaseline'];
    if (baseline is num) {
      _kcalPer100g = baseline.toDouble();
      _loadingDetail = false;
      // With baseline, derive minimal portion options (we will refine by fetching detail if fdcId exists)
      _portionOptions = [];
      _selectedPortion = null;
      // Defer portion options until detail fetch completes
    }

    // Fetch detail (or derive from summary) to build full options
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchAndDerive();
    });
  }

  Future<List<dynamic>> searchFood() async {
    try {
      final response = await http.post(
        Uri.parse(
          "https://api.nal.usda.gov/fdc/v1/foods/search?api_key=KGNooTXUxdwG2I77l5AYAyDBLZU8firI8fEoAl5U",
        ),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"query": searchController.text, "pageSize": 5}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['foods'] ?? [];
      } else {
        if (kDebugMode) {
          print('API Error: ${response.statusCode} - ${response.body}');
        }
        return [];
      }
    } catch (e) {
      if (kDebugMode) {
        print('Exception during API call: $e');
      }
      return [];
    }
  }

  Future<void> pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(dateController.text) ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      dateController.text = picked.toIso8601String().split("T").first;
    }
  }

  Future<void> pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null && mounted) {
      timeController.text = picked.format(context);
    }
  }

  Future<void> _fetchAndDerive() async {
    setState(() => _loadingDetail = true);
    final summary = _foodSummary ?? {};
    final fdcId = summary['fdcId'];
    Map<String, dynamic>? detail;
    if (fdcId != null) {
      try {
        final url = Uri.parse(
          'https://api.nal.usda.gov/fdc/v1/food/$fdcId?api_key=KGNooTXUxdwG2I77l5AYAyDBLZU8firI8fEoAl5U',
        );
        final resp = await http.get(url);
        if (resp.statusCode == 200) {
          detail = jsonDecode(resp.body) as Map<String, dynamic>;
        }
      } catch (_) {}
    }
    _deriveFromData(detail: detail, summary: summary);
    setState(() => _loadingDetail = false);
  }

  void _deriveFromData({
    Map<String, dynamic>? detail,
    required Map<String, dynamic> summary,
  }) {
    // Extract kcal baselines similar to log entry
    double? kcalPerServingFromLabel;
    final label = summary['labelNutrients'];
    if (label is Map && label['calories'] is Map) {
      final v = label['calories']['value'];
      if (v is num) kcalPerServingFromLabel = v.toDouble();
    }

    double? kcalPer100gFromDetail;
    final nutrients =
        (detail != null ? detail['foodNutrients'] : summary['foodNutrients'])
            as List<dynamic>? ??
        [];
    for (final n in nutrients) {
      if (n is! Map) continue;
      final isEnergy =
          n['nutrientId'] == 1008 ||
          (n['nutrientName'] == 'Energy' && n['unitName'] == 'KCAL') ||
          ((n['nutrient'] is Map) &&
              (((n['nutrient']['id']) == 1008) ||
                  (n['nutrient']['number'] == '208') ||
                  (n['nutrient']['name'] == 'Energy')));
      if (!isEnergy) continue;
      final v = (n['amount'] ?? n['value']);
      if (v is num) {
        kcalPer100gFromDetail = v.toDouble();
        break;
      }
    }

    // Build portion options from detail if available
    final opts = <_PortionOption>[];
    final uc = _UnitConverter();
    final portions = (detail?['foodPortions'] as List<dynamic>?) ?? [];
    for (final p in portions) {
      if (p is! Map) continue;
      final gramWeight = p['gramWeight'];
      if (gramWeight is! num || gramWeight <= 0) continue;
      final amount =
          (p['amount'] is num) ? (p['amount'] as num).toDouble() : 1.0;
      final mu = p['measureUnit'] as Map?;
      final unitName = mu != null ? mu['name'] : null;
      String normalizedUnit = '';
      if (unitName is String) {
        final u = unitName.toLowerCase();
        if (u.contains('tablespoon') || u.contains('tbsp')) {
          normalizedUnit = 'tbsp';
        } else if (u.contains('teaspoon') || u.contains('tsp')) {
          normalizedUnit = 'tsp';
        } else if (u.contains('cup')) {
          normalizedUnit = 'cup';
        } else if (u == 'ml' ||
            u.contains('milliliter') ||
            u.contains('millilitre')) {
          normalizedUnit = 'ml';
        } else if (u == 'l' || u.contains('liter') || u.contains('litre')) {
          normalizedUnit = 'L';
        } else if (u.contains('gram')) {
          normalizedUnit = 'g';
        } else if (u.contains('milligram')) {
          normalizedUnit = 'mg';
        } else {
          normalizedUnit = unitName.trim();
        }
      }
      final grams = (gramWeight).toDouble();
      final qtyStr = amount == 1.0 ? '1' : _trimTrailingZeros(amount);
      final labelStr =
          normalizedUnit.isEmpty
              ? '${grams.toString()} g'
              : '$qtyStr $normalizedUnit (${grams.toString()} g)';
      opts.add(_PortionOption(label: labelStr, gramWeight: grams));

      final perUnit = amount > 0 ? grams / amount : grams;
      switch (normalizedUnit) {
        case 'cup':
          uc.gramsPerCup ??= perUnit;
          break;
        case 'tbsp':
          uc.gramsPerTbsp ??= perUnit;
          break;
        case 'tsp':
          uc.gramsPerTsp ??= perUnit;
          break;
        case 'ml':
          uc.gramsPerMl ??= perUnit;
          break;
        case 'L':
          uc.gramsPerMl ??= perUnit / 1000.0;
          break;
      }
    }

    // Serving size hint from summary
    final servingSize = summary['servingSize'];
    final servingUnit = summary['servingSizeUnit'];
    if (servingSize is num &&
        servingUnit is String &&
        servingUnit.toLowerCase() == 'g') {
      final grams = servingSize.toDouble();
      final exists = opts.any((o) => (o.gramWeight - grams).abs() < 0.01);
      if (!exists) {
        opts.insert(
          0,
          _PortionOption(
            label: '1 serving (${grams.toStringAsFixed(0)} g)',
            gramWeight: grams,
          ),
        );
      }
      if (kcalPer100gFromDetail != null) {
        _kcalPer100g = kcalPer100gFromDetail;
      } else {
        _kcalPer100g =
            (kcalPerServingFromLabel != null && grams > 0)
                ? (kcalPerServingFromLabel / grams) * 100
                : _kcalPer100g; // keep previous if already set
      }
    }

    // Establish baseline if still null
    _kcalPer100g ??= kcalPer100gFromDetail;
    if (_kcalPer100g == null) {
      // Try summary nutrients for analytic datasets
      final summaryNutrients = summary['foodNutrients'] as List<dynamic>? ?? [];
      for (final n in summaryNutrients) {
        if (n is! Map) continue;
        final isEnergy =
            n['nutrientId'] == 1008 ||
            (n['nutrientName'] == 'Energy' && n['unitName'] == 'KCAL') ||
            ((n['nutrient'] is Map) &&
                (((n['nutrient']['id']) == 1008) ||
                    (n['nutrient']['number'] == '208') ||
                    (n['nutrient']['name'] == 'Energy')));
        if (!isEnergy) continue;
        final v = (n['amount'] ?? n['value']);
        if (v is num) {
          _kcalPer100g = v.toDouble();
          break;
        }
      }
    }

    // Fallback portion if none and baseline known
    if (opts.isEmpty && _kcalPer100g != null) {
      opts.add(_PortionOption(label: '100 g', gramWeight: 100));
    }

    // Copy unit converter from discovered values
    _unitConverter = uc;
    // Fill converter relationships
    if (_unitConverter.gramsPerMl == null &&
        _unitConverter.gramsPerCup != null) {
      _unitConverter.gramsPerMl = _unitConverter.gramsPerCup! / 240.0;
    }
    if (_unitConverter.gramsPerMl == null &&
        _unitConverter.gramsPerTbsp != null) {
      _unitConverter.gramsPerMl = _unitConverter.gramsPerTbsp! / 15.0;
    }
    if (_unitConverter.gramsPerMl == null &&
        _unitConverter.gramsPerTsp != null) {
      _unitConverter.gramsPerMl = _unitConverter.gramsPerTsp! / 5.0;
    }
    if (_unitConverter.gramsPerMl != null) {
      _unitConverter.gramsPerCup ??= _unitConverter.gramsPerMl! * 240.0;
      _unitConverter.gramsPerTbsp ??= _unitConverter.gramsPerMl! * 15.0;
      _unitConverter.gramsPerTsp ??= _unitConverter.gramsPerMl! * 5.0;
    }

    _portionOptions = opts;
    // Preselect portion according to existing data
    _usingCustom = _prefUsingCustom ?? false;
    _customUnit = _prefCustomUnit ?? 'g';
    if (_usingCustom) {
      customQtyController.text = (_prefCustomQuantity ?? 100).toString();
      _selectedPortion = null;
    } else {
      if (_prefGramsPerServing != null) {
        final match = _portionOptions.firstWhere(
          (o) => (o.gramWeight - _prefGramsPerServing!).abs() < 0.01,
          orElse:
              () =>
                  _portionOptions.isNotEmpty
                      ? _portionOptions.first
                      : _PortionOption(label: '100 g', gramWeight: 100),
        );
        _selectedPortion =
            _portionOptions.contains(match)
                ? match
                : (_portionOptions.isNotEmpty ? _portionOptions.first : null);
      } else {
        _selectedPortion =
            _portionOptions.isNotEmpty ? _portionOptions.first : null;
      }
    }

    _recomputeTotals();
  }

  void _recomputeTotals() {
    final servings = double.tryParse(servingsController.text) ?? 1.0;
    _disabledReason = null;
    double? gramsPerServing;
    if (_usingCustom) {
      gramsPerServing = _gramsFromCustomUnit();
    } else {
      gramsPerServing = _selectedPortion?.gramWeight;
    }

    if (_kcalPer100g == null) {
      _totalGrams = null;
      _totalKcal = null;
      _kcalPerServing = null;
      _disabledReason = 'No calorie data available for this food item.';
    } else if (servings <= 0) {
      _totalGrams = null;
      _totalKcal = null;
      _kcalPerServing = null;
      _disabledReason = 'Enter a servings value greater than 0.';
    } else if (_usingCustom && customQtyController.text.trim().isEmpty) {
      _totalGrams = null;
      _totalKcal = null;
      _kcalPerServing = null;
      _disabledReason = 'Enter a quantity for the custom unit.';
    } else if (gramsPerServing == null) {
      _totalGrams = null;
      _totalKcal = null;
      _kcalPerServing = null;
      _disabledReason =
          _usingCustom
              ? 'Cannot convert $_customUnit to grams for this food. Switch to grams or another unit.'
              : 'Select a portion size.';
    } else {
      _kcalPerServing = (_kcalPer100g! * gramsPerServing) / 100.0;
      _totalGrams = gramsPerServing * servings;
      _totalKcal = (_kcalPer100g! * _totalGrams!) / 100.0;
    }
    setState(() {});
  }

  double? _gramsFromCustomUnit() {
    final qty = double.tryParse(customQtyController.text);
    if (qty == null) return null;
    switch (_customUnit) {
      case 'g':
        return qty;
      case 'mg':
        return qty / 1000.0;
      case 'ml':
        return _unitConverter.gramsPerMl != null
            ? _unitConverter.gramsPerMl! * qty
            : null;
      case 'L':
        return _unitConverter.gramsPerMl != null
            ? _unitConverter.gramsPerMl! * (qty * 1000.0)
            : null;
      case 'cup':
        return _unitConverter.gramsPerCup != null
            ? _unitConverter.gramsPerCup! * qty
            : null;
      case 'tbsp':
        return _unitConverter.gramsPerTbsp != null
            ? _unitConverter.gramsPerTbsp! * qty
            : null;
      case 'tsp':
        return _unitConverter.gramsPerTsp != null
            ? _unitConverter.gramsPerTsp! * qty
            : null;
      default:
        return null;
    }
  }

  String _trimTrailingZeros(double v) {
    if (v % 1 == 0) return v.toInt().toString();
    String s = v.toStringAsFixed(3);
    while (s.contains('.') && s.endsWith('0')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    return s;
  }

  Future<void> _updateLog() async {
    final updateData = {
      'food': searchController.text,
      'fdcId': _foodSummary?['fdcId'],
      'selectedPortion':
          _usingCustom
              ? {
                'label': 'Custom grams',
                'gramWeight': _gramsFromCustomUnit() ?? 0,
              }
              : _selectedPortion?.toJson(),
      'servings': double.tryParse(servingsController.text) ?? 1.0,
      'totalGrams': _totalGrams ?? 0,
      'calories': _totalKcal != null ? _totalKcal!.round() : 0,
      'totalKcal': _totalKcal,
      'kcalPerServing': _kcalPerServing,
      'gramsPerServing':
          _usingCustom ? _gramsFromCustomUnit() : _selectedPortion?.gramWeight,
      'usingCustom': _usingCustom,
      'customUnit': _usingCustom ? _customUnit : null,
      'customQuantity':
          _usingCustom ? double.tryParse(customQtyController.text) : null,
      'kcalPer100gBaseline': _kcalPer100g,
      'date': dateController.text,
      'time': timeController.text,
      'timestamp': FieldValue.serverTimestamp(),
    };
    await FirebaseFirestore.instance
        .collection('calorie_logs')
        .doc(widget.docId)
        .update(updateData);
    if (!mounted) return;
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Log updated successfully!',
          style: GoogleFonts.poppins(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      title: Text('Update Log Entry', style: GoogleFonts.poppins()),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.95,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Food',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              InkWell(
                onTap: () {
                  showDialog(
                    context: context,
                    builder:
                        (_) => StatefulBuilder(
                          builder:
                              (context, setDialogState) => Dialog(
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(context).size.width * 0.9,
                                    maxHeight:
                                        MediaQuery.of(context).size.height *
                                        0.8,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Change food',
                                        style: GoogleFonts.poppins(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      TextField(
                                        controller: searchController,
                                        decoration: const InputDecoration(
                                          hintText: 'Enter food name',
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      ElevatedButton(
                                        onPressed: () async {
                                          setDialogState(
                                            () => isSearching = true,
                                          );
                                          final results = await searchFood();
                                          setDialogState(() {
                                            searchResults = results;
                                            isSearching = false;
                                          });
                                        },
                                        child: Text(
                                          'Search',
                                          style: GoogleFonts.poppins(),
                                        ),
                                      ),
                                      if (isSearching)
                                        const Center(
                                          child: Padding(
                                            padding: EdgeInsets.all(12),
                                            child: CircularProgressIndicator(),
                                          ),
                                        ),
                                      if (!isSearching &&
                                          searchResults.isNotEmpty)
                                        Expanded(
                                          child: ListView.builder(
                                            itemCount: searchResults.length,
                                            itemBuilder: (context, index) {
                                              final food =
                                                  searchResults[index]
                                                      as Map<String, dynamic>;
                                              final description =
                                                  food['description'] ?? '';
                                              return ListTile(
                                                title: Text(
                                                  description,
                                                  style: GoogleFonts.poppins(),
                                                ),
                                                onTap: () async {
                                                  setState(() {
                                                    _foodSummary = food;
                                                    searchController.text =
                                                        description;
                                                    // reset preferences so user reselects
                                                    _prefGramsPerServing = null;
                                                    _prefUsingCustom = false;
                                                    _prefCustomUnit = 'g';
                                                    _prefCustomQuantity = null;
                                                  });
                                                  Navigator.of(context).pop();
                                                  await _fetchAndDerive();
                                                },
                                              );
                                            },
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                        ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _foodSummary?['description'] ?? searchController.text,
                          style: GoogleFonts.poppins(),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.edit),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _loadingDetail
                  ? const LinearProgressIndicator(minHeight: 3)
                  : _buildCalorieSummary(),
              const SizedBox(height: 12),
              if (!_loadingDetail) ...[
                Row(
                  children: [
                    Expanded(
                      flex: 6,
                      child: DropdownButtonFormField<_PortionOption>(
                        isExpanded: true,
                        value: _usingCustom ? null : _selectedPortion,
                        decoration: const InputDecoration(
                          labelText: 'Portion',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          ..._portionOptions.map(
                            (o) => DropdownMenuItem(
                              value: o,
                              child: Text(
                                o.label,
                                style: GoogleFonts.poppins(),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DropdownMenuItem(
                            value: null,
                            child: Text(
                              'Custom (grams)',
                              style: GoogleFonts.poppins(),
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          setState(() {
                            if (val == null) {
                              _usingCustom = true;
                            } else {
                              _usingCustom = false;
                              _selectedPortion = val;
                            }
                          });
                          _recomputeTotals();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 4,
                      child: TextFormField(
                        controller: servingsController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Servings',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => _recomputeTotals(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_usingCustom)
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: _customUnit,
                          decoration: const InputDecoration(
                            labelText: 'Unit',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'g',
                              child: Text('grams (g)'),
                            ),
                            DropdownMenuItem(
                              value: 'mg',
                              child: Text('milligrams (mg)'),
                            ),
                            DropdownMenuItem(
                              value: 'ml',
                              child: Text('milliliters (ml)'),
                            ),
                            DropdownMenuItem(
                              value: 'L',
                              child: Text('liters (L)'),
                            ),
                            DropdownMenuItem(value: 'cup', child: Text('cups')),
                            DropdownMenuItem(
                              value: 'tbsp',
                              child: Text('tablespoons (tbsp)'),
                            ),
                            DropdownMenuItem(
                              value: 'tsp',
                              child: Text('teaspoons (tsp)'),
                            ),
                          ],
                          onChanged: (val) {
                            setState(() => _customUnit = val ?? 'g');
                            _recomputeTotals();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: customQtyController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Quantity (one serving)',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => _recomputeTotals(),
                        ),
                      ),
                    ],
                  ),
                if (_totalGrams != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Total: ${_totalGrams!.toStringAsFixed(0)} g',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                  ),
                  if (_totalKcal != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        'Intake: ${_trimTrailingZeros(double.tryParse(servingsController.text) ?? 1.0)} x ${_usingCustom ? '${customQtyController.text} $_customUnit' : (_selectedPortion?.label ?? 'portion')} = ${_totalKcal!.toStringAsFixed(0)} kcal',
                        style: GoogleFonts.poppins(color: Colors.grey[700]),
                      ),
                    ),
                ],
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: dateController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Date',
                  border: OutlineInputBorder(),
                ),
                onTap: pickDate,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: timeController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Time',
                  border: OutlineInputBorder(),
                ),
                onTap: pickTime,
              ),
              if (_totalKcal == null && _disabledReason != null) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.redAccent,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _disabledReason!,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.redAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: GoogleFonts.poppins()),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.check),
          onPressed: (_totalKcal != null) ? _updateLog : null,
          label: Text(
            (_totalKcal != null)
                ? 'Update ${_totalKcal!.toStringAsFixed(0)} kcal'
                : 'Update',
            style: GoogleFonts.poppins(),
          ),
        ),
      ],
    );
  }

  Widget _buildCalorieSummary() {
    final servings = double.tryParse(servingsController.text) ?? 1.0;
    final parts = <String>[];
    if (_kcalPerServing != null) {
      parts.add('Per serving: ${_kcalPerServing!.toStringAsFixed(0)} kcal');
    }
    if (_totalKcal != null) {
      if (servings > 1.0) {
        parts.add(
          'Total (${_trimTrailingZeros(servings)}): ${_totalKcal!.toStringAsFixed(0)} kcal',
        );
      } else {
        if (_kcalPerServing == null) {
          parts.add('Total: ${_totalKcal!.toStringAsFixed(0)} kcal');
        }
      }
    } else if (_kcalPer100g != null) {
      parts.add('Baseline ${_kcalPer100g!.toStringAsFixed(0)} kcal / 100 g');
    } else {
      parts.add('No calorie info available');
    }
    return Text(
      parts.join(' • '),
      style: GoogleFonts.poppins(color: Colors.grey[700]),
    );
  }
}

class _PortionOption {
  final String label;
  final double gramWeight;
  _PortionOption({required this.label, required this.gramWeight});
  Map<String, dynamic> toJson() => {'label': label, 'gramWeight': gramWeight};
}

class _UnitConverter {
  double? gramsPerMl;
  double? gramsPerCup;
  double? gramsPerTbsp;
  double? gramsPerTsp;
  _UnitConverter();
}
