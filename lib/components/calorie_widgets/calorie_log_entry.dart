import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class CalorieLogEntry extends StatefulWidget {
  final Map<String, dynamic> food;
  const CalorieLogEntry({super.key, required this.food});

  static Route<bool> slideRoute(Map<String, dynamic> food) {
    return PageRouteBuilder<bool>(
      pageBuilder: (c, a, s) => CalorieLogEntry(food: food),
      transitionsBuilder: (c, a, s, child) {
        final tween = Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOutCubic));
        return SlideTransition(position: a.drive(tween), child: child);
      },
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 250),
    );
  }

  @override
  State<CalorieLogEntry> createState() => _CalorieLogEntryState();
}

class _CalorieLogEntryState extends State<CalorieLogEntry> {
  final TextEditingController dateController = TextEditingController();
  final TextEditingController timeController = TextEditingController();
  final TextEditingController servingsController = TextEditingController(
    text: '1',
  );
  final TextEditingController customGramController = TextEditingController();
  String _customUnit = 'g'; // g, mg, ml, L, cup, tbsp, tsp

  bool _loadingDetail = true;
  List<_PortionOption> _portionOptions = [];
  _PortionOption? _selectedPortion;
  double? _kcalPer100g; // derived baseline
  double? _totalGrams; // servings * portion grams
  double? _totalKcal; // computed intake
  double? _kcalPerServing; // calories for ONE serving (portion or custom unit)
  bool _usingCustom = false;
  _UnitConverter _unitConverter = _UnitConverter();
  String? _disabledReason; // explains why Add button is disabled

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    dateController.text = now.toIso8601String().split('T').first;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      timeController.text = TimeOfDay.fromDateTime(now).format(context);
    });
    _fetchDetail();
  }

  Future<void> _fetchDetail() async {
    final fdcId = widget.food['fdcId'];
    if (fdcId == null) {
      // Fall back to minimal normalization if no fdcId
      _deriveBaselineFromSummary(widget.food);
      setState(() {
        _loadingDetail = false;
      });
      return;
    }
    try {
      final url = Uri.parse(
        'https://api.nal.usda.gov/fdc/v1/food/$fdcId?api_key=KGNooTXUxdwG2I77l5AYAyDBLZU8firI8fEoAl5U',
      );
      final resp = await http.get(url);
      if (resp.statusCode == 200) {
        final detail = jsonDecode(resp.body) as Map<String, dynamic>;
        // detail stored locally if needed for future expansion
        _deriveBaselineFromDetail(detail, widget.food);
      } else {
        _deriveBaselineFromSummary(widget.food); // fallback
      }
    } catch (_) {
      _deriveBaselineFromSummary(widget.food);
    }
    if (mounted) {
      setState(() {
        _loadingDetail = false;
      });
    }
  }

  void _deriveBaselineFromSummary(Map<String, dynamic> food) {
    // Extract calorie value
    final nutrients = food['foodNutrients'] as List<dynamic>? ?? [];
    double? kcalValue;
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
      final v = (n['value'] ?? n['amount']);
      if (v is num) {
        kcalValue = v.toDouble();
        break;
      }
    }
    // Determine if value is per serving or per 100g
    final servingSize = food['servingSize'];
    final servingUnit = food['servingSizeUnit'];
    if (servingSize is num &&
        servingUnit is String &&
        servingUnit.toLowerCase() == 'g') {
      final grams = servingSize.toDouble();
      _kcalPer100g =
          (kcalValue != null && grams > 0) ? (kcalValue / grams) * 100 : null;
      // Add portion option from serving
      _portionOptions = [
        _PortionOption(
          label: '${grams.toStringAsFixed(0)} g (serving)',
          gramWeight: grams,
        ),
      ];
      _selectedPortion = _portionOptions.first;
    } else {
      // Assume analytic dataset per 100g
      _kcalPer100g = kcalValue;
      if (kcalValue != null) {
        // Create a synthetic 100g portion
        _portionOptions = [_PortionOption(label: '100 g', gramWeight: 100)];
        // Auto-switch to custom since there is no portion information
        _usingCustom = true;
        _selectedPortion = null;
        _customUnit = 'g';
        if (customGramController.text.trim().isEmpty) {
          customGramController.text = '100';
        }
      }
    }
    _recomputeTotals();
  }

  void _deriveBaselineFromDetail(
    Map<String, dynamic> detail,
    Map<String, dynamic> summary,
  ) {
    // 1. Extract calories
    // 1a. Label calories (per serving) when available (Branded)
    double? kcalPerServingFromLabel;
    final label = summary['labelNutrients'];
    if (label is Map && label['calories'] is Map) {
      final v = label['calories']['value'];
      if (v is num) kcalPerServingFromLabel = v.toDouble();
    }
    // 1b. Per-100g from detail (amount field is typically per 100 g)
    double? kcalPer100gFromDetail;
    final nutrients = detail['foodNutrients'] as List<dynamic>? ?? [];
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

    // 2. Build portion list (concise labels)
    final portions = detail['foodPortions'] as List<dynamic>? ?? [];
    final opts = <_PortionOption>[];
    final uc = _UnitConverter();
    bool hadAnyPortion = false;
    for (final p in portions) {
      if (p is! Map) continue;
      final gramWeight = p['gramWeight'];
      if (gramWeight is! num || gramWeight <= 0) continue;
      hadAnyPortion = true;
      final measureUnit = p['measureUnit'] as Map?; // {name: cup}
      final amount =
          (p['amount'] is num) ? (p['amount'] as num).toDouble() : 1.0;
      final unitName = measureUnit != null ? measureUnit['name'] : null;

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

      final qtyStr = amount == 1.0 ? '1' : _trimTrailingZeros(amount);
      final labelStr =
          normalizedUnit.isEmpty
              ? '${gramWeight.toString()} g'
              : '$qtyStr $normalizedUnit (${gramWeight.toString()} g)';
      opts.add(
        _PortionOption(label: labelStr, gramWeight: gramWeight.toDouble()),
      );

      // density inference
      final grams = gramWeight.toDouble();
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

    // 3. Add serving size (Branded) if present
    final servingSize = summary['servingSize'];
    final servingUnit = summary['servingSizeUnit'];
    bool hadServing = false;
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
      // Prefer per-100g from detail; otherwise derive from label per-serving
      if (kcalPer100gFromDetail != null) {
        _kcalPer100g = kcalPer100gFromDetail;
      } else {
        _kcalPer100g =
            (kcalPerServingFromLabel != null && grams > 0)
                ? (kcalPerServingFromLabel / grams) * 100
                : null;
      }
      hadServing = true;
    }

    // 4. Establish baseline kcal/100g if still null
    _kcalPer100g ??= kcalPer100gFromDetail; // true per-100g when available
    // As a last resort (e.g., Foundation/SR listings), try summary nutrients
    if (_kcalPer100g == null) {
      // summary foodNutrients often carry per-100g values for analytic datasets
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

    // 5. Fallback portion if none
    if (opts.isEmpty && _kcalPer100g != null) {
      opts.add(_PortionOption(label: '100 g', gramWeight: 100));
    }
    _portionOptions = opts;
    if (_portionOptions.isNotEmpty) _selectedPortion = _portionOptions.first;

    // 5.1 Auto-switch to custom if there was no portion info and no serving size
    if (!hadAnyPortion && !hadServing) {
      _usingCustom = true;
      _selectedPortion = null;
      _customUnit = 'g';
      if (customGramController.text.trim().isEmpty) {
        customGramController.text = '100';
      }
    }

    // 6. Fill in missing density using simple conversions if any density known
    if (uc.gramsPerMl == null && uc.gramsPerCup != null) {
      uc.gramsPerMl = uc.gramsPerCup! / 240.0;
    }
    if (uc.gramsPerMl == null && uc.gramsPerTbsp != null) {
      uc.gramsPerMl = uc.gramsPerTbsp! / 15.0;
    }
    if (uc.gramsPerMl == null && uc.gramsPerTsp != null) {
      uc.gramsPerMl = uc.gramsPerTsp! / 5.0;
    }
    if (uc.gramsPerMl != null) {
      uc.gramsPerCup ??= uc.gramsPerMl! * 240.0;
      uc.gramsPerTbsp ??= uc.gramsPerMl! * 15.0;
      uc.gramsPerTsp ??= uc.gramsPerMl! * 5.0;
    }
    _unitConverter = uc;
    // 6.1 Append synthetic portion options based on available conversions
    _appendSyntheticPortions(opts, uc);
    // 6.2 Sort portions by descending gram weight
    opts.sort((a, b) => b.gramWeight.compareTo(a.gramWeight));
    _recomputeTotals();
  }

  String _trimTrailingZeros(double v) {
    if (v % 1 == 0) return v.toInt().toString();
    // Limit to 3 decimals, then strip trailing zeros
    String s = v.toStringAsFixed(3);
    while (s.contains('.') && s.endsWith('0')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    return s;
  }

  void _appendSyntheticPortions(List<_PortionOption> opts, _UnitConverter uc) {
    // Helper to avoid near-duplicate gram weights
    bool existsCloseTo(double grams) =>
        opts.any((o) => (o.gramWeight - grams).abs() < 0.01);
    void add(String label, double grams) {
      if (grams > 0 && !existsCloseTo(grams)) {
        opts.add(_PortionOption(label: label, gramWeight: grams));
      }
    }

    // Mass-based options are always valid
    for (final g in [500.0, 250.0, 100.0, 50.0, 10.0]) {
      add('${g.toStringAsFixed(0)} g', g);
    }

    // Volume-based options only if density known
    if (uc.gramsPerMl != null) {
      final gPerMl = uc.gramsPerMl!;
      final mlOptions = [1000.0, 500.0, 250.0, 100.0]; // L, 500ml, 250ml, 100ml
      for (final ml in mlOptions) {
        final grams = gPerMl * ml;
        final label =
            ml == 1000.0
                ? '1 L (${grams.toStringAsFixed(0)} g)'
                : '${ml.toStringAsFixed(0)} ml (${grams.toStringAsFixed(0)} g)';
        add(label, grams);
      }
    }

    if (uc.gramsPerCup != null) {
      final gPerCup = uc.gramsPerCup!;
      final cupFractions = [1.0, 0.5, 0.25];
      for (final f in cupFractions) {
        final grams = gPerCup * f;
        final qty = (f == 1.0) ? '1' : _trimTrailingZeros(f);
        add('$qty cup (${grams.toStringAsFixed(0)} g)', grams);
      }
    }

    if (uc.gramsPerTbsp != null) {
      final g = uc.gramsPerTbsp!;
      add('1 tbsp (${g.toStringAsFixed(0)} g)', g);
    }
    if (uc.gramsPerTsp != null) {
      final g = uc.gramsPerTsp!;
      add('1 tsp (${g.toStringAsFixed(0)} g)', g);
    }
  }

  void _recomputeTotals() {
    final servings = double.tryParse(servingsController.text) ?? 1.0;
    _disabledReason = null; // reset
    double? grams;
    double? gramsPerServing;
    if (_usingCustom) {
      gramsPerServing = _gramsFromCustomUnit();
      grams = gramsPerServing;
    } else {
      gramsPerServing = _selectedPortion?.gramWeight;
      grams = gramsPerServing;
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
    } else if (_usingCustom && (customGramController.text.trim().isEmpty)) {
      _totalGrams = null;
      _totalKcal = null;
      _kcalPerServing = null;
      _disabledReason = 'Enter a quantity for the custom unit.';
    } else if (grams == null) {
      // Could not derive grams (likely missing density for volume unit)
      _totalGrams = null;
      _totalKcal = null;
      _kcalPerServing = null;
      if (_usingCustom) {
        _disabledReason =
            'Cannot convert $_customUnit to grams for this food. Switch to grams or another unit.';
      } else {
        _disabledReason = 'Select a portion size.';
      }
    } else {
      _totalGrams = grams * servings;
      _totalKcal = (_kcalPer100g! * _totalGrams!) / 100.0;
      if (gramsPerServing != null) {
        _kcalPerServing = (_kcalPer100g! * gramsPerServing) / 100.0;
      } else {
        _kcalPerServing = null;
      }
    }
    setState(() {}); // trigger rebuild for preview
  }

  double? _gramsFromCustomUnit() {
    final qty = double.tryParse(customGramController.text);
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

  Future<void> _pickDate() async {
    final init = DateTime.tryParse(dateController.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        dateController.text = picked.toIso8601String().split('T').first;
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        timeController.text = picked.format(context);
      });
    }
  }

  Future<void> _save() async {
    final logData = {
      "food": widget.food['description'],
      "fdcId": widget.food['fdcId'],
      "selectedPortion":
          _usingCustom
              ? {
                "label": "Custom grams",
                "gramWeight": double.tryParse(customGramController.text) ?? 0,
              }
              : _selectedPortion?.toJson(),
      "servings": double.tryParse(servingsController.text) ?? 1.0,
      "totalGrams": _totalGrams ?? 0,
      // Persist both total and per-serving calorie info for downstream UI accuracy
      "calories":
          _totalKcal != null ? _totalKcal!.round() : 0, // legacy field (total)
      "totalKcal": _totalKcal, // double precision
      "kcalPerServing": _kcalPerServing,
      "gramsPerServing":
          _usingCustom ? _gramsFromCustomUnit() : _selectedPortion?.gramWeight,
      "usingCustom": _usingCustom,
      "customUnit": _usingCustom ? _customUnit : null,
      "customQuantity":
          _usingCustom ? double.tryParse(customGramController.text) : null,
      "kcalPer100gBaseline": _kcalPer100g,
      "date": dateController.text,
      "time": timeController.text,
      "timestamp": FieldValue.serverTimestamp(),
      "userId": FirebaseAuth.instance.currentUser?.uid,
    };
    await FirebaseFirestore.instance.collection('calorie_logs').add(logData);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final food = widget.food;

    return Scaffold(
      appBar: AppBar(title: Text('Log Entry', style: GoogleFonts.poppins())),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              food['description'],
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            _loadingDetail
                ? const Padding(
                  padding: EdgeInsets.only(top: 8.0, bottom: 8),
                  child: LinearProgressIndicator(minHeight: 4),
                )
                : _buildCalorieSummary(),
            const Divider(height: 32),
            if (!_loadingDetail) ...[
              LayoutBuilder(
                builder: (context, constraints) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Portion dropdown
                      Expanded(
                        flex: 7,
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
                                  maxLines: 1,
                                ),
                              ),
                            ),
                            DropdownMenuItem(
                              value: null,
                              child: Text(
                                'Custom (grams)',
                                style: GoogleFonts.poppins(),
                                overflow: TextOverflow.ellipsis,
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
                      // Servings input
                      Expanded(
                        flex: 3,
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
                  );
                },
              ),
              const SizedBox(height: 12),
              if (_usingCustom)
                Row(
                  children: [
                    Expanded(
                      flex: 5,
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
                      flex: 5,
                      child: TextFormField(
                        controller: customGramController,
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
                const SizedBox(height: 12),
                Text(
                  'Total: ${_totalGrams!.toStringAsFixed(0)} g',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                ),
                if (_totalKcal != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Intake: ${_trimTrailingZeros(double.tryParse(servingsController.text) ?? 1.0)} x ${_formatPortionServing()} = ${_totalKcal!.toStringAsFixed(0)} kcal',
                    style: GoogleFonts.poppins(color: Colors.grey[700]),
                  ),
                ],
              ],
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: dateController,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Date',
                border: OutlineInputBorder(),
              ),
              onTap: _pickDate,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: timeController,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Time',
                border: OutlineInputBorder(),
              ),
              onTap: _pickTime,
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check),
                label: Text(
                  _totalKcal != null
                      ? 'Add ${_totalKcal!.toStringAsFixed(0)} kcal'
                      : 'Add Calories',
                  style: GoogleFonts.poppins(),
                ),
                onPressed: _totalKcal != null ? _save : null,
              ),
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
        // If only 1 serving and we already show per serving, avoid duplication
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

  String _formatPortionServing() {
    if (_usingCustom) {
      final qty =
          customGramController.text.trim().isEmpty
              ? '0'
              : customGramController.text.trim();
      final grams = _gramsFromCustomUnit();
      final gramsStr = grams != null ? '${grams.toStringAsFixed(0)} g' : 'g?';
      return '$qty $_customUnit ($gramsStr)';
    } else {
      return _selectedPortion?.label ?? 'portion';
    }
  }
}

class _PortionOption {
  final String label;
  final double gramWeight; // grams for ONE serving of this portion
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
