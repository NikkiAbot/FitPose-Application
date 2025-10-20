import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'shoulderpress_feature_extract.dart';

class ShoulderPressClassifier {
  OrtSession? _session;
  List<double>? _scalerMean;
  List<double>? _scalerScale;
  List<String>? _labelClasses;
  bool _isInitialized = false;

  /// Initialize the model, scaler, and label encoder
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      if (kDebugMode) print('[Classifier] Starting initialization...');

      // 1. Load scaler parameters
      final scalerJson = await rootBundle.loadString(
        'assets/json/scaler_params.json',
      );
      final scalerData = json.decode(scalerJson);
      _scalerMean = List<double>.from(scalerData['mean']);
      _scalerScale = List<double>.from(scalerData['scale']);

      if (kDebugMode) {
        print('[Classifier] ✓ Scaler loaded');
        print('  Mean: $_scalerMean');
        print('  Scale: $_scalerScale');
      }

      // 2. Load label classes
      final labelsJson = await rootBundle.loadString(
        'assets/json/label_encoder.json',
      );
      final labelsData = json.decode(labelsJson);
      _labelClasses = List<String>.from(labelsData['classes']);

      if (kDebugMode) {
        print('[Classifier] ✓ Labels loaded: $_labelClasses');
      }

      // 3. Load ONNX model
      final sessionOptions = OrtSessionOptions();
      final modelBytes = await rootBundle.load(
        'assets/onnx/shoulder_press_model.onnx',
      );
      _session = OrtSession.fromBuffer(
        modelBytes.buffer.asUint8List(),
        sessionOptions,
      );

      // Print model input/output info
      if (kDebugMode) {
        print('[Classifier] Model input names: ${_session!.inputNames}');
        print('[Classifier] Model output names: ${_session!.outputNames}');
      }

      _isInitialized = true;
      if (kDebugMode) {
        print('[Classifier] ✓ ONNX model loaded');
        print('[Classifier] ═══ Initialization Complete ═══');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('[Classifier] ✗ Failed to initialize: $e');
        print('[Classifier] Stack trace: $stackTrace');
      }
      _isInitialized = false;
      rethrow;
    }
  }

  /// Predict form quality from pose
  /// Returns: {label, confidence, isGoodForm, probabilities, features}
  Future<Map<String, dynamic>> predict(Pose pose) async {
    if (!_isInitialized || _session == null) {
      return {
        'label': 'Model not loaded',
        'confidence': 0.0,
        'isGoodForm': false,
        'probabilities': <double>[],
        'error': 'Classifier not initialized',
      };
    }

    try {
      // 1. Extract features (7 features from pose)
      final features = ShoulderPressFeatures.computeFeatures(pose);
      if (features == null || features.length != 7) {
        return {
          'label': 'Incomplete pose',
          'confidence': 0.0,
          'isGoodForm': false,
          'probabilities': <double>[],
          'error': 'Missing landmarks',
        };
      }

      // 2. Scale features using scaler parameters
      final scaledFeatures = <double>[];
      for (int i = 0; i < features.length; i++) {
        final scaled = (features[i] - _scalerMean![i]) / _scalerScale![i];
        scaledFeatures.add(scaled);
      }

      if (kDebugMode) {
        print('─────────────────────────────────────');
        print('[Prediction] Raw features: $features');
        print('[Prediction] Scaled features: $scaledFeatures');
      }

      // 3. Convert to Float32
      final inputShape = [1, 7];
      final inputData = Float32List.fromList(scaledFeatures);

      final inputOrt = OrtValueTensor.createTensorWithDataList(
        inputData,
        inputShape,
      );

      // Get correct input name from model
      final inputName = _session!.inputNames.first;
      final inputs = {inputName: inputOrt};

      if (kDebugMode) {
        print('[Prediction] Input name: $inputName');
        print('[Prediction] Input shape: $inputShape');
        print('[Prediction] Input type: Float32');
      }

      // 4. Run inference
      final runOptions = OrtRunOptions();
      final outputs = _session!.run(runOptions, inputs);
      runOptions.release();

      // 5. Clean up input
      inputOrt.release();

      // 6. Parse outputs
      if (outputs.isEmpty) {
        if (kDebugMode) print('[Prediction] ✗ No outputs from model');
        return {
          'label': 'Prediction failed',
          'confidence': 0.0,
          'isGoodForm': false,
          'probabilities': <double>[],
          'error': 'No model output',
        };
      }

      if (kDebugMode) {
        print(
          '[Prediction] Output indices: ${List<int>.generate(outputs.length, (i) => i)}',
        );
      }

      // Extract outputs by name
      // For List<OrtValue?> outputs, use indices directly
      final labelOutput = outputs.isNotEmpty ? outputs[0]?.value : null;
      final probOutput = outputs.length > 1 ? outputs[1]?.value : null;

      if (kDebugMode) {
        print('[Prediction] Label output: $labelOutput');
        print('[Prediction] Prob output: $probOutput');
      }

      // Release outputs
      for (var value in outputs) {
        value?.release();
      }

      // Parse the predicted class index
      int predictedClassIdx = 0;
      if (labelOutput is List) {
        if (labelOutput[0] is List) {
          predictedClassIdx = (labelOutput[0][0] as num).toInt();
        } else {
          predictedClassIdx = (labelOutput[0] as num).toInt();
        }
      } else if (labelOutput != null) {
        predictedClassIdx = (labelOutput as num).toInt();
      }

      // Parse probabilities
      List<double> probabilities;
      if (probOutput != null) {
        if (probOutput is Map) {
          probabilities = List.generate(
            _labelClasses!.length,
            (i) => (probOutput[i] as num?)?.toDouble() ?? 0.0,
          );
        } else if (probOutput is List && probOutput[0] is List) {
          probabilities =
              (probOutput[0] as List)
                  .map((e) => (e as num).toDouble())
                  .toList();
        } else if (probOutput is List) {
          probabilities = probOutput.map((e) => (e as num).toDouble()).toList();
        } else {
          probabilities = List.filled(_labelClasses!.length, 0.0);
        }
      } else {
        probabilities = List.filled(_labelClasses!.length, 0.0);
        if (predictedClassIdx < probabilities.length) {
          probabilities[predictedClassIdx] = 1.0;
        }
      }

      // Get label and confidence
      if (predictedClassIdx >= _labelClasses!.length) {
        throw Exception('Invalid class index: $predictedClassIdx');
      }

      final label = _labelClasses![predictedClassIdx];
      final confidence =
          probabilities.isNotEmpty ? probabilities[predictedClassIdx] : 1.0;
      final isGoodForm = label.toLowerCase().contains('good');

      if (kDebugMode) {
        print('╔════════════════════════════════════════════════════════╗');
        print('║  ML PREDICTION RESULT                                  ║');
        print('╠════════════════════════════════════════════════════════╣');
        print('║  Label: ${label.padRight(45)} ║');
        print(
          '║  Confidence: ${(confidence * 100).toStringAsFixed(1).padRight(43)}% ║',
        );
        print('║  Good Form: ${isGoodForm.toString().padRight(43)} ║');
        print('║  Class Index: ${predictedClassIdx.toString().padRight(41)} ║');
        print('╚════════════════════════════════════════════════════════╝');
      }

      return {
        'label': label,
        'confidence': confidence,
        'isGoodForm': isGoodForm,
        'probabilities': probabilities,
        'predictedClassIdx': predictedClassIdx,
        'features': features,
        'scaledFeatures': scaledFeatures,
      };
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('[Prediction] ✗✗✗ EXCEPTION ✗✗✗');
        print('[Prediction] Error: $e');
        print('[Prediction] Stack trace: $stackTrace');
      }
      return {
        'label': 'Error',
        'confidence': 0.0,
        'isGoodForm': false,
        'probabilities': <double>[],
        'error': e.toString(),
      };
    }
  }

  /// Check if model is ready
  bool get isReady => _isInitialized;

  /// Get label classes
  List<String>? get classes => _labelClasses;

  /// Dispose resources
  void dispose() {
    _session?.release();
    _isInitialized = false;
    if (kDebugMode) print('[Classifier] Disposed');
  }
}
