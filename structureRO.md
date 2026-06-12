# Structură

## Capitolul 1 - Introducere
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

## Capitolul 2 - Analiza Cerințelor / Motivație
- **2.1 Utilizatori țintă și cazuri de utilizare** - turist/localnic care
  explorează un oraș și dorește sugestii personalizate de obiective, rute și
  stimulente gamificate (quest-uri).
- **2.2 Cerințe funcționale** - hartă cu obiective din apropiere, generare de
  rute, sistem de quest-uri, evaluări/recenzii, profil + sincronizare FL,
  controale de confidențialitate.
- **2.3 Cerințe non-funcționale** - confidențialitate pe dispozitiv (nicio
  dată brută nu părăsește telefonul), reziliență offline (obiective stocate
  în cache), cost redus de antrenare pe dispozitiv (MLP mic), scalabilitatea
  backend-ului pentru încărcări asincrone ale clienților, gestionarea
  pornirii la rece (cold-start) (utilizatorii noi și obiectivele noi trebuie
  să primească recomandări utile din modelul global pre-antrenat și din
  caracteristicile bazate pe conținut, înainte ca personalizarea locală prin
  FL să fi avut loc).
- **2.4 Domeniul de aplicare al proiectului** - ce este acoperit vs. ce nu
  intră în domeniul de aplicare (de ex., un "personal head" per utilizator,
  listat ca lucrare viitoare).

## Capitolul 3 - Studiu de Piață / Soluții Existente
- **3.1 Aplicații existente pentru explorare urbană** - Google Maps,
  TripAdvisor, aplicații de tip city-guide; modul în care acestea
  personalizează (sau nu) și modelul lor de colectare a datelor.
- **3.2 Analiză comparativă între abordările centralizate și învățarea
  federată (FL, *Federated Learning*) pentru recomandări** - filtrare
  colaborativă/bazată pe conținut cu date stocate pe server vs. FL;
  compromisuri legate de confidențialitate.
- **3.3 FL: Stadiul actual** - taxonomia FL (Federated Learning Orizontal,
  Vertical și Federated Transfer Learning - FL cu transfer -, respectiv
  Cross-Device - la nivel de dispozitive individuale - versus Cross-Silo - la
  nivel de organizații) folosită pentru a poziționa CultureQuest ca **FL
  orizontal, de tip cross-device**; FedAvg, FL asincron, robustețe și
  confidențialitate (vezi Bibliografia de mai jos pentru articolele de tip
  survey care susțin această secțiune).
- **3.4 Alternative respinse** - FedProx, SCAFFOLD, FedDyn: de ce termenii lor
  de corecție a derivei (drift) între clienți presupun runde sincrone cu mai
  mulți clienți, ceea ce nu se aplică design-ului asincron al CultureQuest, cu
  un singur client per rundă.
- **3.5 Tehnologiile utilizate și justificarea acestora**
  - 3.5.1 Flutter și Riverpod (vs. React Native/nativ)
  - 3.5.2 FastAPI, MongoDB și Redis (vs. alternative)
  - 3.5.3 Motorul de Rutare OSRM (*Open Source Routing Machine*)
  - 3.5.4 Perceptron multi-strat (MLP, *Multi-Layer Perceptron*) - propriu
    vs. TFLite/PyTorch Mobile (dimensiunea modelului, fără dependență de
    runtime)

## Capitolul 4 - Soluția Propusă
- **4.1 Prezentare generală a sistemului** - diagramă de arhitectură: client
  mobil <-> backend FastAPI <-> MongoDB (date persistente) + Redis (stare FL).
- **4.2 Arhitectura aplicației mobile** - structură Flutter organizată pe
  feature-uri (hartă, profil, federated etc.), management de stare cu
  Riverpod.
- **4.3 Arhitectura serviciilor *backend*** - servicii/rute FastAPI, modelul
  de date (obiective, utilizatori, quest-uri, rute, evenimente); pas de
  moderare a conținutului generat de utilizatori (comentarii, povești)
  înainte de publicare (detalii tehnice în 5.2.3).
- **4.4 Proiectarea sistemului FL**
  - 4.4.1 Arhitectura modelului (MLP 22 -> 32 -> 16 -> 1, ieșire sigmoid,
    detalierea vectorului de caracteristici)
  - 4.4.2 Antrenarea locală (procedura client FedAvg: 5 epoci locale, coborâre
    pe gradient stocastică - Stochastic Gradient Descent, SGD)
  - 4.4.3 Agregare asincronă și reducerea în funcție de vechime (FedAsync:
    `n_effective = n_samples/(1+staleness)`)
  - 4.4.4 Agregare cu limitare (*Gradient Clipping*) (limitarea normei
    delta-ului împotriva actualizărilor adversariale/extreme)
  - 4.4.5 Confidențialitate diferențială (DP, *Differential Privacy*) (zgomot
    Gaussian adăugat pe delta-urile ponderilor)
  - 4.4.6 Controlul concurenței (lock de agregare în Redis)
- **4.5 Fluxul de generare a rutelor** - filtrare cu scor FL x 0.8 +
  proximitate x 0.2, criteriu de departajare pe baza potrivirii intereselor,
  durată de vizitare (dwell time) scalată în funcție de scorul FL.
- **4.6 Proiectarea elementelor de gamificare** - sistemul de quest-uri și
  etichetele de engagement (deschiderea fișei obiectivului, începerea
  navigării, finalizarea quest-ului, evaluări).
- **4.7 Hartă și navigare** - geofencing, rotirea hărții pe baza
  busolei/GPS-ului.
- **4.8 Arhitectura de confidențialitate** - ce rămâne pe dispozitiv vs. ce
  este încărcat pe server; diagramă a fluxului de date.

## Capitolul 5 - Detalii de Implementare
- **5.1 Implementarea aplicației mobile** (subsecțiunile orientate spre
  interfață includ o captură de ecran reprezentativă din aplicație)
  - 5.1.1 Serviciul client FL - forward pass + backpropagation manuală în
    Dart, limitare (clipping)
  - 5.1.2 Adăugare de zgomot pentru asigurarea DP (zgomot Gaussian generat
    prin transformata Box-Muller)
  - 5.1.3 Bufferul local de interacțiuni și persistența datelor (cache
    bazat pe SharedPreferences, persistă la închiderea aplicației)
  - 5.1.4 Stocarea temporară a obiectivelor pentru funcționarea offline
  - 5.1.5 Algoritmul de generare a rutelor - filtrarea candidaților (scor FL x
    0.8 + proximitate x 0.2), criteriu de departajare pe baza potrivirii
    intereselor, durată de vizitare per oprire scalată în funcție de scorul FL
  - 5.1.6 Sistemul de misiuni și tehnologia de *geofencing* - detectarea
    finalizării quest-urilor, declanșatoare de geofencing, înregistrarea
    etichetelor de engagement
- **5.2 Implementarea serviciilor *backend***
  - 5.2.1 Serviciul de agregare (`fedavg`, `clipped_fedavg`, reducerea în
    funcție de vechime, lock Redis)
  - 5.2.2 Puncte de acces API (preluare/actualizare model, status)
  - 5.2.3 Sistemul de recenzii și moderarea conținutului - endpoint-uri de
    comentarii/evaluări pe obiective (agregarea `rating_sum`/`rating_count`);
    moderare prin OpenAI Moderation API, cu fallback local pe o listă de
    cuvinte interzise când API-ul nu este disponibil
- **5.3 Fluxul etapei de pre-antrenare** - pregătirea seturilor de date
  (Foursquare TSMC2014/TIST2015, ubicomp2013, Yelp, date sintetice;
  construcția etichetelor); antrenarea de la zero (MLP, SGD, scăderea ratei de
  învățare); fine-tuning (augmentare de date pentru semnal slab de etichetare,
  modificări de hiperparametri, corectarea regresiei către medie).
- **5.4 Framework-ul pentru simularea procesului FL** - simulare sintetică pe
  mai multe runde, comparând reducerea în funcție de vechime din FedAsync
  activată vs. dezactivată, modelarea derivei conceptuale (concept drift)
  pentru clienții cu date vechi (stale).
- **5.5 Dificultăți întâmpinate în procesul de implementare** - problema
  regresiei către medie din pre-antrenare și modul în care fine-tuning-ul a
  rezolvat-o; ajustarea reducerii în funcție de vechime.

## Capitolul 6 - Evaluare
- **6.1 Corectitudinea funcțională** - funcționalitățile aplicației se
  comportă conform specificațiilor (hartă, rute, quest-uri, declanșarea
  automată a rundei FL la 15 interacțiuni, sincronizarea profilului),
  demonstrate prin capturi de ecran.
- **6.2 Performanța modelului FL**
  - 6.2.1 Rezultatele etapei de pre-antrenare (eroare medie pătratică - Mean
    Squared Error, MSE -, R^2, intervalul predicțiilor; tabel comparativ
    înainte/după fine-tuning)
  - 6.2.2 Rezultatele simulării procesului FL (curbe de loss, deriva
    ponderilor, distribuția vechimii (staleness), probe contextuale pe
    parcursul a 600 de runde)
- **6.3 Evaluarea confidențialității și robusteții** - efectul zgomotului DP
  asupra utilității modelului; efectul limitării (clipping) asupra
  actualizărilor de tip adversarial.
- **6.4 Analiză comparativă și discuții** - compromisurile dintre FedAvg
  sincron și asincron (problema clienților întârziați - straggler problem);
  poziționarea față de alternativele din Capitolul 3.

## Capitolul 7 - Concluzii
- **7.1 Concluzii generale** - obiectivele revizuite în raport cu ce a fost
  livrat.
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
| McMahan, B., Moore, E., Ramage, D., Hampson, S., & y Arcas, B. A. (2017). Communication-Efficient Learning of Deep Networks from Decentralized Data. *AISTATS 2017*. | Originea FedAvg - procedura de antrenare locală la nivelul fiecărui client și formula de agregare prin medie ponderată. | 3.3, 4.4.2 |
| Xie, C., Koyejo, S., & Gupta, I. (2019). Asynchronous Federated Optimization. *arXiv:1903.03934*. | Reducerea pe bază de vechime (staleness discount) din FedAsync (`n_effective = n_samples/(1+staleness)`), nucleul agregării asincrone din CultureQuest. | 3.3, 4.4.3, 6.2.2 |
| Bonawitz, K., Eichner, H., Grieskamp, N., Huba, D., Ingerman, A., Ivanov, V., Kiddon, C., Konečný, J., Mazzocchi, S., McMahan, H. B., Van Overveldt, T., Petrou, D., Ramage, D., & Roselander, J. (2019). Towards Federated Learning at Scale: System Design. *Proceedings of the 2nd SysML Conference*. | Motivația, regăsită în sisteme FL de producție, de a porni modelul global de la ponderi pre-antrenate (warm-start) în loc de o inițializare aleatoare - stă la baza pipeline-ului de pre-antrenare/fine-tuning și a cerinței legate de cold-start. | 1.1, 2.3, 5.3 |
| McMahan, H. B., Ramage, D., Talwar, K., & Zhang, L. (2018). Learning Differentially Private Recurrent Language Models. *ICLR 2018* (arXiv:1710.06963). | Șablonul DP-FedAvg de tip clip-then-aggregate - originea limitării normei L2 per actualizare, folosită de `clipped_fedavg`; pasul de adăugare a zgomotului urmează însă varianta Local-DP de mai jos (Wei et al., 2020). | 4.4.4 |
| Wei, K., Li, J., Ding, M., Ma, C., Yang, H. H., Farokhi, F., Jin, S., Quek, T. Q. S., & Poor, H. V. (2020). Federated Learning with Differential Privacy: Algorithms and Performance Analysis. *IEEE Transactions on Information Forensics and Security*, 15. | NbAFL (Noising before Model Aggregation FL) - fiecare client limitează (clip) și adaugă zgomot Gaussian calibrat pe delta-ul ponderilor *înainte* de transmitere, astfel încât serverul nu vede niciodată o actualizare curată; mecanismul Local-DP efectiv implementat de `_addDPNoise`, împreună cu analiza compromisului confidențialitate-utilitate care stă la baza evaluării din 6.3. | 4.4.5, 6.3 |
| Kairouz, P., McMahan, H. B., et al. (2021). Advances and Open Problems in Federated Learning. *Foundations and Trends in Machine Learning*, 14(1-2). | Articolul de tip survey de referință - acoperă FedAvg, FL asincron, DP, SecAgg, robustețe, personalizare și taxonomia de desfășurare cross-device vs. cross-silo. Co-autori McMahan și Bonawitz. | 1.1, 3.3 (referință principală pe tot parcursul) |
| Lyu, L., Yu, H., & Yang, Q. (2020). Threats to Federated Learning: A Survey. *arXiv:2003.02133*. | Fundamentarea modelului de amenințări pentru agregarea cu limitare (clienți de tip poisoning/adversarial) și pentru DP (atacuri asupra confidențialității). | 3.3, 4.4.4, 4.4.5, 6.3 |
| Shokri, R., Stronati, M., Song, C., & Shmatikov, V. (2017). Membership Inference Attacks Against Machine Learning Models. *IEEE S&P 2017*. | Motivează pasul de adăugare a zgomotului DP pe delta-urile ponderilor (atenuează atacurile de tip membership inference). | 4.4.5, 6.3 |
| Yang, Q., Liu, Y., Chen, T., & Tong, Y. (2019). Federated Machine Learning: Concept and Applications. *ACM Transactions on Intelligent Systems and Technology*, 10(2), Article 12. | Taxonomia canonică Horizontal / Vertical / Federated-Transfer-Learning - poziționează CultureQuest ca **FL orizontal** (spațiu de caracteristici comun, cu 22 de dimensiuni, pentru toți clienții). | 3.3 |
| Li, T., Sahu, A. K., Zaheer, M., Sanjabi, M., Talwalkar, A., & Smith, V. (2020). Federated Optimization in Heterogeneous Networks. *MLSys 2020*. | FedProx - alternativă respinsă; stă la baza discuției din 3.4 despre motivul pentru care termenii proximali de corecție a derivei nu se potrivesc cu FL asincron, cu un singur client per rundă. | 3.4 |
| Karimireddy, S. P., Kale, S., Mohri, M., Reddi, S. J., Stich, S. U., & Suresh, A. T. (2020). SCAFFOLD: Stochastic Controlled Averaging for Federated Learning. *ICML 2020*. | SCAFFOLD - alternativă respinsă; corecția derivei prin variabile de control presupune o cohortă de clienți care antrenează concurent de la același checkpoint, lucru pe care design-ul asincron al CultureQuest, cu un singur client per rundă, nu îl are (3.4). | 3.4 |
| Acar, D. A. E., Zhao, Y., Navarro, R. M., Mattina, M., Whatmough, P. N., & Saligrama, V. (2021). Federated Learning Based on Dynamic Regularization. *ICLR 2021*. | FedDyn - alternativă respinsă; regularizatorul său dinamic este respins din același motiv ca FedProx și SCAFFOLD (3.4). | 3.4 |
| Li, T., Sahu, A. K., Talwalkar, A., & Smith, V. (2020). Federated Learning: Challenges, Methods, and Future Directions. *IEEE Signal Processing Magazine*, 37(3). | Provocări generale ale FL (eterogenitate, comunicare, confidențialitate), inclusiv încadrarea cross-device vs. cross-silo; context pentru discuția despre FedProx de mai sus (autori parțial comuni). | 3.3, 3.4 |
| Zhang, C., Xie, Y., Bai, H., Yu, B., Li, W., & Gao, Y. (2021). A survey on federated learning. *Knowledge-Based Systems*, 216, 106775. | Context general/taxonomie FL. | 1.1, 3.3 (introducere) |
| Li, L., Fan, Y., Tse, M., & Lin, K.-Y. (2020). A review of applications in federated learning. *Computers & Industrial Engineering*, 149, 106854. | Motivație din perspectiva domeniilor de aplicare (cazuri de utilizare FL pe mobil/IoT). | 1.1 (Context) |
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
- Fragmente de cod (forward/backprop pentru clientul FL, formula de agregare)
- Capturi de ecran suplimentare din aplicație (stări alternative, cazuri
  limită neprezentate în 5.1)
- Grafice complete care nu încap în text (prezentare generală a seturilor de
  date, probe contextuale, grafice ale simulării)
