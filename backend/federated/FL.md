# CultureQuest Federated Learning

## Overview

CultureQuest uses Federated Learning (FL) to personalise landmark recommendations
without sending any raw user data to the server. Each device trains a local copy
of the recommendation model on the user's own interactions, then uploads only the
trained weight delta. The server merges deltas from all devices into a shared global
model. No individual visit, rating, or route ever leaves the device.

---

## Model Architecture

A small MLP with sigmoid output, predicting engagement probability in [0, 1]:

```
Input (22)
    |
    W1 (32 × 22) + b1 (32)  ->  ReLU     ->  (32)
    |
    W2 (16 × 32) + b2 (16)  ->  ReLU     ->  (16)
    |
    W3 (1  × 16) + b3 (1)   ->  Sigmoid  ->  scalar [0, 1]

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
| 21 | routeLengthNormalized | (route length − 1) / 4, max 5 stops -> 1.0 |

Dims 17, 19, 20, 21 are always 0 in pretraining data; they only carry signal
once real route interactions flow from the app.

---

## Full Lifecycle

```
1. Pretraining (offline, once)
   Foursquare + Yelp + synthetic data  ->  pretrain.py  ->  pretrained_weights.json
   pretrained_weights.json  ->  finetune.py  ->  finetuned_weights.json  ->  Redis

2. Device initialisation
   GET /api/federated/model/global  ->  device downloads global weights

3. User interacts with app
   Sheet open, navigation start, quest complete, rating, review
   ->  feature vector built + label assigned
   ->  buffered locally (one entry per landmark per round, deduped)

4. Local training triggers (≥ 15 interactions, or manual sync from profile)
   Local SGD for 5 epochs (FedAvg client procedure)  ->  trained weights
   Gaussian DP noise added to delta
   POST /api/federated/model/update  ->  uploads noisy delta + num_samples

5. Server aggregation (async, one client at a time)
   clipped_fedavg(client_update, global_weights, max_norm=1.0)
   Global weights updated in Redis, round counter incremented

6. Device receives updated round number, downloads new global weights next sync
```

---

## What Is Implemented

### Local training

Each device runs the standard FedAvg client procedure: plain SGD on the local
loss for a fixed number of epochs (5 by default, learning rate 0.01), then it
uploads the resulting weights for the server to merge into the global model.

```
w ← w − lr · ∇L(w)
```

**Why not FedProx, SCAFFOLD, or FedDyn?**

Each of these algorithms adds a correction term, a proximal penalty for
FedProx, control variates for SCAFFOLD, a dynamic regulariser for FedDyn,
that pulls a client's local update back toward consistency with its peers
training on the same round's checkpoint. FedProx, for example, adds:

```
L_FedProx(w) = L(w) + (μ/2) · ‖w − w_global‖²
```

so that no single client drifts far from the cohort sharing that checkpoint.
That correction only has meaning when many clients train concurrently from
one snapshot and the server must later reconcile their divergent views.

CultureQuest's async FL aggregates one client per round, so there is no
concurrent cohort to diverge from and no peer set to reconcile against. A
cross-client drift correction would have nothing to correct: it would only
bias every local update toward an arbitrary anchor point, with no convergence
proof behind it (the published proofs for all three algorithms, including
FedProx's in Li et al., MLSys 2020, assume synchronised multi-client rounds;
see *Future Recommendations* below).

What async FL does need, and what none of these algorithms provide, is a way
to discount contributions from clients that trained on an outdated snapshot.
That is a different problem, solved separately by the FedAsync staleness
discount described later in this document.

### FedAsync staleness discount

A client that downloaded global weights at round 3 and submits at round 50 is
47 rounds stale. If its update were weighted equally to a fresh client, stale
knowledge would be treated as current and the global model would regress.

The discount formula follows FedAsync (Xie et al., *Asynchronous Federated
Optimization*, arXiv:1903.03934, 2019):

```
staleness   = current_round − client_round   (clamped to 0)
discount    = 1 / (1 + staleness)
n_effective = max(1, round(n_samples × discount))
```

`n_effective` replaces `n_samples` in the weighted average inside
`clipped_fedavg`. A client that is 9 rounds stale contributes 1/10th the
weight of a fresh one. A fresh client (staleness = 0) is unaffected (discount = 1).

The client's round is already included in the `ModelUpdate` payload (`round`
field) and passed straight to `submit_client_update` as `client_round`.
The staleness and resulting effective sample count are returned in the
aggregation response for client-side logging.

A concrete scenario where staleness accumulates despite the small user base:

- **Holiday concurrent usage**: multiple users launch the app at the same
  time (e.g. a busy weekend in the city centre), all downloading the same
  global round R. As they walk routes and hit the 15-interaction threshold one
  by one, each submission advances the global round. Later submitters in the
  same group are now stale relative to the updates already applied by earlier
  submitters in the same session.

`runFLRound` re-fetches the global weights immediately before every round,
not just at first launch and on `AppLifecycleState.resumed`. This matters
because `_weights` holds the device's own locally-trained-and-noised copy
after the first round, not the server's aggregated result; without a
per-round re-fetch, a user running several rounds back-to-back in one long
session (or one who never backgrounds the app for days) would keep training
on top of their own drifting local copy while still reporting a `client_round`
that *looks* fresh, silently bypassing the discount above. The re-fetch
guarantees `client_round` always honestly reflects the round the weights were
downloaded from, immediately before that round's local training began.

### Server aggregation: clipped FedAvg

For async FL (one client per round), coordinate-wise median and trimmed-mean
are not applicable: there is only one incoming update. Delta norm clipping
is the standard defence:

```
delta       = client_weights − global_weights
scale       = min(1.0, max_norm / ‖delta‖)
clipped     = global_weights + delta · scale
new_global  = fedavg([(n_effective, clipped), (n_virtual, global)])
```

FedAvg computes a weighted average over all weight tensors. With a single client
update, it is a two-term blend between the client's clipped weights and the
current global weights:

```
new_w = (n_effective × clipped_w + n_virtual × global_w) / (n_effective + n_virtual)
```

`n_virtual = max(4 × n_effective, 20)`. These virtual samples represent the
current global model holding its ground as an anchor. With a 4:1 ratio of
virtual to effective samples, a single client update shifts the global model
by at most 20% from where it was; the other 80% is continuity from the
previous round.

The minimum of 20 virtual samples matters for stale clients. A client at
staleness 15 has `n_effective = max(1, round(15 / 16)) = 1`, giving
`n_virtual = max(4, 20) = 20` and a blend weight of `1 / 21 ≈ 5%`. The
staleness discount already reduced effective samples to 1; the virtual sample
floor reduces the blend weight a further factor of four compared to what the
4:1 ratio alone would give. Together they confine stale updates to near-zero
influence on the global model.

`max_norm = 1.0`. After clipping, the delta has L2 norm at most 1.0. A
malicious client submitting a maximally adversarial update can shift the global
model by at most `n_effective / (n_effective + n_virtual)` of that norm. Plain
`fedavg` (without clipping) is exercised in the simulation script's
clipping-robustness sweep to show exactly how much protection this provides
against a single rogue update.

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

### Aggregation lock

The read-aggregate-write cycle in `submit_client_update` is protected by a Redis
`SET NX PX` lock (`fl:agg_lock`, 5 s TTL):

```
acquire fl:agg_lock (SET NX PX 5000)
  -> read global weights
  -> compute clipped_fedavg
  -> write new weights + round + staleness
release fl:agg_lock (Lua: del only if token matches)
```

Without the lock, two simultaneous uploads would both read the same `global_weights`,
each compute an independent update, and one would silently overwrite the other.
At low traffic this is rare; at high concurrency it is near-certain.

The lock token is a per-request UUID checked in the release Lua script, so a
crashed request cannot accidentally release another request's lock.
The 5 s TTL ensures the lock is freed even if the server process is killed mid-aggregation.

### Interaction threshold

Local training triggers automatically after **15 interactions** (`_autoRoundThreshold`).
The user can also trigger it manually from the profile screen, but only once
**8 pending interactions** have accumulated; the sync button stays disabled
and shows "N more to sync" below that count.

### Engagement labels

Defined in `fl_provider.dart`, ordered weakest to strongest:

| Event | Label |
|-------|-------|
| Landmark sheet opened | 0.30 |
| Added to route | 0.50 |
| Quest attempted (incorrect answer) | 0.50 |
| Navigation started | 0.60 |
| Quest suggested | 0.80 |
| Story submitted | 0.85 |
| Quest completed (correct answer) | 0.90 |
| Rating given (1-5 stars) | stars / 5.0 (overrides all other labels) |

One entry per landmark per round. Explicit rating overrides engagement label;
engagement only updates if higher than the current buffered value.

### How FL scores drive route generation

FL inference runs three times per `POST /api/routes/generate`:

**Step 1: Candidate filtering**

All landmarks within 10 km scored and top 10 kept:
```
initial_score = fl_score · 0.8 + proximity · 0.2
```
FL score already encodes user interests, landmark type, and interest-match
fraction via the feature vector. Fallback to `interest_match · 0.8 + proximity · 0.2`
when Redis has no weights.

**Step 2: Greedy selection with interest tiebreaker**

Up to 5 stops selected. Selection key (lower = preferred):
```
interest_match = (categories ∩ user_interests) / len(categories)
selection_key  = distance_m − tiebreaker_m · interest_match
```
`tiebreaker_m` is chosen by the user via a slider (0–1000 m).

**Step 3: Dwell time scaling**

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

In CultureQuest's async FL (one client per round) there is nothing to mask with;
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
in opposite directions, and the result serves neither well. The explicit
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

### Switch to synchronous FL at scale (conditional)

The current architecture aggregates one client update per round (async FL),
chosen because a small user base cannot guarantee concurrent sessions and
async needs no synchronisation barrier. The cost is statistical: the model
moves on a single noisy sample per round instead of an average over many
simultaneous clients, so it converges more slowly and with higher variance
than synchronous FedAvg would. Sync would also unlock the broader FL
catalogue (FedProx, SCAFFOLD, FedDyn, SecAgg) that *Local training* above
already explains async cannot support, for the same reason: their proofs
need a concurrent cohort sharing one checkpoint, and async has none.

But sync only pays off when clients are **reliably available at the same
time**, and CultureQuest's users, from daily commuters to once-a-month
tourists, share no such schedule. That runs into the **straggler problem**:
a round can't close until all N clients submit, so throughput is bounded by
the slowest. **Wait**, and rounds stretch for hours or never close. **Drop**,
and you systematically exclude whoever has older devices, worse connectivity,
or irregular habits, biasing the model toward users with the best hardware
and the most free time. Async sidesteps this entirely (every client
contributes when ready); the FedAsync discount (Xie et al., 2019) absorbs
the resulting staleness instead of dropping anyone or blocking the round.

Sync is the right call only for **homogeneous availability**: a corporate
deployment where every device is online during the same working hours. For a
general-audience app, async with the staleness discount is correct
**regardless of scale**.

If sync were adopted anyway: clients would push updates to a Redis list
(`RPUSH fl:pending_updates`); a worker wakes at N updates (e.g. 50) and runs
`clipped_fedavg` over all of them atomically before writing the new global
weights and incrementing the round counter; with N simultaneous updates,
SecAgg becomes viable (masking each client's delta so the server never sees
individual uploads). The existing `fl:agg_lock` already covers the write;
the only real addition is the buffer in front of it. At very high scale, swap
the Redis list for a message queue (Kafka, RabbitMQ) to avoid memory pressure
and allow horizontal aggregation workers.

### Why not buffered / semi-async FL either?

A middle ground between the two extremes above: buffer K client updates and
aggregate them as a batch, instead of waiting for all N clients (sync) or
merging after every single upload (the current approach). This is FedBuff
(Nguyen et al., arXiv:2106.06639, 2022), and on paper it looks like a fix for
async's "single noisy sample per round" weakness: average K updates together
and the variance drops, without sync's all-N requirement.

Both buffering and sync need the same thing to pay off: client participation
that **clusters in time**, so that K (or N) updates land close enough together
to combine. Whether a deployment can assume that comes down to *who the
clients are*:

- **Cross-silo FL (the textbook hospital/bank examples)**: a handful of
  institutions running FL as a scheduled job on infrastructure they
  contractually committed to maintain. "Everyone trains between 2-6 AM UTC"
  is just an operations decision. Clustering is something the deployment can
  mandate, so sync and buffering work exactly as designed.
- **Cross-device FL on a consumer phone (CultureQuest)**: participation is a
  side effect of someone using the app for its own sake, on their own
  schedule, with no SLA. Nobody can tell a tourist to rack up 15 interactions
  between 2 and 6 AM. Clustering would have to emerge from human behaviour
  rather than be mandated by policy, and self-paced sightseeing doesn't
  produce it: even "Holiday concurrent usage" above, the closest this app
  gets to a concurrency spike, describes submissions crossing the threshold
  "one by one", not as a batch.

A buffer here would mostly wait on arrivals that never cluster, which just
rescales the straggler problem: wait, and updates sit unapplied for hours;
flush on a timeout, and the buffer empties at K ≈ 1, i.e. today's behaviour,
but slower and wrapped in extra machinery (buffer state, timeout tuning, a
second staleness clock for time spent waiting). That isn't a "not enough
users yet" gap that growth closes: a bigger CultureQuest is just more of the
same self-paced, staggered sessions, not more synchrony. Async with the
FedAsync discount matches what this app's users actually do, at any size.

### Personal head (user-level personalisation)

Keep FedAvg for the global backbone (shared patterns: landmark type scores,
time-of-day effects, isOpen penalty). Add a small personal last layer
(16 -> 1, 17 parameters) stored on-device only, never uploaded:

```
Global backbone (shared, FedAvg):   22 -> 32 -> 16
Personal head   (local, on-device):       16 -> 1
```

The global model provides a population-level prior; the personal head learns
each user's specific preferences (e.g. genuinely prefers greek restaurants over
romanian ones, prefers shorter visits, engages more on weekends) without being
diluted by other users' data. This also handles the future taxonomy expansion
case: if "restaurant" is split into cuisine subtypes, two gastronomy users
would have identical feature vectors for any subtype: the global backbone
cannot distinguish their preferences, but their personal heads can learn the
difference from actual engagement history.

### City-specific head (cross-city Federated Transfer Learning)

If CultureQuest scales to multiple cities (Bucharest, Cluj, Timisoara), each
city runs its own server with its own landmark DB and user base. FTL would:

1. Each city aggregates its own users' updates into a local model (same
   local-training + DP pipeline as now)
2. A meta-server runs FedAvg across only the **backbone layers** (W1 + W2)
   of each city's model
3. Each city keeps its **city head** (W3) local; it encodes city-specific
   patterns (landmark density, local cultural behaviour, event calendars)
4. No raw data or city-specific weights cross city boundaries

```
Meta-server:
    FedAvg over W1, W2 across cities  ->  shared backbone

City server (Bucharest):
    W3_bucharest  stays local

City server (Cluj):
    W3_cluj       stays local
```

This is architecturally identical to the personal head proposal: the same
split applied at the organisation/city level instead of the user level.
The shared backbone transfers general cultural engagement knowledge across
cities; the city head adapts it to local specifics without leaking data.
