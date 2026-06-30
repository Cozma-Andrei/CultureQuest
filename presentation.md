# CultureQuest — Structură prezentare

> ~8 minute · 13 slide-uri principale + 8 slide-uri backup Q&A

---

## SLIDE 1 — Titlu

**CultureQuest**
*Personalizarea recomandărilor de rute culturale prin Federated Learning*

- Autor: Andrei Cozma
- Coordonator: [coordonator]
- Universitatea Politehnica București · 2026

**Imagine:** logo UPB + un singur screenshot reprezentativ din app (hartă cu obiective)

---

## SLIDE 2 — De ce? (Motivație)

> *Povestea începe de la un compromis pe care nicio aplicație actuală nu l-a rezolvat.*

**Problema în două rânduri:**
- Aplicațiile de explorare urbană (Google Maps, TripAdvisor) recomandează personalizat — dar *pe baza datelor tale stocate central*
- Confidențialitate sau personalizare — utilizatorul e forțat să aleagă

**Consecința:**
- Istoricul de vizite, locații GPS, preferințe → poate dezvălui rutine zilnice, afiliații
- Un sistem centralizat concentrează date sensibile ale fiecărui turist
- Recomandările bazate pe popularitate amplifică același circuit turistic: obiectivele deja aglomerate primesc și mai multă atenție, cele mai puțin cunoscute rămân invizibile

**→ Teza:** Personalizarea și confidențialitatea *nu se exclud reciproc* — și recomandarea bazată pe interese, nu pe popularitate, poate aduce la suprafață patrimoniul cultural mai puțin vizibil

**Imagine:** schemă simplă — date brute pe server (❌) vs. ponderi model pe server (✓)

---

## SLIDE 3 — State of the art

**Aplicații de explorare urbană:**

| Aplicație | Rute dinamice | Personalizare | Date pe server | Offline | Gamificare |
|---|---|---|---|---|---|
| Google Maps | Navigație | Centralizată | **Da** | Parțial | Nu |
| TripAdvisor | Nu | Centralizată | **Da** | Nu | Limitat |
| GetYourGuide | Tururi fixe | Limitată | **Da** | Nu | Nu |
| izi.TRAVEL | Audio predefinite | Nu | Nu | Parțial | Nu |
| **CultureQuest** | **Dinamice + FL** | **On-device** | **Nu** | **Da** | **Da** |

**Federated Learning în recomandări:**
- McMahan et al. (2017) — FedAvg: standard de facto pentru agregare FL sincronă
- Xie et al. (2019) — FedAsync: agregare asincronă cu discount de vechime → baza algoritmului adoptat
- NbAFL (Truex et al. 2020) — DP pe client prin clipping + zgomot Gaussian → adoptat direct

**Golul identificat:** nicio lucrare nu aplică FL asincron cu DP pe o aplicație de turism cultural cu generare de rute personalizate

---

## SLIDE 4 — Soluție propusă

**Screenshot principal:** hartă cu obiective + rută vizibilă pe ecran

Patru componente integrate:
- Obiective culturale pe hartă (raza 1 500 m pentru lista „nearby")
- Quest-uri activate la apropierea de un obiectiv (< 100 m)
- Rute generate dinamic (candidați din raza 10 km), personalizate prin scorul MLP al fiecărui obiectiv
- **Comunitate activă:** recenzii, povești ale locului, propuneri de obiective noi, vot comunitar — conținut generat de utilizatori, moderat înainte de publicare

Recomandarea bazată pe interese (nu pe popularitate) → obiective culturale mai puțin cunoscute devin vizibile pentru utilizatorii cu interese potrivite

**Imagine:** `pics/proximity-sheet.png` (fișa obiectivului cu scor potrivire) și `pics/route-generation.png`

---

## SLIDE 5 — Arhitectura sistemului

**Imagine:** `pics/arhitectura-generala.pdf`

| Strat | Tehnologie | Rol |
|---|---|---|
| Aplicație mobilă | Flutter + Riverpod | UI, antrenare FL locală, cache offline |
| Backend | FastAPI (Python) | API REST, agregare FL asincronă, generare rute |
| Stocare date | MongoDB | Obiective, utilizatori, recenzii, quests, rute |
| Stocare FL | Redis | Ponderi model global + lock agregare |
| Rutare | OSRM | Traseu real pe stradă (walking / driving) |

Trei fluxuri principale:
1. **Hartă + rute** — dispozitiv trimite poziție → backend interoghează MongoDB + scorează prin modelul din Redis → returnează ruta
2. **Agregare FL** — dispozitiv trimite delta ponderi → backend agregă cu modelul din Redis → returnează modelul actualizat
3. **Conținut comunitar** — recenzii/povești/quests trec prin moderare înainte de salvare în MongoDB

- O singură bază de cod Dart → Android + iOS
- Obiective în cache local SharedPreferences — funcțional și offline (NFR-2)

---

## SLIDE 6 — Federated Learning on-device: antrenare locală

**Principiul:** datele de interacțiune nu părăsesc niciodată dispozitivul

```
Dispozitiv: interacțiuni → buffer local → antrenare SGD → delta ponderi (~5 KB)
                                                                    ↓
                                                              trimis la server
```

**Ce se înregistrează în buffer** (cu label de engagement):
- Sheet obiectiv deschis → 0,3 · Navigație pornită → 0,6
- Quest completat → 0,9 · Rating explicit cu stele → stele/5

**Antrenare locală (procedura FedAvg client):**
- Se declanșează automat după **15 interacțiuni** acumulate în buffer
- **5 epoci SGD** (lr = 0,01) cu gradient clipping la normă L2 = 1 — previne divergența
- Buffer persistat în SharedPreferences — supraviețuiește dacă app-ul e închis înainte de rundă
- Dispozitivul trimite **doar delta ponderilor** față de modelul global, nu interacțiunile brute

---

## SLIDE 7 — Agregare asincronă, concurență și confidențialitate

**FedAsync — discount de vechime (Xie et al. 2019):**
- Fiecare actualizare e procesată individual când sosește, fără a aștepta o cohortă
- Delta e ponderată cu $\frac{1}{1+s}$, unde $s$ = runde scurse de la ultima sincronizare a clientului
- Clienți cu model vechi (stale) contribuie mai puțin → convergență mai rapidă și stabilă

**Redis lock — controlul concurenței:**
- Ciclul read–aggregate–write nu e atomic implicit: doi clienți simultani ar putea suprascrie reciproc agregarea
- `SET NX PX` scrie un token unic sub cheia `fl:agg_lock` doar dacă nu există — un singur client intră în agregare la un moment dat
- Eliberare printr-un script Lua atomic; TTL = 5 s previne blocaje la crash de server

**Differential Privacy — confidențialitate pe dispozitiv (NbAFL):**
- **Pe client:** clipping delta coordonată cu coordonată la $[-1, +1]$ → sensibilitate mărginită → zgomot Gaussian $\mathcal{N}(0,\ 0{,}01)$ pe fiecare coordonată → serverul nu poate reconstitui interacțiunile (membership inference)
- **Pe server:** clipping normă L2 ≤ 1 a deltei primite → protecție împotriva actualizărilor adversariale (poisoning)
- $\sigma = 0{,}1$ ales ca echilibru utilitate–confidențialitate; confirmat de simulare: −30,9% BCE rămâne valabil cu DP activ

---

## SLIDE 8 — Modelul de personalizare

**MLP 22 → 32 → 16 → 1** · 1 281 parametri · inferență ≈ 39 µs pe dispozitiv

Vectorul de 22 dimensiuni:

| Grup | Dimensiuni | Ce codifică |
|---|---|---|
| Interese utilizator | [0–5] | one-hot: art, architecture, history, gastronomy, nature, music |
| Tip obiectiv | [6–13] | one-hot: museum, monument, park, gallery, restaurant, square, building, other |
| Context temporal | [14–16] | isOpen, isWeekend, ora/24 |
| Context spațial/rută | [17–21] | distanță relativă, potrivire interese–obiectiv, poziție în rută |

Scorul MLP → categorie de potrivire afișată în popup:
**scăzut** (< 0,4) · **mediu** · **ridicat** (≥ 0,7)

*Același model rulează atât pe server (scorare candidați pentru rută) cât și pe dispozitiv (scor popup în timp real)*

---

## SLIDE 9 — Generarea rutelor personalizate

**Screenshot:** `pics/route-generation.png`

**Algoritmul (rulează pe server):**
1. Candidați: toate obiectivele din **raza 10 km** față de poziție
2. Scoring inițial: **80% scor MLP + 20% proximitate** (top 10 candidați); fallback pe potrivire categorii–interese dacă modelul FL nu e în Redis
3. Construire traseu **greedy nearest-neighbour** cu tiebreaker configurat de utilizator (slider 0–1000 m): $\min(\text{dist} - \text{tiebreaker} \times \text{interest\_match})$ — un obiectiv mai relevant poate fi ales față de unul mai apropiat
4. Durata fiecărei opriri: timp de bază per tip (15–70 min) scalat ±25% de scorul MLP
5. Ruta reală calculată prin **OSRM** (walking sau driving)

*Buget implicit: 300 minute · maxim 5 opriri · trasee diferite pentru utilizatori cu interese diferite, chiar din același punct de start*

---

## SLIDE 10 — Pre-antrenarea modelului global

**Problema cold-start:** utilizatorul nou descarcă modelul global — fără nicio rundă FL acumulată, modelul trebuie să ofere recomandări utile de la prima utilizare, bazate pe interesele din profil

**Soluție:** model global pre-antrenat pe date publice, încărcat în Redis înainte de prima rundă FL reală

| Etapă | Date | Interval predicții |
|---|---|---|
| Pre-antrenare | 741 618 înregistrări (Foursquare, Yelp, 3 seturi check-in) | [0,595 ; 0,850] — **blocat la medie** |
| Fine-tuning | + 16 000 exemple sintetice (isOpen=0) + suprareprezentare 3× scoruri ≤ 0,4 | [0,050 ; 0,841] — **+211%** |

Fără fine-tuning modelul prezice 0,70–0,75 indiferent de input — datele reale nu conțin niciun caz cu isOpen=0 (nimeni nu interacționează cu un loc închis), deci modelul nu învăța acea dimensiune

**Imagine:** `pics/charts/finetune_results.png`

---

## SLIDE 11 — Evaluare

**1. Corectitudine funcțională** — demo parcurge FR-1 → FR-7:
harta cu obiective în 1500 m · rute diferite per utilizator · quest activat sub 100 m · recenzii moderate · FL local fără date brute pe server · funcționare offline din cache

**2. Performanța FL** — simulare 10 000 clienți sintetici · 600 runde · distribuție staleness: 80% fresh (0–2 runde), 20% stale (15–30 runde)

| | FedAsync | Fără discount |
|---|---|---|
| Pierdere BCE inițială | 0,695 | 0,695 |
| Pierdere BCE finală | **0,480** | 0,506 |
| Reducere | **−30,9%** | −27,2% |
| Pondere efectivă medie (clienți stale) | **0,489** | 1,000 |

Probe scores după 600 runde: gastronomy→restaurant **0,715** ↑ · gastronomy→parc **0,370** ↓ · history→muzeu **0,878** ↑

**3. Scalabilitate backend (load test agregare FL asincronă):**

| Cereri simultane | Succes | Erori | Latență medie | Latență p95 |
|---|---|---|---|---|
| 5 | 5 | 0 | 622,6 ms | 923,5 ms |
| 10 | 10 | 0 | 1 384 ms | 2 442 ms |
| 20 | 12 | **8** | 2 065 ms | 3 076 ms |

0 erori la ≤ 10 cereri simultane (NFR-4 îndeplinit); degradare la 20 din cauza TTL-ului Redis lock de 5 s

**Imagini:** `backend/federated/results/fedasync_effect.png` · `backend/federated/results/probe_scores.png`

---

## SLIDE 12 — Limitări

- **Validare pe clienți sintetici** — comportamentul în producție rămâne neverificat pe date reale de la utilizatori
- **Proximitate exclusiv în foreground** — stream-ul GPS Geolocator se oprește când app-ul e în background; geofencing nativ OS (Region Monitoring / Geofence API) ar rezolva
- **Scalabilitate Redis lock** — la 20 cereri FL simultane, 8/20 respinse; soluție: coadă de lucru (Redis Queue / Celery) elimină lock-ul din calea cererilor HTTP
- **SecAgg și FedPer excluse** — SecAgg presupune coordonare sincronă între clienți incompatibilă cu FL-ul asincron; FedPer necesită straturi locale per utilizator — lăsate ca direcții viitoare

---

## SLIDE 13 — Concluzii

**Ce am construit:**
- Aplicație Flutter end-to-end: hartă, quests, trasee, gamification, comunitate, moderare conținut
- Flux FL complet: pre-antrenare → fine-tuning → antrenare locală → agregare asincronă FedAsync → DP NbAFL

**Ce am obținut:**
- Personalizare on-device fără date brute pe server — **privacy by design** validat
- Reducere pierdere BCE cu **−30,9%** (FedAsync vs. −27,2% fără discount de vechime)
- Interval predicții mărit cu **+211%** prin fine-tuning (de la [0,595; 0,850] la [0,050; 0,841])
- Inferență **≈ 39 µs** per obiectiv — personalizare continuă fără impact perceptibil pe UX
- Scalabilitate confirmată la **≤ 10 cereri FL simultane** fără erori (NFR-4)

**Ce urmează:**
- Colectare interacțiuni FL de la utilizatori reali — validare în producție
- Personalizare mai fină: straturi locale per utilizator (FedPer) — niciodată trimise la server
- Agregare cu buffer (FedBuff) — variantă de mijloc dacă baza de utilizatori crește
- Proximitate în background — notificări chiar cu app-ul închis (Region Monitoring / Geofence API)

**Keywords:**
`Federated Learning` · `FedAsync` · `Differential Privacy` · `NbAFL` · `Route Generation` · `Privacy by Design` · `OSRM` · `MLP` · `Gamification`

---
---
---

# BACKUP — Slide-uri pentru Q&A

*Nu se prezintă în flux normal — se afișează doar la întrebări din comisie*

---

## B1 — Taxonomia FL și pozitionarea CultureQuest

**Axa tip de FL** (Yang et al. 2019):
- **HFL** (Orizontal): același spațiu de caracteristici, exemple diferite ← *CultureQuest*
- VFL (Vertical): caracteristici diferite, exemple comune
- FTL (Transfer): fără suprapunere semnificativă

**Axa mod de desfășurare** (Kairouz et al. 2021):
- **Cross-device**: număr mare de dispozitive, conexiuni intermitente, date puține per client ← *CultureQuest*
- Cross-silo: organizații, conexiuni stabile, seturi mari

**Consecința pentru design:**
- Cross-device asincron → nu se poate aștepta o cohortă completă → FedAsync
- Dispozitive cu conexiuni nesigure → actualizări cu staleness mare → discount $1/(1+s)$

---

## B2 — De ce FedAsync și nu FedProx / SCAFFOLD / FedDyn?

**Problema comună la FedProx, SCAFFOLD, FedDyn:**
- Toate trei leagă actualizarea unui client de comportamentul *cohortei* din aceeași rundă (termen proximal / variabilă de control / regularizator dinamic)
- Toate trei presupun runde **sincrone** cu ≥ K clienți

**În CultureQuest:**
- Agregarea e **asincronă**: câte o actualizare pe rând, pe măsură ce sosește
- Nu există cohortă → nu există medie a grupului față de care să se calculeze termenul de corecție
- Aplicat fără cohortă → tragere spre un punct de referință arbitrar; garanțiile de convergență din literatură **nu mai sunt valabile**

**Soluția adoptată:** FedAsync — procesează fiecare actualizare individual, cu discount $1/(1+s)$ pentru a reduce influența celor cu model local vechi

---

## B3 — Differential Privacy în detaliu

**Ce se trimite la server:** nu delta curată, ci delta cu zgomot aplicat pe dispozitiv (NbAFL)

**Pașii pe client:**
1. Clipping per coordonată: $\delta$ limitat la $[-\tau, \tau]$ cu $\tau = 1$ — sensibilitate mărginită
2. Suprapunere zgomot: $\tilde{w} = w_{\text{global}} + \text{clip}(\delta, \tau) + \mathcal{N}(0, (\sigma \cdot \tau)^2)$ cu $\sigma = 0{,}1$

**Pe server (al doilea nivel):**
- Clipping normă L2 a deltei: dacă $\|\delta\|_2 > 1$ → rescalare proporțională
- Protecție împotriva actualizărilor adversariale (poisoning)

**De ce clipping înainte de zgomot:** fără clipping, un delta arbitrar de mare (ex: 1000) ar face zgomotul de 0,1 invizibil — sensibilitatea trebuie mărginită ca zgomotul fix să aibă efect real

**Protejează împotriva:** membership inference attacks (serverul nu poate reconstitui interacțiunile din delta zgomotoasă)

---

## B4 — Algoritmul de generare a rutei (detalii)

**Etapa 1 — Scoring inițial candidați (top 10):**
- Scor FL (80%) + distanță față de start normalizată (20%)
- Dacă modelul FL nu e disponibil în Redis: potrivire categorii–interese (fallback)

**Etapa 2 — Construire traseu greedy:**
```
poziție curentă = locație utilizator
cât timp există candidați și buget de timp disponibil:
    alege obiectivul cu distanță minimă - (tiebreaker_m × potrivire_interese)
    durata = timp_baza_tip × (0.75 + 0.5 × scor_FL)  # scalat ±25%
    dacă depășește bugetul → oprire
    adaugă la traseu
```

**Etapa 3 — Ruta reală:** OSRM (walking sau driving) calculat din coordonatele opririlor

**Buget implicit:** 300 minute · cel mult 5 opriri

---

## B5 — Cold-start: ce vede un utilizator nou?

**Fără runde FL acumulate**, scorul MLP vine din modelul global pre-antrenat + fine-tuned (descărcat din Redis la prima autentificare)

**Fluxul cold-start:**
1. Utilizator nou → descarcă modelul global pre-antrenat + fine-tuned din Redis
2. Scorul inițial reflectă interesele setate în profil (one-hot în vectorul de 22 dimensiuni) + tipul obiectivului
3. După **15 interacțiuni** → prima rundă FL locală → modelul se personalizează

**De ce e suficient:**
- Fine-tuning-ul a extins intervalul de predicție la [0,05; 0,84]: modelul discriminează de la start obiectivele potrivite de cele nepotrivite pentru profilul de interese, fără să fi văzut nicio rundă FL reală

---

## B6 — Sursele de date pentru pre-antrenare

**741 618 înregistrări din 5 surse:**
- Foursquare TSMC2014 (NYC + Tokyo), TIST2015 (global), ubicomp2013 (NYC restaurante) — check-in-uri reale, label = 0,70 (+ bonus repetare)
- Yelp — recenzii cu stele, label = stele/5 — singura sursă cu rating explicit
- Exemple sintetice cu `isOpen=0` (16 000) — absente în datele reale (niciun utilizator nu interacționează cu un loc închis)
- Suprareprezentare 3× a înregistrărilor cu etichetă ≤ 0,4 — corectează regresia modelului spre medie (Yelp are 60% recenzii de 4–5 stele)

**Problema inițială:** fără fine-tuning, modelul prezice 0,70–0,75 indiferent de input; intervalul de predicție era [0,595; 0,850] — nu putea distinge obiectivele potrivite de cele nepotrivite

| Metrică | Înainte fine-tuning | După fine-tuning |
|---|---|---|
| MSE validare | 0,0233 | 0,0269 |
| Interval predicții | 0,255 | **0,792** (+211%) |
| Predicție minimă | 0,595 | **0,050** |

---

## B7 — Scalabilitate: testul de concurență FL (detalii)

**Redis lock** (`SET NX PX`): serializează ciclul read–aggregate–write, câte un client la un moment dat

| Cereri simultane | Succes | Erori | Latență medie | Latență p95 |
|---|---|---|---|---|
| 1 | 1 | 0 | 6,5 ms | 6,5 ms |
| 5 | 5 | 0 | 622,6 ms | 923,5 ms |
| 10 | 10 | 0 | 1 384 ms | 2 442 ms |
| 20 | 12 | **8** | 2 065 ms | 3 076 ms |

**De ce apar erori la 20:** lock-ul TTL = 5 s; la 20 cereri, unele depășesc fereastra de 2,7 s de reîncercare (9 reîncercări × 0,3 s). Nu există corupere de date — lock-ul garantează că ciclul read–aggregate–write rămâne sincronizat chiar și la timeout

**Soluție identificată:** coadă de lucru (Redis Queue / Celery) — actualizările se procesează asincron, fără concurență pe lock-ul de agregare

**Buget implicit:** 300 minute (jumătate de zi turistică); cel mult 5 opriri

---

## B8 — Consum de baterie și proximitate în foreground

**Cum funcționează `ProximityService`:**
- **Event-driven**, nu polling — `Geolocator.getPositionStream(distanceFilter: 10)` se declanșează doar când utilizatorul se mișcă ≥ 10 m
- La fiecare update: calculează distanța față de toate obiectivele din raza 1 500 m, detectează intrarea / ieșirea din raza de 100 m
- Relistează obiectivele din apropiere la fiecare ≥ 200 m față de ultimul punct de fetch

**Limitare actuală:**
- Activ **exclusiv în foreground** — dacă app-ul e în background sau ecranul e blocat, stream-ul Geolocator nu mai primește update-uri GPS

**Ce ar rezolva:**
- Region Monitoring (iOS CoreLocation) / Geofence API (Android) — OS-ul monitorizează granițele și notifică app-ul chiar și când e închis, fără a ține GPS-ul activ în permanență
