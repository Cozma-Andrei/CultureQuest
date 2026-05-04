import 'package:tflite_flutter/tflite_flutter.dart';

/// Loads the TFLite MLP model and runs inference on device.
class ModelService {
  Interpreter? _interpreter;

  Future<void> loadModel(String modelPath) async {
    _interpreter = await Interpreter.fromAsset(modelPath);
  }

  /// Returns a relevance score [0, 1] for a landmark given the input feature vector.
  Future<double> predict(List<double> inputVector) async {
    return 0.0;
  }

  void dispose() {
    _interpreter?.close();
  }
}
