# CultureQuest Federated Learning

## Overview

CultureQuest uses Federated Learning (FL) to personalise landmark recommendations
without sending any raw user data to the server. Each device trains a local copy
of the recommendation model on the user's own interactions, then uploads only the
trained weight delta. The server merges deltas from all devices into a shared global
model — no individual visit, rating, or route ever leaves the device.

---

## Model Architecture

A small MLP with sigmoid output, predicting engagement probability in [0, 1]:

```
Input (22,)
    |
    W1 (32 × 22) + b1 (32,)  →  ReLU  →  (32,)
    |
    W2 (16 × 32) + b2 (16,)  →  ReLU  →  (16,)
    |
    W3 (1  × 16) + b3  (1,)  →  Sigmoid  →  scalar [0, 1]

Total parameters: 1,281
```

### Feature vector (22 dimensions)

| Dims | Name | Value |
|------|------|-------|
| 0-5 | User interests (one-hot) | art, architecture, history, gastronomy, nature, music |
| 6-13 | Landmark type (one-hot) | museum, monument, park, gallery, restaurant, square, building, other |
| 14 | isOpen | 0 or 1 |
| 15 | isWeekend | 0 or 1 |
| 16 | hour / 24.0 | [0, 1] |
| 17 | relativeDistanceRank | 0 = closest nearby, 1 = farthest |
| 18 | interestMatchScore | (user interests ∩ landmark categories) / len(user interests) |
| 19 | isPartOfRoute | 0 or 1 |
| 20 | routeStopNormalized | 0 = first stop, 1 = last stop |
| 21 | routeLengthNormalized | (route length − 1) / 4, max 5 stops → 1.0 |

Dims 17, 19, 20, 21 are always 0 in pretraining data — they only carry signal
once real route interactions flow from the app.

---

## Full Lifecycle

```
1. Pretraining (offline, once)
   Foursquare + Yelp + synthetic data  →  pretrain.py  →  pretrained_weights.json
   pretrained_weights.json  →  finetune.py  →  finetuned_weights.json  →  Redis

2. Device initialisation
   GET /api/federated/model/global  →  device downloads global weights

3. User interacts with app
   Sheet open, navigation start, quest complete, rating, review
   →  feature vector built + label assigned
   →  buffered locally (one entry per landmark per round, deduped)

4. Local training triggers (≥ 15 interactions, or manual sync from profile)
   FedProx local SGD for 5 epochs  →  trained weights
   Gaussian DP noise added to delta
   POST /api/federated/model/update  →  uploads noisy delta + num_samples

5. Server aggregation (async — one client at a time)
   clipped_fedavg(client_update, global_weights, max_norm=1.0)
   Global weights updated in Redis, round counter incremented

6. Device receives updated round number, downloads new global weights next sync
```

---

## What Is Implemented

### Local training — FedProx

Standard FedAvg uses plain SGD on the local loss. FedProx adds a proximal term
that prevents the local weights from drifting too far from the global model:

```
L_FedProx(w) = L(w) + (μ/2) · ‖w − w_global‖²
```

Gradient per coordinate during local training:

```
w ← w − lr · (∇L(w) + μ · (w − w_global))
```

`μ = 0.1` (configurable via `kFedProxMu`). Higher μ → less client drift,
more conservative updates. FedAvg is kept in code for baseline comparison
via the `FLAlgorithm` enum (`kFLAlgorithm = FLAlgorithm.fedProx`).

### Server aggregation — clipped FedAvg

For async FL (one client per round), coordinate-wise median and trimmed-mean
are not applicable — there is only one incoming update. Delta norm clipping
is the standard defence:

```
delta       = client_weights − global_weights
scale       = min(1.0, max_norm / ‖delta‖)
clipped     = global_weights + delta · scale
new_global  = fedavg([(num_samples, clipped), (virtual_samples, global)])
```

`max_norm = 1.0`. A malicious client can move any weight coordinate by at
most `1.0 / virtual_samples`, regardless of how extreme its update is.
Plain `fedavg` is kept alongside for the future comparison script.

### Differential Privacy

After local training, Gaussian noise is added to the weight delta before upload:

```
delta_i += N(0, (σ · C)²)    for each weight coordinate i
```

`σ = 0.1` (`kDPSigma`), `C = 1.0` (`kDPClipNorm`). This provides a
mathematical bound on membership inference: an adversary querying the global
model cannot determine whether a specific interaction (e.g. "did this user
visit the Romanian Athenaeum?") was in any client's training set.

Noise is generated on-device via Box-Muller transform. DP can be disabled
by setting `kDPEnabled = false` for performance testing.

### Interaction threshold

Local training triggers automatically after **15 interactions** (`_autoRoundThreshold`).
The user can also trigger it manually from the profile screen at any point
with ≥ 1 pending interaction.

### Engagement labels

| Event | Label |
|-------|-------|
| Landmark sheet opened | 0.40 |
| Navigation started | 0.65 |
| Quest completed | 0.90 |
| Rating given (1-5 stars) | stars / 5.0 (overrides all other labels) |

One entry per landmark per round. Explicit rating overrides engagement label;
engagement only updates if higher than the current buffered value.

### How FL scores drive route generation

FL inference runs three times per `POST /api/routes/generate`:

**Step 1 — Candidate filtering**

All landmarks within 10 km scored and top 10 kept:
```
initial_score = fl_score · 0.8 + proximity · 0.2
```
FL score already encodes user interests, landmark type, and interest-match
fraction via the feature vector. Fallback to `interest_match · 0.8 + proximity · 0.2`
when Redis has no weights.

**Step 2 — Greedy selection with interest tiebreaker**

Up to 5 stops selected. Selection key (lower = preferred):
```
interest_match = (categories ∩ user_interests) / len(categories)
selection_key  = distance_m − tiebreaker_m · interest_match
```
`tiebreaker_m` is chosen by the user via a slider (0–1000 m).

**Step 3 — Dwell time scaling**

FL runs a second inference pass with actual route-position dims filled in:
```
dwell = max(5, round(base_dwell · (0.75 + 0.5 · fl_score)))
```
Range: 0.75× (low engagement predicted) to 1.25× (high engagement predicted).

---

## Limitations of the Current Architecture

### No Secure Aggregation

Secure Aggregation (SecAgg, Bonawitz et al., 2017) is a cryptographic protocol
where the server computes only the **sum** of client updates and never sees any
individual client's weight delta. It requires multiple clients to submit
simultaneously so their masked contributions cancel each other out.

In CultureQuest's async FL (one client per round) there is nothing to mask with —
the server inherently sees the single incoming update. SecAgg is therefore
architecturally inapplicable without switching to synchronous multi-client rounds.

Differential Privacy partially compensates: the server receives a noisy delta,
which degrades its ability to reconstruct exact training samples. DP protects
against membership inference from the **global model**; it does not hide the
individual upload from the server itself. Since the server is the app's own
backend (trusted), this gap is an architectural constraint rather than an
oversight. If the server were ever untrusted, switching to synchronous FL
first would be a prerequisite for adding SecAgg.

### FedAvg washes out individual preferences

Each device upload is merged into the global model via weighted average.
A gastronomy-only user and a nature-only user both pull the global model
in opposite directions — the result serves neither well. The explicit
interest declarations in the feature vector (dims 0-5) compensate at
inference time, but the learned weights still reflect the population average.

### Yelp negative sentiment biases restaurant scores

Yelp contributes ~20-25% low-label restaurant records (1-3 stars) under
gastronomy user profiles. The model learns a muddled average for
`gastronomy + restaurant`, giving lower scores than expected for users who
actually love restaurants. FL rounds with positive in-app engagement
gradually correct this, but it is slow across many users.

---

## Future Recommendations

### Personal head (user-level personalisation)

Keep FedAvg for the global backbone (shared patterns: landmark type scores,
time-of-day effects, isOpen penalty). Add a small personal last layer
(16 → 1, 17 parameters) stored on-device only, never uploaded:

```
Global backbone (shared, FedAvg):   22 → 32 → 16
Personal head   (local, on-device):         16 → 1
```

The global model provides a population-level prior; the personal head learns
each user's specific preferences (e.g. genuinely prefers greek restaurants over
romanian ones, prefers shorter visits, engages more on weekends) without being
diluted by other users' data. This also handles the future taxonomy expansion
case: if "restaurant" is split into cuisine subtypes, two gastronomy users
would have identical feature vectors for any subtype — the global backbone
cannot distinguish their preferences, but their personal heads can learn the
difference from actual engagement history.

### City-specific head (cross-city Federated Transfer Learning)

If CultureQuest scales to multiple cities (Bucharest, Cluj, Timisoara), each
city runs its own server with its own landmark DB and user base. FTL would:

1. Each city aggregates its own users' updates into a local model (same
   FedProx + DP pipeline as now)
2. A meta-server runs FedAvg across only the **backbone layers** (W1 + W2)
   of each city's model
3. Each city keeps its **city head** (W3) local — it encodes city-specific
   patterns (landmark density, local cultural behaviour, event calendars)
4. No raw data or city-specific weights cross city boundaries

```
Meta-server:
    FedAvg over W1, W2 across cities  →  shared backbone

City server (Bucharest):
    W3_bucharest  stays local

City server (Cluj):
    W3_cluj       stays local
```

This is architecturally identical to the personal head proposal — the same
split applied at the organisation/city level instead of the user level.
The shared backbone transfers general cultural engagement knowledge across
cities; the city head adapts it to local specifics without leaking data.
