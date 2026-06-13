# Structură

## Capitolul 1 - Introducere
*Resurse:* fără figuri/tabele/cod dedicate - capitol narativ, scris ultimul
(vezi Ordinea capitolelor din `thesis_writing_conventions.md`). Opțional, ca
preview reluat (nu recreat): la 1.4, o variantă simplificată a diagramei de
arhitectură din 4.1; la 1.5, un grafic din 6.2.2 (ex. `loss_curve.png`).

- **1.1 Context** - apariția aplicațiilor mobile bazate pe locație pentru
  turism/descoperire culturală; preocupări legate de confidențialitate
  privind ML centralizat pe date comportamentale personale; învățarea
  federată (FL, Federated Learning) ca alternativă.
- **1.2 Definirea problemei** - aplicațiile generice de tip city-guide oferă
  aceleași obiective turistice și rute tuturor utilizatorilor; personalizarea
  presupune, de regulă, încărcarea istoricului brut de interacțiuni pe un
  server.
- **1.3 Obiective** - (a) aplicație mobilă pentru descoperirea obiectivelor
  culturale prin explorare bazată pe proximitate și quest-uri gamificate, (b)
  personalizarea recomandărilor de obiective/rute per utilizator fără ca
  datele brute să părăsească dispozitivul, (c) implementarea pipeline-ului FL
  complet (pre-antrenare -> fine-tuning -> FedAvg pe dispozitiv -> agregare
  asincronă cu garanții de confidențialitate).
- **1.4 Soluția propusă** (la nivel general) - o aplicație mobilă Flutter
  pentru descoperirea obiectivelor culturale bazată pe proximitate, cu
  generare de rute și quest-uri gamificate; personalizarea este realizată
  printr-un model mic, rulat pe dispozitiv: un perceptron multi-strat
  (MLP, Multi-Layer Perceptron) cu arhitectura 22->32->16->1, antrenat prin
  FL, cu păstrarea confidențialității (backend FastAPI/MongoDB/Redis).
- **1.5 Rezultatele obținute** (la nivel general) - aplicație funcțională cu
  hartă/rute/quest-uri; model global pre-antrenat și ajustat fin
  (fine-tuned); simulare a reducerii în funcție de vechime (staleness
  discount) din FedAsync pe parcursul a 600 de runde.
- **1.6 Structura lucrării** - rezumat de 1-2 propoziții pentru fiecare
  capitol de mai jos.

## Capitolul 2 - Analiza Cerințelor
- **2.1 Utilizatori țintă și cazuri de utilizare** - turist/localnic care
  explorează un oraș și dorește sugestii personalizate de obiective, rute și
  stimulente gamificate (quest-uri).
- **2.2 Cerințe funcționale** - hartă cu obiective din apropiere, generare de
  rute, sistem de quest-uri, evaluări/recenzii, profil + sincronizare FL,
  controale de confidențialitate, rol de administrator pentru moderarea și
  aprobarea conținutului generat de utilizatori (obiective, povești,
  quest-uri, recenzii semnalate).
  - *Resurse:* Tabel cu cerințele funcționale (FR-1, FR-2, ... + descriere +
    secțiunea de proiectare/implementare/evaluare unde sunt tratate - leagă
    spre 4.x/5.x și spre demonstrația din 6.1).
- **2.3 Cerințe non-funcționale** - confidențialitate pe dispozitiv (nicio
  dată brută nu părăsește telefonul), reziliență offline (obiective stocate
  în cache), cost redus de antrenare pe dispozitiv (MLP mic), scalabilitatea
  backend-ului pentru încărcări asincrone ale clienților, gestionarea
  pornirii la rece (cold-start) (utilizatorii noi și obiectivele noi trebuie
  să primească recomandări utile din modelul global pre-antrenat și din
  caracteristicile bazate pe conținut, înainte ca personalizarea locală prin
  FL să fi avut loc).
  - *Resurse:* Tabel similar (NFR-1, NFR-2, ...), în aceeași formă ca cel de
    la 2.2.
- **2.4 Domeniul de aplicare al proiectului** - ce este acoperit vs. ce nu
  intră în domeniul de aplicare (de ex., un "personal head" per utilizator,
  listat ca lucrare viitoare).
  - *Resurse:* opțional, tabel scurt pe două coloane "Inclus / Exclus din
    domeniul de aplicare".

## Capitolul 3 - Soluții Existente
- **3.1 Aplicații existente pentru explorare urbană** - Google Maps,
  TripAdvisor, aplicații de tip city-guide; modul în care acestea
  personalizează (sau nu) și modelul lor de colectare a datelor.
  - *Resurse:* Tabel comparativ Google Maps / TripAdvisor / city-guide generic
    / CultureQuest, pe coloane: personalizare, model de colectare a datelor,
    ML on-device, gamificare. Sursele pentru rândurile altor aplicații sunt
    notele de subsol din `footnotesRO.md` (3.1).
- **3.2 Analiză comparativă între abordările centralizate și învățarea
  federată (FL, *Federated Learning*) pentru recomandări** - filtrare
  colaborativă/bazată pe conținut cu date stocate pe server vs. FL;
  compromisuri legate de confidențialitate.
  - *Resurse:* Tabel comparativ recomandare centralizată vs. FL, pe coloane:
    locația datelor, confidențialitate, gestionarea pornirii la rece
    (cold-start), cost de comunicare.
- **3.3 FL: Stadiul actual** - taxonomia FL (Federated Learning Orizontal,
  Vertical și Federated Transfer Learning - FL cu transfer -, respectiv
  Cross-Device - la nivel de dispozitive individuale - versus Cross-Silo - la
  nivel de organizații) folosită pentru a poziționa CultureQuest ca **FL
  orizontal, de tip cross-device**; FedAvg, FL asincron, robustețe și
  confidențialitate (vezi Bibliografia de mai jos pentru articolele de tip
  survey care susțin această secțiune).
  - *Resurse:* Figură - diagramă a taxonomiei HFL/VFL/FTL + cross-device vs.
    cross-silo, adaptată din Yang et al. 2019 și/sau Kairouz et al. 2021 (nu
    e un grafic din repo, se redesenează); caption "Adaptat din [N]" conform
    `footnotesRO.md` (3.3) - cu CultureQuest evidențiat în poziția HFL
    cross-device.
- **3.4 Alternative respinse** - FedProx, SCAFFOLD, FedDyn: de ce termenii lor
  de corecție a derivei (drift) între clienți presupun runde sincrone cu mai
  mulți clienți, ceea ce nu se aplică design-ului asincron al CultureQuest, cu
  un singur client per rundă.
  - *Resurse:* Tabel comparativ FedAvg / FedProx / SCAFFOLD / FedDyn /
    CultureQuest (FedAvg async + staleness discount), pe coloane: necesită
    runde sincrone?, mecanism de corecție a derivei, compatibil cu un singur
    client per rundă?. Acest tabel se poate relua/extinde în 6.4 cu o coloană
    de evaluare.
- **3.5 Tehnologiile utilizate și justificarea acestora**
  - 3.5.1 Flutter și Riverpod (vs. React Native/nativ)
    - *Resurse:* opțional, tabel comparativ scurt Flutter+Riverpod vs. React
      Native (cod unic cross-platform, hot reload, gestionarea stării) - dacă
      diferențele nu justifică un tabel, rămâne text.
  - 3.5.2 FastAPI, MongoDB și Redis (vs. alternative)
    - *Resurse:* opțional, tabel comparativ scurt similar cu 3.5.1 (ex. vs.
      Django/PostgreSQL) - doar dacă justifică o decizie clară.
  - 3.5.3 Motorul de Rutare OSRM (*Open Source Routing Machine*)
    - *Resurse:* fără figură/tabel dedicat - notă de subsol pentru
      documentația OSRM (`footnotesRO.md`).
  - 3.5.4 Perceptron multi-strat (MLP, *Multi-Layer Perceptron*) - propriu
    vs. TFLite/PyTorch Mobile (dimensiunea modelului, fără dependență de
    runtime)
    - *Resurse:* Tabel comparativ MLP propriu vs. TFLite vs. PyTorch Mobile,
      pe coloane: dimensiune model, dependențe de runtime, compatibilitate
      cross-platform (Flutter) - tabel decizional, justifică direct alegerea
      implementării proprii.

## Capitolul 4 - Soluția Propusă
*Resurse generale:* acesta e capitolul de proiectare - diagrame, tabele și
ecuații care justifică deciziile; fără listinguri de cod (codul efectiv merge
în Capitolul 5).

- **4.1 Prezentare generală a sistemului** - diagramă de arhitectură: client
  mobil <-> backend FastAPI <-> MongoDB (date persistente) + Redis (stare FL).
  - *Resurse:* Figura centrală a tezei - diagramă nouă (de desenat, ex.
    draw.io/Mermaid, exportată ca PDF/SVG vectorial), cu cele 3-4 componente
    (mobil, FastAPI, MongoDB, Redis) și săgețile numerotate pentru fluxurile
    principale (cerere hartă/rute, sincronizare FL, moderare conținut).
- **4.2 Arhitectura aplicației mobile** - structură Flutter organizată pe
  feature-uri (hartă, profil, federated etc.), management de stare cu
  Riverpod.
  - *Resurse:* Figură nouă - diagramă cu cutii per feature (map, profile,
    federated, quest, auth, onboarding) și un strat comun Riverpod
    dedesubt/deasupra; simplă, nu necesită mai mult de o jumătate de pagină.
- **4.3 Arhitectura serviciilor *backend*** - servicii/rute FastAPI, modelul
  de date (obiective, utilizatori, quest-uri, rute, evenimente); pas de
  moderare a conținutului generat de utilizatori (comentarii, povești)
  înainte de publicare (detalii tehnice în 5.2.3).
  - *Resurse:* Figură - diagramă ER simplificată/la nivel înalt, derivată din
    `db.svg` (doar entitățile principale - USERS, LANDMARKS, QUESTS, ROUTES,
    EVENTS, COMMENTS, STORIES, VISITS - și relațiile cheie, fără toate
    câmpurile; `db.svg` e prea dens pentru text). Opțional, tabel cu
    colecțiile principale + câmpurile cheie (din `backend/app/models/*.py`:
    `user.py`, `landmark.py`, `quest.py`, `route.py`, `event.py`). *Versiunea
    completă a `db.svg` (toate câmpurile) merge în Anexe.*
- **4.4 Proiectarea sistemului FL**
  - 4.4.1 Arhitectura modelului (MLP 22 -> 32 -> 16 -> 1, ieșire sigmoid,
    detalierea vectorului de caracteristici)
    - *Resurse:* Figură - diagramă a arhitecturii MLP (straturi 22->32->16->1,
      activare, ieșire sigmoid). Tabel - cele 22 de caracteristici de intrare,
      grupate pe categorii (sursă: blocul de comentarii deja existent în
      `backend/app/federated/model.py:4-29`, de transformat în tabel).
  - 4.4.2 Antrenarea locală (procedura client FedAvg: 5 epoci locale, coborâre
    pe gradient stocastică - Stochastic Gradient Descent, SGD)
    - *Resurse:* Ecuația actualizării SGD (fără listing - implementarea
      efectivă e cod, vezi 5.1.1).
  - 4.4.3 Agregare asincronă și reducerea în funcție de vechime (FedAsync:
    `n_effective = n_samples/(1+staleness)`)
    - *Resurse:* Ecuația factorului de reducere în funcție de vechime
      (`1/(1+staleness)`) + Figură - grafic nou, mic, al acestei funcții,
      pentru a justifica vizual formula.
  - 4.4.4 Agregare cu limitare (*Gradient Clipping*) (limitarea normei
    delta-ului împotriva actualizărilor adversariale/extreme)
    - *Resurse:* Ecuația limitării normei L2; opțional o schiță "înainte/după
      clipping" pentru un vector de actualizare. Fără listing aici (codul
      `clipped_fedavg` -> 5.2.1).
  - 4.4.5 Confidențialitate diferențială (DP, *Differential Privacy*) (zgomot
    Gaussian adăugat pe delta-urile ponderilor)
    - *Resurse:* Ecuația mecanismului NbAFL (zgomot Gaussian calibrat pe
      delta). Fără listing aici (codul `_addDPNoise` -> 5.1.2); poate
      reutiliza un fragment din diagrama de la 4.8.
  - 4.4.6 Controlul concurenței (lock de agregare în Redis)
    - *Resurse:* Figură - diagramă de secvență cu doi clienți concurenți și
      lock-ul Redis, **săgeți numerotate** (1-4: cerere lock, acordare,
      agregare, eliberare) pentru a justifica ordinea.
- **4.5 Fluxul de generare a rutelor** - filtrare cu scor FL x 0.8 +
  proximitate x 0.2, criteriu de departajare pe baza potrivirii intereselor,
  durată de vizitare (dwell time) scalată în funcție de scorul FL.
  - *Resurse:* Figură - diagramă de flux cu **săgeți numerotate** (1: filtrare
    candidați, 2: scor FL x0.8 + proximitate x0.2, 3: departajare după
    interese, 4: scalare dwell time, 5: rută finală). Notă: blend-ul de scor
    (`_initial_score`) e implementat în backend
    (`backend/app/services/route_service.py`), nu în mobil - 5.1.5 ar trebui
    să trimită către acest fișier, nu la un echivalent Dart.
- **4.6 Proiectarea elementelor de gamificare** - sistemul de quest-uri și
  etichetele de engagement (deschiderea fișei obiectivului, începerea
  navigării, finalizarea quest-ului, evaluări); quest-urile trimise de
  utilizatori obișnuiți rămân în starea "pending" până la aprobarea unui
  administrator, în timp ce cele create de administrator sau de creatorul
  obiectivului devin active imediat.
  - *Resurse:* Figură - diagramă de stări pentru un quest (pending ->
    approved/rejected -> active -> completed), cu **tranziții numerotate**
    care separă traseul "trimis de utilizator -> aprobat de admin" de traseul
    "creat de admin/de autorul obiectivului -> activ direct". Tabel - etichetele
    de engagement (sursă: `mobile/lib/features/federated/providers/
    fl_provider.dart:12-18` - sheetOpened=0.3, questAttempted=0.5,
    questCompleted=0.9, plus eticheta din evaluări).
- **4.7 Hartă și navigare** - geofencing, rotirea hărții pe baza
  busolei/GPS-ului.
  - *Resurse:* opțional, schiță mică a zonelor de geofencing (cercuri
    concentrice enter/exit) - altfel, se poate baza doar pe captura de ecran
    din 5.1.6.
- **4.8 Arhitectura de confidențialitate** - ce rămâne pe dispozitiv vs. ce
  este încărcat pe server; diagramă a fluxului de date.
  - *Resurse:* Figură - diagramă flux de date (dispozitiv vs. server) cu
    **săgeți numerotate** pentru pașii de confidențialitate (1: date brute
    rămân local, 2: se extrag caracteristici, 3: antrenare locală, 4: clipping
    + zgomot DP, 5: trimitere delta). Tabel - date locale / date pe server /
    date niciodată stocate (sursă: structura deja existentă a
    `mobile/lib/features/profile/screens/privacy_screen.dart:58-184`, direct
    mapabilă pe 3 coloane).

## Capitolul 5 - Detalii de Implementare
*Resurse generale:* capitolul de "cum" - aici intră listingurile de cod, dar
selectiv (cf. `thesis_writing_conventions.md`, ## Listări de cod): un listing
justifică o decizie, nu explică cod de dragul explicației. Total propus: 5
listinguri principale în tot capitolul (5.1.1, 5.1.2, 5.2.1, 5.2.3, 5.4) -
restul fragmentelor rămân referințe `fișier:linii` sau merg în Anexe.

- **5.1 Implementarea aplicației mobile** (subsecțiunile orientate spre
  interfață includ o captură de ecran reprezentativă din aplicație)
  - 5.1.1 Serviciul client FL - forward pass + backpropagation manuală în
    Dart, limitare (clipping)
    - *Resurse:* **Listing 1** - `mobile/lib/features/federated/services/
      fl_client_service.dart` (forward pass ~243-249 + backprop/clipping
      ~251-281; selectează ~25-30 linii din 251-281). Justifică decizia de
      implementare manuală în Dart (fără framework ML) și limitarea
      gradientului. *Varianta completă a `_trainLocally` (227-291, 65 linii)
      -> Anexe.*
  - 5.1.2 Adăugarea de zgomot pentru asigurarea DP (zgomot Gaussian generat
    prin transformata Box-Muller)
    - *Resurse:* **Listing 2** - `_addDPNoise`,
      `fl_client_service.dart:327-344` (~18 linii, încadrare perfectă în
      15-30). Justifică decizia de Local-DP client-side (serverul nu vede
      niciodată o actualizare curată). Transformata Box-Muller
      (`_gaussian`, 347-352) - notă de subsol, conform `footnotesRO.md`
      (5.1.2).
  - 5.1.3 Bufferul local de interacțiuni și persistența datelor (cache
    bazat pe SharedPreferences, persistă la închiderea aplicației)
    - *Resurse:* Captură de ecran - ecranul de profil, secțiunea de status FL
      (`mobile/lib/features/profile/screens/profile_screen.dart:169-211`),
      arată contorul de interacțiuni în buffer. Fără listing pentru
      getter/saver/clearer (`local_data_service.dart:129-138`) - simple
      operații CRUD, nu justifică o decizie dedicată; referință
      `fișier:linii` în text e suficientă.
  - 5.1.4 Stocarea temporară a obiectivelor pentru funcționarea offline
    - *Resurse:* fără figură/captură dedicată - poate reutiliza captura de la
      5.1.5/5.1.6 (harta cu obiective încărcate din cache).
  - 5.1.5 Algoritmul de generare a rutelor - filtrarea candidaților (scor FL x
    0.8 + proximitate x 0.2), criteriu de departajare pe baza potrivirii
    intereselor, durată de vizitare per oprire scalată în funcție de scorul FL
    - *Resurse:* Captură de ecran - fereastra de generare a rutei
      (`map_screen.dart`, sheet ~1247-1308) și ruta rezultată pe hartă. Notă:
      blend-ul FL x0.8 + proximitate x0.2 (`_initial_score`) e implementat în
      `backend/app/services/route_service.py` (~110-115), nu în acest fișier
      mobil - secțiunea ar trebui să trimită spre 4.5/5.2 pentru algoritm și
      să se limiteze aici la integrarea UI.
  - 5.1.6 Sistemul de misiuni și tehnologia de *geofencing* - detectarea
    finalizării quest-urilor, declanșatoare de geofencing, înregistrarea
    etichetelor de engagement
    - *Resurse:* Captură de ecran - harta cu sheet-ul de proximitate/quest
      declanșat. Referință `fișier:linii` (fără listing principal, pentru a
      păstra numărul total mic) -
      `mobile/lib/features/proximity/services/proximity_service.dart:44-56`
      (logica ENTER/EXIT); fișierul complet (66 linii) e candidat opțional de
      listing în Anexe dacă se dorește un al 6-lea exemplu.
- **5.2 Implementarea serviciilor *backend***
  - 5.2.1 Serviciul de agregare (`fedavg`, `clipped_fedavg`, reducerea în
    funcție de vechime, lock Redis)
    - *Resurse:* **Listing 3** - `clipped_fedavg`,
      `backend/app/federated/model.py:72-100` (~29 linii). Justifică decizia
      de limitare a actualizărilor agregate. Formula de reducere în funcție
      de vechime (`fl_service.py:75-77`) apare deja ca ecuație în 4.4.3 - nu
      se repetă ca listing separat aici.
  - 5.2.2 Punctele de acces API (preluare/actualizare model, status)
    - *Resurse:* Tabel - cele 4 endpoint-uri FL
      (`backend/app/api/routes/federated.py:9-41`): `GET /model/global`,
      `POST /model/update`, `POST /admin/initialize`, `GET /model/status`
      (metodă, path, scop, autorizare). Un tabel extins cu toate
      endpoint-urile REST (landmarks/quests/comments/routes) -> Anexe, dacă
      e necesar.
  - 5.2.3 Sistemul de recenzii și moderarea conținutului - endpoint-uri de
    comentarii/evaluări pe obiective (agregarea `rating_sum`/`rating_count`);
    moderare prin OpenAI Moderation API, cu fallback local pe o listă de
    cuvinte interzise când API-ul nu este disponibil; coadă de revizuire
    pentru administratori - obiective, povești și quest-uri trimise de
    utilizatori rămân în starea "pending" până la aprobare/respingere, iar
    comentariile semnalate de moderarea AI ajung într-o listă separată pentru
    revizuire manuală (aprobare sau ștergere)
    - *Resurse:* **Listing 4** - `_moderate`,
      `backend/app/services/comment_service.py:34-72` (~39 linii - de
      restrâns la ~25-30 pentru limita din convenții). Justifică decizia
      "OpenAI Moderation API + fallback local pe listă de cuvinte interzise".
      Agregarea `rating_sum`/`rating_count` (`landmark_service.py:108-134`) -
      ecuație/formulă scurtă în text, nu listing separat.
- **5.3 Fluxul etapei de pre-antrenare** - pregătirea seturilor de date
  (Foursquare TSMC2014/TIST2015, ubicomp2013, Yelp, date sintetice;
  construcția etichetelor); antrenarea de la zero (MLP, SGD, scăderea ratei de
  învățare); fine-tuning (augmentare de date pentru semnal slab de etichetare,
  modificări de hiperparametri, corectarea regresiei către medie).
  - *Resurse:* Figuri existente din `backend/pretraining/output/charts/` (NU
    din `pics/`): `dataset_overview.png` (prezentare seturi de date),
    `label_by_type.png` (distribuția etichetelor), `train_val_split.png`
    (split train/val) - figuri de pipeline/date, una sau toate trei, în
    funcție de spațiu (restul -> Anexe). Fără listing pentru
    `prepare_data.py`/`pretrain.py`/`finetune.py` (fișiere lungi, generice) -
    opțional, un fragment scurt de augmentare (`finetune.py:308-318`, ~11
    linii, posibil extins la ~20) doar dacă se dorește un 6-lea listing.
- **5.4 Framework-ul pentru simularea procesului FL** - simulare sintetică pe
  mai multe runde, comparând reducerea în funcție de vechime din FedAsync
  activată vs. dezactivată, modelarea derivei conceptuale (concept drift)
  pentru clienții cu date vechi (stale).
  - *Resurse:* **Listing 5** - comutatorul FedAsync + modelarea derivei
    conceptuale, `backend/federated/simulate_fl.py` (~20 linii în jurul
    220-240). Justifică design-ul experimental (cum sunt simulați clienții
    "stale"/cu derivă). Tabel - parametrii simulării
    (`simulate_fl.py:36-52`: N_CLIENTS=10000, N_ROUNDS=600,
    INTERACTIONS_PER_ROUND=15, LEARNING_RATE=0.01, LOCAL_EPOCHS=5,
    DP_SIGMA=0.1, DP_CLIP_NORM=1.0, SERVER_MAX_NORM=1.0, FRESH_PROB=0.80,
    FRESH_STALENESS=(0,2), STALE_STALENESS=(15,30),
    STALE_LABEL_FLIP_RATE=0.70).
- **5.5 Dificultăți întâmpinate în procesul de implementare** - problema
  regresiei către medie din pre-antrenare și modul în care fine-tuning-ul a
  rezolvat-o; ajustarea reducerii în funcție de vechime.
  - *Resurse:* fără figură/tabel nou - se poate referi tabelul
    înainte/după fine-tuning din 6.2.1 ca dovadă a rezolvării regresiei către
    medie.

## Capitolul 6 - Evaluare
- **6.1 Corectitudinea funcțională** - funcționalitățile aplicației se
  comportă conform specificațiilor (hartă, rute, quest-uri, declanșarea
  automată a rundei FL la 15 interacțiuni, sincronizarea profilului),
  demonstrate prin capturi de ecran.
  - *Resurse:* Figură cu mai multe sub-capturi (subfigures), fiecare etichetată
    și mapată pe un FR din tabelul de la 2.2 (hartă cu obiective din
    apropiere, rută generată, quest finalizat -> rundă FL declanșată automat
    la 15 interacțiuni, profil sincronizat, recenzie trimisă/moderată).
    Fiecare sub-captură se referă explicit în text (nu doar o figură mare cu
    o mențiune vagă).
- **6.2 Performanța modelului FL**
  - 6.2.1 Rezultatele etapei de pre-antrenare (eroare medie pătratică - Mean
    Squared Error, MSE -, R^2, intervalul predicțiilor; tabel comparativ
    înainte/după fine-tuning)
    - *Resurse:* Figuri existente din `backend/pretraining/output/charts/`
      (NU din `pics/`): `training_results.png` (rezultate antrenare de la
      zero), `finetune_results.png` (rezultate după fine-tuning). Tabel
      înainte/după fine-tuning (MSE, R², interval predicții) - valorile sunt
      deja în `RESULTS.md` și `FINETUNING_RESULTS.md` din
      `backend/pretraining/`, doar de transcris în format `booktabs`.
  - 6.2.2 Rezultatele simulării procesului FL (curbe de loss, deriva
    ponderilor, distribuția vechimii (staleness), probe contextuale pe
    parcursul a 600 de runde)
    - *Resurse:* 7 figuri existente în `backend/federated/results/` (NU din
      `pics/`), generate de `simulate_fl.py`. Principale (3, în text):
      `loss_curve.png`, `fedasync_effect.png`, `staleness_distribution.png`.
      Secundare (4, -> Anexe ca set complet de grafice): `weight_drift.png`,
      `per_staleness_loss_delta.png`, `probe_scores.png`,
      `contextual_probes.png`. Datele numerice din `stats.json` (102KB) pot
      alimenta un tabel sumar complementar figurilor principale.
- **6.3 Evaluarea confidențialității și robusteții** - efectul zgomotului DP
  asupra utilității modelului; efectul limitării (clipping) asupra
  actualizărilor de tip adversarial.
  - *Resurse:* verifică `backend/federated/results/stats.json` pentru date
    privind efectul DP/clipping (MSE vs. nivel de zgomot, robustețe vs.
    actualizări adversariale); dacă nu există, secțiunea necesită un experiment
    nou (grafic/tabel) - de marcat separat când se redactează 6.3.
- **6.4 Analiză comparativă și discuții** - compromisurile dintre FedAvg
  sincron și asincron (problema clienților întârziați - straggler problem);
  poziționarea față de alternativele din Capitolul 3.
  - *Resurse:* Reia tabelul de la 3.4 (FedAvg/FedProx/SCAFFOLD/FedDyn/
    CultureQuest), extins cu o coloană de evaluare (ex. comportament în
    prezența clienților întârziați) - nu un tabel nou separat.

## Capitolul 7 - Concluzii
*Resurse:* fără figuri/tabele/cod noi - capitol narativ.

- **7.1 Concluzii generale** - obiectivele revizuite în raport cu ce a fost
  livrat.
  - *Resurse:* opțional, tabel scurt "obiectiv (din 1.3) -> rezultat obținut
    -> secțiune relevantă", ca recapitulare - nu introduce date noi.
- **7.2 Direcții de cercetare și lucrări viitoare** - "personal head" per
  utilizator, agregare de tip buffer (FedBuff) dacă participarea clienților se
  grupează în timp, schimbări de model/arhitectură mai ample, colectare de
  date FL de la utilizatori reali la scară mare.

---

## Bibliografie

### A. Articole

Ordonate în funcție de relevanța pentru lucrare, de la cele mai importante la
cele mai puțin importante (algoritmii efectiv implementați apar primii, iar
referințele de context sau pentru lucrări viitoare apar ultimele). Cheile
bibtex și locațiile surselor se află în `bibliography_sourcesRO.md`.

| Citare | Folosit pentru | Citat în |
|---|---|---|
| McMahan, B., Moore, E., Ramage, D., Hampson, S., & y Arcas, B. A. (2017). Communication-Efficient Learning of Deep Networks from Decentralized Data. *AISTATS 2017*. | Originea FedAvg - procedura de antrenare locală la nivelul fiecărui client și formula de agregare prin medie ponderată. | 1.3, 3.3, 4.4.2 |
| Xie, C., Koyejo, S., & Gupta, I. (2019). Asynchronous Federated Optimization. *arXiv:1903.03934*. | Reducerea pe bază de vechime (staleness discount) din FedAsync (`n_effective = n_samples/(1+staleness)`), nucleul agregării asincrone din CultureQuest. | 1.5, 3.3, 4.4.3, 6.2.2 |
| Bonawitz, K., Eichner, H., Grieskamp, N., Huba, D., Ingerman, A., Ivanov, V., Kiddon, C., Konečný, J., Mazzocchi, S., McMahan, H. B., Van Overveldt, T., Petrou, D., Ramage, D., & Roselander, J. (2019). Towards Federated Learning at Scale: System Design. *Proceedings of the 2nd SysML Conference*. | Motivația, regăsită în sisteme FL de producție, de a porni modelul global de la ponderi pre-antrenate (warm-start) în loc de o inițializare aleatoare - stă la baza pipeline-ului de pre-antrenare/fine-tuning și a cerinței legate de cold-start. | 1.1, 2.3, 5.3 |
| McMahan, H. B., Ramage, D., Talwar, K., & Zhang, L. (2018). Learning Differentially Private Recurrent Language Models. *ICLR 2018* (arXiv:1710.06963). | Șablonul DP-FedAvg de tip clip-then-aggregate - originea limitării normei L2 per actualizare, folosită de `clipped_fedavg`; pasul de adăugare a zgomotului urmează însă varianta Local-DP de mai jos (Wei et al., 2020). | 4.4.4 |
| Wei, K., Li, J., Ding, M., Ma, C., Yang, H. H., Farokhi, F., Jin, S., Quek, T. Q. S., & Poor, H. V. (2020). Federated Learning with Differential Privacy: Algorithms and Performance Analysis. *IEEE Transactions on Information Forensics and Security*, 15. | NbAFL (Noising before Model Aggregation FL) - fiecare client limitează (clip) și adaugă zgomot Gaussian calibrat pe delta-ul ponderilor *înainte* de transmitere, astfel încât serverul nu vede niciodată o actualizare curată; mecanismul Local-DP efectiv implementat de `_addDPNoise`, împreună cu analiza compromisului confidențialitate-utilitate care stă la baza evaluării din 6.3. | 4.4.5, 6.3 |
| Kairouz, P., McMahan, H. B., et al. (2021). Advances and Open Problems in Federated Learning. *Foundations and Trends in Machine Learning*, 14(1-2). | Articolul de tip survey de referință - acoperă FedAvg, FL asincron, DP, SecAgg, robustețe, personalizare și taxonomia de desfășurare cross-device vs. cross-silo. Co-autori McMahan și Bonawitz. | 1.1, 3.3, 6.4 (referință principală pe tot parcursul) |
| Lyu, L., Yu, H., & Yang, Q. (2020). Threats to Federated Learning: A Survey. *arXiv:2003.02133*. | Fundamentarea modelului de amenințări pentru agregarea cu limitare (clienți de tip poisoning/adversarial) și pentru DP (atacuri asupra confidențialității). | 3.3, 4.4.4, 4.4.5, 6.3 |
| Shokri, R., Stronati, M., Song, C., & Shmatikov, V. (2017). Membership Inference Attacks Against Machine Learning Models. *IEEE S&P 2017*. | Motivează pasul de adăugare a zgomotului DP pe delta-urile ponderilor (atenuează atacurile de tip membership inference). | 4.4.5, 6.3 |
| Yang, Q., Liu, Y., Chen, T., & Tong, Y. (2019). Federated Machine Learning: Concept and Applications. *ACM Transactions on Intelligent Systems and Technology*, 10(2), Article 12. | Taxonomia canonică Horizontal / Vertical / Federated-Transfer-Learning - poziționează CultureQuest ca **FL orizontal** (spațiu de caracteristici comun, cu 22 de dimensiuni, pentru toți clienții). | 3.3 |
| Li, T., Sahu, A. K., Zaheer, M., Sanjabi, M., Talwalkar, A., & Smith, V. (2020). Federated Optimization in Heterogeneous Networks. *MLSys 2020*. | FedProx - alternativă respinsă; stă la baza discuției din 3.4 despre motivul pentru care termenii proximali de corecție a derivei nu se potrivesc cu FL asincron, cu un singur client per rundă. | 3.4 |
| Karimireddy, S. P., Kale, S., Mohri, M., Reddi, S. J., Stich, S. U., & Suresh, A. T. (2020). SCAFFOLD: Stochastic Controlled Averaging for Federated Learning. *ICML 2020*. | SCAFFOLD - alternativă respinsă; corecția derivei prin variabile de control presupune o cohortă de clienți care antrenează concurent de la același checkpoint, lucru pe care design-ul asincron al CultureQuest, cu un singur client per rundă, nu îl are (3.4). | 3.4 |
| Acar, D. A. E., Zhao, Y., Navarro, R. M., Mattina, M., Whatmough, P. N., & Saligrama, V. (2021). Federated Learning Based on Dynamic Regularization. *ICLR 2021*. | FedDyn - alternativă respinsă; regularizatorul său dinamic este respins din același motiv ca FedProx și SCAFFOLD (3.4). | 3.4 |
| Li, T., Sahu, A. K., Talwalkar, A., & Smith, V. (2020). Federated Learning: Challenges, Methods, and Future Directions. *IEEE Signal Processing Magazine*, 37(3). | Provocări generale ale FL (eterogenitate, comunicare, confidențialitate), inclusiv încadrarea cross-device vs. cross-silo; context pentru discuția despre FedProx de mai sus (autori parțial comuni). | 3.3, 3.4 |
| Zhang, C., Xie, Y., Bai, H., Yu, B., Li, W., & Gao, Y. (2021). A survey on federated learning. *Knowledge-Based Systems*, 216, 106775. | Context general/taxonomie FL. | 1.1, 3.3 (introducere) |
| Li, L., Fan, Y., Tse, M., & Lin, K.-Y. (2020). A review of applications in federated learning. *Computers & Industrial Engineering*, 149, 106854. | Motivație din perspectiva domeniilor de aplicare (cazuri de utilizare FL pe mobil/IoT). | 1.1 (Context) |
| Adomavicius, G., & Tuzhilin, A. (2005). Toward the Next Generation of Recommender Systems: A Survey of the State-of-the-Art and Possible Extensions. *IEEE Transactions on Knowledge and Data Engineering*, 17(6), 734-749. | Survey fundamental al sistemelor de recomandare - clasifică abordările în filtrare bazată pe conținut, filtrare colaborativă și hibride; fundamentează analiza comparativă dintre abordările centralizate de recomandare și FL. | 3.2 |
| Gavalas, D., Konstantopoulos, C., Mastakas, K., & Pantziou, G. (2014). Mobile recommender systems in tourism. *Journal of Network and Computer Applications*, 39, 319-333. | Context pentru apariția și funcționarea aplicațiilor mobile de explorare/turism de tip city-guide (Google Maps, TripAdvisor) și pentru personalizarea bazată pe context/locație. | 1.1, 3.1 |
| Arivazhagan, M. G., Aggarwal, V., Singh, A. K., & Choudhary, S. (2019). Federated Learning with Personalization Layers. *arXiv:1912.00818*. | FedPer - împarte modelul în straturi de bază comune (agregate la nivel federat prin FedAvg) și straturi de personalizare locale (păstrate pe dispozitiv, niciodată încărcate); arhitectura propusă pentru "personal head"-ul din lucrările viitoare. | 2.4, 7.2 |
| Bonawitz, K., Ivanov, V., Kreuter, B., Marcedone, A., McMahan, H. B., Patel, S., Ramage, D., Segal, A., & Seth, K. (2017). Practical Secure Aggregation for Privacy-Preserving Machine Learning. *ACM CCS 2017*. | SecAgg - discutat ca protocol complementar, neimplementat încă (serverul vede doar suma actualizărilor). | 4.8, 7.2 |
| Nguyen, J., Malik, K., Zhan, H., Yousefpour, A., Rabbat, M., Malek, M., & Huba, D. (2022). Federated Learning with Buffered Asynchronous Aggregation (FedBuff). *arXiv:2106.06639*. | Agregare asincronă cu buffer - considerată o cale de mijloc între FedAvg sincron și varianta complet asincronă; marcată ca lucrare viitoare. | 3.3, 7.2 |

### B. Seturi de Date

Cheile bibtex și locațiile surselor se află în `bibliography_sourcesRO.md`.

| Citare | Folosit pentru | Citat în |
|---|---|---|
| Yang, D., Zhang, D., Zheng, V. W., & Yu, Z. (2015). Modeling User Activity Preference by Leveraging User Spatial Temporal Characteristics in LBSNs. *IEEE Transactions on Systems, Man, and Cybernetics: Systems*, 45(1). | Setul de date TSMC2014 (check-in-uri Foursquare din New York și Tokyo). | 5.3 |
| Yang, D., Zhang, D., & Qu, B. (2016). Participatory Cultural Mapping Based on Collective Behavior Data in Location-Based Social Networks. *ACM Transactions on Intelligent Systems and Technology*, 7(3). | Setul de date TIST2015 (check-in-uri Foursquare la nivel global). | 5.3 |
| Yang, D., Zhang, D., Yu, Z., & Yu, Z. (2013). Fine-Grained Preference-Aware Location Search Leveraging Crowdsourced Digital Footprints from LBSNs. *UbiComp 2013*. | Setul de date ubicomp2013 (check-in-uri/recenzii la restaurante din New York). | 5.3 |
| Yelp Inc. Yelp Open Dataset. (academic license). | Recenzii Yelp - sursa etichetelor explicite cu sentiment negativ (recenzii de 1-2 stele). | 5.3 |

---

## Anexe
Conform regulii din `thesis_writing_conventions.md` (## Anexe): elemente care
ocupă mai mult de o pagină și ar întrerupe firul textului dacă ar fi inline.

- **Diagrame complete**
  - `db.svg` complet (toate colecțiile și câmpurile din schema MongoDB - vezi
    4.3); în text rămâne doar versiunea simplificată/la nivel înalt.
- **Fragmente de cod extinse**
  - `_trainLocally` complet,
    `mobile/lib/features/federated/services/fl_client_service.dart:227-291`
    (65 linii) - varianta extinsă a Listing-ului 1 din 5.1.1 (forward pass +
    backpropagation + clipping, integral).
  - opțional, `proximity_service.dart` complet (66 linii) - varianta extinsă
    a referinței din 5.1.6, dacă se dorește un al 6-lea exemplu de cod.
- **Grafice complete de simulare/pre-antrenare** (din
  `backend/federated/results/` și `backend/pretraining/output/charts/`, NU
  din `pics/`)
  - `weight_drift.png`, `per_staleness_loss_delta.png`, `probe_scores.png`,
    `contextual_probes.png` - secundare față de cele 3 figuri principale din
    6.2.2.
  - `dataset_overview.png`, `label_by_type.png`, `train_val_split.png` - cele
    neincluse inline în 5.3.
- **Capturi de ecran suplimentare**
  - Fluxul de onboarding (`onboarding_screen.dart`, `interests_screen.dart`).
  - Ecranele de autentificare (`login_screen.dart`, `register_screen.dart`).
  - Panoul de administrare (`_AdminSubmissionsSheet`,
    `map_screen.dart:3573-3806`) - cele 5 tab-uri de moderare.
  - Stări alternative/cazuri limită neprezentate în 5.1 (ex. ecran offline,
    erori de rețea).
- **Fișiere de configurare/build**
  - `docker-compose.yml`, `backend/Dockerfile`, `backend/requirements.txt`,
    `backend/.env.example`.
- **Tabele extinse**
  - Tabelul complet al endpoint-urilor REST (landmarks/quests/comments/routes),
    dacă 5.2.2 prezintă în text doar cele 4 endpoint-uri FL.
