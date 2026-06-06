#!/usr/bin/env python3
"""
FL simulation: FedAvg vs FedProx over N rounds with N_CLIENTS synthetic clients.
Run from backend/: python federated/simulate_fl.py
Results written to backend/federated/results/
"""
import sys, os, json, math, random, asyncio
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from app.federated.model import build_initial_weights, clipped_fedavg, fl_predict, INPUT_DIM, HIDDEN_DIMS

# ── Config ─────────────────────────────────────────────────────────────────────
N_CLIENTS              = 1000
N_ROUNDS               = 100
INTERACTIONS_PER_ROUND = 15
LEARNING_RATE          = 0.01
LOCAL_EPOCHS           = 5
FEDPROX_MU             = 0.1
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

# ── Domain ─────────────────────────────────────────────────────────────────────
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

# ── Feature vector ─────────────────────────────────────────────────────────────
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

# ── Forward / backward (pure Python, mirrors Dart client) ─────────────────────
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

def _backward(weights, cache, y, mu=0.0, gw=None):
    x, z1, a1, z2, a2, W1, W2, W3 = cache
    a3 = float(1.0 / (1.0 + np.exp(-np.clip((W3 @ a2 + np.array(weights[5]))[0], -30, 30))))

    dz3 = np.array([a3 - y])
    dW3 = np.outer(dz3, a2);  db3 = dz3.copy()

    da2 = W3.T @ dz3
    dz2 = da2 * (z2 > 0);     dW2 = np.outer(dz2, a1); db2 = dz2.copy()

    da1 = W2.T @ dz2
    dz1 = da1 * (z1 > 0);     dW1 = np.outer(dz1, x);  db1 = dz1.copy()

    grads = [dW1.flatten(), db1, dW2.flatten(), db2, dW3.flatten(), db3]
    if mu > 0.0 and gw is not None:
        grads = [g + mu * (np.array(w) - np.array(g0))
                 for g, w, g0 in zip(grads, weights, gw)]
    return [g.tolist() for g in grads]

def _train_local(weights, data, lr, epochs, mu=0.0, gw=None):
    w = [list(layer) for layer in weights]
    for _ in range(epochs):
        random.shuffle(data)
        for x, y in data:
            pred, cache = _forward(w, x)
            grads = _backward(w, cache, y, mu, gw)
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

# ── Probe samples (deterministic, no randomness) ───────────────────────────────
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

# ── Simulation ─────────────────────────────────────────────────────────────────
def run_simulation(algo, initial_weights, clients, test_data, use_staleness=True):
    gw = [list(layer) for layer in initial_weights]
    loss_hist, drift_hist, eff_weight_hist = [], [], []

    for rnd in range(N_ROUNDS):
        interests = random.choice(clients)
        data      = [_generate_interaction(interests) for _ in range(INTERACTIONS_PER_ROUND)]
        mu        = FEDPROX_MU if algo == 'fedprox' else 0.0

        # Staleness-aware aggregation: mirrors submit_client_update in fl_service.py.
        # Each client trained on weights from `staleness` rounds ago; discount their
        # vote proportionally so stale updates have less influence on the global model.
        staleness = random.randint(0, STALENESS_MAX)
        discount  = (1.0 / (1.0 + staleness)) if use_staleness else 1.0
        effective = max(1, round(len(data) * discount))
        eff_weight_hist.append(discount)
        last_staleness = staleness

        local_w = _train_local(gw, data, LEARNING_RATE, LOCAL_EPOCHS, mu=mu, gw=gw)

        drift_hist.append(_drift(local_w, gw))

        noisy_w = _add_dp_noise(local_w, gw)
        virtual = effective * 4
        gw = clipped_fedavg([(effective, noisy_w), (virtual, gw)], gw, max_norm=SERVER_MAX_NORM)

        loss_hist.append(_bce_loss(gw, test_data))

        if (rnd + 1) % 20 == 0:
            print(f'  [{algo:7s}] round {rnd+1:3d}/{N_ROUNDS}  '
                  f'loss={loss_hist[-1]:.4f}  drift={drift_hist[-1]:.4f}  '
                  f'eff_weight={discount:.2f} (staleness={staleness if use_staleness else "off"})')

    probes = {name: fl_predict(gw, fv.tolist()) for name, (fv, _) in PROBES.items()}
    return {'loss': loss_hist, 'drift': drift_hist, 'effective_weight': eff_weight_hist,
            'probes': probes,
            'final_loss': loss_hist[-1], 'min_loss': min(loss_hist),
            'avg_drift': float(np.mean(drift_hist)),
            'avg_effective_weight': float(np.mean(eff_weight_hist)),
            'last_staleness': last_staleness,
            'weights': gw}

# ── Plots ──────────────────────────────────────────────────────────────────────
def _smooth(vals, k=5):
    return np.convolve(vals, np.ones(k) / k, mode='valid')

def _save(fig, name):
    path = os.path.join(RESULTS_DIR, name)
    fig.savefig(path, dpi=150)
    plt.close(fig)
    print(f'  saved {path}')

def plot_loss(res):
    fig, ax = plt.subplots(figsize=(9, 5))
    init_loss = res['initial']['loss']
    # round 0 = initial model, rounds 1..N = after each FL round
    rounds = np.arange(0, N_ROUNDS + 1)
    k = 5
    sr = rounds[k - 1:]
    colors = {'fedavg': 'C0', 'fedprox': 'C1'}
    for algo, style in (('fedavg', '-'), ('fedprox', '--')):
        full_loss = [init_loss] + res[algo]['loss']
        ax.plot(sr, _smooth(full_loss, k), style,
                label=algo.upper(), linewidth=2, color=colors[algo])
    ax.set_xlabel('Round'); ax.set_ylabel('BCE Loss (test set)')
    ax.set_title('Global Model Loss: FedAvg vs FedProx')
    ax.legend(); ax.grid(True, alpha=0.3); fig.tight_layout()
    _save(fig, 'loss_curve.png')

def plot_drift(res):
    fig, ax = plt.subplots(figsize=(9, 5))
    rounds = np.arange(1, N_ROUNDS + 1)
    k = 5; sr = rounds[k - 1:]
    for algo, style in (('fedavg', '-'), ('fedprox', '--')):
        ax.plot(sr, _smooth(res[algo]['drift'], k), style,
                label=algo.upper(), linewidth=2, color={'fedavg': 'C0', 'fedprox': 'C1'}[algo])
    ax.set_xlabel('Round'); ax.set_ylabel('L2 norm (local - global)')
    ax.set_title('Local Weight Drift: FedAvg vs FedProx')
    ax.legend(); ax.grid(True, alpha=0.3); fig.tight_layout()
    _save(fig, 'weight_drift.png')

def plot_staleness_effect(res):
    """Loss with vs without staleness discounting — shows effect of FedAsync weighting."""
    fig, ax = plt.subplots(figsize=(9, 5))
    init_loss = res['initial']['loss']
    rounds = np.arange(0, N_ROUNDS + 1)
    k = 5; sr = rounds[k - 1:]
    styles = {
        ('fedavg',  True):  ('C0', '-',  'FedAvg  + staleness discount'),
        ('fedavg',  False): ('C0', ':',  'FedAvg  no discount'),
        ('fedprox', True):  ('C1', '-',  'FedProx + staleness discount'),
        ('fedprox', False): ('C1', ':',  'FedProx no discount'),
    }
    for (algo, stale), (color, ls, label) in styles.items():
        key = f'{algo}_nostale' if not stale else algo
        full = [init_loss] + res[key]['loss']
        ax.plot(sr, _smooth(full, k), ls, label=label, linewidth=2, color=color)
    ax.set_xlabel('Round'); ax.set_ylabel('BCE Loss (test set)')
    ax.set_title('Effect of Staleness Discount (FedAsync) on Global Loss')
    ax.legend(); ax.grid(True, alpha=0.3); fig.tight_layout()
    _save(fig, 'staleness_effect.png')

def plot_probes(res):
    labels   = list(PROBES.keys())
    expected = [v for _, v in PROBES.values()]
    x = np.arange(len(labels)); w = 0.18
    fig, ax = plt.subplots(figsize=(13, 6))
    ax.bar(x - 1.5*w, expected,                                      w, label='Expected', color='lightgray', edgecolor='black')
    ax.bar(x - 0.5*w, [res['initial']['probes'][l] for l in labels], w, label='Initial',  color='#aaaaaa',   edgecolor='black')
    ax.bar(x + 0.5*w, [res['fedavg']['probes'][l]  for l in labels], w, label='FedAvg',   color='C0')
    ax.bar(x + 1.5*w, [res['fedprox']['probes'][l] for l in labels], w, label='FedProx',  color='C1')
    ax.set_xticks(x); ax.set_xticklabels(labels, rotation=18, ha='right', fontsize=9)
    ax.set_ylabel('Predicted engagement'); ax.set_ylim(0, 1.15)
    ax.set_title('Probe Scores: Initial vs FedAvg vs FedProx vs Expected')
    ax.legend(); ax.grid(True, alpha=0.3, axis='y'); fig.tight_layout()
    _save(fig, 'probe_scores.png')

# ── Redis helpers ───────────────────────────────────────────────────────────────
async def _redis_fetch():
    from redis.asyncio import Redis as ARedis
    from app.services.fl_service import get_global_weights
    redis = ARedis.from_url(REDIS_URL, decode_responses=True)
    try:
        _, weights = await get_global_weights(redis)
        return weights
    finally:
        await redis.aclose()

async def _redis_push(weights, algo, n_rounds, last_staleness):
    import json
    from redis.asyncio import Redis as ARedis
    from app.services.fl_service import (
        FL_WEIGHTS_KEY, FL_ROUND_KEY, FL_SAMPLES_KEY,
        FL_ALGORITHM_KEY, FL_CLIENTS_KEY, FL_LAST_STALENESS_KEY,
    )
    redis = ARedis.from_url(REDIS_URL, decode_responses=True)
    try:
        current_round = int(await redis.get(FL_ROUND_KEY) or 0)
        await redis.set(FL_WEIGHTS_KEY, json.dumps(weights))
        await redis.set(FL_ROUND_KEY, str(current_round + n_rounds))
        await redis.set(FL_ALGORITHM_KEY, algo)
        await redis.set(FL_LAST_STALENESS_KEY, str(last_staleness))
        await redis.incrby(FL_SAMPLES_KEY, n_rounds * INTERACTIONS_PER_ROUND)
        # Add synthetic client IDs so the dashboard reflects the simulated population
        await redis.sadd(FL_CLIENTS_KEY, *[f'sim_client_{i}' for i in range(N_CLIENTS)])
        print(f'  pushed {algo.upper()} weights to Redis — round {current_round} -> {current_round + n_rounds}')
        print(f'  last_staleness={last_staleness}  unique_contributors={N_CLIENTS} (synthetic)')
    finally:
        await redis.aclose()

# ── Main ───────────────────────────────────────────────────────────────────────
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
        print(f'  Redis unavailable ({e}) — falling back to random weights')
        initial_weights = build_initial_weights()

    print('\nMeasuring initial model baseline...')
    initial_loss   = _bce_loss(initial_weights, test_data)
    initial_probes = {name: fl_predict(initial_weights, fv.tolist()) for name, (fv, _) in PROBES.items()}
    print(f'  initial loss = {initial_loss:.4f}')

    results = {'initial': {'loss': initial_loss, 'probes': initial_probes}}
    for algo in ('fedavg', 'fedprox'):
        print(f'\n── {algo.upper()} (with staleness discount) ──')
        random.seed(SEED); np.random.seed(SEED)
        results[algo] = run_simulation(algo, initial_weights, clients, test_data, use_staleness=True)
        print(f'\n── {algo.upper()} (no staleness discount) ──')
        random.seed(SEED); np.random.seed(SEED)
        results[f'{algo}_nostale'] = run_simulation(algo, initial_weights, clients, test_data, use_staleness=False)

    # Stats JSON
    stats = {
        'config': {
            'n_clients': N_CLIENTS, 'n_rounds': N_ROUNDS,
            'interactions_per_round': INTERACTIONS_PER_ROUND,
            'local_epochs': LOCAL_EPOCHS, 'lr': LEARNING_RATE,
            'fedprox_mu': FEDPROX_MU, 'dp_sigma': DP_SIGMA,
            'dp_clip_norm': DP_CLIP_NORM, 'server_max_norm': SERVER_MAX_NORM,
            'staleness_max': STALENESS_MAX,
        },
        'baseline': {
            'initial_loss':   initial_loss,
            'initial_probes': initial_probes,
        },
        'summary': {
            algo: {
                'final_loss':           results[algo]['final_loss'],
                'min_loss':             results[algo]['min_loss'],
                'avg_drift':            results[algo]['avg_drift'],
                'loss_improvement':        round(initial_loss - results[algo]['final_loss'], 6),
                'loss_improvement_pct':    round((initial_loss - results[algo]['final_loss']) / initial_loss * 100, 2),
                'avg_effective_weight':    results[algo]['avg_effective_weight'],
                'probes':                  results[algo]['probes'],
            }
            for algo in ('fedavg', 'fedprox')
        },
        'per_round': {
            algo: {
                'loss':             results[algo]['loss'],
                'drift':            results[algo]['drift'],
                'effective_weight': results[algo]['effective_weight'],
            }
            for algo in ('fedavg', 'fedprox')
        },
    }
    p = os.path.join(RESULTS_DIR, 'stats.json')
    with open(p, 'w') as f:
        json.dump(stats, f, indent=2)
    print(f'\n  saved {p}')

    print('\nPlotting...')
    plot_loss(results)
    plot_drift(results)
    plot_staleness_effect(results)
    plot_probes(results)

    print('\n── Summary ───────────────────────────────────────────────────')
    print(f'  {"INITIAL":8s}  loss={initial_loss:.4f}')
    for algo in ('fedavg', 'fedprox'):
        s = stats['summary'][algo]
        sign = '+' if s['loss_improvement'] >= 0 else ''
        print(f'  {algo.upper():8s}  final_loss={s["final_loss"]:.4f}  '
              f'min_loss={s["min_loss"]:.4f}  avg_drift={s["avg_drift"]:.4f}  '
              f'avg_eff_weight={s["avg_effective_weight"]:.3f}  '
              f'vs_initial={sign}{s["loss_improvement"]:.4f} ({sign}{s["loss_improvement_pct"]:.1f}%)')
    fa  = stats['summary']['fedavg']['final_loss']
    fp  = stats['summary']['fedprox']['final_loss']
    winner     = 'fedprox' if fp < fa else 'fedavg'
    winner_w   = results[winner]['weights']
    print(f'\n  Best algorithm: {winner.upper()}  (Δloss vs other = {abs(fa - fp):.4f})')

    print('\nPushing winner weights to Redis...')
    try:
        asyncio.run(_redis_push(winner_w, winner, N_ROUNDS, results[winner]['last_staleness']))
    except Exception as e:
        print(f'  Redis push failed: {e}')
        print('  (start the backend stack, or set REDIS_URL env var)')

    print(f'\nAll results in: {RESULTS_DIR}/')

if __name__ == '__main__':
    main()
