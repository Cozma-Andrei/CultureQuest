#!/usr/bin/env python3
"""
CultureQuest FL Pre-training Data Preparation
=============================================
Processes Foursquare (TSMC2014, TIST2015, ubicomp2013) + Yelp + Seeder data
into 22-dim feature vectors with engagement labels for MLP warm-start.

Run from project root:
    python backend/pretraining/prepare_data.py

Outputs (in backend/pretraining/output/):
    train.npz, val.npz  - feature arrays X (N,22) and labels y (N,)
    stats.json          - dataset statistics
    charts/             - analysis plots
"""

import os, sys, json, zipfile, tarfile, io
import numpy as np
import matplotlib; matplotlib.use('Agg')
import matplotlib.pyplot as plt
from datetime import datetime, timedelta
from collections import defaultdict

try:
    from pymongo import MongoClient
    HAS_MONGO = True
except ImportError:
    HAS_MONGO = False
    print("WARNING: pymongo not installed. Seeder data will be skipped.")

# ── Paths ──────────────────────────────────────────────────────────────────────
BASE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TSMC2014_ZIP = '/home/andrei-cozma/Desktop/dataset_tsmc2014.zip'
TIST2015_ZIP = '/home/andrei-cozma/Desktop/dataset_TIST2015.zip'
UBICOMP_ZIP  = '/home/andrei-cozma/Desktop/dataset_ubicomp2013.zip'
YELP_ZIP     = '/home/andrei-cozma/Desktop/Yelp-JSON.zip'
MONGO_URI    = 'mongodb://admin:secret@localhost:27017/culturequest?authSource=admin'
OUT_DIR      = os.path.join(os.path.dirname(__file__), 'output')
CHARTS_DIR   = os.path.join(OUT_DIR, 'charts')
os.makedirs(CHARTS_DIR, exist_ok=True)

# ── Feature schema (must match fl_client_service.dart) ────────────────────────
INTERESTS = ['art', 'architecture', 'history', 'gastronomy', 'nature', 'music']
TYPES     = ['museum', 'monument', 'park', 'gallery', 'restaurant', 'square', 'building', 'other']
INPUT_DIM = 22

# Features fixed to neutral in global pretraining (no per-session context):
#   [17] relativeDistanceRank  -> 0.5
#   [19] isPartOfRoute         -> 0.0
#   [20] routeStopNormalized   -> 0.0
#   [21] routeLengthNormalized -> 0.0

# ── Label constants ────────────────────────────────────────────────────────────
L_CHECKIN  = 0.70   # single Foursquare check-in
L_REPEAT   = 0.90   # 3+ check-ins same venue (capped)
L_TIP      = 0.75   # user left a tip/comment (stronger engagement)
L_SEEDER   = 0.70   # seeder simulated visit baseline

# Yelp: label = stars / 5.0  (explicit sentiment, overrides everything)
# Repeat check-in bonus: L_CHECKIN + 0.05 * max(0, count-1), capped at L_REPEAT

# ── Category mappings ─────────────────────────────────────────────────────────

FS_EXACT = {
    'museum':'museum','art museum':'museum','history museum':'museum',
    'science museum':'museum',"children's museum":'museum',
    'natural history museum':'museum','war memorial museum':'museum',
    'maritime museum':'museum','folk art museum':'museum',
    'art gallery':'gallery','gallery':'gallery','arts & crafts store':'gallery',
    'performing arts venue':'gallery','art school':'gallery',
    'park':'park','national park':'park','state park':'park',
    'garden':'park','botanical garden':'park','playground':'park',
    'beach':'park','trail':'park','forest':'park','lake':'park',
    'river':'park','harbor':'park','scenic lookout':'park','waterfall':'park',
    'skate park':'park','pier':'park','nature preserve':'park',
    'restaurant':'restaurant','bar':'restaurant','café':'restaurant','cafe':'restaurant',
    'bakery':'restaurant','food truck':'restaurant','fast food restaurant':'restaurant',
    'pizza place':'restaurant','burger joint':'restaurant','chinese restaurant':'restaurant',
    'italian restaurant':'restaurant','sushi restaurant':'restaurant',
    'steakhouse':'restaurant','diner':'restaurant','food court':'restaurant',
    'brewery':'restaurant','wine bar':'restaurant','cocktail bar':'restaurant',
    'pub':'restaurant','coffee shop':'restaurant','tea room':'restaurant',
    'dessert shop':'restaurant','ice cream shop':'restaurant',
    'sandwich place':'restaurant','seafood restaurant':'restaurant',
    'vegetarian / vegan restaurant':'restaurant','middle eastern restaurant':'restaurant',
    'japanese restaurant':'restaurant','thai restaurant':'restaurant',
    'indian restaurant':'restaurant','mexican restaurant':'restaurant',
    'french restaurant':'restaurant','mediterranean restaurant':'restaurant',
    'tapas restaurant':'restaurant','barbeque joint':'restaurant',
    'american restaurant':'restaurant','gastropub':'restaurant',
    'noodle house':'restaurant','dim sum restaurant':'restaurant',
    'ramen restaurant':'restaurant','latin american restaurant':'restaurant',
    'deli / bodega':'restaurant','bistro':'restaurant','brasserie':'restaurant',
    'historic site':'monument','monument':'monument','memorial site':'monument',
    'landmark':'monument','bridge':'monument','church':'monument',
    'cathedral':'monument','mosque':'monument','temple':'monument',
    'synagogue':'monument','castle':'monument','palace':'monument',
    'memorial':'monument','war memorial':'monument','cemetery':'monument',
    'ruins':'monument','historic building':'monument','shrine':'monument',
    'monastery':'monument','statue':'monument','sculpture garden':'monument',
    'theater':'square','theatre':'square','concert hall':'square',
    'opera house':'square','music venue':'square','comedy club':'square',
    'nightclub':'square','stadium':'square','amphitheater':'square',
    'event space':'square','town square':'square','plaza':'square',
    'convention center':'square','auditorium':'square','arena':'square',
    'festival':'square','market':'square','farmers market':'square',
    'boardwalk':'square','promenade':'square',
    'library':'building','university':'building','college':'building',
    'city hall':'building','government building':'building',
    'courthouse':'building','capitol':'building','embassy':'building',
    'observatory':'building','lighthouse':'building','tower':'building',
    'skyscraper':'building','aquarium':'building','zoo':'building',
    'planetarium':'building',
}

FS_SUBSTRINGS = [
    ('museum','museum'),('gallery','gallery'),('art center','gallery'),
    ('art space','gallery'),('arts center','gallery'),
    ('park','park'),('garden','park'),('beach','park'),('trail','park'),
    ('reserve','park'),('nature','park'),('forest','park'),('lake','park'),
    ('restaurant','restaurant'),('café','restaurant'),('cafe','restaurant'),
    ('bar','restaurant'),('pub','restaurant'),('bakery','restaurant'),
    ('coffee','restaurant'),('pizza','restaurant'),('burger','restaurant'),
    ('sushi','restaurant'),('grill','restaurant'),('bistro','restaurant'),
    ('brasserie','restaurant'),('diner','restaurant'),('eatery','restaurant'),
    ('brewery','restaurant'),('winery','restaurant'),('taco','restaurant'),
    ('noodle','restaurant'),('ramen','restaurant'),('dim sum','restaurant'),
    ('seafood','restaurant'),('steakhouse','restaurant'),
    ('historic','monument'),('monument','monument'),('memorial','monument'),
    ('landmark','monument'),('church','monument'),('cathedral','monument'),
    ('mosque','monument'),('temple','monument'),('synagogue','monument'),
    ('castle','monument'),('palace','monument'),('ruins','monument'),
    ('shrine','monument'),('cemetery','monument'),
    ('theater','square'),('theatre','square'),('concert','square'),
    ('opera','square'),('stadium','square'),('arena','square'),
    ('nightclub','square'),('plaza','square'),('market','square'),
    ('library','building'),('university','building'),('college','building'),
    ('city hall','building'),('government','building'),
    ('observatory','building'),('lighthouse','building'),('tower','building'),
    ('aquarium','building'),('zoo','building'),('planetarium','building'),
]

FS_SKIP = {
    'home','home (private)','office','hospital','medical center','pharmacy',
    'doctor','atm','bank','gas station','parking','airport','train station',
    'bus station','metro station','subway','gym','fitness center','yoga studio',
    'laundry','dry cleaners','grocery store','supermarket','convenience store',
    'department store','clothing store','shoe store','jewelry store',
    'electronics store','furniture store','hardware store','pet store',
    'auto dealership','car wash','moving company','storage facility',
    'residential building','neighborhood','road','highway','intersection',
    'taxi','rental car','bike rental','post office','government building',
}

YELP_MAP = {
    'museums':'museum','art museums':'museum','history museums':'museum',
    'science museums':'museum',"children's museums":'museum',
    'specialty museums':'museum',
    'art galleries':'gallery','galleries':'gallery',
    'parks':'park','botanical gardens':'park','national parks':'park',
    'state parks':'park','lakes':'park','beaches':'park',
    'hiking':'park','nature parks':'park','gardens':'park','trails':'park',
    'restaurants':'restaurant','food':'restaurant','bars':'restaurant',
    'cafes':'restaurant','bakeries':'restaurant','coffee & tea':'restaurant',
    'fast food':'restaurant','pizza':'restaurant','burgers':'restaurant',
    'sushi bars':'restaurant','steakhouses':'restaurant','diners':'restaurant',
    'breweries':'restaurant','wine bars':'restaurant','pubs':'restaurant',
    'gastropubs':'restaurant','cocktail bars':'restaurant',
    'breakfast & brunch':'restaurant','desserts':'restaurant',
    'ice cream & frozen yogurt':'restaurant','seafood':'restaurant',
    'italian':'restaurant','chinese':'restaurant','mexican':'restaurant',
    'french':'restaurant','japanese':'restaurant','thai':'restaurant',
    'indian':'restaurant','mediterranean':'restaurant','greek':'restaurant',
    'american (traditional)':'restaurant','american (new)':'restaurant',
    'nightlife':'restaurant','beer bar':'restaurant','sports bars':'restaurant',
    'tapas/small plates':'restaurant','brasseries':'restaurant',
    'landmarks & historical buildings':'monument','churches':'monument',
    'cathedrals':'monument','mosques':'monument','temples':'monument',
    'synagogues':'monument','cemeteries':'monument','monasteries':'monument',
    'historical tours':'monument','local flavor':'monument',
    'arts & entertainment':'square','performing arts':'square',
    'music venues':'square','theaters':'square','comedy clubs':'square',
    'stadiums & arenas':'square','venues & event spaces':'square',
    'festivals':'square','opera & ballet':'square','jazz & blues':'square',
    'cinemas':'square',
    'libraries':'building','universities':'building',
    'colleges & universities':'building','courthouses':'building',
    'aquariums':'building','zoos':'building','observatories':'building',
}

TYPE_TO_INTERESTS = {
    'museum':     ['art', 'history'],
    'gallery':    ['art'],
    'park':       ['nature'],
    'restaurant': ['gastronomy'],
    'monument':   ['history', 'architecture'],
    'square':     ['music'],
    'building':   ['architecture'],
    'other':      [],
}

# ── Utility functions ─────────────────────────────────────────────────────────

def map_fs_category(cat: str) -> str | None:
    if not cat:
        return None
    low = cat.lower().strip()
    if low in FS_SKIP:
        return None
    if low in FS_EXACT:
        return FS_EXACT[low]
    for substr, t in FS_SUBSTRINGS:
        if substr in low:
            return t
    return None

def map_yelp_categories(cats_str: str) -> str | None:
    if not cats_str:
        return None
    for cat in [c.strip().lower() for c in cats_str.split(',')]:
        if cat in YELP_MAP:
            return YELP_MAP[cat]
    return None

def infer_interests(type_counts: dict) -> list:
    total = sum(type_counts.values()) or 1
    out = []
    mus_gal = (type_counts.get('museum',0) + type_counts.get('gallery',0)) / total
    if mus_gal > 0.12:     out.append('art')
    if type_counts.get('monument',0)/total > 0.12: out.append('history')
    if type_counts.get('park',0)/total > 0.12:     out.append('nature')
    if type_counts.get('restaurant',0)/total > 0.35: out.append('gastronomy')
    if type_counts.get('square',0)/total > 0.12:   out.append('music')
    if type_counts.get('building',0)/total > 0.15: out.append('architecture')
    if not out:
        top = max(type_counts, key=type_counts.get, default='restaurant')
        m   = {'museum':'art','gallery':'art','monument':'history','park':'nature',
               'restaurant':'gastronomy','square':'music','building':'architecture'}
        out = [m.get(top, 'gastronomy')]
    return list(set(out))

def interest_match(user_interests: list, lm_type: str) -> float:
    if not user_interests:
        return 0.0
    type_ints = set(TYPE_TO_INTERESTS.get(lm_type, []))
    return len(set(user_interests) & type_ints) / len(user_interests)

def build_fv(user_interests, lm_type, is_open, is_weekend, hour_norm) -> np.ndarray:
    v = np.zeros(INPUT_DIM, dtype=np.float32)
    for i, ing in enumerate(INTERESTS):
        if ing in user_interests: v[i] = 1.0
    if lm_type in TYPES:         v[6 + TYPES.index(lm_type)] = 1.0
    v[14] = 1.0 if is_open  else 0.0
    v[15] = 1.0 if is_weekend else 0.0
    v[16] = float(hour_norm)
    v[17] = 0.5          # relativeDistanceRank - neutral (not available globally)
    v[18] = interest_match(user_interests, lm_type)
    v[19] = 0.0          # isPartOfRoute
    v[20] = 0.0          # routeStopNormalized
    v[21] = 0.0          # routeLengthNormalized
    return v

def parse_fs_time(utc_str: str, tz_offset: int) -> datetime | None:
    try:
        utc = datetime.strptime(utc_str.strip(), "%a %b %d %H:%M:%S +0000 %Y")
        return utc + timedelta(minutes=tz_offset)
    except:
        return None

# ── Dataset processors ────────────────────────────────────────────────────────

def process_tsmc2014() -> list:
    print("\n[TSMC2014] NYC + Tokyo Foursquare check-ins...")
    if not os.path.exists(TSMC2014_ZIP):
        print("  SKIP: file not found")
        return []

    raw = []   # (uid, vid, lm_type, is_weekend, hour_norm)
    with zipfile.ZipFile(TSMC2014_ZIP) as zf:
        for fname in ['dataset_tsmc2014/dataset_TSMC2014_NYC.txt',
                      'dataset_tsmc2014/dataset_TSMC2014_TKY.txt']:
            try:
                fobj = zf.open(fname)
            except KeyError:
                continue
            for line in fobj:
                p = line.decode('utf-8','ignore').strip().split('\t')
                if len(p) < 8: continue
                uid, vid, cat_name, tz_str, utc_str = p[0], p[1], p[3], p[6], p[7]
                lm_type = map_fs_category(cat_name)
                if not lm_type: continue
                dt = parse_fs_time(utc_str, int(tz_str) if tz_str.lstrip('-').isdigit() else 0)
                if not dt: continue
                raw.append((uid, vid, lm_type, dt.weekday()>=5, dt.hour/24.0))

    print(f"  Raw tourist check-ins: {len(raw):,}")

    # Per-user type counts for interest inference
    utc = defaultdict(lambda: defaultdict(int))
    vc  = defaultdict(int)
    for uid, vid, t, *_ in raw:
        utc[uid][t] += 1
        vc[(uid,vid)] += 1

    user_ints = {u: infer_interests(c) for u,c in utc.items()}

    # Deduplicate (uid,vid): best label, feature from first occurrence
    seen = {}
    for uid, vid, lm_type, is_wk, hour in raw:
        key = (uid, vid)
        count = vc[key]
        label = min(L_CHECKIN + 0.05 * max(0, count-1), L_REPEAT)
        if key not in seen or label > seen[key][1]:
            fv = build_fv(user_ints.get(uid,['gastronomy']), lm_type, True, is_wk, hour)
            seen[key] = (fv, label)

    records = list(seen.values())
    print(f"  Deduplicated records: {len(records):,}")
    return records


def process_tist2015(max_checkins: int = 2_000_000) -> list:
    print(f"\n[TIST2015] Global Foursquare check-ins (cap {max_checkins:,})...")
    if not os.path.exists(TIST2015_ZIP):
        print("  SKIP: file not found")
        return []

    # Load POIs: only keep tourist-relevant ones
    print("  Loading POI categories from zip...")
    pois = {}   # venue_id -> lm_type
    with zipfile.ZipFile(TIST2015_ZIP) as zf:
        try:
            with zf.open('dataset_TIST2015_POIs.txt') as f:
                for i, line in enumerate(f):
                    p = line.decode('utf-8','ignore').strip().split('\t')
                    if len(p) < 4: continue
                    vid, cat = p[0], p[3]
                    t = map_fs_category(cat)
                    if t: pois[vid] = t
                    if i % 500_000 == 0:
                        print(f"    POIs processed: {i:,} | kept: {len(pois):,}", end='\r')
        except KeyError:
            print("  WARNING: POIs file not found in zip")
            return []
    print(f"\n  Tourist POIs loaded: {len(pois):,}")

    raw = []
    n_total = 0
    with zipfile.ZipFile(TIST2015_ZIP) as zf:
        try:
            with zf.open('dataset_TIST2015_Checkins.txt') as f:
                for line in f:
                    if len(raw) >= max_checkins: break
                    p = line.decode('utf-8','ignore').strip().split('\t')
                    if len(p) < 4: continue
                    n_total += 1
                    uid, vid, utc_str, tz_str = p[0], p[1], p[2], p[3]
                    lm_type = pois.get(vid)
                    if not lm_type: continue
                    dt = parse_fs_time(utc_str, int(tz_str) if tz_str.lstrip('-').isdigit() else 0)
                    if not dt: continue
                    raw.append((uid, vid, lm_type, dt.weekday()>=5, dt.hour/24.0))
                    if len(raw) % 100_000 == 0:
                        print(f"    Processed: {len(raw):,}", end='\r')
        except KeyError:
            print("  WARNING: Checkins file not found in zip")
            return []

    print(f"\n  Raw tourist check-ins: {len(raw):,} (from {n_total:,} total)")

    utc = defaultdict(lambda: defaultdict(int))
    vc  = defaultdict(int)
    for uid, vid, t, *_ in raw:
        utc[uid][t] += 1
        vc[(uid,vid)] += 1

    user_ints = {u: infer_interests(c) for u,c in utc.items()}

    seen = {}
    for uid, vid, lm_type, is_wk, hour in raw:
        key = (uid, vid)
        count = vc[key]
        label = min(L_CHECKIN + 0.05 * max(0, count-1), L_REPEAT)
        if key not in seen or label > seen[key][1]:
            fv = build_fv(user_ints.get(uid,['gastronomy']), lm_type, True, is_wk, hour)
            seen[key] = (fv, label)

    records = list(seen.values())
    print(f"  Deduplicated records: {len(records):,}")
    return records


def process_ubicomp2013() -> list:
    print("\n[ubicomp2013] NYC restaurant check-ins + tips...")
    if not os.path.exists(UBICOMP_ZIP):
        print("  SKIP: file not found")
        return []

    # All venues are restaurants - fixed type
    # No time info available - use weekday noon as neutral
    LM_TYPE  = 'restaurant'
    IS_WK    = False
    HOUR_N   = 0.5   # noon

    checkin_vids = defaultdict(set)   # uid -> set of vids
    tip_pairs    = set()              # (uid, vid) with tip

    with zipfile.ZipFile(UBICOMP_ZIP) as zf:
        # Check-ins
        with zf.open('dataset_ubicomp2013/dataset_ubicomp2013_checkins.txt') as f:
            for line in f:
                p = line.decode('utf-8','ignore').strip().split('\t')
                if len(p) < 2: continue
                checkin_vids[p[0]].add(p[1])

        # Tips (user commented = stronger engagement)
        with zf.open('dataset_ubicomp2013/dataset_ubicomp2013_tips.txt') as f:
            for line in f:
                p = line.decode('utf-8','ignore').strip().split('\t')
                if len(p) < 2: continue
                tip_pairs.add((p[0], p[1]))

    # All users here visit restaurants - infer gastronomy interest
    user_ints = ['gastronomy']

    seen = {}
    for uid, vids in checkin_vids.items():
        for vid in vids:
            label = L_TIP if (uid,vid) in tip_pairs else L_CHECKIN
            key = (uid, vid)
            if key not in seen or label > seen[key][1]:
                fv = build_fv(user_ints, LM_TYPE, True, IS_WK, HOUR_N)
                seen[key] = (fv, label)

    records = list(seen.values())
    print(f"  Deduplicated records: {len(records):,}")
    return records


def _yelp_is_open(hours: dict, review_date: str) -> bool:
    """Check if business was open at noon on the review date."""
    if not hours: return True
    try:
        dt = datetime.strptime(review_date, '%Y-%m-%d')
        day_name = dt.strftime('%A')  # Monday, Tuesday...
        schedule = hours.get(day_name, '')
        if not schedule: return False
        parts = schedule.split('-')
        if len(parts) < 2: return True
        open_h, open_m = map(int, parts[0].split(':'))
        close_h, close_m = map(int, parts[1].split(':'))
        noon_min = 12 * 60
        open_min = open_h * 60 + open_m
        close_min = close_h * 60 + close_m
        if close_min > open_min:
            return open_min <= noon_min < close_min
        return True  # midnight cross-over: assume open
    except:
        return True


YELP_TEMP_TAR = '/tmp/cq_yelp_dataset.tar'

def _extract_yelp_tar():
    """Extract the tar from inside the Yelp zip to a temp file (done once)."""
    import shutil
    if os.path.exists(YELP_TEMP_TAR):
        print(f"  Using cached tar: {YELP_TEMP_TAR}")
        return True
    print(f"  Extracting tar from zip to {YELP_TEMP_TAR} (~4.3 GB, takes a few minutes)...")
    try:
        with zipfile.ZipFile(YELP_ZIP) as zf:
            # Find the tar entry
            tar_entry = next((n for n in zf.namelist() if n.endswith('.tar') and 'MACOSX' not in n), None)
            if not tar_entry:
                print("  ERROR: no .tar file found inside Yelp zip")
                return False
            print(f"  Found: {tar_entry}")
            with zf.open(tar_entry) as src, open(YELP_TEMP_TAR, 'wb') as dst:
                shutil.copyfileobj(src, dst, length=64 * 1024 * 1024)  # 64 MB chunks
        print(f"  Extraction complete.")
        return True
    except Exception as e:
        print(f"  ERROR during extraction: {e}")
        if os.path.exists(YELP_TEMP_TAR):
            os.remove(YELP_TEMP_TAR)
        return False


def process_yelp(max_reviews: int = 1_500_000) -> list:
    print(f"\n[Yelp] Reviews with star ratings (cap {max_reviews:,})...")
    if not os.path.exists(YELP_ZIP):
        print("  SKIP: file not found")
        return []

    # Extract tar to disk if not already done (avoids streaming-mode issues)
    if not _extract_yelp_tar():
        return []

    # --- Pass 1: build business dict ---
    print("  Pass 1/3: loading business data from tar...")
    biz_dict = {}
    try:
        with tarfile.open(YELP_TEMP_TAR) as tf:
            for member in tf.getmembers():
                if 'business' in member.name and member.name.endswith('.json'):
                    f = tf.extractfile(member)
                    if not f: continue
                    n = 0
                    for line in f:
                        try:
                            b = json.loads(line)
                            t = map_yelp_categories(b.get('categories', '') or '')
                            if t:
                                biz_dict[b['business_id']] = {
                                    'type': t,
                                    'hours': b.get('hours') or {},
                                }
                            n += 1
                            if n % 50_000 == 0:
                                print(f"    Businesses: {n:,} | kept: {len(biz_dict):,}", end='\r')
                        except:
                            continue
                    print(f"\n  Tourist businesses: {len(biz_dict):,}")
                    break
    except Exception as e:
        print(f"  ERROR reading tar business file: {e}")
        return []

    if not biz_dict:
        print("  No businesses found - skipping Yelp")
        return []

    # --- Pass 2: user interest inference from review history ---
    print("  Pass 2/3: building user interest map...")
    user_type_counts = defaultdict(lambda: defaultdict(int))
    n_scanned = 0
    try:
        with tarfile.open(YELP_TEMP_TAR) as tf:
            for member in tf.getmembers():
                if 'review' in member.name and member.name.endswith('.json'):
                    f = tf.extractfile(member)
                    if not f: continue
                    for line in f:
                        try:
                            r = json.loads(line)
                            b = biz_dict.get(r['business_id'])
                            if b:
                                user_type_counts[r['user_id']][b['type']] += 1
                            n_scanned += 1
                            if n_scanned % 200_000 == 0:
                                print(f"    Reviews scanned: {n_scanned:,}", end='\r')
                            if n_scanned >= max_reviews * 2:
                                break
                        except:
                            continue
                    break
    except Exception as e:
        print(f"  WARNING: user interest scan failed: {e}")

    user_ints = {u: infer_interests(c) for u, c in user_type_counts.items()}
    print(f"\n  Users profiled: {len(user_ints):,}")

    # --- Pass 3: build feature vectors ---
    print("  Pass 3/3: building feature vectors from reviews...")
    seen = {}
    n_read = 0
    try:
        with tarfile.open(YELP_TEMP_TAR) as tf:
            for member in tf.getmembers():
                if 'review' in member.name and member.name.endswith('.json'):
                    f = tf.extractfile(member)
                    if not f: continue
                    for line in f:
                        if n_read >= max_reviews:
                            break
                        try:
                            r = json.loads(line)
                            b = biz_dict.get(r['business_id'])
                            if not b: continue
                            uid   = r['user_id']
                            stars = int(r.get('stars', 0))
                            date  = (r.get('date') or '')[:10]
                            if not stars or not date: continue

                            label   = stars / 5.0
                            is_open = _yelp_is_open(b['hours'], date)
                            try:
                                dt    = datetime.strptime(date, '%Y-%m-%d')
                                is_wk = dt.weekday() >= 5
                            except:
                                is_wk = False

                            key  = (uid, r['business_id'])
                            ints = user_ints.get(uid, ['gastronomy'])
                            fv   = build_fv(ints, b['type'], is_open, is_wk, 0.5)
                            if key not in seen or label > seen[key][1]:
                                seen[key] = (fv, label)
                            n_read += 1
                            if n_read % 100_000 == 0:
                                print(f"    Reviews processed: {n_read:,}", end='\r')
                        except:
                            continue
                    break
    except Exception as e:
        print(f"  WARNING: review build failed: {e}")

    records = list(seen.values())
    print(f"\n  Deduplicated records: {len(records):,}")
    return records


def process_seeder() -> list:
    print("\n[Seeder] MongoDB comments with star ratings...")
    if not HAS_MONGO:
        print("  SKIP: pymongo not available")
        return []
    try:
        client = MongoClient(MONGO_URI, serverSelectionTimeoutMS=5000)
        db = client['culturequest']
        db.command('ping')
    except Exception as e:
        print(f"  SKIP: MongoDB not reachable ({e})")
        return []

    # Load users for interests
    users = {str(u['_id']): [i for i in u.get('interests',[])]
             for u in db.users.find({}, {'interests':1})}
    # Load landmarks for type/categories
    landmarks = {str(l['_id']): {'type': l.get('type','other'),
                                  'categories': l.get('categories',[])}
                 for l in db.landmarks.find({'status':'approved'}, {'type':1,'categories':1})}

    records = []

    # Comments with ratings
    for c in db.comments.find({'flagged': False}):
        lid   = c.get('landmark_id','')
        lm    = landmarks.get(lid)
        stars = int(c.get('rating', 0))
        if not lm or not stars: continue
        label = stars / 5.0

        # No user_id in comments - use a random user's interests as proxy
        # (best we can do with anonymous comments)
        import random
        ints = random.choice(list(users.values())) if users else ['gastronomy']
        fv = build_fv(ints, lm['type'], True, False, 0.5)
        records.append((fv, label))

    # Simulated visit ratings from landmark aggregates
    for lm_doc in db.landmarks.find({'status':'approved','rating':{'$gt':0}}):
        lid    = str(lm_doc['_id'])
        lm_type = lm_doc.get('type','other')
        rating  = lm_doc.get('rating', 0)
        if rating <= 0: continue
        label = min(rating / 5.0, 1.0)
        # Create one sample per landmark with neutral user
        fv = build_fv(['gastronomy','art','history'], lm_type, True, False, 0.5)
        records.append((fv, label))

    client.close()
    print(f"  Records generated: {len(records):,}")
    return records

# ── Charts ────────────────────────────────────────────────────────────────────

def save_charts(X: np.ndarray, y: np.ndarray, source_counts: dict):
    print("\n[Charts] Generating analysis plots...")

    fig, axes = plt.subplots(2, 4, figsize=(20, 10))
    fig.suptitle('CultureQuest FL Pre-training Dataset Analysis', fontsize=14, fontweight='bold')

    # 1. Label distribution
    ax = axes[0,0]
    ax.hist(y, bins=40, color='steelblue', edgecolor='white', alpha=0.8)
    ax.set_title('Label Distribution'); ax.set_xlabel('Label (engagement score)'); ax.set_ylabel('Count')
    ax.axvline(y.mean(), color='red', linestyle='--', label=f'mean={y.mean():.2f}')
    ax.legend()

    # 2. Landmark type distribution
    ax = axes[0,1]
    type_indices = np.argmax(X[:,6:14], axis=1)
    type_counts_arr = np.bincount(type_indices, minlength=8)
    bars = ax.bar(TYPES, type_counts_arr, color='teal', alpha=0.8)
    ax.set_title('Landmark Type Distribution'); ax.set_xlabel('Type'); ax.set_ylabel('Count')
    ax.tick_params(axis='x', rotation=45)
    for bar, cnt in zip(bars, type_counts_arr):
        ax.text(bar.get_x()+bar.get_width()/2, bar.get_height()+50, f'{cnt:,}',
                ha='center', va='bottom', fontsize=7)

    # 3. Dataset source pie
    ax = axes[0,2]
    ax.pie(list(source_counts.values()), labels=list(source_counts.keys()),
           autopct='%1.1f%%', startangle=140, colors=['#4C72B0','#DD8452','#55A868','#C44E52','#8172B3'])
    ax.set_title('Records by Source')

    # 4. User interest distribution
    ax = axes[0,3]
    int_counts = [X[:,i].sum() for i in range(6)]
    ax.bar(INTERESTS, int_counts, color='orchid', alpha=0.8)
    ax.set_title('User Interest Frequency'); ax.set_xlabel('Interest'); ax.set_ylabel('Count')
    ax.tick_params(axis='x', rotation=30)

    # 5. isOpen distribution
    ax = axes[1,0]
    open_counts = [(X[:,14]==1).sum(), (X[:,14]==0).sum()]
    ax.bar(['Open','Closed'], open_counts, color=['green','salmon'], alpha=0.8)
    ax.set_title('isOpen Distribution'); ax.set_ylabel('Count')
    for i, (lbl, cnt) in enumerate(zip(['Open','Closed'], open_counts)):
        ax.text(i, cnt+20, f'{cnt:,}\n({cnt/len(y)*100:.1f}%)', ha='center', va='bottom', fontsize=9)

    # 6. isWeekend distribution
    ax = axes[1,1]
    wk_counts = [(X[:,15]==1).sum(), (X[:,15]==0).sum()]
    ax.bar(['Weekend','Weekday'], wk_counts, color=['coral','cornflowerblue'], alpha=0.8)
    ax.set_title('isWeekend Distribution'); ax.set_ylabel('Count')

    # 7. Hour distribution
    ax = axes[1,2]
    hours = X[:,16] * 24
    ax.hist(hours, bins=24, color='gold', edgecolor='white', alpha=0.8)
    ax.set_title('Hour of Day Distribution'); ax.set_xlabel('Hour'); ax.set_ylabel('Count')
    ax.set_xticks(range(0,25,4))

    # 8. Interest match score
    ax = axes[1,3]
    ax.hist(X[:,18], bins=20, color='mediumseagreen', edgecolor='white', alpha=0.8)
    ax.set_title('Interest Match Score'); ax.set_xlabel('Score [0,1]'); ax.set_ylabel('Count')

    plt.tight_layout()
    path = os.path.join(CHARTS_DIR, 'dataset_overview.png')
    plt.savefig(path, dpi=150, bbox_inches='tight')
    plt.close()
    print(f"  Saved: {path}")

    # Label by type (box plot)
    fig, ax = plt.subplots(figsize=(12,5))
    type_labels_data = []
    for ti in range(8):
        mask = np.argmax(X[:,6:14], axis=1) == ti
        type_labels_data.append(y[mask] if mask.any() else np.array([0]))
    bp = ax.boxplot(type_labels_data, labels=TYPES, patch_artist=True)
    colors = plt.cm.Set2(np.linspace(0,1,8))
    for patch, color in zip(bp['boxes'], colors):
        patch.set_facecolor(color)
    ax.set_title('Label Distribution by Landmark Type')
    ax.set_xlabel('Landmark Type'); ax.set_ylabel('Label (engagement)')
    ax.tick_params(axis='x', rotation=30)
    plt.tight_layout()
    path = os.path.join(CHARTS_DIR, 'label_by_type.png')
    plt.savefig(path, dpi=150, bbox_inches='tight')
    plt.close()
    print(f"  Saved: {path}")

    # Training/validation split summary
    n = len(y)
    n_train = int(n * 0.8)
    fig, ax = plt.subplots(figsize=(6,4))
    ax.bar(['Train (80%)','Val (20%)'], [n_train, n-n_train], color=['royalblue','tomato'], alpha=0.8)
    ax.set_title(f'Train/Val Split  (total={n:,})')
    ax.set_ylabel('Samples')
    for i,(lbl,cnt) in enumerate(zip(['Train','Val'],[n_train,n-n_train])):
        ax.text(i, cnt+50, f'{cnt:,}', ha='center', va='bottom')
    plt.tight_layout()
    path = os.path.join(CHARTS_DIR, 'train_val_split.png')
    plt.savefig(path, dpi=150, bbox_inches='tight')
    plt.close()
    print(f"  Saved: {path}")

# ── Main ──────────────────────────────────────────────────────────────────────

def generate_closed_samples(n_per_type: int = 300) -> list:
    """
    Synthetic samples for closed landmarks.

    All real data sources (Foursquare check-ins, Yelp reviews) only record
    interactions where the place was actually open — a user who finds a
    closed museum doesn't check in. Without synthetic examples the model
    never sees isOpen=0 during pretraining and can't learn that feature.

    Each sample: isOpen=0, hour in night/early-morning range, label=0.10
    (user opened the sheet, saw it was closed, did not engage).
    """
    import random
    print("\n[Synthetic] Generating closed-landmark samples...")
    interest_profiles = [
        ['art'], ['history'], ['gastronomy'], ['nature'], ['music'], ['architecture'],
        ['art', 'history'], ['gastronomy', 'nature'], ['art', 'music'],
        ['history', 'architecture'], ['nature', 'music'],
    ]
    records = []
    for lm_type in TYPES:
        for _ in range(n_per_type):
            ints  = random.choice(interest_profiles)
            is_wk = random.random() > 0.5
            # Typical closed hours: late night (22:00-24:00) or early morning (00:00-08:00)
            if random.random() > 0.4:
                hour = random.uniform(22 / 24, 1.0)   # late night
            else:
                hour = random.uniform(0.0, 8 / 24)    # early morning
            fv = build_fv(ints, lm_type, is_open=False, is_weekend=is_wk, hour_norm=hour)
            records.append((fv, 0.10))
    print(f"  Generated: {len(records):,} closed samples ({n_per_type} per type × {len(TYPES)} types)")
    return records


def main():
    print("=" * 60)
    print("CultureQuest FL Pre-training Data Preparation")
    print("=" * 60)

    all_records = []
    source_counts = {}

    datasets = [
        ('TSMC2014',   process_tsmc2014),
        ('TIST2015',   lambda: process_tist2015(max_checkins=2_000_000)),
        ('ubicomp2013',process_ubicomp2013),
        ('Yelp',       lambda: process_yelp(max_reviews=1_500_000)),
        ('Seeder',     process_seeder),
        ('Synthetic-Closed', lambda: generate_closed_samples(n_per_type=300)),
    ]

    for name, fn in datasets:
        try:
            records = fn()
            n = len(records)
            source_counts[name] = n
            all_records.extend(records)
            print(f"  -> {name}: {n:,} records added")
        except Exception as e:
            print(f"  ERROR in {name}: {e}")
            import traceback; traceback.print_exc()
            source_counts[name] = 0

    if not all_records:
        print("\nERROR: No records generated. Check dataset paths.")
        sys.exit(1)

    print(f"\nTotal records before balancing: {len(all_records):,}")

    import random

    # ── Fix 1: Balance type distribution ─────────────────────────────────────
    # Restaurant dominance skews the model toward gastronomy users.
    # Cap any single type at 2x the median type count so all 8 types
    # contribute meaningfully to weight training.
    X_raw = np.array([r[0] for r in all_records], dtype=np.float32)
    type_indices = np.argmax(X_raw[:, 6:14], axis=1)
    type_counts_raw = np.bincount(type_indices, minlength=8)
    median_count = int(np.median(type_counts_raw[type_counts_raw > 0]))
    cap = median_count * 2
    print(f"\nType balancing: median={median_count:,}  cap={cap:,}")

    balanced = []
    type_kept = np.zeros(8, dtype=int)
    random.shuffle(all_records)
    for rec in all_records:
        ti = int(np.argmax(rec[0][6:14]))
        if type_kept[ti] < cap:
            balanced.append(rec)
            type_kept[ti] += 1
    all_records = balanced
    for i, t in enumerate(TYPES):
        print(f"  {t:12s}: {type_kept[i]:,}")
    print(f"  Total after balancing: {len(all_records):,}")

    # ── Fix 2: Replace artificial noon spike ─────────────────────────────────
    # Yelp records have hour=0.5 (noon) because review timestamps have no time.
    # Replace with a realistic random hour per landmark type to avoid training
    # a spurious "noon → high engagement" association.
    TYPE_HOUR_RANGES = {
        'museum':     (10/24, 18/24),
        'gallery':    (10/24, 20/24),
        'park':       ( 8/24, 21/24),
        'restaurant': (11/24, 23/24),
        'monument':   ( 9/24, 19/24),
        'square':     (10/24, 23/24),
        'building':   ( 9/24, 18/24),
        'other':      ( 9/24, 20/24),
    }

    def randomise_hour(fv: np.ndarray) -> np.ndarray:
        if abs(fv[16] - 0.5) > 0.01:
            return fv  # already has a real hour, leave it
        ti = int(np.argmax(fv[6:14]))
        lm_type = TYPES[ti] if ti < len(TYPES) else 'other'
        lo, hi = TYPE_HOUR_RANGES.get(lm_type, (9/24, 20/24))
        fv = fv.copy()
        fv[16] = random.uniform(lo, hi)
        return fv

    all_records = [(randomise_hour(fv), label) for fv, label in all_records]
    print("Noon spike removed: Yelp hours randomised per landmark type.")

    # Shuffle and split
    random.shuffle(all_records)
    X = np.array([r[0] for r in all_records], dtype=np.float32)
    y = np.array([r[1] for r in all_records], dtype=np.float32)

    # Clip labels to [0,1]
    y = np.clip(y, 0.0, 1.0)

    n     = len(y)
    n_train = int(n * 0.8)
    X_train, y_train = X[:n_train], y[:n_train]
    X_val,   y_val   = X[n_train:], y[n_train:]

    # Save
    np.savez_compressed(os.path.join(OUT_DIR, 'train.npz'), X=X_train, y=y_train)
    np.savez_compressed(os.path.join(OUT_DIR, 'val.npz'),   X=X_val,   y=y_val)

    stats = {
        'total': n, 'train': n_train, 'val': n - n_train,
        'input_dim': INPUT_DIM,
        'label_mean': float(y.mean()), 'label_std': float(y.std()),
        'source_counts': source_counts,
        'type_counts': {t: int((np.argmax(X[:,6:14], axis=1)==i).sum()) for i,t in enumerate(TYPES)},
    }
    with open(os.path.join(OUT_DIR, 'stats.json'), 'w') as f:
        json.dump(stats, f, indent=2)

    print(f"\nSaved:")
    print(f"  train.npz  ({n_train:,} samples)")
    print(f"  val.npz    ({n-n_train:,} samples)")
    print(f"  stats.json")
    print(f"\nLabel stats: mean={y.mean():.3f}  std={y.std():.3f}")

    save_charts(X, y, source_counts)

    print("\nDone. Run pretrain.py next.")

if __name__ == '__main__':
    main()
