# FL Simulation Script

Simulates N synthetic clients running FedAvg and FedProx side-by-side
from the **same pretrained weights** and **same random seed**, so differences
in the results come only from the algorithm, not noise.

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
2. Generates `N_CLIENTS` client profiles (each with 1–3 random interests).
3. Builds a shared test set (300 synthetic samples).
4. Measures baseline loss and probe scores on the fetched weights before any training.
5. Runs `N_ROUNDS` FL rounds twice — once per algorithm, both starting from the same weights.  
   Each round: pick a random client → generate interactions → train locally →
   add DP noise → `clipped_fedavg` on server.
6. Pushes the winning algorithm's final weights back to Redis via `initialize_model`,
   replacing the global model.
7. Saves stats and four plots.

## Outputs

| File | Contents |
|------|----------|
| `results/stats.json` | Config, initial baseline, per-algorithm summary (incl. % improvement vs initial), per-round arrays |
| `results/loss_curve.png` | Global Binary Cross-Entropy loss over rounds with a dotted baseline for the pretrained model before simulation |
| `results/weight_drift.png` | L2 norm of local−global delta each round |
| `results/probe_scores.png` | 4-bar groups: Expected / Initial / FedAvg / FedProx — shows how much each algorithm moved from the untrained model |
| `results/loss_gap.png` | Round-by-round loss difference (FedAvg − FedProx) — positive means FedProx wins |

## Key config (top of script)

| Variable | Default | Meaning |
|----------|---------|---------|
| `N_CLIENTS` | 10 | Distinct client interest profiles |
| `N_ROUNDS` | 100 | Total FL rounds per algorithm |
| `INTERACTIONS_PER_ROUND` | 15 | Synthetic interactions per round (matches app threshold) |
| `LOCAL_EPOCHS` | 5 | SGD passes over local data |
| `FEDPROX_MU` | 0.1 | Proximal penalty strength |
| `DP_SIGMA` | 0.1 | DP noise scale |
| `SEED` | 42 | Controls both client profiles and per-round client selection |

## Notes

- Both runs start from the same Redis weights and use the same client sequence — only the local training step differs.
- DP noise and server-side delta clipping are applied in both runs (same as production).
- `fedavg` (plain, no clipping) is kept in `model.py` for reference but is not used here; production always uses `clipped_fedavg`.
- The winning algorithm's weights are pushed to Redis at the end, so the real model benefits from the simulation.
- If Redis is unreachable at startup the script falls back to random weights and still runs (push at the end will also fail gracefully).
