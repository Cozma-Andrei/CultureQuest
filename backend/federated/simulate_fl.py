#!/usr/bin/env python3
"""
FL simulation: measures the effect of the FedAsync staleness discount and
server-side delta-norm clipping over N rounds with N_CLIENTS synthetic clients.
Run from backend/: python federated/simulate_fl.py
Results written to backend/federated/results/
"""
import sys, os, json, math, random, asyncio
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from app.federated.model import build_initial_weights, fedavg, clipped_fedavg, fl_predict, INPUT_DIM, HIDDEN_DIMS

# Config
N_CLIENTS              = 1000
N_ROUNDS               = 100
INTERACTIONS_PER_ROUND = 15
LEARNING_RATE          = 0.01
LOCAL_EPOCHS           = 5
DP_SIGMA               = 0.1
DP_CLIP_NORM           = 1.0
SERVER_MAX_NORM        = 1.0
STALENESS_MAX          = 20    # max rounds a client can be behind the global model
SEED                   = 42
RESULTS_DIR            = os.path.join(os.path.dirname(__file__), 'results')
# Redis URL: override via REDIS_URL env var.
# Inside Docker: redis://:secret@redis:6379/0
# Outside Docker (default): redis://:secret@localhost:6379/0
REDIS_URL              = os.environ.get('REDIS_URL', 'redis://:secret@localhost:6379/0')

# Domain
INTERESTS = ['art', 'architecture', 'history', 'gastronomy', 'nature', 'music']
TYPES     = ['museum', 'monument', 'park', 'gallery', 'restaurant', 'square', 'building', 'other']

AFFINITY = {
    'art':          {'gallery', 'museum'},
    'architecture': {'monument', 'building'},
    'history':      {'museum', 'monument'},
    'gastronomy':   {'restaurant'},
    'nature':       {'park'},
    'music':        {'square'},
}

# Feature vector
def _fv(interests, ltype):
    matched = set().union(*(AFFINITY.get(i, set()) for i in interests))
    return np.array(
        [1.0 if i in interests else 0.0 for i in INTERESTS] +
        [1.0 if t == ltype else 0.0 for t in TYPES] +
        [float(random.random() > 0.2),          # isOpen
         float(random.random() > 0.7),          # isWeekend
         random.randint(8, 22) / 24.0,          # hour
         random.random(),                        # distRank
         1.0 if ltype in matched else 0.0,      # interestMatch
         0.0, 0.0, 0.0],                        # route dims (unused here)
        dtype=np.float32,
    )

def _generate_interaction(interests):
    ltype   = random.choice(TYPES)
    matched = ltype in set().union(*(AFFINITY.get(i, set()) for i in interests))
    label   = random.uniform(0.65, 0.95) if matched else random.uniform(0.05, 0.40)
    return _fv(interests, ltype), label

def _make_test_set(n=300):
    data = []
    for _ in range(n):
        interests = random.sample(INTERESTS, random.randint(1, 3))
        data.append(_generate_interaction(interests))
    return data

# Forward / backward (pure Python, mirrors Dart client)
def _forward(weights, x):
    W1 = np.array(weights[0]).reshape(HIDDEN_DIMS[0], INPUT_DIM)
    b1 = np.array(weights[1])
    W2 = np.array(weights[2]).reshape(HIDDEN_DIMS[1], HIDDEN_DIMS[0])
    b2 = np.array(weights[3])
    W3 = np.array(weights[4]).reshape(1, HIDDEN_DIMS[1])
    b3 = np.array(weights[5])
    z1 = W1 @ x + b1;  a1 = np.maximum(0.0, z1)
    z2 = W2 @ a1 + b2; a2 = np.maximum(0.0, z2)
    z3 = (W3 @ a2 + b3)[0]
    a3 = float(1.0 / (1.0 + np.exp(-np.clip(z3, -30, 30))))
    return a3, (x, z1, a1, z2, a2, W1, W2, W3)

def _backward(weights, cache, y):
    x, z1, a1, z2, a2, W1, W2, W3 = cache
    a3 = float(1.0 / (1.0 + np.exp(-np.clip((W3 @ a2 + np.array(weights[5]))[0], -30, 30))))

    dz3 = np.array([a3 - y])
    dW3 = np.outer(dz3, a2);  db3 = dz3.copy()

    da2 = W3.T @ dz3
    dz2 = da2 * (z2 > 0);     dW2 = np.outer(dz2, a1); db2 = dz2.copy()

    da1 = W2.T @ dz2
    dz1 = da1 * (z1 > 0);     dW1 = np.outer(dz1, x);  db1 = dz1.copy()

    grads = [dW1.flatten(), db1, dW2.flatten(), db2, dW3.flatten(), db3]
    return [g.tolist() for g in grads]

def _train_local(weights, data, lr, epochs):
    w = [list(layer) for layer in weights]
    for _ in range(epochs):
        random.shuffle(data)
        for x, y in data:
            pred, cache = _forward(w, x)
            grads = _backward(w, cache, y)
            for i in range(len(w)):
                w[i] = (np.array(w[i]) - lr * np.array(grads[i])).tolist()
    return w

def _add_dp_noise(local_w, global_w):
    result = []
    for lw, gw in zip(local_w, global_w):
        delta = np.clip(np.array(lw) - np.array(gw), -DP_CLIP_NORM, DP_CLIP_NORM)
        delta += np.random.normal(0, DP_SIGMA * DP_CLIP_NORM, size=delta.shape)
        result.append((np.array(gw) + delta).tolist())
    return result

def _bce_loss(weights, data):
    total = 0.0
    for x, y in data:
        p, _ = _forward(weights, x)
        p = max(1e-7, min(1 - 1e-7, p))
        total += -(y * math.log(p) + (1 - y) * math.log(1 - p))
    return total / len(data)

def _drift(local_w, global_w):
    return math.sqrt(sum(
        float(np.dot(np.array(lw) - np.array(gw), np.array(lw) - np.array(gw)))
        for lw, gw in zip(local_w, global_w)
    ))

# Probe samples (deterministic, no randomness)
def _static_fv(interests, ltype):
    matched = set().union(*(AFFINITY.get(i, set()) for i in interests))
    return np.array(
        [1.0 if i in interests else 0.0 for i in INTERESTS] +
        [1.0 if t == ltype else 0.0 for t in TYPES] +
        [1.0, 0.0, 14/24, 0.3, 1.0 if ltype in matched else 0.0, 0.0, 0.0, 0.0],
        dtype=np.float32,
    )

PROBES = {
    'gastronomy→restaurant': (_static_fv(['gastronomy'], 'restaurant'), 0.90),
    'gastronomy→park':       (_static_fv(['gastronomy'], 'park'),       0.10),
    'nature→park':           (_static_fv(['nature'],     'park'),       0.90),
    'nature→restaurant':     (_static_fv(['nature'],     'restaurant'), 0.10),
    'art→gallery':           (_static_fv(['art'],         'gallery'),   0.90),
    'history→museum':        (_static_fv(['history'],     'museum'),    0.90),
}

# Simulation
def run_simulation(initial_weights, clients, test_data, use_fedasync=True):
    """Runs N_ROUNDS of the production client/server pipeline (local SGD, DP
    noise, clipped_fedavg) from the same starting weights and client sequence.

    use_fedasync toggles the staleness discount: when on, each round mirrors
    submit_client_update in fl_service.py and weights the client's contribution
    by 1 / (1 + staleness); when off every update counts equally regardless of
    how stale the client's snapshot was, which is what the global model would
    see without FedAsync.
    """
    gw = [list(layer) for layer in initial_weights]
    loss_hist, drift_hist, eff_weight_hist, staleness_hist = [], [], [], []

    for rnd in range(N_ROUNDS):
        interests = random.choice(clients)
        data      = [_generate_interaction(interests) for _ in range(INTERACTIONS_PER_ROUND)]

        # FedAsync staleness discount (Xie et al., arXiv:1903.03934, 2019):
        # the client trained on weights from `staleness` rounds ago, so its
        # vote is discounted proportionally to how outdated that snapshot is.
        staleness = random.randint(0, STALENESS_MAX)
        discount  = (1.0 / (1.0 + staleness)) if use_fedasync else 1.0
        effective = max(1, round(len(data) * discount))
        eff_weight_hist.append(discount)
        staleness_hist.append(staleness)

        local_w = _train_local(gw, data, LEARNING_RATE, LOCAL_EPOCHS)
        drift_hist.append(_drift(local_w, gw))

        noisy_w = _add_dp_noise(local_w, gw)
        virtual = max(effective * 4, 20)   # mirrors global_virtual_samples in submit_client_update
        gw = clipped_fedavg([(effective, noisy_w), (virtual, gw)], gw, max_norm=SERVER_MAX_NORM)

        loss_hist.append(_bce_loss(gw, test_data))

        if (rnd + 1) % 20 == 0:
            tag = 'fedasync' if use_fedasync else 'no-discount'
            print(f'  [{tag:11s}] round {rnd+1:3d}/{N_ROUNDS}  '
                  f'loss={loss_hist[-1]:.4f}  drift={drift_hist[-1]:.4f}  '
                  f'eff_weight={discount:.2f} (staleness={staleness})')

    probes = {name: fl_predict(gw, fv.tolist()) for name, (fv, _) in PROBES.items()}
    return {'loss': loss_hist, 'drift': drift_hist, 'effective_weight': eff_weight_hist,
            'staleness': staleness_hist, 'probes': probes,
            'final_loss': loss_hist[-1], 'min_loss': min(loss_hist),
            'avg_drift': float(np.mean(drift_hist)),
            'avg_effective_weight': float(np.mean(eff_weight_hist)),
            'last_staleness': staleness_hist[-1],
            'weights': gw}

# Adversarial-update sweep (for the clipping comparison)
def sweep_clipping_robustness(initial_weights):
    """One rogue client submits an update whose raw weight delta has a growing
    L2 norm (think: a buggy client, or a malicious one trying to steer the
    model). Aggregates that single update via plain `fedavg` (no clipping) and
    via production `clipped_fedavg`, and measures how far each pushes the
    global model from where it started.

    Plain FedAvg has no defence: drift grows linearly with the rogue delta's
    norm. Clipped FedAvg rescales any delta whose norm exceeds `max_norm`
    before averaging, so the resulting drift plateaus regardless of how
    extreme the rogue update is.
    """
    gw = [list(layer) for layer in initial_weights]
    n_samples = INTERACTIONS_PER_ROUND
    virtual   = max(n_samples * 4, 20)   # mirrors global_virtual_samples in submit_client_update
    target_norms = np.linspace(0.25, 25, 20)
    plain_drift, clipped_drift = [], []

    for target in target_norms:
        direction = [np.random.randn(len(layer)) for layer in gw]
        flat_norm = math.sqrt(sum(float(np.dot(d, d)) for d in direction))
        delta     = [d / flat_norm * target for d in direction]
        rogue_w   = [(np.array(layer) + d).tolist() for layer, d in zip(gw, delta)]

        plain_gw   = fedavg([(n_samples, rogue_w), (virtual, gw)])
        clipped_gw = clipped_fedavg([(n_samples, rogue_w), (virtual, gw)], gw, max_norm=SERVER_MAX_NORM)
        plain_drift.append(_drift(plain_gw, gw))
        clipped_drift.append(_drift(clipped_gw, gw))

    return target_norms.tolist(), plain_drift, clipped_drift

# Plots
def _smooth(vals, k=5):
    return np.convolve(vals, np.ones(k) / k, mode='valid')

def _save(fig, name):
    path = os.path.join(RESULTS_DIR, name)
    fig.savefig(path, dpi=150)
    plt.close(fig)
    print(f'  saved {path}')

def plot_loss(res):
    """Global model loss over training rounds in the production configuration
    (FedAsync discount enabled)."""
    fig, ax = plt.subplots(figsize=(9, 5))
    init_loss = res['initial']['loss']
    rounds = np.arange(0, N_ROUNDS + 1)
    k = 5
    sr = rounds[k - 1:]
    full_loss = [init_loss] + res['fedasync']['loss']
    ax.plot(sr, _smooth(full_loss, k), '-', linewidth=2, color='C0', label='Global model (production)')
    ax.set_xlabel('Round'); ax.set_ylabel('BCE loss (test set)')
    ax.set_title('Global Model Loss over Training Rounds')
    ax.legend(); ax.grid(True, alpha=0.3); fig.tight_layout()
    _save(fig, 'loss_curve.png')

def plot_drift(res):
    fig, ax = plt.subplots(figsize=(9, 5))
    rounds = np.arange(1, N_ROUNDS + 1)
    k = 5; sr = rounds[k - 1:]
    ax.plot(sr, _smooth(res['fedasync']['drift'], k), '-', linewidth=2, color='C0', label='Local SGD drift')
    ax.set_xlabel('Round'); ax.set_ylabel('L2 norm (local minus global)')
    ax.set_title('Local Weight Drift per Round')
    ax.legend(); ax.grid(True, alpha=0.3); fig.tight_layout()
    _save(fig, 'weight_drift.png')

def plot_fedasync_effect(res):
    """Loss with vs without the FedAsync staleness discount, all else identical."""
    fig, ax = plt.subplots(figsize=(9, 5))
    init_loss = res['initial']['loss']
    rounds = np.arange(0, N_ROUNDS + 1)
    k = 5; sr = rounds[k - 1:]
    for key, color, ls, label in (
        ('fedasync',    'C0', '-',  'With FedAsync discount'),
        ('no_fedasync', 'C1', '--', 'Without discount (every update counted equally)'),
    ):
        full = [init_loss] + res[key]['loss']
        ax.plot(sr, _smooth(full, k), ls, label=label, linewidth=2, color=color)
    ax.set_xlabel('Round'); ax.set_ylabel('BCE loss (test set)')
    ax.set_title('FedAsync Staleness Discount: Effect on Global Loss')
    ax.legend(); ax.grid(True, alpha=0.3); fig.tight_layout()
    _save(fig, 'fedasync_effect.png')

def plot_probes(res):
    labels   = list(PROBES.keys())
    expected = [v for _, v in PROBES.values()]
    x = np.arange(len(labels)); w = 0.25
    fig, ax = plt.subplots(figsize=(13, 6))
    ax.bar(x - w, expected,                                       w, label='Expected', color='lightgray', edgecolor='black')
    ax.bar(x,     [res['initial']['probes'][l]  for l in labels], w, label='Initial',  color='#aaaaaa',   edgecolor='black')
    ax.bar(x + w, [res['fedasync']['probes'][l] for l in labels], w, label='Trained',  color='C0')
    ax.set_xticks(x); ax.set_xticklabels(labels, rotation=18, ha='right', fontsize=9)
    ax.set_ylabel('Predicted engagement'); ax.set_ylim(0, 1.15)
    ax.set_title('Probe Scores: Initial vs Trained vs Expected')
    ax.legend(); ax.grid(True, alpha=0.3, axis='y'); fig.tight_layout()
    _save(fig, 'probe_scores.png')

def plot_fedasync_discount_curve():
    """Pure illustration of the FedAsync weighting function itself:
    discount = 1 / (1 + staleness), and the effective sample count it produces
    for a typical round (15 raw interactions)."""
    fig, ax = plt.subplots(figsize=(9, 5))
    staleness = np.arange(0, STALENESS_MAX + 1)
    discount  = 1.0 / (1.0 + staleness)
    effective = np.maximum(1, np.round(INTERACTIONS_PER_ROUND * discount))

    line1, = ax.plot(staleness, discount, 'o-', linewidth=2, color='C0',
                     label='Discount = 1 / (1 + staleness)')
    ax.set_xlabel('Staleness (rounds behind the global model)')
    ax.set_ylabel('Discount applied to the client update')
    ax.set_ylim(0, 1.05)
    ax.set_title('FedAsync Discount Function')

    ax2 = ax.twinx()
    line2, = ax2.plot(staleness, effective, 's--', linewidth=1.5, color='C1', alpha=0.8,
                      label=f'Effective samples (raw count = {INTERACTIONS_PER_ROUND})')
    ax2.set_ylabel('Effective sample count')

    ax.legend(handles=[line1, line2], loc='upper right')
    ax.grid(True, alpha=0.3); fig.tight_layout()
    _save(fig, 'fedasync_discount_curve.png')

def plot_clipping_robustness(norms, plain_drift, clipped_drift):
    """Compares plain fedavg (unclipped) against production clipped_fedavg
    when merging a single rogue update of growing magnitude."""
    fig, ax = plt.subplots(figsize=(9, 5))
    ax.plot(norms, plain_drift,   'o-', linewidth=2, color='C3', label='Plain FedAvg (unclipped)')
    ax.plot(norms, clipped_drift, 's-', linewidth=2, color='C0', label=f'Clipped FedAvg (production, max_norm={SERVER_MAX_NORM:.1f})')
    ax.set_xlabel('L2 norm of one rogue client update')
    ax.set_ylabel('Resulting drift in the global model (L2 norm)')
    ax.set_title('Clipped vs Plain FedAvg Under a Rogue Client Update')
    ax.legend(); ax.grid(True, alpha=0.3); fig.tight_layout()
    _save(fig, 'clipping_robustness.png')

# Redis helpers
async def _redis_fetch():
    from redis.asyncio import Redis as ARedis
    from app.services.fl_service import get_global_weights
    redis = ARedis.from_url(REDIS_URL, decode_responses=True)
    try:
        _, weights = await get_global_weights(redis)
        return weights
    finally:
        await redis.aclose()

async def _redis_push(weights, n_rounds, last_staleness):
    from redis.asyncio import Redis as ARedis
    from app.services.fl_service import (
        FL_WEIGHTS_KEY, FL_ROUND_KEY, FL_SAMPLES_KEY,
        FL_CLIENTS_KEY, FL_LAST_STALENESS_KEY,
    )
    redis = ARedis.from_url(REDIS_URL, decode_responses=True)
    try:
        current_round = int(await redis.get(FL_ROUND_KEY) or 0)
        await redis.set(FL_WEIGHTS_KEY, json.dumps(weights))
        await redis.set(FL_ROUND_KEY, str(current_round + n_rounds))
        await redis.set(FL_LAST_STALENESS_KEY, str(last_staleness))
        await redis.incrby(FL_SAMPLES_KEY, n_rounds * INTERACTIONS_PER_ROUND)
        # Add synthetic client IDs so the dashboard reflects the simulated population
        await redis.sadd(FL_CLIENTS_KEY, *[f'sim_client_{i}' for i in range(N_CLIENTS)])
        print(f'  pushed weights to Redis - round {current_round} -> {current_round + n_rounds}')
        print(f'  last_staleness={last_staleness}  unique_contributors={N_CLIENTS} (synthetic)')
    finally:
        await redis.aclose()

# Main
def main():
    random.seed(SEED)
    np.random.seed(SEED)
    os.makedirs(RESULTS_DIR, exist_ok=True)

    print(f'Clients ({N_CLIENTS}):')
    clients = [random.sample(INTERESTS, random.randint(1, 3)) for _ in range(N_CLIENTS)]
    for i, c in enumerate(clients):
        print(f'  {i+1:2d}: {c}')

    print(f'\nBuilding test set...')
    test_data = _make_test_set(300)

    print('\nFetching initial weights from Redis...')
    try:
        initial_weights = asyncio.run(_redis_fetch())
        print(f'  loaded pretrained weights from Redis ({REDIS_URL})')
    except Exception as e:
        print(f'  Redis unavailable ({e}) - falling back to random weights')
        initial_weights = build_initial_weights()

    print('\nMeasuring initial model baseline...')
    initial_loss   = _bce_loss(initial_weights, test_data)
    initial_probes = {name: fl_predict(initial_weights, fv.tolist()) for name, (fv, _) in PROBES.items()}
    print(f'  initial loss = {initial_loss:.4f}')

    results = {'initial': {'loss': initial_loss, 'probes': initial_probes}}

    print('\nRunning with FedAsync staleness discount (production)...')
    random.seed(SEED); np.random.seed(SEED)
    results['fedasync'] = run_simulation(initial_weights, clients, test_data, use_fedasync=True)

    print('\nRunning without discount (every update weighted equally)...')
    random.seed(SEED); np.random.seed(SEED)
    results['no_fedasync'] = run_simulation(initial_weights, clients, test_data, use_fedasync=False)

    print('\nTesting clipped vs plain FedAvg under a rogue update of growing magnitude...')
    rogue_norms, plain_drift, clipped_drift = sweep_clipping_robustness(initial_weights)
    print(f'  at norm={rogue_norms[-1]:.1f}: plain drift={plain_drift[-1]:.3f}  clipped drift={clipped_drift[-1]:.3f}')

    # Stats JSON
    stats = {
        'config': {
            'n_clients': N_CLIENTS, 'n_rounds': N_ROUNDS,
            'interactions_per_round': INTERACTIONS_PER_ROUND,
            'local_epochs': LOCAL_EPOCHS, 'lr': LEARNING_RATE,
            'dp_sigma': DP_SIGMA, 'dp_clip_norm': DP_CLIP_NORM,
            'server_max_norm': SERVER_MAX_NORM, 'staleness_max': STALENESS_MAX,
        },
        'baseline': {
            'initial_loss':   initial_loss,
            'initial_probes': initial_probes,
        },
        'summary': {
            variant: {
                'final_loss':           results[variant]['final_loss'],
                'min_loss':             results[variant]['min_loss'],
                'avg_drift':            results[variant]['avg_drift'],
                'loss_improvement':     round(initial_loss - results[variant]['final_loss'], 6),
                'loss_improvement_pct': round((initial_loss - results[variant]['final_loss']) / initial_loss * 100, 2),
                'avg_effective_weight': results[variant]['avg_effective_weight'],
                'probes':               results[variant]['probes'],
            }
            for variant in ('fedasync', 'no_fedasync')
        },
        'per_round': {
            variant: {
                'loss':             results[variant]['loss'],
                'drift':            results[variant]['drift'],
                'effective_weight': results[variant]['effective_weight'],
                'staleness':        results[variant]['staleness'],
            }
            for variant in ('fedasync', 'no_fedasync')
        },
        'clipping_robustness': {
            'rogue_update_norm': rogue_norms,
            'plain_fedavg_drift':   plain_drift,
            'clipped_fedavg_drift': clipped_drift,
        },
    }
    p = os.path.join(RESULTS_DIR, 'stats.json')
    with open(p, 'w') as f:
        json.dump(stats, f, indent=2)
    print(f'\n  saved {p}')

    print('\nPlotting...')
    plot_loss(results)
    plot_drift(results)
    plot_fedasync_effect(results)
    plot_probes(results)
    plot_fedasync_discount_curve()
    plot_clipping_robustness(rogue_norms, plain_drift, clipped_drift)

    print('\nSummary:')
    print(f'  {"INITIAL":11s}  loss={initial_loss:.4f}')
    for variant, label in (('fedasync', 'FEDASYNC'), ('no_fedasync', 'NO DISCOUNT')):
        s = stats['summary'][variant]
        sign = '+' if s['loss_improvement'] >= 0 else ''
        print(f'  {label:11s}  final_loss={s["final_loss"]:.4f}  '
              f'min_loss={s["min_loss"]:.4f}  avg_drift={s["avg_drift"]:.4f}  '
              f'avg_eff_weight={s["avg_effective_weight"]:.3f}  '
              f'vs_initial={sign}{s["loss_improvement"]:.4f} ({sign}{s["loss_improvement_pct"]:.1f}%)')
    fa = stats['summary']['fedasync']['final_loss']
    nf = stats['summary']['no_fedasync']['final_loss']
    print(f'\n  FedAsync vs no-discount final-loss delta: {abs(fa - nf):.4f}')
    print(f'  Rogue update at norm={rogue_norms[-1]:.1f}: plain FedAvg drift={plain_drift[-1]:.3f} '
          f'vs clipped FedAvg drift={clipped_drift[-1]:.3f} (bounded by max_norm={SERVER_MAX_NORM:.1f})')

    print('\nPushing trained weights to Redis...')
    try:
        asyncio.run(_redis_push(results['fedasync']['weights'], N_ROUNDS, results['fedasync']['last_staleness']))
    except Exception as e:
        print(f'  Redis push failed: {e}')
        print('  (start the backend stack, or set REDIS_URL env var)')

    print(f'\nAll results in: {RESULTS_DIR}/')

if __name__ == '__main__':
    main()
