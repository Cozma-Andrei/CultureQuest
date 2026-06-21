#!/usr/bin/env python3
"""
FL simulation: demonstrates why the FedAsync staleness discount is necessary
even in an already-async FL system.

Two identical async runs (one client per round) are compared:
  - fedasync:    discount = 1 / (1 + staleness) applied to each update
  - no_fedasync: every update counted equally, regardless of staleness

With a realistic heterogeneous staleness distribution (80% fresh [0-2 rounds],
20% very stale [15-30 rounds]) and concept-drifted stale clients, the
no-discount run degrades: it incorporates stale, conflicting gradients at
full weight. FedAsync nearly ignores them (discount ~0.04-0.06 for staleness
15-30) while fresh clients pass through at near-full strength (discount ~1.0).

Concept drift model for stale clients: a device that was offline for 15-30
rounds re-syncs with interaction data that reflects outdated preferences or
behaviour. We model this as partial label inversion (STALE_LABEL_FLIP_RATE):
the stale client's gradient partly opposes the current training objective.
Without discount this corrupts the global model; with FedAsync it is safely
down-weighted.

Run from backend/: python3 federated/simulate_fl.py
Results written to backend/federated/results/
"""
import sys, os, json, math, random, asyncio, collections, time
import numpy as np
try:
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    matplotlib.rcParams['axes.unicode_minus'] = False
    _HAS_MPL = True
except ImportError:
    _HAS_MPL = False

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from app.federated.model import build_initial_weights, avg, clipped_avg, fl_predict, INPUT_DIM, HIDDEN_DIMS

# Config
N_CLIENTS              = 10000
N_ROUNDS               = 600
INTERACTIONS_PER_ROUND = 15
LEARNING_RATE          = 0.01
LOCAL_EPOCHS           = 5
DP_SIGMA               = 0.1
DP_CLIP_NORM           = 1.0
SERVER_MAX_NORM        = 1.0
SEED                   = 42
RESULTS_DIR            = os.path.join(os.path.dirname(__file__), 'results')

# Heterogeneous staleness: realistic FL has a fast majority and a slow long-tail
FRESH_PROB            = 0.80
FRESH_STALENESS       = (0, 2)    # 80%: fast / recently synced devices
STALE_STALENESS       = (15, 30)  # 20%: slow / offline devices
HISTORY_SIZE          = 35        # rounds of global weight history to keep
# Concept-drift model for stale clients: a device offline for 15-30 rounds
# re-syncs with interaction data that partially reflects outdated preferences.
# We simulate this by flipping a fraction of the stale client's labels, so
# its gradient partly opposes the current training objective.  Fresh clients
# (0-2 rounds stale) are not affected.
STALE_LABEL_FLIP_RATE = 0.70

REDIS_URL = os.environ.get('REDIS_URL', 'redis://:secret@localhost:6379/0')

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

def _fv(interests, ltype, is_open=None, is_weekend=None, hour=None, dist_rank=None):
    matched = set().union(*(AFFINITY.get(i, set()) for i in interests))
    if is_open   is None: is_open   = float(random.random() > 0.2)
    if is_weekend is None: is_weekend = float(random.random() > 0.7)
    if hour      is None: hour      = random.randint(8, 22) / 24.0
    if dist_rank is None: dist_rank = random.random()
    return np.array(
        [1.0 if i in interests else 0.0 for i in INTERESTS] +
        [1.0 if t == ltype else 0.0 for t in TYPES] +
        [is_open, is_weekend, hour, dist_rank, 1.0 if ltype in matched else 0.0, 0.0, 0.0, 0.0],
        dtype=np.float32,
    )

def _generate_interaction(interests):
    ltype    = random.choice(TYPES)
    is_open  = float(random.random() > 0.2)   # 80% of venues are open
    is_wknd  = float(random.random() > 0.7)   # 30% chance it's a weekend
    hour_raw = random.randint(8, 22)
    matched  = ltype in set().union(*(AFFINITY.get(i, set()) for i in interests))
    base     = random.uniform(0.65, 0.95) if matched else random.uniform(0.05, 0.40)
    # Contextual modifiers so these dims carry real signal the model can learn
    if not is_open:
        base *= 0.15                           # closed venue: near-zero engagement
    if is_wknd and ltype in {'museum', 'gallery', 'park', 'square'}:
        base = min(1.0, base * 1.2)            # cultural/outdoor venues busier on weekends
    if ltype == 'restaurant' and hour_raw >= 18:
        base = min(1.0, base * 1.2)            # restaurants peak in the evening
    return _fv(interests, ltype, is_open, is_wknd, hour_raw / 24.0), float(np.clip(base, 0.0, 1.0))

def _make_test_set(n=300):
    data = []
    for _ in range(n):
        interests = random.sample(INTERESTS, random.randint(1, 3))
        data.append(_generate_interaction(interests))
    return data

# Neural net (mirrors Dart client)
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

def _copy_weights(w):
    return [list(layer) for layer in w]

def _sample_staleness():
    """Bimodal distribution: most clients are fresh, a minority are very stale."""
    if random.random() < FRESH_PROB:
        return random.randint(*FRESH_STALENESS)
    return random.randint(*STALE_STALENESS)

# Probe samples (deterministic)
def _static_fv(interests, ltype):
    return _fv(interests, ltype, is_open=1.0, is_weekend=0.0, hour=14/24, dist_rank=0.3)

def _probe_fv(interests, ltype, *, is_open=1.0, is_weekend=0.0, hour=14/24, dist_rank=0.3):
    return _fv(interests, ltype, is_open, is_weekend, hour, dist_rank)

PROBES = {
    'gastronomy->restaurant': (_static_fv(['gastronomy'], 'restaurant'), 0.80),
    'gastronomy->park':       (_static_fv(['gastronomy'], 'park'),       0.20),
    'nature->park':           (_static_fv(['nature'],     'park'),       0.80),
    'nature->restaurant':     (_static_fv(['nature'],     'restaurant'), 0.20),
    'art->gallery':           (_static_fv(['art'],         'gallery'),   0.80),
    'history->museum':        (_static_fv(['history'],     'museum'),    0.80),
}

# Simulation
def run_simulation(initial_weights, clients, test_data, use_fedasync=True):
    """Async FL: one client update per round.

    The key fix vs the old simulation: stale clients now train from the global
    snapshot they actually had (staleness rounds ago), not from the current
    model. This makes their gradient genuinely outdated. use_fedasync controls
    whether the server discounts that outdated gradient.

    Both runs must be called with the same random seed so they see identical
    clients and staleness values -- the only variable is the discount.
    """
    gw      = _copy_weights(initial_weights)
    history = collections.deque([_copy_weights(gw)] * HISTORY_SIZE, maxlen=HISTORY_SIZE)

    loss_hist, drift_hist, eff_weight_hist, staleness_hist = [], [], [], []

    for rnd in range(N_ROUNDS):
        interests = random.choice(clients)
        staleness = _sample_staleness()

        # Client trained on the snapshot it had when it last synced (staleness rounds ago)
        hist_idx = max(0, len(history) - 1 - staleness)
        gw_snap  = list(history)[hist_idx]
        data     = [_generate_interaction(interests) for _ in range(INTERACTIONS_PER_ROUND)]
        # Concept drift: stale client re-syncs with outdated interactions whose
        # labels partially contradict the current training objective.
        if staleness >= STALE_STALENESS[0]:
            data = [
                (x, 1.0 - y if random.random() < STALE_LABEL_FLIP_RATE else y)
                for x, y in data
            ]
        local_w  = _train_local(gw_snap, data, LEARNING_RATE, LOCAL_EPOCHS)
        drift_hist.append(_drift(local_w, gw_snap))

        noisy_w  = _add_dp_noise(local_w, gw_snap)
        discount  = (1.0 / (1.0 + staleness)) if use_fedasync else 1.0
        effective = max(1, round(INTERACTIONS_PER_ROUND * discount))
        virtual   = max(effective * 4, 20)
        gw = clipped_avg([(effective, noisy_w), (virtual, gw)], gw, max_norm=SERVER_MAX_NORM)
        history.append(_copy_weights(gw))

        loss_hist.append(_bce_loss(gw, test_data))
        eff_weight_hist.append(discount)
        staleness_hist.append(staleness)

        if (rnd + 1) % 25 == 0:
            tag = 'fedasync' if use_fedasync else 'no-discount'
            print(f'  [{tag:11s}] round {rnd+1:3d}/{N_ROUNDS}  '
                  f'loss={loss_hist[-1]:.4f}  drift={drift_hist[-1]:.4f}  '
                  f'staleness={staleness}  discount={discount:.3f}')

    probes = {name: fl_predict(gw, fv.tolist()) for name, (fv, _) in PROBES.items()}
    return {
        'loss': loss_hist, 'drift': drift_hist,
        'effective_weight': eff_weight_hist, 'staleness': staleness_hist,
        'probes': probes, 'final_loss': loss_hist[-1], 'min_loss': min(loss_hist),
        'avg_drift': float(np.mean(drift_hist)),
        'avg_effective_weight': float(np.mean(eff_weight_hist)),
        'last_staleness': staleness_hist[-1], 'weights': gw,
    }

# Plots
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
    k = 5
    full = [init_loss] + res['fedasync']['loss']
    ax.plot(np.arange(len(full))[k-1:], _smooth(full, k),
            '-', linewidth=2, color='C0', label='FedAsync')
    ax.set_xlabel('Round'); ax.set_ylabel('BCE loss (test set)')
    ax.set_title('Global Model Loss over Training Rounds')
    ax.legend(); ax.grid(True, alpha=0.3); fig.tight_layout()
    _save(fig, 'loss_curve.png')

def plot_drift(res):
    fig, ax = plt.subplots(figsize=(9, 5))
    k = 5
    drift = res['fedasync']['drift']
    ax.plot(np.arange(1, len(drift)+1)[k-1:], _smooth(drift, k),
            '-', linewidth=2, color='C0', label='Local SGD drift')
    ax.set_xlabel('Round'); ax.set_ylabel('L2 norm (local minus global)')
    ax.set_title('Local Weight Drift per Round')
    ax.legend(); ax.grid(True, alpha=0.3); fig.tight_layout()
    _save(fig, 'weight_drift.png')

def plot_fedasync_effect(res):
    """Main comparison: FedAsync discount vs no discount, same async setup.
    Both runs see identical clients and staleness values (same seed).
    The only variable is whether the staleness discount is applied.
    """
    fig, ax = plt.subplots(figsize=(10, 5))
    init_loss = res['initial']['loss']
    rounds = np.arange(0, N_ROUNDS + 1)
    k = 5; sr = rounds[k-1:]

    for key, color, ls, label in (
        ('fedasync',    'C0', '-',
         f'FedAsync discount  (avg weight = {res["fedasync"]["avg_effective_weight"]:.3f})'),
        ('no_fedasync', 'C3', '--',
         f'No discount: stale updates counted equally  (avg weight = 1.000)'),
    ):
        full = [init_loss] + res[key]['loss']
        ax.plot(sr, _smooth(full, k), ls, label=label, linewidth=2, color=color)

    ax.set_xlabel('Round')
    ax.set_ylabel('BCE loss (test set, lower = better)')
    ax.set_title(
        f'FedAsync Discount vs No Discount\n'
        f'{FRESH_PROB*100:.0f}% fresh [staleness {FRESH_STALENESS[0]}-{FRESH_STALENESS[1]}],  '
        f'{(1-FRESH_PROB)*100:.0f}% stale [staleness {STALE_STALENESS[0]}-{STALE_STALENESS[1]}, '
        f'{STALE_LABEL_FLIP_RATE*100:.0f}% concept-drifted labels]'
    )
    ax.legend(fontsize=9); ax.grid(True, alpha=0.3); fig.tight_layout()
    _save(fig, 'fedasync_effect.png')

def plot_staleness_distribution(res):
    """Bimodal staleness histogram with fresh/stale zone annotations."""
    fig, ax = plt.subplots(figsize=(9, 5))
    s    = res['fedasync']['staleness']
    bins = list(range(0, STALE_STALENESS[1] + 2))
    ax.hist(s, bins=bins, color='steelblue', alpha=0.8, edgecolor='white', rwidth=0.85)
    ax.axvline(float(np.mean(s)), color='black', linestyle='--', linewidth=1.5,
               label=f'Mean staleness = {float(np.mean(s)):.1f}')
    ax.axvspan(FRESH_STALENESS[0] - 0.5, FRESH_STALENESS[1] + 0.5,
               alpha=0.12, color='green', label=f'Fresh zone  ({FRESH_PROB*100:.0f}%)')
    ax.axvspan(STALE_STALENESS[0] - 0.5, STALE_STALENESS[1] + 0.5,
               alpha=0.12, color='red', label=f'Stale zone  ({(1-FRESH_PROB)*100:.0f}%)')
    ax.set_xlabel('Staleness (rounds behind global model)')
    ax.set_ylabel('Count (out of %d rounds)' % N_ROUNDS)
    ax.set_title('Observed staleness distribution')
    ax.legend(fontsize=9); ax.grid(True, alpha=0.3)
    fig.tight_layout()
    _save(fig, 'staleness_distribution.png')

def plot_per_staleness_loss_delta(res):
    """For each staleness bucket, compare the loss change right after the update
    in the fedasync vs no-discount run. Stale updates should cause a larger
    loss increase (or smaller decrease) in the no-discount run."""
    staleness_seq = res['fedasync']['staleness']
    loss_fa       = res['fedasync']['loss']
    loss_no       = res['no_fedasync']['loss']

    buckets = {'fresh (0-2)': [], 'stale (15-30)': []}
    for i in range(1, len(staleness_seq)):
        st       = staleness_seq[i]
        delta_fa = loss_fa[i] - loss_fa[i - 1]
        delta_no = loss_no[i] - loss_no[i - 1]
        if st <= FRESH_STALENESS[1]:
            buckets['fresh (0-2)'].append((delta_fa, delta_no))
        elif st >= STALE_STALENESS[0]:
            buckets['stale (15-30)'].append((delta_fa, delta_no))

    fig, axes = plt.subplots(1, 2, figsize=(12, 5))
    labels = ['FedAsync', 'No discount']
    colors = ['C0', 'C3']

    for ax, (bucket, vals) in zip(axes, buckets.items()):
        fa_vals = [v[0] for v in vals]
        no_vals = [v[1] for v in vals]
        bp = ax.boxplot([fa_vals, no_vals], labels=labels, patch_artist=True,
                        medianprops=dict(color='black', linewidth=2))
        for patch, color in zip(bp['boxes'], colors):
            patch.set_facecolor(color); patch.set_alpha(0.6)
        ax.axhline(0, color='gray', linestyle='--', linewidth=1)
        ax.set_ylabel('Loss change after update (negative = improvement)')
        ax.set_title(f'Loss change per round: {bucket} clients\n'
                     f'n = {len(vals)} rounds')
        ax.grid(True, alpha=0.3, axis='y')

    fig.suptitle(
        'Impact of a single client update on test loss:\n'
        'stale updates hurt more without discount',
        fontsize=11
    )
    fig.tight_layout()
    _save(fig, 'per_staleness_loss_delta.png')

def plot_probes(res):
    labels   = list(PROBES.keys())
    expected = [v for _, v in PROBES.values()]
    x = np.arange(len(labels)); w = 0.25
    fig, ax = plt.subplots(figsize=(13, 6))
    ax.bar(x - w, expected,                                       w, label='Expected',    color='lightgray', edgecolor='black')
    ax.bar(x,     [res['initial']['probes'][l]   for l in labels], w, label='Initial',     color='#aaaaaa',   edgecolor='black')
    ax.bar(x + w, [res['fedasync']['probes'][l]  for l in labels], w, label='FedAsync',    color='C0')
    ax.set_xticks(x); ax.set_xticklabels(labels, rotation=18, ha='right', fontsize=9)
    ax.set_ylabel('Predicted engagement'); ax.set_ylim(0, 1.15)
    ax.set_title('Probe Scores: Initial vs Trained (FedAsync) vs Expected')
    ax.legend(); ax.grid(True, alpha=0.3, axis='y'); fig.tight_layout()
    _save(fig, 'probe_scores.png')

def plot_contextual_probes(res):
    """Show how the trained model responds to isOpen and isWeekend.
    These features carry real signal in the training data (see _generate_interaction),
    so the plot shows what contextual patterns the model actually learned."""
    gw = res['fedasync']['weights']
    combos = [
        (['gastronomy'], 'restaurant'),
        (['art'],        'gallery'),
        (['history'],    'museum'),
        (['nature'],     'park'),
    ]
    xlabels = ['gastronomy\n+restaurant', 'art\n+gallery', 'history\n+museum', 'nature\n+park']
    x = np.arange(len(combos)); w = 0.35

    fig, axes = plt.subplots(1, 2, figsize=(10, 5))

    # isOpen: closed vs open
    ax = axes[0]
    closed = [fl_predict(gw, _probe_fv(i, t, is_open=0.0).tolist()) for i, t in combos]
    opened = [fl_predict(gw, _probe_fv(i, t, is_open=1.0).tolist()) for i, t in combos]
    ax.bar(x - w/2, closed, w, label='Closed (isOpen=0)', color='#cc6666', alpha=0.85)
    ax.bar(x + w/2, opened, w, label='Open   (isOpen=1)', color='#66bb66', alpha=0.85)
    ax.set_xticks(x); ax.set_xticklabels(xlabels, fontsize=8)
    ax.set_ylabel('Predicted engagement'); ax.set_ylim(0, 1.0)
    ax.set_title('isOpen effect')
    ax.legend(fontsize=9); ax.grid(True, alpha=0.3, axis='y')

    # isWeekend: weekday vs weekend
    ax = axes[1]
    wday = [fl_predict(gw, _probe_fv(i, t, is_weekend=0.0).tolist()) for i, t in combos]
    wend = [fl_predict(gw, _probe_fv(i, t, is_weekend=1.0).tolist()) for i, t in combos]
    ax.bar(x - w/2, wday, w, label='Weekday', color='#6688cc', alpha=0.85)
    ax.bar(x + w/2, wend, w, label='Weekend', color='#ffaa44', alpha=0.85)
    ax.set_xticks(x); ax.set_xticklabels(xlabels, fontsize=8)
    ax.set_ylabel('Predicted engagement'); ax.set_ylim(0, 1.0)
    ax.set_title('isWeekend effect')
    ax.legend(fontsize=9); ax.grid(True, alpha=0.3, axis='y')

    fig.suptitle('Contextual feature effects (trained model)', fontsize=11)
    fig.tight_layout()
    _save(fig, 'contextual_probes.png')

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
    for i, c in enumerate(clients[:8]):
        print(f'  {i+1:2d}: {c}')
    print(f'  ... ({N_CLIENTS - 8} more)')

    print('\nBuilding test set (300 samples)...')
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

    print('\nBenchmarking inference (single forward pass)...')
    _bench_input = test_data[0][0].tolist()
    N_BENCH = 10000
    _t0 = time.perf_counter()
    for _ in range(N_BENCH):
        fl_predict(initial_weights, _bench_input)
    inference_us = (time.perf_counter() - _t0) / N_BENCH * 1_000_000
    print(f'  avg inference: {inference_us:.2f} µs over {N_BENCH} runs (numpy, laptop)')

    results = {'initial': {'loss': initial_loss, 'probes': initial_probes}}

    print(f'\nRunning with FedAsync staleness discount...')
    print(f'  Staleness: {FRESH_PROB*100:.0f}% fresh [{FRESH_STALENESS[0]}-{FRESH_STALENESS[1]}], '
          f'{(1-FRESH_PROB)*100:.0f}% stale [{STALE_STALENESS[0]}-{STALE_STALENESS[1]}]')
    random.seed(SEED); np.random.seed(SEED)
    t0_fa = time.perf_counter()
    results['fedasync'] = run_simulation(initial_weights, clients, test_data, use_fedasync=True)
    t_fa = time.perf_counter() - t0_fa

    print('\nRunning without discount (every update weighted equally)...')
    random.seed(SEED); np.random.seed(SEED)
    t0_nf = time.perf_counter()
    results['no_fedasync'] = run_simulation(initial_weights, clients, test_data, use_fedasync=False)
    t_nf = time.perf_counter() - t0_nf

    stats = {
        'config': {
            'n_clients': N_CLIENTS, 'n_rounds': N_ROUNDS,
            'interactions_per_round': INTERACTIONS_PER_ROUND,
            'local_epochs': LOCAL_EPOCHS, 'lr': LEARNING_RATE,
            'dp_sigma': DP_SIGMA, 'dp_clip_norm': DP_CLIP_NORM,
            'server_max_norm': SERVER_MAX_NORM,
            'fresh_prob': FRESH_PROB,
            'fresh_staleness_range': list(FRESH_STALENESS),
            'stale_staleness_range': list(STALE_STALENESS),
            'stale_label_flip_rate': STALE_LABEL_FLIP_RATE,
        },
        'baseline': {'initial_loss': initial_loss, 'initial_probes': initial_probes},
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
        'timing': {
            'fedasync_seconds':    round(t_fa, 2),
            'no_fedasync_seconds': round(t_nf, 2),
            'seconds_per_round': {
                'fedasync':    round(t_fa / N_ROUNDS, 4),
                'no_fedasync': round(t_nf / N_ROUNDS, 4),
            },
            'inference_us_numpy': round(inference_us, 2),
        },
    }
    p = os.path.join(RESULTS_DIR, 'stats.json')
    with open(p, 'w') as f:
        json.dump(stats, f, indent=2)
    print(f'\n  saved {p}')

    if _HAS_MPL:
        print('\nPlotting...')
        plot_loss(results)
        plot_drift(results)
        plot_fedasync_effect(results)
        plot_staleness_distribution(results)
        plot_per_staleness_loss_delta(results)
        plot_probes(results)
        plot_contextual_probes(results)
    else:
        print('\nPlotting skipped (matplotlib not available).')

    print('\nSummary:')
    print(f'  {"INITIAL":11s}  loss={initial_loss:.4f}')
    for variant, label in (('fedasync', 'FEDASYNC'), ('no_fedasync', 'NO DISCOUNT')):
        s    = stats['summary'][variant]
        sign = '+' if s['loss_improvement'] >= 0 else ''
        print(f'  {label:11s}  final_loss={s["final_loss"]:.4f}  '
              f'min_loss={s["min_loss"]:.4f}  avg_drift={s["avg_drift"]:.4f}  '
              f'avg_eff_weight={s["avg_effective_weight"]:.3f}  '
              f'vs_initial={sign}{s["loss_improvement"]:.4f} ({sign}{s["loss_improvement_pct"]:.1f}%)')
    fa    = stats['summary']['fedasync']['final_loss']
    nf    = stats['summary']['no_fedasync']['final_loss']
    delta = nf - fa
    print(f'\n  FedAsync advantage: {delta:+.4f} lower final loss than no-discount.')
    print(f'\n  Timing: fedasync={t_fa:.1f}s  no_fedasync={t_nf:.1f}s  '
          f'({t_fa/N_ROUNDS*1000:.1f}ms/round  vs  {t_nf/N_ROUNDS*1000:.1f}ms/round)')
    print(f'  avg_eff_weight: fedasync={stats["summary"]["fedasync"]["avg_effective_weight"]:.3f}  '
          f'(old uniform-staleness sim would give ~0.162 -- fresh clients unfairly penalised)')

    print('\nPushing trained weights to Redis...')
    try:
        asyncio.run(_redis_push(results['fedasync']['weights'], N_ROUNDS, results['fedasync']['last_staleness']))
    except Exception as e:
        print(f'  Redis push failed: {e}')
        print('  (start the backend stack, or set REDIS_URL env var)')

    print(f'\nAll results in: {RESULTS_DIR}/')

if __name__ == '__main__':
    main()
