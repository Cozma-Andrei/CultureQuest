/// Federated Learning client running on the mobile device.
///
/// Flow:
/// 1. Download global model weights from server.
/// 2. Train locally on device interaction data.
/// 3. Send only updated weights (not raw data) back to server.
class FLClientService {
  Future<List<List<double>>> fetchGlobalWeights() async {
    return [];
  }

  Future<List<List<double>>> trainLocally(
    List<List<double>> currentWeights,
    List<Map<String, dynamic>> localSamples,
  ) async {
    return currentWeights;
  }

  Future<void> sendWeightsToServer(List<List<double>> weights, int numSamples) async {}

  void recordInteraction({required String landmarkId, required String category, required double durationSeconds}) {}
}
