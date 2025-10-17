import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class BicepKNNClassifier {
  List<double>? _scalerMean;
  List<double>? _scalerScale;
  List<String>? _labelClasses;
  
  List<List<double>>? _trainingData;
  List<int>? _trainingLabels;
  int _kNeighbors = 5;

  bool _isReady = false;
  bool get isReady => _isReady;

  Future<void> initialize() async {
    if (_isReady) return; // Already initialized
    
    final stopwatch = Stopwatch()..start();
    
    try {
      // Load all files in parallel for faster initialization
      final futures = await Future.wait([
        rootBundle.loadString('assets/models/bicep_scaler.json'),
        rootBundle.loadString('assets/models/bicep_label_encoder.json'),
        rootBundle.loadString('assets/models/bicep_knn_data.json'),
      ]);

      // Parse scaler
      final scalerData = json.decode(futures[0]);
      _scalerMean = List<double>.from(scalerData['mean']);
      _scalerScale = List<double>.from(scalerData['scale']);

      // Parse label encoder
      final labelData = json.decode(futures[1]);
      _labelClasses = List<String>.from(labelData['classes']);

      // Parse KNN training data
      final knnData = json.decode(futures[2]);
      _kNeighbors = knnData['n_neighbors'];
      
      _trainingData = (knnData['training_data'] as List)
          .map((row) => List<double>.from(row))
          .toList();
      _trainingLabels = List<int>.from(knnData['training_labels']);

      _isReady = true;
      
      stopwatch.stop();
      if (kDebugMode) {
        print('✅ Bicep KNN Classifier initialized in ${stopwatch.elapsedMilliseconds}ms');
        print('   - Training samples: ${_trainingData!.length}');
        print('   - Features: ${_trainingData!.first.length}');
        print('   - Classes: $_labelClasses');
        print('   - K neighbors: $_kNeighbors');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error initializing Bicep KNN classifier: $e');
      }
      _isReady = false;
    }
  }

  Map<String, dynamic> predict(List<double> features) {
    if (!_isReady || features.length != 7) {
      return {
        'label': 'neutral',
        'confidence': 0.0,
        'label_index': -1,
      };
    }

    // 1. Standardize features using scaler
    final scaledFeatures = _standardizeFeatures(features);

    // 2. Find K nearest neighbors (optimized with early exit)
    final distances = <_DistanceLabel>[];
    double maxDistSoFar = double.infinity;
    
    for (int i = 0; i < _trainingData!.length; i++) {
      final distance = _euclideanDistance(scaledFeatures, _trainingData![i]);
      
      // Early exit optimization: skip if we have K neighbors and this is farther
      if (distances.length >= _kNeighbors && distance > maxDistSoFar) {
        continue;
      }
      
      distances.add(_DistanceLabel(distance, _trainingLabels![i]));
      
      // Keep only top K by sorting and trimming
      if (distances.length >= _kNeighbors) {
        distances.sort((a, b) => a.distance.compareTo(b.distance));
        if (distances.length > _kNeighbors) {
          distances.removeRange(_kNeighbors, distances.length);
        }
        maxDistSoFar = distances.last.distance;
      }
    }

    // Final sort to ensure we have K nearest
    distances.sort((a, b) => a.distance.compareTo(b.distance));
    final kNearest = distances.take(_kNeighbors).toList();

    // 3. Count votes (majority voting)
    final votes = <int, int>{};
    for (final neighbor in kNearest) {
      votes[neighbor.label] = (votes[neighbor.label] ?? 0) + 1;
    }

    // 4. Get majority vote
    int predictedLabelIndex = votes.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;

    // 5. Calculate confidence (proportion of votes for winning class)
    final confidence = votes[predictedLabelIndex]! / _kNeighbors;

    return {
      'label': _labelClasses![predictedLabelIndex],
      'confidence': confidence,
      'label_index': predictedLabelIndex,
    };
  }

  List<double> _standardizeFeatures(List<double> features) {
    final standardized = <double>[];
    for (int i = 0; i < features.length; i++) {
      final scaled = (features[i] - _scalerMean![i]) / (_scalerScale![i] + 1e-6);
      standardized.add(scaled);
    }
    return standardized;
  }

  // Optimized distance calculation (unrolled for 7 features)
  double _euclideanDistance(List<double> a, List<double> b) {
    final d0 = a[0] - b[0];
    final d1 = a[1] - b[1];
    final d2 = a[2] - b[2];
    final d3 = a[3] - b[3];
    final d4 = a[4] - b[4];
    final d5 = a[5] - b[5];
    final d6 = a[6] - b[6];
    
    return math.sqrt(
      d0*d0 + d1*d1 + d2*d2 + d3*d3 + d4*d4 + d5*d5 + d6*d6
    );
  }

  void dispose() {
    _isReady = false;
    if (kDebugMode) {
      print('🗑️ Bicep KNN Classifier disposed');
    }
  }
}

class _DistanceLabel {
  final double distance;
  final int label;
  _DistanceLabel(this.distance, this.label);
}