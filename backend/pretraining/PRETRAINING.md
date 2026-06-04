# CultureQuest FL Model Pre-training

## Overview

The MLP (22 -> 32 -> 16 -> 1) starts from **random weights** by default,
which means early users receive useless recommendations. Pre-training runs
supervised learning on public datasets before any real user connects,
so the global model already understands basic landmark-type preferences
from day one.

---

## Datasets Used

### 1. TSMC2014 - Foursquare NYC + Tokyo (~800k raw check-ins)

**Source**: Yang et al., IEEE TSMC 2015  
**Files**: `dataset_TSMC2014_NYC.txt`, `dataset_TSMC2014_TKY.txt`  
**Format**: `user_id | venue_id | cat_id | cat_name | lat | lng | tz_offset | utc_time`

**What we extract**:
- Venue category name -> mapped to our 8 landmark types
- UTC time + timezone offset -> local hour and day-of-week
- Per-user check-in history -> inferred user interests

**Label**:
- Single check-in = **0.70** (user was physically there - strong positive)
- Repeat visits (same user, same venue): `min(0.70 + 0.05*(count-1), 0.90)`
- Deduplicated to one record per (user, venue) pair

**isOpen**: always `1` (check-in happened, so venue was open)

---

### 2. TIST2015 - Global Foursquare (~33M check-ins, sampled to 2M)

**Source**: Yang et al., 2015 (NationTelescope paper)  
**Files**: `dataset_TIST2015_Checkins.txt` (2.2 GB), `dataset_TIST2015_POIs.txt` (231 MB)

**What we extract**:
- POIs file loaded into memory first: `venue_id -> category_name`
  (only tourist-relevant categories kept, ~30% of 3.7M venues)
- Checkins file streamed from zip - only checkins with matching tourist POIs processed
- Same interest inference and label scheme as TSMC2014
- Capped at 2M check-ins for reasonable processing time

**Why useful**: Global coverage (77 countries, 415 cities) prevents the model
from being biased toward NYC/Tokyo patterns only.

---

### 3. ubicomp2013 - NYC Restaurants (~27k check-ins, ~10k tips)

**Source**: Yang et al., UbiComp 2013  
**Files**: `dataset_ubicomp2013_checkins.txt`, `dataset_ubicomp2013_tips.txt`

**What we extract**:
- All venues are restaurants in NYC - fixed type = `restaurant`
- Check-in = **0.70**, tip/comment left = **0.75** (stronger engagement)
- No time info available -> `hour=0.5` (noon, neutral), `isWeekend=False`
- All users assumed `gastronomy` interest

**Why useful**: Tips are the closest analogue to our review system -
a user who wrote a comment engaged more deeply than one who just checked in.

---

### 4. Yelp Open Dataset (~7M reviews, sampled to 1.5M)

**Source**: Yelp Inc. (academic license)  
**Files**: `yelp_academic_dataset_business.json`, `yelp_academic_dataset_review.json`
(inside `yelp_dataset.tar` inside `Yelp-JSON.zip`)

**Note on extraction**: Python's `tarfile` in streaming mode cannot reliably read
a tar that is itself inside a zip (the zip decompression stream is not seekable
in the way tarfile expects). The script extracts the tar to `/tmp/cq_yelp_dataset.tar`
(~4.3 GB) on first run and reuses it on subsequent runs. Requires ~5 GB free in `/tmp`.

**What we extract**:
- **Business file** (pass 1): `business_id -> {type, hours}` for tourist-relevant businesses
- **Review file** (pass 2+3): star ratings as labels, review date for isOpen/isWeekend

**Label**: `stars / 5.0` — this is an **explicit rating override**, the most
valuable signal because it reflects direct user sentiment (not just presence).

**isOpen**: computed from business hours + review date (noon assumption,
since review timestamps don't include time).

**isWeekend**: from review date (Python `weekday() >= 5`).

**Why this is the most important dataset**: Yelp provides **explicit negative
signals** (1-2 star reviews = labels 0.2-0.4) which the check-in datasets lack.
A model trained only on check-ins would never see "user disliked this place"
since people don't check in to places they don't like. Yelp fixes this.

---

### 5. Synthetic Closed Samples (generated, 300 per type = 2,400 total)

**Problem**: Every real-world source (Foursquare check-ins, Yelp reviews) only
records interactions where the place was open — if a user finds a museum closed,
they simply leave and no data is recorded. Without synthetic examples the model
never trains on `isOpen=0` and cannot learn that closed places get low engagement.

**Solution**: For each of the 8 landmark types, 300 synthetic samples are
generated with:
- `isOpen = 0`
- `hour` in night (22:00-24:00) or early morning (00:00-08:00) range
- `label = 0.10` (user opened the sheet, saw it was closed, disengaged)
- Random user interest profiles and weekend/weekday flags

These samples are a small fraction of the total dataset (~2,400 out of
hundreds of thousands) but are the only source of `isOpen=0` signal.

---

### 6. Seeder Data (CultureQuest MongoDB)

**Source**: The seed script that populates the development database.

**What we extract**:
- **Comments**: `rating / 5.0` as label (explicit rating from seeder comments)
- **Landmark aggregates**: average rating as label for each approved landmark
- User interests pulled from seeder user profiles

**Why useful**: Ensures the model starts with some Bucharest-specific
knowledge (Romanian landmark types, Central-Eastern European cultural patterns).

---

## Feature Vector (22 dimensions)

| Dim | Name | Value | Notes |
|-----|------|-------|-------|
| 0-5 | User interests (one-hot) | 0 or 1 | art, architecture, history, gastronomy, nature, music |
| 6-13 | Landmark type (one-hot) | 0 or 1 | museum, monument, park, gallery, restaurant, square, building, other |
| 14 | isOpen | 0 or 1 | Is the landmark currently open? |
| 15 | isWeekend | 0 or 1 | Saturday or Sunday? |
| 16 | hour / 24.0 | [0, 1] | Current hour of day normalised |
| 17 | relativeDistanceRank | [0, 1] | 0=closest nearby, 1=farthest nearby |
| 18 | interestMatchScore | [0, 1] | Fraction of user interests matching landmark type |
| 19 | isPartOfRoute | 0 or 1 | Was this interaction within a route? |
| 20 | routeStopNormalized | [0, 1] | 0=first/farthest stop, 1=last/closest |
| 21 | routeLengthNormalized | [0, 1] | Route length / 9 stops |

### Features NOT used in global pre-training

| Dim | Reason |
|-----|--------|
| 17 relativeDistanceRank | Requires knowing all landmarks visible in a specific session - unavailable in static datasets. Set to **0.5** (neutral). |
| 19 isPartOfRoute | Route concept does not exist in Foursquare or Yelp. Set to **0.0**. |
| 20 routeStopNormalized | Same as above. Set to **0.0**. |
| 21 routeLengthNormalized | Same as above. Set to **0.0**. |

These four features are set to neutral values during global pre-training.
Real user FL rounds are where the model first learns route ordering preferences,
as those features only have meaningful values during actual app usage.

---

## Label System

### Label values (engagement scale)

| Event | Label | Source |
|-------|-------|--------|
| Foursquare check-in (once) | 0.70 | TSMC2014, TIST2015 |
| Foursquare repeat visit (3+) | 0.90 (max) | TSMC2014, TIST2015 |
| ubicomp tip/comment | 0.75 | ubicomp2013 |
| 1-star Yelp rating | 0.20 | Yelp |
| 2-star Yelp rating | 0.40 | Yelp |
| 3-star Yelp rating | 0.60 | Yelp |
| 4-star Yelp rating | 0.80 | Yelp |
| 5-star Yelp rating | 1.00 | Yelp |
| Seeder comment (stars/5) | 0.20-1.00 | MongoDB |

### Deduplication rule

One record per (user, venue) pair per dataset:
- **Explicit rating present** (Yelp, seeder): use `stars / 5.0` regardless of other signals
- **No explicit rating** (Foursquare, ubicomp): use highest engagement event seen

This mirrors the in-app rule where a star rating overrides any implicit engagement label.

---

## Category Mapping

### Foursquare -> our 8 types

The Foursquare taxonomy has hundreds of categories. Mapping strategy:

1. **Exact match** against a curated dictionary of ~120 category names
2. **Substring match** for categories not in the exact dict (e.g. anything containing "museum" -> museum)
3. **Skip** if in the explicit exclusion list (home, office, hospital, ATM, pharmacy, gym, etc.)
4. **Skip** if no match found (preserves quality over quantity)

Tourist-relevant categories kept (approximate percentages of TSMC2014):
- restaurant / bar / café: ~55%
- park / beach / garden: ~15%
- museum / gallery: ~8%
- monument / church / historic: ~7%
- square / theater / stadium: ~8%
- building / library / university: ~7%

Non-tourist categories filtered out: home (private), office, medical center,
parking, gas station, gym, supermarket, clothing store, etc.

### Yelp -> our 8 types

Yelp categories are comma-separated strings (e.g. "Restaurants, Italian, Pizza").
We check each comma-separated token against a mapping dictionary.
First matching token wins.

---

## User Interest Inference

Since Foursquare check-in data contains no explicit interest declarations,
we infer interests from each user's visitation pattern:

```
art          if (museum + gallery visits) / total > 12%
history      if monument visits / total > 12%
nature       if park visits / total > 12%
gastronomy   if restaurant visits / total > 35%  (higher threshold - restaurants dominate)
music        if square/entertainment / total > 12%
architecture if building visits / total > 15%
```

If no interest meets the threshold, the user is assigned their top category's
corresponding interest as default.

For Yelp: same algorithm applied to each user's review history by business type.
For seeder: interests come directly from `user.interests` in MongoDB.

---

## Model Architecture

```
Input (22,)
    |
    W1 (32 x 22) + b1 (32,)  -> ReLU -> (32,)
    |
    W2 (16 x 32) + b2 (16,)  -> ReLU -> (16,)
    |
    W3 (1 x 16)  + b3 (1,)   -> Sigmoid -> scalar [0, 1]

Total parameters: 704 + 32 + 512 + 16 + 16 + 1 = 1,281
```

**Initialisation**: Xavier/He-like (`sqrt(2/fan_in)` scaling)  
**Loss**: Mean Squared Error `(pred - label)^2`  
**Optimiser**: Mini-batch SGD, batch size 256  
**Learning rate**: 0.01 with 0.98 decay per epoch  
**Early stopping**: patience 10 epochs on validation loss

---

## Data Analysis and Known Biases

After running `prepare_data.py` the `output/charts/` directory contains plots
that help diagnose dataset quality. Two structural biases are present in the
raw data and are corrected automatically by the script.

### Bias 1 — Restaurant dominance

**Origin**: Yelp's dataset is ~65% restaurants and bars. ubicomp2013 is 100%
restaurants. In the raw combined dataset, restaurants can account for 55-60%
of all records.

**Effect on the model**: The weight column `W1[:,10]` (restaurant type, dim 10
of the input) receives far more gradient updates than columns for museum,
gallery, or monument. The model becomes highly confident about restaurant
engagement patterns but underfitted for cultural landmark types — exactly the
wrong outcome for a cultural tourism app where art and history users are the
primary audience.

**What you see in the charts**: In `dataset_overview.png`, the
`Landmark Type Distribution` bar will show restaurant towering over all other
types before balancing. After balancing the bars should be within 2× of each
other.

**Fix applied**: After all sources are combined, the median count across the
8 types is computed. Any type exceeding `2 × median` is subsampled randomly
down to that cap. A 2× cap (not 1×) preserves the realistic signal that
restaurants are genuinely more common tourist stops than museums, while
preventing the ratio from becoming 50:1. The balancing is logged per type
so you can inspect the final counts.

---

### Bias 2 — Artificial noon spike (Yelp)

**Origin**: Yelp reviews carry a date (`2020-06-15`) but no time of day.
The script cannot determine what hour the user actually visited, so a neutral
`hour = 0.5` (noon) is assigned. Since Yelp contributes potentially hundreds
of thousands of records, this creates a sharp spike at 0.5 in the hour
distribution (dim 16).

**Effect on the model**: The model sees an outsized number of
`(restaurant, noon, star rating)` training samples. It trains a spurious
correlation: `hour ≈ 0.5 → moderate/high engagement`. At inference time this
slightly biases scores upward around midday regardless of the actual landmark
type or context.

**What you see in the charts**: In `dataset_overview.png`, the
`Hour of Day Distribution` histogram will show a spike at 0.5 if the fix is
not applied.

**Fix applied**: Any record with `hour == 0.5` exactly (the Yelp placeholder)
has its hour replaced with a random value drawn from a realistic range for
that landmark type:

| Type | Realistic hours |
|------|----------------|
| museum | 10:00 – 18:00 |
| gallery | 10:00 – 20:00 |
| park | 08:00 – 21:00 |
| restaurant | 11:00 – 23:00 |
| monument | 09:00 – 19:00 |
| square | 10:00 – 23:00 |
| building | 09:00 – 18:00 |

Foursquare and seeder records already have real timestamps and are left
untouched (detected by `|hour - 0.5| > 0.01`). This removes the artificial
spike without injecting real information — we are honest about the uncertainty
rather than pretending Yelp reviewers always visit at noon.

---

### Bias 3 — No closed landmarks in real data (corrected synthetically)

All real-world sources record only interactions where the place was open
(you only check in to or review an open venue). Without intervention, `isOpen`
(dim 14) is `1.0` for 100% of records and the model cannot learn that closed
landmarks get low engagement.

**Fix applied**: 300 synthetic samples per landmark type (2,400 total) are
generated with `isOpen=0`, night/early-morning hours, and `label=0.10`.
These are a small fraction of the full dataset but are the only training signal
for the negative case of `isOpen`. See the Synthetic section above for details.

---

### Reading the charts

| Chart | What to look for |
|-------|-----------------|
| `dataset_overview.png` — Label Distribution | Bell-curve-ish shape with mean ~0.65. Heavy skew toward 1.0 means dataset is too positive; heavy skew toward low values means too much synthetic negative data. |
| `dataset_overview.png` — Landmark Type Distribution | After balancing, bars should be within 2× of each other. If restaurant still dominates, increase balancing stringency. |
| `dataset_overview.png` — isOpen Distribution | Should show a visible Closed bar (~2,400 records). If absent, synthetic samples failed. |
| `dataset_overview.png` — Hour of Day | Should be roughly uniform or bimodal (lunch + evening peaks). A spike at exactly 0.5 means the noon fix did not apply. |
| `label_by_type.png` | Each box plot should span a reasonable range. A type with a very narrow box and high median means too few negative examples for that type. |
| `training_results.png` — Predicted vs Actual | Points should cluster along the diagonal. A horizontal band means the model collapsed to predicting the mean. |

---

## How to Run

### 1. Install dependencies (on host machine)

```bash
pip install numpy matplotlib requests pymongo
```

### 2. Prepare data

```bash
cd /path/to/CultureQuest
python backend/pretraining/prepare_data.py
```

This reads all dataset zips, generates feature vectors, and saves:
- `backend/pretraining/output/train.npz`
- `backend/pretraining/output/val.npz`
- `backend/pretraining/output/stats.json`
- `backend/pretraining/output/charts/*.png`

Expected time: 20-60 minutes (dominated by Yelp's 4.3GB tar).

### 3. Train and upload

Make sure the backend is running (`flutter run` or docker-compose), then:

```bash
python backend/pretraining/pretrain.py
```

This trains the MLP (~3 minutes), saves weights locally to
`backend/pretraining/output/pretrained_weights.json`, then POSTs them
to `POST /api/federated/admin/initialize` which writes to Redis and
resets the FL round counter to 0.

### 4. Verify

Check that the backend returns non-random predictions:
```bash
curl http://localhost:8000/api/federated/model/status
# Expected: {"round": 0, "status": "active", "num_clients": 0, "total_samples": 0}
```

The first time a device calls `GET /api/federated/model/global` it will
receive the pre-trained weights instead of the random initialization.

---

## After Pre-training: FL Lifecycle

```
Pre-training (offline, once):
    Public datasets + seeder -> train.npz/val.npz -> pretrain.py -> Redis

FL round N (online, per user sync):
    Device downloads global weights (pre-trained baseline)
    User interacts with app (sheet opened, quest, rating, review, navigation, route)
    After 10+ landmark interactions: local training for 5 epochs
    Device uploads delta weights with num_samples
    Server FedAvg: new_global = weighted_avg(device_update, current_global)
    Round counter increments
```

The pre-trained model provides:
- Meaningful baseline recommendations from day 1
- Correct prior that art-interested users engage with galleries
- Understanding that closed venues get low labels
- Weekend vs weekday behavioral differences
- Calibrated gastronomy baseline (most users visit restaurants)

FL then personalises this baseline per user over time, with
`relativeDistanceRank`, `isPartOfRoute`, `routeStopNormalized`, and
`routeLengthNormalized` only becoming meaningful once real route interaction
data starts flowing from the app.
