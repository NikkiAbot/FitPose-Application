import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class LungesErrorClassifier {
  List<double>? _scalerMean;
  List<double>? _scalerScale;
  
  // Logistic Regression parameters
  List<double>? _coefficients;
  double? _intercept;
  List<int>? _classes; // [0, 1] where 0=correct, 1=knee-over-toe

  bool get isReady =>
      _scalerMean != null &&
      _scalerScale != null &&
      _coefficients != null &&
      _intercept != null &&
      _classes != null;

  Future<void> initialize() async {
    debugPrint('🟢 [ErrorClassifier] initialize() CALLED');
    try {
      debugPrint('🟢 [ErrorClassifier] Loading scaler...');
      // Load scaler (same as stage classifier)
      final scalerJson = await rootBundle.loadString('assets/json/lunges_scaler.json');
      final scalerData = json.decode(scalerJson);
      _scalerMean = List<double>.from(scalerData['mean']);
      _scalerScale = List<double>.from(scalerData['scale']);

      debugPrint('🟢 [ErrorClassifier] Loading Logistic Regression model...');
      // Load Logistic Regression model data
      final modelJson = await rootBundle.loadString('assets/json/lunges_error_knn.json');
      final modelData = json.decode(modelJson);

      _coefficients = List<double>.from(modelData['coefficients'][0]);
      _intercept = (modelData['intercept'] as List)[0].toDouble();
      _classes = List<int>.from(modelData['classes']);

      if (kDebugMode) {
        print('✅ Lunges Error Classifier initialized (Logistic Regression)');
        print('   - Classes: [0 (correct), 1 (knee-over-toe)]');
        print('   - Features: ${_coefficients!.length}');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('❌ Error initializing Lunges Error Classifier: $e');
        print('Stack trace: $stackTrace');
      }
      rethrow;
    }
  }

  /// Predict error using Logistic Regression
  Map<String, dynamic> predict(List<double> features) {
    if (!isReady) {
      return {'class': 'C', 'probability': 0.0};
    }

    // Standardize features
    final standardized = <double>[];
    for (int i = 0; i < features.length; i++) {
      standardized.add((features[i] - _scalerMean![i]) / _scalerScale![i]);
    }

    // Compute logit: z = intercept + sum(coefficients * features)
    double logit = _intercept!;
    for (int i = 0; i < standardized.length; i++) {
      logit += _coefficients![i] * standardized[i];
    }

    // Apply sigmoid: probability = 1 / (1 + e^(-z))
    final probability = 1.0 / (1.0 + math.exp(-logit));

    // Predict class: if probability > 0.5, class is 1 (knee-over-toe), else 0 (correct)
    final predictedClass = probability > 0.5 ? 1 : 0;
    final className = predictedClass == 1 ? 'K' : 'C';

    return {
      'class': className,
      'probability': probability,
    };
  }

  void dispose() {
    if (kDebugMode) {
      print('🗑️ Lunges Error Classifier disposed');
    }
  }
}