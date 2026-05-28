import numpy as np

# Architecture: 16 → 32 → 16 → 1
# Input: 6 user interests (one-hot) + 8 landmark types (one-hot) + hour/24 + distance/1500
INPUT_DIM = 16
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


def build_initial_weights() -> list[list[float]]:
    result = []
    for shape in LAYER_SHAPES:
        if len(shape) == 2:
            w = np.random.randn(*shape) * 0.1
        else:
            w = np.zeros(shape)
        result.append(w.flatten().tolist())
    return result


def fedavg(updates: list[tuple[int, list[list[float]]]]) -> list[list[float]]:
    """Weighted average of weight tensors across client updates."""
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
