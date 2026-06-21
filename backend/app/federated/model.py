import math
import numpy as np

# Architecture: 22 -> 32 -> 16 -> 1
# Input (22 dims):
#  [0-5]  user interests one-hot     (art, architecture, history, gastronomy, nature, music)
#  [6-13] landmark type one-hot      (museum, monument, park, gallery, restaurant, square, building, other)
#  [14]   isOpen                     binary
#  [15]   isWeekend                  binary
#  [16]   hour / 24.0                float
#  [17]   relativeDistanceRank       float [0=closest, 1=farthest]
#  [18]   interestMatchScore         float [0,1]
#  [19]   isPartOfRoute              binary
#  [20]   routeStopNormalized        float [0,1]
#  [21]   routeLengthNormalized      float [0,1]
INPUT_DIM = 22
HIDDEN_DIMS = [32, 16]
OUTPUT_DIM = 1

# Each tuple is the shape of one tensor stored in (out, in) order so that
# z = W @ x + b works directly. Flattened order: W1, b1, W2, b2, W3, b3.
LAYER_SHAPES = [
    (HIDDEN_DIMS[0], INPUT_DIM),         # W1: (32, 16)
    (HIDDEN_DIMS[0],),                   # b1: (32,)
    (HIDDEN_DIMS[1], HIDDEN_DIMS[0]),    # W2: (16, 32)
    (HIDDEN_DIMS[1],),                   # b2: (16,)
    (OUTPUT_DIM,    HIDDEN_DIMS[1]),     # W3: (1,  16)
    (OUTPUT_DIM,),                       # b3: (1,)
]


def fl_predict(weights: list[list[float]], x: list[float]) -> float:
    """Single-sample inference: weights = [W1, b1, W2, b2, W3, b3]."""
    W1 = np.array(weights[0]).reshape(HIDDEN_DIMS[0], INPUT_DIM)
    b1 = np.array(weights[1])
    W2 = np.array(weights[2]).reshape(HIDDEN_DIMS[1], HIDDEN_DIMS[0])
    b2 = np.array(weights[3])
    W3 = np.array(weights[4]).reshape(OUTPUT_DIM, HIDDEN_DIMS[1])
    b3 = np.array(weights[5])
    a = np.array(x, dtype=np.float32)
    a = np.maximum(0, W1 @ a + b1)
    a = np.maximum(0, W2 @ a + b2)
    return float(1.0 / (1.0 + np.exp(-np.clip((W3 @ a + b3)[0], -30, 30))))


def build_initial_weights() -> list[list[float]]:
    result = []
    for shape in LAYER_SHAPES:
        if len(shape) == 2:
            w = np.random.randn(*shape) * 0.1
        else:
            w = np.zeros(shape)
        result.append(w.flatten().tolist())
    return result


def avg(updates: list[tuple[int, list[list[float]]]]) -> list[list[float]]:
    """Weighted average of weight tensors across client updates.
    Kept for baseline comparison; use clipped_avg in production."""
    total = sum(n for n, _ in updates)
    result: list[list[float]] | None = None
    for n_samples, client_weights in updates:
        factor = n_samples / total
        if result is None:
            result = [[v * factor for v in layer] for layer in client_weights]
        else:
            for i, layer in enumerate(client_weights):
                result[i] = [acc + v * factor for acc, v in zip(result[i], layer)]
    return result  # type: ignore[return-value]


def clipped_avg(
    updates: list[tuple[int, list[list[float]]]],
    global_weights: list[list[float]],
    max_norm: float = 1.0,
) -> list[list[float]]:
    """FedAvg with per-client delta norm clipping (production aggregator).

    For async FL (one client per round) coordinate-wise median/trimmed-mean
    are not applicable: there is only one incoming update to compare against.
    Delta clipping is the standard defence: each client's update is allowed to
    move the global model by at most max_norm in L2 distance. A malicious client
    that rates everything adversarially will produce a large-norm delta that gets
    scaled down to max_norm before being averaged in, limiting its influence to
    at most max_norm / global_virtual_samples per weight coordinate.
    """
    clipped: list[tuple[int, list[list[float]]]] = []
    for n_samples, client_weights in updates:
        delta = [
            [c - g for c, g in zip(cl, gl)]
            for cl, gl in zip(client_weights, global_weights)
        ]
        norm = math.sqrt(sum(v ** 2 for layer in delta for v in layer))
        scale = min(1.0, max_norm / max(norm, 1e-8))
        clipped_weights = [
            [g + d * scale for g, d in zip(gl, dl)]
            for gl, dl in zip(global_weights, delta)
        ]
        clipped.append((n_samples, clipped_weights))
    return avg(clipped)


