import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class LungesStageClassifier {
  List<double>? _scalerMean;
  List<double>? _scalerScale;
  List<String>? _stageClasses; // ['I', 'M', 'D']
  
  List<List<double>>? _trainingData;
  List<String>? _trainingLabels;
  int _k = 5;

  bool get isReady =>
      _scalerMean != null &&
      _scalerScale != null &&
      _stageClasses != null &&
      _trainingData != null &&
      _trainingLabels != null;

  Future<void> initialize() async {
    final startTime = DateTime.now();

    try {
      // Load scaler
      final scalerJson = await rootBundle.loadString('assets/models/lunges_scaler.json');
      final scalerData = json.decode(scalerJson);
      _scalerMean = List<double>.from(scalerData['mean']);
      _scalerScale = List<double>.from(scalerData['scale']);

      // Load stage classes
      final classesJson = await rootBundle.loadString('assets/models/lunges_stage_classes.json');
      final classesData = json.decode(classesJson);
      _stageClasses = List<String>.from(classesData['classes']);

      // Load KNN training data
      final knnJson = await rootBundle.loadString('assets/models/lunges_stage_knn.json');
      final knnData = json.decode(knnJson);
      _k = knnData['n_neighbors'] ?? 5;

      _trainingData = (knnData['training_data'] as List)
          .map((e) => List<double>.from(e))
          .toList();
      _trainingLabels = List<String>.from(knnData['training_labels']);

      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      if (kDebugMode) {
        print('✅ Lunges Stage Classifier initialized in ${elapsed}ms');
        print('   - Training samples: ${_trainingData!.length}');
        print('   - Features: ${_scalerMean!.length}');
        print('   - Classes: $_stageClasses');
        print('   - K neighbors: $_k');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error initializing Lunges Stage Classifier: $e');
      }
      rethrow;
    }
  }

  /// Predict stage (I/M/D) with probability
  Map<String, dynamic> predict(List<double> features) {
    if (!isReady) {
      return {'class': 'I', 'probability': 0.0, 'probabilities': [0.0, 0.0, 0.0]};
    }

    // Standardize features
    final standardized = <double>[];
    for (int i = 0; i < features.length; i++) {
      standardized.add((features[i] - _scalerMean![i]) / _scalerScale![i]);
    }

    // Calculate distances to all training samples
    final distances = <_DistanceLabel>[];
    for (int i = 0; i < _trainingData!.length; i++) {
      double dist = 0.0;
      for (int j = 0; j < standardized.length; j++) {
        final diff = standardized[j] - _trainingData![i][j];
        dist += diff * diff;
      }
      distances.add(_DistanceLabel(math.sqrt(dist), _trainingLabels![i]));
    }

    // Sort by distance and get k nearest
    distances.sort((a, b) => a.distance.compareTo(b.distance));
    final kNearest = distances.take(_k).toList();

    // Count votes with distance weighting
    final votes = <String, double>{};
    for (final neighbor in kNearest) {
      final weight = 1.0 / (neighbor.distance + 1e-10);
      votes[neighbor.label] = (votes[neighbor.label] ?? 0.0) + weight;
    }

    // Get prediction
    String predictedClass = votes.entries.reduce((a, b) => a.value > b.value ? a : b).key;
    
    // Calculate probabilities
    final totalWeight = votes.values.reduce((a, b) => a + b);
    final probabilities = <double>[];
    for (final className in _stageClasses!) {
      probabilities.add((votes[className] ?? 0.0) / totalWeight);
    }

    final maxProb = probabilities.reduce(math.max);

    return {
      'class': predictedClass,
      'probability': maxProb,
      'probabilities': probabilities,
    };
  }

  void dispose() {
    if (kDebugMode) {
      print('🗑️ Lunges Stage Classifier disposed');
    }
  }
}

class _DistanceLabel {
  final double distance;
  final String label;
  _DistanceLabel(this.distance, this.label);
}