#!/usr/bin/env python3
"""
CultureQuest FL Global Model Pre-training
==========================================
Trains MLP (22->32->16->1) on prepared dataset and uploads
warm-start weights to the backend (stored in Redis).

Prerequisites:
    python backend/pretraining/prepare_data.py  # must run first

Run:
    python backend/pretraining/pretrain.py

The backend must be running at localhost:8000.
"""

import os, sys, json, time
import numpy as np
import matplotlib; matplotlib.use('Agg')
import matplotlib.pyplot as plt
import requests

# ── Config ────────────────────────────────────────────────────────────────────
OUT_DIR       = os.path.join(os.path.dirname(__file__), 'output')
CHARTS_DIR    = os.path.join(OUT_DIR, 'charts')
API_BASE      = 'http://localhost:8000/api'
ADMIN_EMAIL   = 'admin@culturequest.ro'
ADMIN_PASS    = 'admin1234'

# Training hyperparameters
EPOCHS        = 60
LR_INIT       = 0.01
LR_DECAY      = 0.98   # multiply LR by this each epoch
BATCH_SIZE    = 256
PATIENCE      = 10     # early stopping patience

# Architecture (must match model.py and fl_client_service.dart)
INPUT_DIM  = 22
H1, H2     = 32, 16
OUTPUT_DIM = 1

np.random.seed(42)

# ── Model (pure numpy, mirrors Dart implementation) ───────────────────────────

def init_weights():
    """Xavier-like initialisation."""
    scale = lambda fan_in: np.sqrt(2.0 / fan_in)
    return {
        'W1': np.random.randn(H1, INPUT_DIM).astype(np.float32) * scale(INPUT_DIM),
        'b1': np.zeros(H1, dtype=np.float32),
        'W2': np.random.randn(H2, H1).astype(np.float32) * scale(H1),
        'b2': np.zeros(H2, dtype=np.float32),
        'W3': np.random.randn(OUTPUT_DIM, H2).astype(np.float32) * scale(H2),
        'b3': np.zeros(OUTPUT_DIM, dtype=np.float32),
    }

def relu(x):      return np.maximum(0, x)
def relu_d(x):    return (x > 0).astype(np.float32)
def sigmoid(x):   return 1.0 / (1.0 + np.exp(-np.clip(x, -30, 30)))

def forward(W, x_batch):
    """x_batch: (B, 22) -> returns (out, cache)"""
    z1 = x_batch @ W['W1'].T + W['b1']
    a1 = relu(z1)
    z2 = a1 @ W['W2'].T + W['b2']
    a2 = relu(z2)
    z3 = a2 @ W['W3'].T + W['b3']
    out = sigmoid(z3).squeeze(axis=-1)   # (B,)
    return out, (z1, a1, z2, a2, z3)

def backward(W, x_batch, y_batch, cache, lr):
    z1, a1, z2, a2, z3 = cache
    B = len(y_batch)
    out = sigmoid(z3).squeeze(axis=-1)

    # MSE loss gradient
    dout = 2.0 * (out - y_batch) / B   # (B,)
    dz3  = dout[:, None] * (out * (1 - out))[:, None]  # (B,1)

    dW3 = dz3.T @ a2          # (1, H2)
    db3 = dz3.sum(axis=0)
    da2 = dz3 @ W['W3']       # (B, H2)

    dz2 = da2 * relu_d(z2)
    dW2 = dz2.T @ a1          # (H2, H1)
    db2 = dz2.sum(axis=0)
    da1 = dz2 @ W['W2']       # (B, H1)

    dz1 = da1 * relu_d(z1)
    dW1 = dz1.T @ x_batch     # (H1, 22)
    db1 = dz1.sum(axis=0)

    W['W1'] -= lr * dW1
    W['b1'] -= lr * db1
    W['W2'] -= lr * dW2
    W['b2'] -= lr * db2
    W['W3'] -= lr * dW3
    W['b3'] -= lr * db3

def mse_loss(W, X, y):
    out, _ = forward(W, X)
    return float(np.mean((out - y) ** 2))

def weights_to_list(W) -> list:
    """Flatten to the format expected by fl_client_service.dart and fl_service.py."""
    return [
        W['W1'].flatten().tolist(),   # (32*22,)
        W['b1'].tolist(),             # (32,)
        W['W2'].flatten().tolist(),   # (16*32,)
        W['b2'].tolist(),             # (16,)
        W['W3'].flatten().tolist(),   # (1*16,)
        W['b3'].tolist(),             # (1,)
    ]

# ── Training loop ─────────────────────────────────────────────────────────────

def train(X_train, y_train, X_val, y_val):
    W   = init_weights()
    lr  = LR_INIT
    best_val  = float('inf')
    best_W    = None
    patience  = 0
    train_losses, val_losses = [], []

    n = len(y_train)
    n_batches = max(1, n // BATCH_SIZE)

    print(f"\nTraining MLP {INPUT_DIM}->{H1}->{H2}->1")
    print(f"  Train: {n:,}  Val: {len(y_val):,}  Epochs: {EPOCHS}  BS: {BATCH_SIZE}  LR: {LR_INIT}")
    print("-" * 60)

    t0 = time.time()
    for epoch in range(1, EPOCHS + 1):
        # Shuffle training set
        idx = np.random.permutation(n)
        X_sh, y_sh = X_train[idx], y_train[idx]

        for b in range(n_batches):
            xb = X_sh[b*BATCH_SIZE:(b+1)*BATCH_SIZE]
            yb = y_sh[b*BATCH_SIZE:(b+1)*BATCH_SIZE]
            _, cache = forward(W, xb)
            backward(W, xb, yb, cache, lr)

        lr *= LR_DECAY

        train_loss = mse_loss(W, X_train, y_train)
        val_loss   = mse_loss(W, X_val, y_val)
        train_losses.append(train_loss)
        val_losses.append(val_loss)

        # Early stopping
        if val_loss < best_val:
            best_val = val_loss
            best_W   = {k: v.copy() for k, v in W.items()}
            patience = 0
        else:
            patience += 1

        if epoch % 5 == 0 or patience == PATIENCE:
            elapsed = time.time() - t0
            print(f"  Epoch {epoch:3d}/{EPOCHS}  train={train_loss:.4f}  val={val_loss:.4f}"
                  f"  best={best_val:.4f}  lr={lr:.5f}  [{elapsed:.0f}s]")

        if patience >= PATIENCE:
            print(f"\nEarly stopping at epoch {epoch} (no improvement for {PATIENCE} epochs)")
            break

    print(f"\nBest validation loss: {best_val:.4f}")

    # Evaluate predictions
    out_train, _ = forward(best_W, X_train)
    out_val,   _ = forward(best_W, X_val)
    print(f"Train pred range: [{out_train.min():.3f}, {out_train.max():.3f}]  mean={out_train.mean():.3f}")
    print(f"Val   pred range: [{out_val.min():.3f},  {out_val.max():.3f}]   mean={out_val.mean():.3f}")

    return best_W, train_losses, val_losses, out_val, y_val

# ── Charts ────────────────────────────────────────────────────────────────────

def save_training_charts(train_losses, val_losses, y_pred, y_true):
    fig, axes = plt.subplots(1, 3, figsize=(18, 5))

    # Loss curves
    ax = axes[0]
    ax.plot(train_losses, label='Train MSE', color='steelblue')
    ax.plot(val_losses,   label='Val MSE',   color='tomato')
    ax.set_title('Training Curves'); ax.set_xlabel('Epoch'); ax.set_ylabel('MSE Loss')
    ax.legend(); ax.grid(True, alpha=0.3)

    # Predicted vs actual
    ax = axes[1]
    ax.scatter(y_true, y_pred, alpha=0.2, s=8, color='mediumseagreen')
    ax.plot([0,1],[0,1],'--', color='red', label='Perfect')
    ax.set_title('Predicted vs Actual (Val)'); ax.set_xlabel('Actual'); ax.set_ylabel('Predicted')
    ax.legend(); ax.set_xlim(-0.05,1.05); ax.set_ylim(-0.05,1.05)

    # Residuals
    ax = axes[2]
    residuals = y_pred - y_true
    ax.hist(residuals, bins=40, color='orchid', edgecolor='white', alpha=0.8)
    ax.axvline(0, color='red', linestyle='--')
    ax.set_title('Residuals (Val)'); ax.set_xlabel('Predicted - Actual'); ax.set_ylabel('Count')
    ax.text(0.05, 0.95, f'mean={residuals.mean():.3f}\nstd={residuals.std():.3f}',
            transform=ax.transAxes, va='top', bbox=dict(boxstyle='round', alpha=0.1))

    plt.suptitle('CultureQuest FL Model Pre-training Results', fontsize=13, fontweight='bold')
    plt.tight_layout()
    path = os.path.join(CHARTS_DIR, 'training_results.png')
    plt.savefig(path, dpi=150, bbox_inches='tight')
    plt.close()
    print(f"  Chart saved: {path}")

# ── Upload to backend ─────────────────────────────────────────────────────────

def upload_weights(weights_list: list):
    print("\nUploading pre-trained weights to backend...")

    # Authenticate as admin
    resp = requests.post(f'{API_BASE}/auth/login',
                         json={'email': ADMIN_EMAIL, 'password': ADMIN_PASS},
                         timeout=10)
    if resp.status_code != 200:
        print(f"ERROR: Login failed ({resp.status_code}): {resp.text}")
        sys.exit(1)
    token = resp.json()['access_token']
    headers = {'Authorization': f'Bearer {token}'}

    # Initialize model (clears FL history, sets round=0)
    resp = requests.post(f'{API_BASE}/federated/admin/initialize',
                         json={'weights': weights_list},
                         headers=headers,
                         timeout=30)
    if resp.status_code != 200:
        print(f"ERROR: Initialize failed ({resp.status_code}): {resp.text}")
        sys.exit(1)

    data = resp.json()
    print(f"  Status: {data['status']}")
    print(f"  Layers: {data['layers']}")
    print(f"  Round:  {data['round']} (reset)")
    print("  Pre-trained weights are now the global model.")

# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    print("=" * 60)
    print("CultureQuest FL Global Model Pre-training")
    print("=" * 60)

    train_path = os.path.join(OUT_DIR, 'train.npz')
    val_path   = os.path.join(OUT_DIR, 'val.npz')
    if not os.path.exists(train_path):
        print(f"ERROR: {train_path} not found. Run prepare_data.py first.")
        sys.exit(1)

    print("Loading data...")
    train_data = np.load(train_path)
    val_data   = np.load(val_path)
    X_train, y_train = train_data['X'], train_data['y']
    X_val,   y_val   = val_data['X'],   val_data['y']
    print(f"  Train: {X_train.shape}  Val: {X_val.shape}")

    # Load stats for context
    stats_path = os.path.join(OUT_DIR, 'stats.json')
    if os.path.exists(stats_path):
        with open(stats_path) as f:
            stats = json.load(f)
        print(f"  Label mean={stats['label_mean']:.3f}  std={stats['label_std']:.3f}")

    # Train
    best_W, train_losses, val_losses, y_pred, y_true = train(X_train, y_train, X_val, y_val)

    # Save weights locally (backup)
    weights_list = weights_to_list(best_W)
    weights_path = os.path.join(OUT_DIR, 'pretrained_weights.json')
    with open(weights_path, 'w') as f:
        json.dump({'round': 0, 'weights': weights_list}, f)
    print(f"\nWeights saved locally: {weights_path}")

    # Charts
    print("Generating training charts...")
    save_training_charts(train_losses, val_losses, y_pred, y_true)

    # Upload to backend
    upload_weights(weights_list)

    print("\nPre-training complete.")
    print("Devices will receive these weights on next FL sync.")

if __name__ == '__main__':
    main()
