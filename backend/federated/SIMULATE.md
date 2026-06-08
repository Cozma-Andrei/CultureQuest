# FL Simulation Script

Simulates `N_CLIENTS` synthetic clients running the production FL pipeline
from the **same pretrained weights** and **same random seed**, then compares
two things: the effect of the FedAsync staleness discount, and how much
protection server-side delta clipping provides against a rogue update.

## How to run

Redis is only reachable inside the Docker network, so run the script inside the
backend container:

```bash
docker exec -it culturequest_backend python3 federated/simulate_fl.py
```

Then copy the results out to the host:

```bash
docker cp culturequest_backend:/app/federated/results federated
```

Results are written to `backend/federated/results/`.

## What it does

1. **Fetches** the current global weights from Redis (the finetuned pretrained model).  
   Falls back to random weights if Redis is unreachable.
2. Generates `N_CLIENTS` client profiles (each with 1-3 random interests).
3. Builds a shared test set (300 synthetic samples).
4. Measures baseline loss and probe scores on the fetched weights before any training.
5. Runs `N_ROUNDS` FL rounds twice, from the same weights and the same client
   sequence: once with the FedAsync staleness discount applied (production
   behaviour), once with every update weighted equally regardless of staleness.  
   Each round: pick a random client, generate interactions, train locally,
   add DP noise, aggregate via `clipped_fedavg` on the server.
6. Sweeps one rogue client update through a range of L2 norms and aggregates
   it with both plain `fedavg` and production `clipped_fedavg`, to measure how
   much drift each allows into the global model.
7. Pushes the FedAsync run's final weights back to Redis via `_redis_push`,
   so the real model benefits from the simulation.
8. Saves stats and six plots.

## Outputs

| File | Contents |
|------|----------|
| `results/stats.json` | Config, initial baseline, per-variant summary (final/min loss, drift, effective weight, % improvement vs initial), per-round arrays, clipping-robustness sweep |
| `results/loss_curve.png` | Global Binary Cross-Entropy loss over rounds (production configuration) |
| `results/weight_drift.png` | L2 norm of the local-global delta each round |
| `results/fedasync_effect.png` | Loss curves with vs without the FedAsync discount, all else identical: isolates the discount's effect on convergence |
| `results/probe_scores.png` | 3-bar groups, Expected / Initial / Trained: shows how much training moved the model from its untrained state |
| `results/fedasync_discount_curve.png` | The discount function itself, `1 / (1 + staleness)`, and the effective sample count it produces for a typical round |
| `results/clipping_robustness.png` | Drift caused by one rogue update of growing magnitude, plain FedAvg vs production clipped FedAvg |

## Key config (top of script)

| Variable | Default | Meaning |
|----------|---------|---------|
| `N_CLIENTS` | 1000 | Distinct client interest profiles |
| `N_ROUNDS` | 100 | Total FL rounds per variant |
| `INTERACTIONS_PER_ROUND` | 15 | Synthetic interactions per round (matches app threshold) |
| `LOCAL_EPOCHS` | 5 | SGD passes over local data |
| `DP_SIGMA` | 0.1 | DP noise scale |
| `STALENESS_MAX` | 20 | Maximum simulated staleness in rounds (uniform 0-20 per client) |
| `SEED` | 42 | Controls both client profiles and per-round client selection |

## Notes

- Both FedAsync-comparison runs start from the same Redis weights and use the
  same client sequence; only the staleness discount differs, so any gap
  between them is attributable to that discount alone.
- The simulation writes weights directly via `_redis_push`, bypassing the
  `fl:agg_lock` used in production. This is intentional: the simulation is a
  single sequential process with no concurrent callers.
- DP noise and server-side delta clipping are applied in every FL round, same
  as production. The clipping-robustness sweep additionally runs plain
  `fedavg` (no clipping) purely for comparison; production always aggregates
  through `clipped_fedavg`.
- The FedAsync run's weights are the ones pushed to Redis at the end, so the
  real model benefits from the simulation.
- If Redis is unreachable at startup the script falls back to random weights
  and still runs (the push at the end will also fail gracefully).
