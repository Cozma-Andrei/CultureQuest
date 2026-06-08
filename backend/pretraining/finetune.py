#!/usr/bin/env python3
"""
CultureQuest FL Global Model Fine-tuning

Continues training from the pre-trained weights (does NOT reinitialise).
Addresses two weaknesses identified in pretraining:
  1. Too few low-label examples -> model collapses toward mean (~0.74)
  2. LR decayed too fast -> model stuck in plateau after epoch 5

Differences from pretrain.py:
  - Loads weights from pretrained_weights.json instead of random init
  - Augments training data with more synthetic low-label samples
  - Oversamples records with label <= 0.40 (low engagement) by 3x
  - Uses LR=0.02 with slower decay (0.995) to escape the plateau
    without catastrophically overwriting what pretraining learned

Run AFTER pretrain.py:
    python backend/pretraining/finetune.py

The backend must be running at localhost:8000.
"""

import os, sys, json, time, random
import numpy as np
import matplotlib; matplotlib.use('Agg')
import matplotlib.pyplot as plt
import requests

OUT_DIR    = os.path.join(os.path.dirname(__file__), 'output')
CHARTS_DIR = os.path.join(OUT_DIR, 'charts')
API_BASE   = 'http://localhost:8000/api'
ADMIN_EMAIL = 'admin@culturequest.ro'
ADMIN_PASS  = 'admin1234'

# Fine-tuning hyperparameters
# Lower LR than scratch training (0.01) to avoid catastrophic forgetting,
# but higher than where pretraining stalled (~0.003 at epoch 60).
FT_LR_INIT  = 0.02
FT_LR_DECAY = 0.995   # much slower than pretraining's 0.98
FT_EPOCHS   = 40
BATCH_SIZE  = 256
PATIENCE    = 12

INPUT_DIM = 22
H1, H2    = 32, 16
TYPES     = ['museum', 'monument', 'park', 'gallery', 'restaurant', 'square', 'building', 'other']

np.random.seed(42)
random.seed(42)

# Model (identical to pretrain.py)

def relu(x):    return np.maximum(0, x)
def relu_d(x):  return (x > 0).astype(np.float32)
def sigmoid(x): return 1.0 / (1.0 + np.exp(-np.clip(x, -30, 30)))

def weights_from_list(wl: list) -> dict:
    return {
        'W1': np.array(wl[0], dtype=np.float32).reshape(H1, INPUT_DIM),
        'b1': np.array(wl[1], dtype=np.float32),
        'W2': np.array(wl[2], dtype=np.float32).reshape(H2, H1),
        'b2': np.array(wl[3], dtype=np.float32),
        'W3': np.array(wl[4], dtype=np.float32).reshape(1,  H2),
        'b3': np.array(wl[5], dtype=np.float32),
    }

def weights_to_list(W) -> list:
    return [
        W['W1'].flatten().tolist(), W['b1'].tolist(),
        W['W2'].flatten().tolist(), W['b2'].tolist(),
        W['W3'].flatten().tolist(), W['b3'].tolist(),
    ]

def forward(W, x):
    z1 = x @ W['W1'].T + W['b1'];  a1 = relu(z1)
    z2 = a1 @ W['W2'].T + W['b2']; a2 = relu(z2)
    z3 = a2 @ W['W3'].T + W['b3']
    return sigmoid(z3).squeeze(-1), (z1, a1, z2, a2)

def backward(W, x, y, cache, lr, max_norm: float = 1.0):
    z1, a1, z2, a2 = cache
    out, _ = forward(W, x)
    B = len(y)
    dout = 2.0 * (out - y) / B
    dz3  = dout[:, None] * (out * (1 - out))[:, None]
    dW3 = dz3.T @ a2;  db3 = dz3.sum(0)
    da2 = dz3 @ W['W3']
    dz2 = da2 * relu_d(z2);  dW2 = dz2.T @ a1; db2 = dz2.sum(0)
    da1 = dz2 @ W['W2']
    dz1 = da1 * relu_d(z1);  dW1 = dz1.T @ x;  db1 = dz1.sum(0)

    # NaN guard
    if any(np.isnan(g).any() or np.isinf(g).any() for g in [dW1, dW2, dW3]):
        return

    # Global gradient norm clipping
    all_g = np.concatenate([g.flatten() for g in [dW1, db1, dW2, db2, dW3, db3]])
    norm  = np.linalg.norm(all_g)
    scale = min(1.0, max_norm / norm) if norm > 0 else 1.0

    W['W1'] -= lr*scale*dW1; W['b1'] -= lr*scale*db1
    W['W2'] -= lr*scale*dW2; W['b2'] -= lr*scale*db2
    W['W3'] -= lr*scale*dW3; W['b3'] -= lr*scale*db3

def mse(W, X, y):
    out, _ = forward(W, X)
    return float(np.mean((out - y)**2))

# Data augmentation

TYPE_HOUR_RANGES = {
    'museum':     (10/24, 18/24), 'gallery':    (10/24, 20/24),
    'park':       ( 8/24, 21/24), 'restaurant': (11/24, 23/24),
    'monument':   ( 9/24, 19/24), 'square':     (10/24, 23/24),
    'building':   ( 9/24, 18/24), 'other':      ( 9/24, 20/24),
}
INTERESTS = ['art','architecture','history','gastronomy','nature','music']
INTEREST_PROFILES = [
    ['art'],['history'],['gastronomy'],['nature'],['music'],['architecture'],
    ['art','history'],['gastronomy','nature'],['art','music'],
    ['history','architecture'],['nature','music'],['art','architecture','history'],
]

def build_closed_fv(lm_type: str) -> np.ndarray:
    v = np.zeros(INPUT_DIM, dtype=np.float32)
    ints = random.choice(INTEREST_PROFILES)
    for i, ing in enumerate(INTERESTS):
        if ing in ints: v[i] = 1.0
    ti = TYPES.index(lm_type) if lm_type in TYPES else 7
    v[6 + ti] = 1.0
    v[14] = 0.0                        # isOpen = False
    v[15] = 1.0 if random.random() > 0.5 else 0.0
    lo, hi = TYPE_HOUR_RANGES.get(lm_type, (9/24, 20/24))
    # Night / early-morning hours
    v[16] = random.uniform(22/24, 1.0) if random.random() > 0.4 else random.uniform(0, 8/24)
    v[17] = 0.5   # relativeDistanceRank neutral
    # interestMatchScore
    type_ints = {'museum':['art','history'],'gallery':['art'],'park':['nature'],
                 'restaurant':['gastronomy'],'monument':['history','architecture'],
                 'square':['music'],'building':['architecture']}.get(lm_type,[])
    v[18] = len(set(ints) & set(type_ints)) / max(len(ints), 1)
    return v

def generate_extra_closed(n_per_type: int = 2000) -> tuple:
    """Extra synthetic closed samples beyond those in train.npz."""
    X, y = [], []
    for t in TYPES:
        for _ in range(n_per_type):
            X.append(build_closed_fv(t))
            y.append(0.10)
    return np.array(X, dtype=np.float32), np.array(y, dtype=np.float32)

def oversample_low_label(X: np.ndarray, y: np.ndarray,
                          threshold: float = 0.40,
                          factor: int = 3) -> tuple:
    """
    Duplicate records with label <= threshold by `factor` times.
    Compensates for:
    - Type balancing that removed many low-star Yelp restaurant reviews
    - Yelp's natural positive skew (60% of reviews are 4-5 stars)
    """
    mask = y <= threshold
    n_low = mask.sum()
    X_low, y_low = X[mask], y[mask]
    X_aug = np.tile(X_low, (factor - 1, 1))
    y_aug = np.tile(y_low, factor - 1)
    X_out = np.concatenate([X, X_aug], axis=0)
    y_out = np.concatenate([y, y_aug], axis=0)
    print(f"  Low-label records (≤{threshold}): {n_low:,} -> {n_low * factor:,} after {factor}x oversample")
    return X_out, y_out

# Training loop

def finetune(W, X_train, y_train, X_val, y_val):
    lr       = FT_LR_INIT
    best_val = float('inf')
    best_W   = None
    patience = 0
    train_losses, val_losses = [], []
    n = len(y_train)

    # Prediction range before fine-tuning
    pre_out, _ = forward(W, X_val)
    print(f"\nBefore fine-tuning:")
    print(f"  Val MSE={mse(W, X_val, y_val):.4f}  pred=[{pre_out.min():.3f},{pre_out.max():.3f}]  mean={pre_out.mean():.3f}")

    print(f"\nFine-tuning MLP {INPUT_DIM}->{H1}->{H2}->1")
    print(f"  Train: {n:,}  Val: {len(y_val):,}  Epochs: {FT_EPOCHS}  LR: {FT_LR_INIT}  Decay: {FT_LR_DECAY}")

    t0 = time.time()
    n_batches = max(1, n // BATCH_SIZE)

    for epoch in range(1, FT_EPOCHS + 1):
        idx = np.random.permutation(n)
        Xs, ys = X_train[idx], y_train[idx]
        for b in range(n_batches):
            xb = Xs[b*BATCH_SIZE:(b+1)*BATCH_SIZE]
            yb = ys[b*BATCH_SIZE:(b+1)*BATCH_SIZE]
            _, cache = forward(W, xb)
            backward(W, xb, yb, cache, lr)
        lr *= FT_LR_DECAY

        tl = mse(W, X_train, y_train)
        vl = mse(W, X_val,   y_val)
        train_losses.append(tl); val_losses.append(vl)

        if vl < best_val:
            best_val = vl
            best_W   = {k: v.copy() for k, v in W.items()}
            patience = 0
        else:
            patience += 1

        if epoch % 5 == 0 or patience == PATIENCE:
            elapsed = time.time() - t0
            print(f"  Epoch {epoch:3d}/{FT_EPOCHS}  train={tl:.4f}  val={vl:.4f}"
                  f"  best={best_val:.4f}  lr={lr:.5f}  [{elapsed:.0f}s]")

        if patience >= PATIENCE:
            print(f"\nEarly stopping at epoch {epoch}")
            break

    post_out, _ = forward(best_W, X_val)
    print(f"\nAfter fine-tuning:")
    print(f"  Best val MSE={best_val:.4f}  pred=[{post_out.min():.3f},{post_out.max():.3f}]  mean={post_out.mean():.3f}")
    print(f"  Prediction range widened by: {(post_out.max()-post_out.min()) - (pre_out.max()-pre_out.min()):.3f}")

    return best_W, train_losses, val_losses, post_out, y_val

# Charts

def save_charts(train_losses, val_losses, y_pred, y_true,
                pre_pred_range, post_pred_range):
    fig, axes = plt.subplots(1, 3, figsize=(18, 5))

    ax = axes[0]
    ax.plot(train_losses, label='Train MSE', color='steelblue')
    ax.plot(val_losses,   label='Val MSE',   color='tomato')
    ax.set_title('Fine-tuning Loss Curves')
    ax.set_xlabel('Epoch'); ax.set_ylabel('MSE Loss')
    ax.legend(); ax.grid(True, alpha=0.3)

    ax = axes[1]
    ax.scatter(y_true, y_pred, alpha=0.15, s=6, color='mediumseagreen')
    ax.plot([0,1],[0,1],'--', color='red', label='Perfect')
    ax.set_title('Predicted vs Actual (Val)')
    ax.set_xlabel('Actual'); ax.set_ylabel('Predicted')
    ax.legend(); ax.set_xlim(-0.05,1.05); ax.set_ylim(-0.05,1.05)

    ax = axes[2]
    labels = ['Pre-finetune', 'Post-finetune']
    ranges = [pre_pred_range, post_pred_range]
    bars = ax.bar(labels, ranges, color=['lightcoral','steelblue'], alpha=0.8)
    ax.set_title('Prediction Range Width\n(wider = better differentiation)')
    ax.set_ylabel('max(pred) - min(pred)')
    for bar, r in zip(bars, ranges):
        ax.text(bar.get_x()+bar.get_width()/2, bar.get_height()+0.002,
                f'{r:.3f}', ha='center', va='bottom', fontweight='bold')
    ax.set_ylim(0, max(ranges)*1.3)

    plt.suptitle('CultureQuest FL Fine-tuning Results', fontsize=13, fontweight='bold')
    plt.tight_layout()
    path = os.path.join(CHARTS_DIR, 'finetune_results.png')
    plt.savefig(path, dpi=150, bbox_inches='tight')
    plt.close()
    print(f"  Chart saved: {path}")

# Upload

def upload(weights_list: list):
    print("\nUploading fine-tuned weights to backend...")
    resp = requests.post(f'{API_BASE}/auth/login',
                         json={'email': ADMIN_EMAIL, 'password': ADMIN_PASS}, timeout=10)
    token = resp.json()['access_token']
    resp = requests.post(f'{API_BASE}/federated/admin/initialize',
                         json={'weights': weights_list},
                         headers={'Authorization': f'Bearer {token}'}, timeout=30)
    data = resp.json()
    print(f"  Status: {data['status']}  Round: {data['round']} (reset)")

# Main

def main():
    print("CultureQuest FL Global Model Fine-tuning")

    # Load base weights
    weights_path = os.path.join(OUT_DIR, 'pretrained_weights.json')
    if not os.path.exists(weights_path):
        print(f"ERROR: {weights_path} not found. Run pretrain.py first.")
        sys.exit(1)
    with open(weights_path) as f:
        data = json.load(f)
    W = weights_from_list(data['weights'])
    print(f"Loaded pre-trained weights (round {data.get('round', 0)})")

    # Load base training data
    train_data = np.load(os.path.join(OUT_DIR, 'train.npz'))
    val_data   = np.load(os.path.join(OUT_DIR, 'val.npz'))
    X_train, y_train = train_data['X'], train_data['y']
    X_val,   y_val   = val_data['X'],   val_data['y']
    print(f"Base train: {X_train.shape}  Val: {X_val.shape}")
    print(f"Label mean={y_train.mean():.3f}  std={y_train.std():.3f}")

    # Measure pre-finetune prediction range
    pre_out, _ = forward(W, X_val)
    pre_range  = float(pre_out.max() - pre_out.min())

    # --- Fix 1: more synthetic closed samples ---
    print("\n[Augmentation] Adding extra synthetic closed samples...")
    X_closed, y_closed = generate_extra_closed(n_per_type=2000)
    print(f"  Extra closed: {len(y_closed):,} (2,000 per type × {len(TYPES)} types)")

    X_train = np.concatenate([X_train, X_closed], axis=0)
    y_train = np.concatenate([y_train, y_closed], axis=0)

    # --- Fix 2: oversample existing low-label records ---
    print("\n[Augmentation] Oversampling low-label records (label <= 0.40)...")
    X_train, y_train = oversample_low_label(X_train, y_train, threshold=0.40, factor=3)

    print(f"\nAugmented train: {X_train.shape}  label mean={y_train.mean():.3f}  std={y_train.std():.3f}")

    # Shuffle
    idx = np.random.permutation(len(y_train))
    X_train, y_train = X_train[idx], y_train[idx]

    # Fine-tune
    best_W, train_losses, val_losses, y_pred, y_true = finetune(W, X_train, y_train, X_val, y_val)

    # Measure post-finetune prediction range
    post_range = float(y_pred.max() - y_pred.min())

    # Save weights
    weights_list = weights_to_list(best_W)
    ft_path = os.path.join(OUT_DIR, 'finetuned_weights.json')
    with open(ft_path, 'w') as f:
        json.dump({'round': 0, 'weights': weights_list,
                   'note': 'fine-tuned from pretrained_weights.json'}, f)
    print(f"\nWeights saved: {ft_path}")

    # Charts
    print("Generating charts...")
    save_charts(train_losses, val_losses, y_pred, y_true, pre_range, post_range)

    # Upload
    upload(weights_list)

    # Summary
    print(f"\nPrediction range: {pre_range:.3f} -> {post_range:.3f}  "
          f"({'wider' if post_range > pre_range else 'narrower'})")
    print("Fine-tuning complete.")

if __name__ == '__main__':
    main()
