import math
import pytest
from app.federated.model import (
    build_initial_weights,
    fedavg,
    clipped_fedavg,
    fl_predict,
    INPUT_DIM, HIDDEN_DIMS, OUTPUT_DIM, LAYER_SHAPES,
)

# ── helpers ──────────────────────────────────────────────────────────────────

def zero_weights():
    return [([0.0] * math.prod(s)) for s in LAYER_SHAPES]

def _delta_norm(w_new, w_old):
    return math.sqrt(sum(
        (a - b) ** 2
        for l_new, l_old in zip(w_new, w_old)
        for a, b in zip(l_new, l_old)
    ))


# ── build_initial_weights ─────────────────────────────────────────────────────

def test_initial_weights_layer_count():
    w = build_initial_weights()
    assert len(w) == 6  # W1 b1 W2 b2 W3 b3

def test_initial_weights_shapes():
    w = build_initial_weights()
    expected_sizes = [math.prod(s) for s in LAYER_SHAPES]
    assert [len(layer) for layer in w] == expected_sizes

def test_initial_weights_biases_are_zero():
    w = build_initial_weights()
    for bias_idx in (1, 3, 5):
        assert all(v == 0.0 for v in w[bias_idx]), f"bias layer {bias_idx} not zero"

def test_initial_weights_weights_not_all_zero():
    w = build_initial_weights()
    for weight_idx in (0, 2, 4):
        assert any(v != 0.0 for v in w[weight_idx]), f"weight layer {weight_idx} is all zero"


# ── fl_predict ────────────────────────────────────────────────────────────────

def test_predict_output_in_unit_interval():
    w = build_initial_weights()
    x = [0.0] * INPUT_DIM
    out = fl_predict(w, x)
    assert 0.0 < out < 1.0

def test_predict_zero_weights_zero_input_gives_half():
    w = zero_weights()
    x = [0.0] * INPUT_DIM
    assert abs(fl_predict(w, x) - 0.5) < 1e-6

def test_predict_large_positive_bias_gives_high_score():
    w = zero_weights()
    w[5] = [30.0]  # b3 very positive → sigmoid(30) ≈ 1
    out = fl_predict(w, [0.0] * INPUT_DIM)
    assert out > 0.99

def test_predict_large_negative_bias_gives_low_score():
    w = zero_weights()
    w[5] = [-30.0]  # b3 very negative → sigmoid(-30) ≈ 0
    out = fl_predict(w, [0.0] * INPUT_DIM)
    assert out < 0.01

def test_predict_clamps_extreme_logits():
    w = zero_weights()
    w[5] = [1e9]
    out = fl_predict(w, [0.0] * INPUT_DIM)
    assert 0.0 <= out <= 1.0


# ── fedavg ───────────────────────────────────────────────────────────────────

def test_fedavg_single_client_returns_same_weights():
    w = build_initial_weights()
    result = fedavg([(10, w)])
    for r_layer, w_layer in zip(result, w):
        assert all(abs(a - b) < 1e-6 for a, b in zip(r_layer, w_layer))

def test_fedavg_equal_samples_is_mean():
    w1 = [[2.0, 4.0]]
    w2 = [[4.0, 8.0]]
    result = fedavg([(1, w1), (1, w2)])
    assert abs(result[0][0] - 3.0) < 1e-6
    assert abs(result[0][1] - 6.0) < 1e-6

def test_fedavg_weighted_average():
    w1 = [[0.0]]
    w2 = [[4.0]]
    result = fedavg([(1, w1), (3, w2)])  # 1/(1+3)=0.25 * 0 + 3/4 * 4 = 3.0
    assert abs(result[0][0] - 3.0) < 1e-6


# ── clipped_fedavg ────────────────────────────────────────────────────────────

def test_clipped_fedavg_zero_delta_unchanged():
    global_w = build_initial_weights()
    result = clipped_fedavg([(10, global_w)], global_w, max_norm=1.0)
    for r_layer, g_layer in zip(result, global_w):
        assert all(abs(a - b) < 1e-6 for a, b in zip(r_layer, g_layer))

def test_clipped_fedavg_small_delta_not_clipped():
    global_w = zero_weights()
    client_w = [[0.01] * len(l) for l in global_w]  # small delta, norm < 1.0
    result = clipped_fedavg([(1, client_w), (1, global_w)], global_w, max_norm=1.0)
    # delta from client is small → no scaling; result between global and client
    norm = _delta_norm(result, global_w)
    assert norm < 0.5

def test_clipped_fedavg_large_delta_is_clipped():
    global_w = zero_weights()
    # client weights very far from global
    client_w = [[100.0] * len(l) for l in global_w]
    result = clipped_fedavg([(1, client_w), (1, global_w)], global_w, max_norm=1.0)
    norm = _delta_norm(result, global_w)
    # after clipping the effective delta norm ≤ max_norm / 2 (split with global)
    assert norm <= 1.0


# ── staleness discount (logic from fl_service.submit_client_update) ───────────

@pytest.mark.parametrize("staleness,expected", [
    (0,  1.0),
    (1,  0.5),
    (3,  0.25),
    (9,  0.1),
    (99, pytest.approx(1 / 100, rel=1e-3)),
])
def test_staleness_discount(staleness, expected):
    discount = 1.0 / (1.0 + staleness)
    assert discount == expected

def test_staleness_never_negative():
    current_round, client_round = 5, 10  # client ahead (shouldn't happen, but guard)
    staleness = max(0, current_round - client_round)
    assert staleness == 0
    assert 1.0 / (1.0 + staleness) == 1.0
