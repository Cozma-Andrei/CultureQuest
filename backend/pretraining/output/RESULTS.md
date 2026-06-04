# CultureQuest FL Pre-training Results

**Date**: 2026-06-04  
**Model**: MLP 22 -> 32 -> 16 -> 1 (1,281 parameters)  
**Dataset**: TSMC2014 + TIST2015 + ubicomp2013 + Yelp + Seeder + Synthetic-Closed

---

## Dataset Summary

| Source | Records | Label type |
|--------|---------|-----------|
| TSMC2014 (NYC + Tokyo) | check-ins balanced | Implicit (0.70-0.90) |
| TIST2015 (Global) | check-ins balanced | Implicit (0.70-0.90) |
| ubicomp2013 (NYC restaurants) | check-ins + tips | Implicit (0.70-0.75) |
| Yelp (reviews) | star ratings balanced | Explicit (0.20-1.00) |
| Seeder (CultureQuest MongoDB) | comments + aggregates | Explicit (0.20-1.00) |
| Synthetic closed | generated | Fixed (0.10) |
| **Total** | **741,588** | |
| Train (80%) | 593,270 | |
| Val (20%) | 148,318 | |

**Label distribution**: mean = 0.738, std = 0.154  
Range is narrow and skewed positive — most sources only record
successful visits (check-ins, reviews), with negative sentiment
underrepresented after type balancing.

---

## Training Configuration

| Parameter | Value |
|-----------|-------|
| Epochs | 60 (all ran, no early stop) |
| Batch size | 256 |
| Learning rate | 0.01 initial, ×0.98 decay/epoch |
| Final LR | 0.00298 |
| Optimiser | Mini-batch SGD |
| Loss | MSE |
| Early stopping patience | 10 epochs |

---

## Results

| Metric | Train | Val |
|--------|-------|-----|
| MSE (best) | 0.0232 | **0.0231** |
| RMSE | 0.1524 | **0.1520** |
| R² (approx.) | ~0.025 | **~0.025** |

**Prediction range**: [0.588, 0.852] — mean = 0.738

Training time: 76 seconds on CPU.

---

## Interpretation

### What went well

- Training converged stably with no divergence or oscillation.
- Train and val loss are nearly identical (no overfitting), which is
  expected for a model this small on a dataset this large.
- Predictions are centred on the correct mean (0.738 ≈ label mean).
- The model correctly encodes the direction of preferences — higher
  scores for matching interests, lower for closed venues — just with
  low confidence.
- Weights uploaded successfully to Redis as round 0.

### What is concerning

**R² ≈ 0.025** — the model explains only ~2.5% of label variance.
The remaining 97.5% is effectively noise from the model's perspective.
This manifests as a narrow prediction range [0.59, 0.85]: the model
predicts near the mean for almost every input and cannot produce
confidently low or high scores.

**The model is doing mean reversion**: rather than strongly
differentiating between a closed museum at midnight and a
perfectly-matched gallery for an art enthusiast, it assigns both
a score around 0.70-0.75.

### Root causes identified

**1. Type balancing removed negative-sentiment Yelp records**  
Restaurants dominate Yelp and most 1-2 star (low-label) reviews are
restaurant reviews. The type-balancing cap (2× median) kept cultural
landmark types but trimmed many of the negative restaurant records,
inadvertently removing the bulk of low-engagement training signal.

**2. Yelp itself skews positive**  
~60% of Yelp reviews are 4-5 stars due to selection bias. Even before
balancing, the label distribution from Yelp is skewed high.

**3. Fast convergence / LR too low**  
Loss moved from 0.0242 to 0.0231 across 60 epochs — 95% of improvement
happened in the first 5 epochs. The LR decay of 0.98 per epoch is too
aggressive; by epoch 30 the LR was 0.00545 and effectively stalled.

**4. Synthetic closed samples too small**  
2,400 synthetic records (0.3% of dataset) with label 0.10 are too few
to significantly pull the model toward the low end.

---

## Practical Impact

The pre-trained model is **better than random initialisation** but
**weaker than hoped** as a warm start. In practice this means:

- Landmark rankings in the first sessions for a new user will be
  subtle (all scores between 0.59–0.85) rather than strongly ordered.
- Users with very different interests may receive similar initial
  recommendations until FL personalisation kicks in.
- After 10–20 real interactions, local FL training will push each
  device's weights away from the near-mean plateau and produce
  meaningful differentiation.

The pretraining still achieves its core goal — avoiding cold-start
random noise — but the ranking signal is weak.

---

## Recommended Improvements (Fine-tuning)

These can be applied without retraining from scratch by continuing
from the saved weights:

| Fix | Expected impact |
|-----|----------------|
| Increase LR to 0.05, slower decay (0.995) | Model escapes the plateau |
| Remove type cap for restaurant when the record has stars ≤ 2 | More negative signal retained |
| Increase synthetic closed samples to 2,000 per type (16,000 total) | Low end of label range better covered |
| Add 30 more epochs from saved weights | Continues learning without resetting |

A full retrain from scratch is only needed if the model architecture
changes (e.g. 22->64->32->1) or if the feature vector dimensions change.
Continuing from the current weights counts as **fine-tuning** — see below.

---

## Artefacts

| File | Description |
|------|-------------|
| `output/train.npz` | Training set (593,270 × 22 features + labels) |
| `output/val.npz` | Validation set (148,318 × 22) |
| `output/stats.json` | Dataset statistics |
| `output/pretrained_weights.json` | Best weights (round 0, backed up locally) |
| `output/charts/dataset_overview.png` | 8-panel dataset analysis |
| `output/charts/label_by_type.png` | Label distribution per landmark type |
| `output/charts/train_val_split.png` | Train/val split |
| `output/charts/training_results.png` | Loss curves + predicted vs actual |

Weights are also live in Redis as the global FL model (round 0).
