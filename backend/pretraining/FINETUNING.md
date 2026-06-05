# CultureQuest FL Global Model Fine-tuning

## What is fine-tuning vs full retraining

**Fine-tuning**: continue gradient updates from the existing weights.
The model starts where pretraining left off, so what was already learned
is preserved. Learning rate is kept lower than scratch training to avoid
overwriting useful patterns (catastrophic forgetting).

**Full retrain**: reset weights to random initialisation, run prepare_data.py
and pretrain.py from scratch. Required only when the model architecture
changes (layer sizes or input dimensions).

**FL rounds**: every FL round is also fine-tuning — each device continues
from the global weights for a few local epochs before uploading its update.
The only on-device computation that would NOT be fine-tuning would be a
completely different mechanism (nearest-neighbour lookup, frozen layers
with a fresh personal head trained from scratch per user). Neither applies
to CultureQuest's current architecture.

---

## Why fine-tuning was needed

The pre-trained model showed **mean reversion** — predictions collapsed into
a narrow band [0.588, 0.852] despite labels spanning [0.10, 1.00].
R² ≈ 0.025: the model explained only 2.5% of label variance.

Two structural causes were identified:

### Cause 1 — Insufficient low-label signal

All real-world sources (Foursquare check-ins, Yelp reviews) record only
successful visits. There are two distinct types of low-engagement signal:

| Type | Source | Label |
|------|--------|-------|
| Negative sentiment | 1-2 star Yelp reviews | 0.20-0.40 |
| Contextually closed | Synthetic (isOpen=0) | 0.10 |

Both were underrepresented:
- Type-balancing capped restaurants (where most 1-2 star Yelp reviews live),
  inadvertently removing the bulk of negative-sentiment records
- Synthetic closed samples were only 0.3% of the dataset (2,400 of 741,588)

**Fix**: 2,000 additional synthetic closed samples per type (16,000 new records),
plus 3× oversampling of any existing record with label ≤ 0.40.

### Cause 2 — Learning rate decayed too fast

Pre-training used LR=0.01 with 0.98 decay per epoch. By epoch 30 the LR
was 0.00545 and the model effectively stalled — MSE moved from 0.0242 at
epoch 5 to only 0.0231 at epoch 60 (95% of improvement in first 5 epochs).

**Fix**: Fine-tuning uses LR=0.02 (higher than where pretraining stalled,
lower than scratch-training's 0.01 to avoid catastrophic forgetting) with
0.995 decay (much slower). This gives the model room to escape the plateau
without aggressively overwriting what was learned.

---

## What fine-tuning changes

### Data augmentation

**Extra synthetic closed samples (16,000 new)**:
- 2,000 per landmark type × 8 types
- isOpen=0, night/early-morning hours, label=0.10
- Random interest profiles and weekend/weekday flags
- These join the existing train.npz records

**3× oversampling of low-label records (label ≤ 0.40)**:
- Every record with label 0.10-0.40 is duplicated 3 times
- Compensates for type-balancing removing restaurant-shaped negative examples
- Does not add new information — just corrects the weight each existing
  negative record has in gradient updates

Effect on label distribution: mean shifts from 0.738 down toward 0.70,
std increases, low-label bin is better populated.

### Hyperparameters

| Parameter | Pretraining | Fine-tuning | Reason |
|-----------|------------|-------------|--------|
| Initial LR | 0.010 | **0.020** | Escape plateau; still below scratch LR |
| LR decay | 0.980 / epoch | **0.995 / epoch** | Slower decay, more epochs at useful LR |
| Epochs | 60 | **40** | Fewer needed since weights are already close |
| Early stop patience | 10 | **12** | Slightly more tolerance for slow improvement |
| Weight init | Random (Xavier) | **From pretrained_weights.json** | This is what makes it fine-tuning |

### What stays the same

- Architecture: 22 -> 32 -> 16 -> 1 (must match the global model in Redis)
- Loss: MSE
- Validation set: same val.npz (unchanged, fair comparison)
- Feature schema: all 22 dimensions identical

---

## What to expect from the charts

### `finetune_results.png` — three panels

**Loss curves (left)**:
- Should decrease more smoothly than pretraining (slower decay gives it more
  time to improve)
- Train and val should remain close (no overfitting expected given model size)
- If val starts rising while train falls, early stopping catches it

**Predicted vs Actual (centre)**:
- Key improvement to look for: points should appear in the bottom-left
  corner (model predicting low scores for low-label records) and
  top-right (high scores for high-label records)
- Pre-fine-tuning this plot had no points below ~0.59 predicted

**Prediction range width (right)**:
- Pre-fine-tuning: ~0.26 (predictions clustered near mean)
- Goal: widen to ≥ 0.40 (better discrimination between landmark contexts)
- If the bar does not grow significantly, the plateau issue persists
  and a larger model or more epochs is needed

---

## What fine-tuning cannot fix

**The proxy-preference gap**: the labels (0.70 for a Foursquare check-in,
stars/5 for a Yelp rating) are proxies, not ground-truth preference.
No amount of fine-tuning makes the model predict "actual engagement" —
it predicts a reconstruction of the proxy labels.

**Individual user preferences**: the global model learns population-level
patterns. Personal distance preference, route ordering preference, and
nuanced interest weighting only emerge after FL rounds with real user data.
Fine-tuning improves the starting point; FL personalisation does the rest.

---

## How to run

```bash
# Prerequisites: pretrain.py must have run first
# Backend must be running at localhost:8000

python backend/pretraining/finetune.py
```

Output:
- `output/finetuned_weights.json` — local backup of fine-tuned weights
- `output/charts/finetune_results.png` — loss curves + analysis
- Weights uploaded to Redis as round 0 via `POST /api/federated/admin/initialize`, replacing whatever weights are currently stored

### Determinism

`np.random.seed(42)` and `random.seed(42)` are both set at the top of `finetune.py`
(numpy and Python's built-in `random` module are separate states; both must be seeded).
Every run with the same `pretrained_weights.json` and `train.npz` produces byte-for-byte identical weights.
The output file is rewritten (timestamp changes) but the values do not change.
To get different weights: change the seed, change the data, or change the architecture.

---

## Decision tree for future iterations

```
Model predictions still collapse to mean?
  -> Yes: increase closed synthetic samples further, try LR 0.03, add epochs
  -> No: fine-tuning worked, monitor FL rounds

Architecture change needed (bigger model)?
  -> Yes: full retrain from scratch (pretrain.py with new INPUT/HIDDEN dims)
  -> No: continue fine-tuning from finetuned_weights.json

Real user FL data available?
  -> Yes: stop manual fine-tuning, let FL do the personalisation
  -> No: continue offline fine-tuning iterations
```
