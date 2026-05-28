import 'dart:math' as math;
import '../../../core/services/api_service.dart';

// Architecture mirrors backend: 16 → 32 → 16 → 1
// Weights stored as flat lists matching backend LAYER_SHAPES order:
//   W1(16×32), b1(32), W2(32×16), b2(16), W3(16×1), b3(1)
const _shapes = [
  (16, 32), (32, 1),  // W1, b1
  (32, 16), (16, 1),  // W2, b2
  (16, 1),  (1, 1),   // W3, b3
];

const _interests = ['art', 'architecture', 'history', 'gastronomy', 'nature', 'music'];
const _types = ['museum', 'monument', 'park', 'gallery', 'restaurant', 'square', 'building', 'other'];

class Interaction {
  final List<double> features; // 16-dim input vector
  final double label;          // 1.0 = explored, 0.0 = dismissed
  const Interaction(this.features, this.label);
}

class FLClientService {
  final ApiService _api;

  // Current weights: 6 flat lists matching LAYER_SHAPES
  List<List<double>> _weights = [];
  int _currentRound = 0;
  final List<Interaction> _interactions = [];

  FLClientService(this._api);

  bool get hasWeights => _weights.isNotEmpty;
  int get round => _currentRound;
  int get pendingInteractions => _interactions.length;

  // ── Feature engineering ────────────────────────────────────────────────────

  List<double> buildFeatureVector({
    required List<String> userInterests,
    required String landmarkType,
    double distanceM = 0,
  }) {
    final v = List<double>.filled(16, 0.0);
    for (int i = 0; i < _interests.length; i++) {
      if (userInterests.contains(_interests[i])) v[i] = 1.0;
    }
    final typeIdx = _types.indexOf(landmarkType);
    if (typeIdx >= 0) v[6 + typeIdx] = 1.0;
    v[14] = DateTime.now().hour / 24.0;
    v[15] = (distanceM / 1500.0).clamp(0.0, 1.0);
    return v;
  }

  void recordInteraction(List<double> features, double label) {
    _interactions.add(Interaction(features, label));
  }

  // ── FL round ───────────────────────────────────────────────────────────────

  Future<void> fetchGlobalWeights() async {
    final res = await _api.get('/federated/model/global');
    _currentRound = res.data['round'] as int;
    _weights = (res.data['weights'] as List)
        .map((layer) => (layer as List).map((v) => (v as num).toDouble()).toList())
        .toList();
  }

  Future<Map<String, dynamic>> runFLRound() async {
    if (_interactions.isEmpty) return {'skipped': true};
    if (_weights.isEmpty) await fetchGlobalWeights();

    _trainLocally();

    final res = await _api.post('/federated/model/update', data: {
      'round': _currentRound,
      'weights': _weights,
      'num_samples': _interactions.length,
    });

    _interactions.clear();
    _currentRound = res.data['round'] as int;
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getStatus() async {
    final res = await _api.get('/federated/model/status');
    return res.data as Map<String, dynamic>;
  }

  // ── MLP forward + backprop ─────────────────────────────────────────────────

  void _trainLocally({double lr = 0.01, int epochs = 5}) {
    // Shapes: W1(32,16), b1(32), W2(16,32), b2(16), W3(1,16), b3(1)
    final w1 = _reshape(_weights[0], 32, 16);
    final b1 = List<double>.from(_weights[1]);
    final w2 = _reshape(_weights[2], 16, 32);
    final b2 = List<double>.from(_weights[3]);
    final w3 = _reshape(_weights[4], 1, 16);
    final b3 = List<double>.from(_weights[5]);

    for (int epoch = 0; epoch < epochs; epoch++) {
      for (final sample in _interactions) {
        final x = sample.features;
        final y = sample.label;

        // ── Forward ───────────────────────────────────────────────────────
        final z1 = _matVec(w1, x, b1);          // (32,)
        final a1 = z1.map(_relu).toList();

        final z2 = _matVec(w2, a1, b2);          // (16,)
        final a2 = z2.map(_relu).toList();

        final z3 = _matVec(w3, a2, b3);          // (1,)
        final out = _sigmoid(z3[0]);

        // ── Backward ──────────────────────────────────────────────────────
        final dLoss = 2.0 * (out - y);
        final dSig = out * (1.0 - out);
        final dz3 = [dLoss * dSig];

        final dW3 = _outerVec(dz3, a2);
        final db3 = List<double>.from(dz3);

        final da2 = _vecMatT(dz3, w3);
        final dz2 = List.generate(16, (i) => da2[i] * _reluDeriv(z2[i]));

        final dW2 = _outerVec(dz2, a1);
        final db2g = List<double>.from(dz2);

        final da1 = _vecMatT(dz2, w2);
        final dz1 = List.generate(32, (i) => da1[i] * _reluDeriv(z1[i]));

        final dW1 = _outerVec(dz1, x);
        final db1g = List<double>.from(dz1);

        // ── Update ────────────────────────────────────────────────────────
        _applyGrad(w1, dW1, lr);
        _applyGradVec(b1, db1g, lr);
        _applyGrad(w2, dW2, lr);
        _applyGradVec(b2, db2g, lr);
        _applyGrad(w3, dW3, lr);
        _applyGradVec(b3, db3, lr);
      }
    }

    _weights[0] = w1.expand((row) => row).toList();
    _weights[1] = b1;
    _weights[2] = w2.expand((row) => row).toList();
    _weights[3] = b2;
    _weights[4] = w3.expand((row) => row).toList();
    _weights[5] = b3;
  }

  double predict(List<double> x) {
    if (_weights.isEmpty) return 0.5;
    final w1 = _reshape(_weights[0], 32, 16);
    final b1 = _weights[1];
    final w2 = _reshape(_weights[2], 16, 32);
    final b2 = _weights[3];
    final w3 = _reshape(_weights[4], 1, 16);
    final b3 = _weights[5];

    final a1 = _matVec(w1, x, b1).map(_relu).toList();
    final a2 = _matVec(w2, a1, b2).map(_relu).toList();
    return _sigmoid(_matVec(w3, a2, b3)[0]);
  }

  // ── Math helpers ───────────────────────────────────────────────────────────

  List<List<double>> _reshape(List<double> flat, int rows, int cols) =>
      List.generate(rows, (r) => flat.sublist(r * cols, r * cols + cols));

  List<double> _matVec(List<List<double>> W, List<double> x, List<double> b) =>
      List.generate(W.length, (i) {
        double s = b[i];
        for (int j = 0; j < x.length; j++) s += W[i][j] * x[j];
        return s;
      });

  // dz (out_dim) × a (in_dim) → matrix (out_dim × in_dim)
  List<List<double>> _outerVec(List<double> dz, List<double> a) =>
      List.generate(dz.length, (i) => List.generate(a.length, (j) => dz[i] * a[j]));

  // v (out_dim) × W^T (out_dim × in_dim) → (in_dim,)
  List<double> _vecMatT(List<double> v, List<List<double>> W) =>
      List.generate(W[0].length, (j) {
        double s = 0;
        for (int i = 0; i < v.length; i++) s += v[i] * W[i][j];
        return s;
      });

  void _applyGrad(List<List<double>> W, List<List<double>> dW, double lr) {
    for (int i = 0; i < W.length; i++) {
      for (int j = 0; j < W[i].length; j++) W[i][j] -= lr * dW[i][j];
    }
  }

  void _applyGradVec(List<double> b, List<double> db, double lr) {
    for (int i = 0; i < b.length; i++) b[i] -= lr * db[i];
  }

  double _relu(double x) => x > 0 ? x : 0;
  double _reluDeriv(double x) => x > 0 ? 1.0 : 0.0;
  double _sigmoid(double x) => 1.0 / (1.0 + math.exp(-x.clamp(-30, 30)));
}
