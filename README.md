# CultureQuest

Mobile platform for urban cultural exploration driven by proximity awareness and on-device Federated Learning.

---

## Stack

| Layer | Technology |
|---|---|
| Mobile | Flutter + Riverpod |
| Backend | FastAPI (Python 3.11) |
| Database | MongoDB |
| Cache / FL state | Redis |
| Routing | OSRM (via public API) |
| Geofencing | geofence_service (Flutter) |
| FL model | Custom MLP (22→32→16→1), implemented from scratch in Dart and Python |

No TensorFlow, no Flower. The FL model runs entirely in Dart on-device.

---

## Structure

```
CultureQuest/
├── backend/
│   ├── app/                  # FastAPI application
│   │   ├── api/              # Route handlers
│   │   ├── federated/        # Model architecture, FedAvg, clipped FedAvg
│   │   └── services/         # FL service, route service, etc.
│   ├── pretraining/          # Pretrain + finetune scripts and MD docs
│   ├── federated/            # FL documentation and simulation script
│   │   ├── FL.md             # Full FL architecture doc
│   │   ├── SIMULATE.md       # Simulation script doc
│   │   └── simulate_fl.py    # FedAvg vs FedProx comparison simulation
│   ├── seed_bucharest.py     # DB seeder (landmarks, users, quests, etc.)
│   └── requirements.txt
├── mobile/
│   └── lib/
│       ├── features/
│       │   ├── federated/    # FL client service (FedProx, DP noise, weight training)
│       │   ├── map/          # Map screen, navigation, route generation
│       │   ├── profile/      # Profile, privacy screen, FL sync
│       │   └── ...
│       └── core/
├── web/
│   └── dashboard.html        # Admin FL dashboard (open locally in browser)
└── docker-compose.yml
```

---

## How to start

### 1. Start the backend stack

```bash
docker compose up -d
```

Starts MongoDB, Redis, and the FastAPI backend on port 8000.

### 2. Seed the database

```bash
docker exec culturequest_backend python3 seed_bucharest.py
```

Creates landmarks, users, quests, routes, events, and simulated activity for Bucharest.

### 3. Load the FL model (pretrain + finetune)

```bash
python3 backend/pretraining/pretrain.py
python3 backend/pretraining/finetune.py
```

Trains the recommendation MLP on Foursquare + Yelp + synthetic data, then pushes the weights to Redis. Only needed once after initial setup or after clearing Redis.

Run from the repo root. Requires `numpy`, `scikit-learn`, `requests`.

### 4. Run the mobile app

```bash
cd mobile
flutter pub get
flutter run
```

The app connects to `http://10.0.2.2:8000` (Android emulator) or the configured backend URL.

---

## FL dashboard

Open `web/dashboard.html` directly in a browser. It connects to the backend to show:

- Current FL round, number of contributing devices, total training samples
- Last training algorithm (FedAvg or FedProx)
- Live engagement heatmap (Interest × Landmark type)
- W1 / W2 weight matrix visualisation with feature labels
- Interactive predictor and sensitivity panel

---

## Federated Learning system

### Model

A small MLP with sigmoid output predicting engagement probability ∈ [0, 1]:

```
Input (22) → W1 (32×22) → ReLU → W2 (16×32) → ReLU → W3 (1×16) → Sigmoid
```

1,281 parameters. Implemented from scratch in both Dart (client) and Python (server/simulation).

### What is implemented

| Component | Detail |
|---|---|
| **FedProx** (client) | Proximal term `μ/2 · ‖w − w_global‖²` added to local loss during SGD. Prevents excessive drift. Default `μ = 0.1`. |
| **Clipped FedAvg** (server) | Delta norm clipped to `max_norm = 1.0` before aggregation. Limits influence of adversarial clients. |
| **Differential Privacy** (client) | Gaussian noise `N(0, (σ·C)²)` added to weight delta before upload. Mitigates membership inference attacks (Shokri et al., 2017). `σ = 0.1`, `C = 1.0`. |
| **Staleness-aware aggregation** | Client uploads include the round number at which they downloaded the global model. The server discounts stale updates: `effective_samples = num_samples / (1 + staleness)`, where `staleness = current_round − client_round`. A client 9 rounds behind contributes 1/10th the weight of a fresh one. Discount formula follows FedAsync (Xie et al., 2019). |
| **Aggregation lock** | A Redis `SET NX PX` lock (`fl:agg_lock`, 5 s TTL) wraps the read-aggregate-write cycle in `submit_client_update`. Prevents two simultaneous uploads from reading the same global weights and overwriting each other. Auto-expires on crash. |
| **Async FL** | One client per round. Server aggregates immediately after each upload. No synchronisation barrier needed. Chosen because client availability is heterogeneous — occasional tourists, daily commuters, and infrequent users cannot be expected to submit simultaneously. Synchronous FL would suffer from the straggler problem: rounds block on the slowest client, or slow/irregular users get dropped and the model becomes biased toward frequent users with good hardware. Async with FedAsync staleness discount is the correct architecture for a general-audience mobile app at any scale. |
| **Interaction threshold** | Local training triggers automatically after 15 interactions, or manually from the profile screen. |
| **Route generation pipeline** | Step 1: FL score × 0.8 + proximity × 0.2 for candidate filtering. Step 2: interest-match tiebreaker for greedy selection. Step 3: FL-scaled dwell time per stop. |
| **Pretraining** | Offline MLP trained on Foursquare check-ins + Yelp reviews + synthetic engagement data. |
| **Finetuning** | Second training pass with route-aware features and bias corrections before pushing to Redis. |

### Engagement labels

| Event | Label |
|---|---|
| Landmark sheet opened | 0.40 |
| Navigation started | 0.65 |
| Quest completed | 0.90 |
| Rating (1–5 stars) | stars / 5.0 (overrides all others) |

### Privacy

- Raw visit history, ratings, routes, and quest answers never leave the device.
- Only trained weight deltas (with DP noise) are uploaded.
- Server applies delta norm clipping before aggregation.
- Privacy details are surfaced to users in the in-app Privacy screen.

---

## FL simulation script

Compares FedAvg vs FedProx over 100 synthetic rounds starting from the current Redis weights.

```bash
# Run inside the backend container (Redis is not exposed to the host)
docker exec -it culturequest_backend python3 federated/simulate_fl.py

# Copy results to host
docker cp culturequest_backend:/app/federated/results backend/federated/results
```

Produces `loss_curve.png`, `weight_drift.png`, `probe_scores.png`, and `stats.json`. Pushes the winning algorithm's weights back to Redis.

See `backend/federated/SIMULATE.md` for full details.

---

## Useful commands

```bash
# Rebuild backend after code changes
docker compose up -d --build backend

# Clear all FL state from Redis (forces re-init from finetune weights on next request)
docker exec $(docker ps -qf name=redis) redis-cli -a secret --no-auth-warning \
    DEL fl:global_weights fl:round fl:client_ids fl:total_samples fl:algorithm fl:last_staleness fl:agg_lock

# Reseed database
docker exec culturequest_backend python3 seed_bucharest.py
```
