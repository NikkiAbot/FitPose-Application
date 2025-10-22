import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class LungesErrorClassifier {
  List<double>? _scalerMean;
  List<double>? _scalerScale;
  
  List<List<double>>? _trainingData;
  List<String>? _trainingLabels; // ['C' (correct), 'K' (knee-over-toe)]
  int _k = 5;

  bool get isReady =>
      _scalerMean != null &&
      _scalerScale != null &&
      _trainingData != null &&
      _trainingLabels != null;

  Future<void> initialize() async {
    try {
      // Load scaler (same as stage classifier)
      final scalerJson = await rootBundle.loadString('assets/models/lunges_scaler.json');
      final scalerData = json.decode(scalerJson);
      _scalerMean = List<double>.from(scalerData['mean']);
      _scalerScale = List<double>.from(scalerData['scale']);

      // Load error KNN data
      final knnJson = await rootBundle.loadString('assets/models/lunges_error_knn.json');
      final knnData = json.decode(knnJson);
      _k = knnData['n_neighbors'] ?? 5;

      _trainingData = (knnData['training_data'] as List)
          .map((e) => List<double>.from(e))
          .toList();
      _trainingLabels = List<String>.from(knnData['training_labels']);

      if (kDebugMode) {
        print('✅ Lunges Error Classifier initialized');
        print('   - Classes: [C (correct), K (knee-over-toe)]');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error initializing Lunges Error Classifier: $e');
      }
      rethrow;
    }
  }

  /// Predict error (C/K) with probability
  Map<String, dynamic> predict(List<double> features) {
    if (!isReady) {
      return {'class': 'C', 'probability': 0.0};
    }

    // Standardize features
    final standardized = <double>[];
    for (int i = 0; i < features.length; i++) {
      standardized.add((features[i] - _scalerMean![i]) / _scalerScale![i]);
    }

    // KNN prediction (same logic as stage classifier)
    final distances = <_DistanceLabel>[];
    for (int i = 0; i < _trainingData!.length; i++) {
      double dist = 0.0;
      for (int j = 0; j < standardized.length; j++) {
        final diff = standardized[j] - _trainingData![i][j];
        dist += diff * diff;
      }
      distances.add(_DistanceLabel(math.sqrt(dist), _trainingLabels![i]));
    }

    distances.sort((a, b) => a.distance.compareTo(b.distance));
    final kNearest = distances.take(_k).toList();

    final votes = <String, double>{};
    for (final neighbor in kNearest) {
      final weight = 1.0 / (neighbor.distance + 1e-10);
      votes[neighbor.label] = (votes[neighbor.label] ?? 0.0) + weight;
    }

    String predictedClass = votes.entries.reduce((a, b) => a.value > b.value ? a : b).key;
    final totalWeight = votes.values.reduce((a, b) => a + b);
    final maxProb = votes[predictedClass]! / totalWeight;

    return {
      'class': predictedClass,
      'probability': maxProb,
    };
  }

  void dispose() {
    if (kDebugMode) {
      print('🗑️ Lunges Error Classifier disposed');
    }
  }
}

class _DistanceLabel {
  final double distance;
  final String label;
  _DistanceLabel(this.distance, this.label);
}