import 'dart:math' as math;
import '../../../core/services/api_service.dart';
import '../../../core/services/local_data_service.dart';

// Architecture: 22 -> 32 -> 16 -> 1
// Input:
//  [0-5]  user interests one-hot     (art, architecture, history, gastronomy, nature, music)
//  [6-13] landmark type one-hot      (museum, monument, park, gallery, restaurant, square, building, other)
//  [14]   isOpen                     binary
//  [15]   isWeekend                  binary
//  [16]   hour / 24.0                float
//  [17]   relativeDistanceRank       float [0=closest, 1=farthest among nearby]
//  [18]   interestMatchScore         float [0,1]
//  [19]   isPartOfRoute              binary
//  [20]   routeStopNormalized        float [0=first/farthest stop, 1=last/closest]
//  [21]   routeLengthNormalized      float [0=short, 1=long, /4 = max 5 stops]
const _inputDim = 22;

const _interests = ['art', 'architecture', 'history', 'gastronomy', 'nature', 'music'];
const _types = ['museum', 'monument', 'park', 'gallery', 'restaurant', 'square', 'building', 'other'];

// Differential Privacy settings.
// Gaussian noise N(0, (kDPSigma * kDPClipNorm)²) is added to each weight
// coordinate of the delta before upload, preventing membership inference:
// an adversary querying the global model cannot determine whether a specific
// interaction (e.g. "did this user visit the Romanian Athenaeum?") was in
// any client's training set.
// kDPSigma = 0   -> DP disabled (noise-free, maximum utility)
// kDPSigma = 0.1 -> mild noise, practical privacy for a low-stakes app
// kDPSigma = 1.0 -> strong DP guarantee, noticeable accuracy impact
const kDPEnabled  = true;
const kDPSigma    = 0.1;   // noise multiplier
const kDPClipNorm = 1.0;   // must match server-side max_norm in clipped_fedavg

class Interaction {
  final List<double> features;
  final double label;
  const Interaction(this.features, this.label);
}

// Deduplication buffer: one entry per landmark per round.
// Rating (explicit) overrides engagement label; engagement only replaces if higher.
class _LandmarkBuffer {
  final List<double> features;
  final double maxEngagement;
  final double? explicitRating; // 1-5 mapped to /5.0; overrides maxEngagement

  const _LandmarkBuffer({
    required this.features,
    required this.maxEngagement,
    this.explicitRating,
  });

  double get label => explicitRating ?? maxEngagement;

  _LandmarkBuffer withEngagement(double e, List<double> f) {
    if (e <= maxEngagement) return this;
    return _LandmarkBuffer(features: f, maxEngagement: e, explicitRating: explicitRating);
  }

  _LandmarkBuffer withRating(double r, List<double> f) =>
      _LandmarkBuffer(features: f, maxEngagement: maxEngagement, explicitRating: r);
}

class FLClientService {
  final ApiService _api;
  final LocalDataService _local;

  List<List<double>> _weights = [];
  int _currentRound = 0;
  final Map<String, _LandmarkBuffer> _buffer = {};
  final _rng = math.Random();

  FLClientService(this._api, this._local) {
    _restoreBuffer();
  }

  bool get hasWeights => _weights.isNotEmpty;
  int get round => _currentRound;
  int get pendingInteractions => _buffer.length;

  void _restoreBuffer() {
    final saved = _local.getFlBuffer();
    for (final entry in saved.entries) {
      final v = entry.value as Map<String, dynamic>;
      _buffer[entry.key] = _LandmarkBuffer(
        features: (v['features'] as List).map((e) => (e as num).toDouble()).toList(),
        maxEngagement: (v['maxEngagement'] as num).toDouble(),
        explicitRating: v['explicitRating'] != null ? (v['explicitRating'] as num).toDouble() : null,
      );
    }
  }

  Future<void> _persistBuffer() => _local.saveFlBuffer({
    for (final e in _buffer.entries)
      e.key: {
        'features': e.value.features,
        'maxEngagement': e.value.maxEngagement,
        'explicitRating': e.value.explicitRating,
      }
  });

  void clearInteractions() {
    _buffer.clear();
    _local.clearFlBuffer();
  }

  // Feature engineering

  List<double> buildFeatureVector({
    required List<String> userInterests,
    required String landmarkType,
    required List<String> landmarkCategories,
    required bool isOpen,
    required bool isWeekend,
    double relativeDistanceRank = 0.5,
    bool isPartOfRoute = false,
    int routeStopIndex = 0,
    int routeLength = 0,
  }) {
    final v = List<double>.filled(_inputDim, 0.0);

    for (int i = 0; i < _interests.length; i++) {
      if (userInterests.contains(_interests[i])) v[i] = 1.0;
    }

    final typeIdx = _types.indexOf(landmarkType);
    if (typeIdx >= 0) v[6 + typeIdx] = 1.0;

    v[14] = isOpen ? 1.0 : 0.0;
    v[15] = isWeekend ? 1.0 : 0.0;
    v[16] = DateTime.now().hour / 24.0;
    v[17] = relativeDistanceRank.clamp(0.0, 1.0);

    // Interest match: fraction of user's interests that appear in landmark categories
    if (userInterests.isNotEmpty) {
      final matches = userInterests.where((i) => landmarkCategories.contains(i)).length;
      v[18] = matches / userInterests.length;
    }

    v[19] = isPartOfRoute ? 1.0 : 0.0;
    v[20] = isPartOfRoute && routeLength > 1
        ? (routeStopIndex / (routeLength - 1)).clamp(0.0, 1.0)
        : 0.0;
    v[21] = isPartOfRoute && routeLength > 0
        ? ((routeLength - 1) / 4.0).clamp(0.0, 1.0) // max 5 stops -> (5-1)/4 = 1.0
        : 0.0;

    return v;
  }

  // Interaction recording

  /// Record an engagement event (sheet opened, navigation, quest, etc.)
  /// Label should be the engagement constant for this event type.
  void recordEngagement(String landmarkId, List<double> features, double label) {
    final existing = _buffer[landmarkId];
    _buffer[landmarkId] = existing == null
        ? _LandmarkBuffer(features: features, maxEngagement: label)
        : existing.withEngagement(label, features);
    _persistBuffer();
  }

  void recordRating(String landmarkId, List<double> features, int stars) {
    final r = stars.clamp(1, 5) / 5.0;
    final existing = _buffer[landmarkId];
    _buffer[landmarkId] = existing == null
        ? _LandmarkBuffer(features: features, maxEngagement: r, explicitRating: r)
        : existing.withRating(r, features);
    _persistBuffer();
  }

  // FL round

  Future<void> fetchGlobalWeights() async {
    final res = await _api.get('/federated/model/global');
    _currentRound = res.data['round'] as int;
    _weights = (res.data['weights'] as List)
        .map((layer) => (layer as List).map((v) => (v as num).toDouble()).toList())
        .toList();
  }

  Future<Map<String, dynamic>> runFLRound() async {
    if (_buffer.isEmpty) return {'skipped': true};
    // Always re-sync before training: _weights holds this device's own
    // locally-trained-and-noised copy after the first round, not the
    // server's aggregated result. Re-fetching guarantees local training
    // starts from the true current global model and that the `client_round`
    // we report is honest, so the server's staleness discount is never
    // silently bypassed by a multi-round session.
    await fetchGlobalWeights();

    // Snapshot the global weights before local training so the DP noise step
    // can clip the delta (trained - global) coordinate-wise.
    final globalSnapshot = _weights.map((layer) => List<double>.from(layer)).toList();

    _trainLocally();

    // Differential Privacy: add Gaussian noise to the weight delta before
    // uploading. This prevents membership inference: an adversary querying
    // the global model cannot determine whether a specific interaction was in
    // this client's training set.
    if (kDPEnabled) _addDPNoise(globalSnapshot);

    final res = await _api.post('/federated/model/update', data: {
      'round': _currentRound,
      'weights': _weights,
      'num_samples': _buffer.length,
    });

    _buffer.clear();
    _local.clearFlBuffer();
    _currentRound = res.data['round'] as int;
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getStatus() async {
    final res = await _api.get('/federated/model/status');
    return res.data as Map<String, dynamic>;
  }

  // Inference

  /// Forward pass only, with the current weights - used to show a
  /// personalization "match" indicator for a landmark. Does not touch
  /// `_buffer` or run backprop.
  double predictScore(List<double> features) {
    final w1 = _reshape(_weights[0], 32, _inputDim);
    final b1 = _weights[1];
    final w2 = _reshape(_weights[2], 16, 32);
    final b2 = _weights[3];
    final w3 = _reshape(_weights[4], 1, 16);
    final b3 = _weights[5];

    final z1 = _matVec(w1, features, b1);
    final a1 = z1.map(_relu).toList();
    final z2 = _matVec(w2, a1, b2);
    final a2 = z2.map(_relu).toList();
    final z3 = _matVec(w3, a2, b3);
    return _sigmoid(z3[0]);
  }

  // MLP forward + backprop

  // Local training: plain SGD on the local loss for a few epochs, the
  // standard FedAvg client procedure (train locally, then upload for the
  // server to merge into the global model).
  void _trainLocally({double lr = 0.01, int epochs = 5}) {
    final samples = _buffer.values.map((b) => Interaction(b.features, b.label)).toList();

    // W1(32,22) b1(32) W2(16,32) b2(16) W3(1,16) b3(1)
    final w1 = _reshape(_weights[0], 32, _inputDim);
    final b1 = List<double>.from(_weights[1]);
    final w2 = _reshape(_weights[2], 16, 32);
    final b2 = List<double>.from(_weights[3]);
    final w3 = _reshape(_weights[4], 1, 16);
    final b3 = List<double>.from(_weights[5]);

    for (int epoch = 0; epoch < epochs; epoch++) {
      for (final sample in samples) {
        final x = sample.features;
        final y = sample.label;

        // Forward
        final z1 = _matVec(w1, x, b1);
        final a1 = z1.map(_relu).toList();
        final z2 = _matVec(w2, a1, b2);
        final a2 = z2.map(_relu).toList();
        final z3 = _matVec(w3, a2, b3);
        final out = _sigmoid(z3[0]);

        // Backward
        final dLoss = 2.0 * (out - y);
        final dSig  = out * (1.0 - out);
        final dz3   = [dLoss * dSig];

        final dW3  = _outerVec(dz3, a2);
        final db3  = List<double>.from(dz3);
        final da2  = _vecMatT(dz3, w3);
        final dz2  = List.generate(16, (i) => da2[i] * _reluDeriv(z2[i]));

        final dW2  = _outerVec(dz2, a1);
        final db2g = List<double>.from(dz2);
        final da1  = _vecMatT(dz2, w2);
        final dz1  = List.generate(32, (i) => da1[i] * _reluDeriv(z1[i]));

        final dW1  = _outerVec(dz1, x);
        final db1g = List<double>.from(dz1);

        if (_hasNaN(db1g) || _hasNaN(db2g) || _hasNaN(db3)) continue;

        final allGrads = [
          ...dW1.expand((r) => r), ...db1g,
          ...dW2.expand((r) => r), ...db2g,
          ...dW3.expand((r) => r), ...db3,
        ];
        final norm = math.sqrt(allGrads.fold(0.0, (s, v) => s + v * v));
        final scale = (norm > 1.0) ? 1.0 / norm : 1.0;

        _applyGrad(w1, dW1, lr * scale);  _applyGradVec(b1, db1g, lr * scale);
        _applyGrad(w2, dW2, lr * scale);  _applyGradVec(b2, db2g, lr * scale);
        _applyGrad(w3, dW3, lr * scale);  _applyGradVec(b3, db3,  lr * scale);
      }
    }

    _weights[0] = w1.expand((r) => r).toList();
    _weights[1] = b1;
    _weights[2] = w2.expand((r) => r).toList();
    _weights[3] = b2;
    _weights[4] = w3.expand((r) => r).toList();
    _weights[5] = b3;
  }

  // Math helpers

  List<List<double>> _reshape(List<double> flat, int rows, int cols) =>
      List.generate(rows, (r) => flat.sublist(r * cols, r * cols + cols));

  List<double> _matVec(List<List<double>> W, List<double> x, List<double> b) =>
      List.generate(W.length, (i) {
        double s = b[i];
        for (int j = 0; j < x.length; j++) s += W[i][j] * x[j];
        return s;
      });

  List<List<double>> _outerVec(List<double> dz, List<double> a) =>
      List.generate(dz.length, (i) => List.generate(a.length, (j) => dz[i] * a[j]));

  List<double> _vecMatT(List<double> v, List<List<double>> W) =>
      List.generate(W[0].length, (j) {
        double s = 0;
        for (int i = 0; i < v.length; i++) s += v[i] * W[i][j];
        return s;
      });

  void _applyGrad(List<List<double>> W, List<List<double>> dW, double lr) {
    for (int i = 0; i < W.length; i++)
      for (int j = 0; j < W[i].length; j++) W[i][j] -= lr * dW[i][j];
  }

  void _applyGradVec(List<double> b, List<double> db, double lr) {
    for (int i = 0; i < b.length; i++) b[i] -= lr * db[i];
  }

  // Adds calibrated Gaussian noise N(0, (kDPSigma * kDPClipNorm)²) to each
  // coordinate of the weight delta (trained - global). The delta is clipped to
  // kDPClipNorm before noise is added so sensitivity is bounded.
  void _addDPNoise(List<List<double>> globalSnapshot) {
    final noiseStd = kDPSigma * kDPClipNorm;
    for (int l = 0; l < _weights.length; l++) {
      // Clip delta coordinate-wise (bound sensitivity)
      final delta = List<double>.generate(
        _weights[l].length,
        (i) => (_weights[l][i] - globalSnapshot[l][i]).clamp(-kDPClipNorm, kDPClipNorm),
      );
      // Add Gaussian noise to each delta coordinate
      for (int i = 0; i < delta.length; i++) {
        delta[i] += _gaussian(noiseStd);
      }
      // Reconstruct noisy weights
      for (int i = 0; i < _weights[l].length; i++) {
        _weights[l][i] = globalSnapshot[l][i] + delta[i];
      }
    }
  }

  // Box-Muller transform: produces N(0, sigma²) samples from uniform RNG.
  double _gaussian(double sigma) {
    final u1 = _rng.nextDouble().clamp(1e-10, 1.0);
    final u2 = _rng.nextDouble();
    final z = math.sqrt(-2.0 * math.log(u1)) * math.cos(2.0 * math.pi * u2);
    return z * sigma;
  }

  double _relu(double x) => x > 0 ? x : 0;
  double _reluDeriv(double x) => x > 0 ? 1.0 : 0.0;
  double _sigmoid(double x) => 1.0 / (1.0 + math.exp(-x.clamp(-30, 30)));
  bool _hasNaN(List<double> v) => v.any((x) => x.isNaN || x.isInfinite);
}
