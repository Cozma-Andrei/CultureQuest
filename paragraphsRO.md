# Estimare lungime: paragrafe per secțiune/subsecțiune

Completează `structureRO.md` (ce conținut/resurse) cu o estimare de
**lungime**, pentru un target de **~40 de pagini, fără Anexă** (bibliografia e
discutată separat la final). Numerele sunt estimări orientative, nu cerințe
stricte - pot varia +/-1 paragraf per secțiune fără să schimbe concluzia
generală.

## Metodologie și premise

- Format presupus: A4, 12pt, ~1.5 rânduri -> **~400-450 cuvinte/pagină** de
  text plin -> un paragraf de 100-150 cuvinte -> **1 paragraf ≈ 0.25 pagini**.
- O figură/tabel/listing de cod ocupă **~0.3-0.5 pagini** (conform regulii
  "1/3-1/2 pagină" din `thesis_writing_conventions.md`) și necesită minim 1-2
  paragrafe de explicație - paragrafele de explicație sunt **incluse** în
  coloana "Paragrafe", nu adăugate separat.
- **Cadru de capitol** (conform "Încadrarea capitolelor" din
  `thesis_writing_conventions.md`): primul paragraf din prima secțiune a
  fiecărui capitol prezintă capitolul (ce conține, de ce, legătura cu
  capitolul anterior); ultimul paragraf din ultima secțiune face rezumatul
  capitolului și tranziția spre următorul. Ambele sunt incluse în numărul de
  paragrafe al acelei secțiuni, nu adaugă rânduri separate - notat sub
  titlul fiecărui capitol mai jos.
- Coloana "Resursă" reia, prescurtat, adnotările `*Resurse:*` din
  `structureRO.md` - pentru detalii (fișier/linii exacte), vezi acolo.
- "Pagini est." = (paragrafe x 0.25) + spațiul resurselor vizuale, rotunjit la
  0.1.
- **Liste cu marcatori**: o listă scurtă (3-5 itemi, 1-2 rânduri/item), cu
  spațierea înainte/după, ocupă aprox. cât **1 paragraf normal** (~0.25
  pagini) - apare ca unitate proprie în coloana "Paragrafe" (ex: 1.3
  Obiective, 5.5 Dificultăți, 7.2 Direcții viitoare), nu e ignorată în calcul.
- **Formule afișate**: o ecuație pe rând propriu + lista "unde: ..." cu 2-4
  termeni ocupă **~0.2 pagini suplimentare** față de paragrafele de explicație
  - nu e neglijabilă, comparabilă cu o figură mică (relevant la 4.4.2, 4.4.3,
  4.4.4, 4.4.5).

---

## Capitolul 1 - Introducere (narativ, fără figuri/tabele)

*(1.1 include paragraful de prezentare a capitolului; 1.6 include paragraful
de tranziție spre Cap. 2.)*

| Secțiune | Paragrafe | Resursă | Pagini est. |
|---|---|---|---|
| 1.1 Context | 3 | - | 0.8 |
| 1.2 Definirea problemei | 2 | - | 0.5 |
| 1.3 Obiective | 1 + listă (3 obiective a/b/c) | listă | 0.6 |
| 1.4 Soluția propusă | 2 | opțional preview fig. 4.1 | 0.5 |
| 1.5 Rezultatele obținute | 2 | opțional preview `loss_curve.png` | 0.5 |
| 1.6 Structura lucrării | ~7 paragrafe scurte (1-2 propoziții/capitol) | - | 0.6 |

**Subtotal Capitolul 1: ~3.1 pagini** (~14 paragrafe + 1 listă, din care 7
paragrafe foarte scurte la 1.6)

---

## Capitolul 2 - Analiza Cerințelor

*(2.1 include paragraful de prezentare a capitolului, legat de obiectivele
din 1.3; 2.4 include tranziția spre Cap. 3.)*

| Secțiune | Paragrafe | Resursă | Pagini est. |
|---|---|---|---|
| 2.1 Utilizatori țintă și cazuri de utilizare | 2 | - | 0.5 |
| 2.2 Cerințe funcționale | 2-3 | Tabel FR-1..N | 1.0 |
| 2.3 Cerințe non-funcționale | 1-2 | Tabel NFR-1..N | 0.7 |
| 2.4 Domeniul de aplicare | 1-2 | opțional tabel Inclus/Exclus | 0.6 |

**Subtotal Capitolul 2: ~3 pagini** (~7-9 paragrafe + 2-3 tabele)

---

## Capitolul 3 - Soluții Existente

*(3.1 include paragraful de prezentare a capitolului; 3.5.4 include
tranziția spre Cap. 4.)*

| Secțiune | Paragrafe | Resursă | Pagini est. |
|---|---|---|---|
| 3.1 Aplicații existente pentru explorare urbană | 2-3 | Tabel comparativ apps | 1.0 |
| 3.2 Centralizat vs. FL pentru recomandări | 2-3 | Tabel comparativ | 1.0 |
| 3.3 FL: Stadiul actual | 3 | Figură taxonomie HFL/VFL/FTL | 1.2 |
| 3.4 Alternative respinse | 2-3 | Tabel FedAvg/FedProx/SCAFFOLD/FedDyn | 1.0 |
| 3.5 (intro tehnologii) | 1 | - | 0.2 |
| 3.5.1 Flutter și Riverpod | 1-2 | opțional tabel | 0.6 |
| 3.5.2 FastAPI, MongoDB, Redis | 1-2 | opțional tabel | 0.6 |
| 3.5.3 OSRM | 1 | - | 0.3 |
| 3.5.4 MLP propriu vs. TFLite/PyTorch Mobile | 2 | Tabel comparativ | 0.8 |

**Subtotal Capitolul 3: ~6.7 pagini** (~16-19 paragrafe + 5-7 tabele + 1 figură)

---

## Capitolul 4 - Soluția Propusă (proiectare - diagrame/tabele/ecuații, fără cod)

*(4.1 include paragraful de prezentare a capitolului - se poate baza pe nota
*Resurse generale* din `structureRO.md`; 4.8 include tranziția spre Cap. 5.)*

| Secțiune | Paragrafe | Resursă | Pagini est. |
|---|---|---|---|
| 4.1 Prezentare generală a sistemului | 2 | Figură arhitectură (centrală) | 1.0 |
| 4.2 Arhitectura aplicației mobile | 2 | Figură module Flutter | 0.8 |
| 4.3 Arhitectura serviciilor backend | 2-3 | Figură ER simplificată (+ opțional tabel) | 1.0 |
| 4.4 (intro proiectare FL) | 1 | - | 0.2 |
| 4.4.1 Arhitectura modelului (MLP) | 2-3 | Figură MLP + Tabel 22 caracteristici | 1.3 |
| 4.4.2 Antrenarea locală (FedAvg client) | 2 | Ecuație SGD + termeni "unde:..." | 0.7 |
| 4.4.3 Agregare asincronă (FedAsync) | 1-2 | Figură curbă `1/(1+staleness)` + formulă discount | 0.7 |
| 4.4.4 Agregare cu limitare (clipping) | 2 | Ecuație normă L2 + termeni "unde:..." | 0.7 |
| 4.4.5 Confidențialitate diferențială (DP) | 2 | Ecuație mecanism NbAFL + termeni "unde:..." | 0.7 |
| 4.4.6 Controlul concurenței (lock Redis) | 1-2 | Figură secvență, săgeți numerotate | 0.7 |
| 4.5 Fluxul de generare a rutelor | 2 | Figură flux, săgeți numerotate | 0.9 |
| 4.6 Proiectarea elementelor de gamificare | 2 | Figură stări quest + Tabel etichete engagement | 1.1 |
| 4.7 Hartă și navigare | 1 | opțional schiță geofencing | 0.4 |
| 4.8 Arhitectura de confidențialitate | 2 | Figură flux date, săgeți numerotate + Tabel | 1.1 |

**Subtotal Capitolul 4: ~11.3 pagini** (~23-27 paragrafe + 9 figuri + 4 tabele
+ 3 ecuații cu termeni "unde:...") - **cel mai mare capitol**, cum e firesc
pentru proiectare.

---

## Capitolul 5 - Detalii de Implementare (cod selectiv, 5 listinguri principale)

*(5.1 include paragraful de prezentare a capitolului - se poate baza pe nota
*Resurse generale* din `structureRO.md`; 5.5 include tranziția spre Cap. 6.)*

| Secțiune | Paragrafe | Resursă | Pagini est. |
|---|---|---|---|
| 5.1 (intro implementare mobilă) | 1 | - | 0.2 |
| 5.1.1 Serviciul client FL (forward+backprop+clipping) | 2-3 | **Listing 1** | 1.1 |
| 5.1.2 Adăugarea zgomotului DP | 2 | **Listing 2** | 0.9 |
| 5.1.3 Bufferul local de interacțiuni | 1-2 | Captură ecran (profil/status FL) | 0.6 |
| 5.1.4 Stocarea offline a obiectivelor | 1 | - | 0.25 |
| 5.1.5 Algoritmul de generare a rutelor (integrare UI) | 2 | Captură ecran (sheet generare rută) | 0.8 |
| 5.1.6 Misiuni și geofencing | 2 | Captură ecran (proximitate/quest) | 0.8 |
| 5.2 (intro implementare backend) | 1 | - | 0.2 |
| 5.2.1 Serviciul de agregare | 2-3 | **Listing 3** | 1.1 |
| 5.2.2 Punctele de acces API | 1-2 | Tabel 4 endpoint-uri FL | 0.6 |
| 5.2.3 Recenzii și moderarea conținutului | 2-3 | **Listing 4** | 1.1 |
| 5.3 Fluxul etapei de pre-antrenare | 2-3 | Figuri (1-3, din `pretraining/output/charts/`) | 1.3 |
| 5.4 Framework simulare FL | 2 | **Listing 5** + Tabel parametri simulare | 1.3 |
| 5.5 Dificultăți întâmpinate | 1 + listă (3-4 dificultăți) | listă | 0.6 |

**Subtotal Capitolul 5: ~10.85 pagini** (~21-25 paragrafe + 1 listă + 5
listinguri + 3 capturi + 1-3 figuri + 2 tabele)

---

## Capitolul 6 - Evaluare

*(6.1 include paragraful de prezentare a capitolului; 6.4 include tranziția
spre Cap. 7.)*

| Secțiune | Paragrafe | Resursă | Pagini est. |
|---|---|---|---|
| 6.1 Corectitudinea funcțională | 2-3 | Figură multi-panel (capturi FR) | 1.3 |
| 6.2 (intro performanță model FL) | 1 | - | 0.2 |
| 6.2.1 Rezultate pre-antrenare | 2-3 | 2 figuri + Tabel înainte/după fine-tuning | 1.5 |
| 6.2.2 Rezultate simulare FL | 2-3 | 3 figuri (`loss_curve`, `fedasync_effect`, `staleness_distribution`) + `timing.inference_us_numpy` din `stats.json` | 1.8 |
| 6.3 Evaluare confidențialitate/robustețe/scalabilitate | 3-4 | `stats.json` (loss final, îmbunătățire %) + Tabel load test (4 niveluri concurență) | 1.3 |
| 6.4 Analiză comparativă și discuții | 2-3 | Tabel extins din 3.4 | 1.0 |

**Subtotal Capitolul 6: ~7.1 pagini** (~14-17 paragrafe + ~6 figuri + 3 tabele)

*Față de estimarea inițială (6,6 pagini), secțiunea 6.3 a crescut cu ~0,5
pagini pentru a include testul de scalabilitate (tabel load test + concluzie
NFR-4) și parametrii DP expliciți (σ=0,1; ℓ₂≤1,0). Creșterea e justificată
de conținut nou demonstrabil: `federated/results/load_test.json` și cheia
`timing` din `stats.json`.*

---

## Capitolul 7 - Concluzii (narativ)

*(7.1 include paragraful de prezentare a capitolului; 7.2 e ultima secțiune a
tezei - paragraful final e o încheiere generală, nu o tranziție spre alt
capitol.)*

| Secțiune | Paragrafe | Resursă | Pagini est. |
|---|---|---|---|
| 7.1 Concluzii generale | 3 | opțional tabel recapitulativ obiectiv->rezultat | 1.0 |
| 7.2 Direcții de cercetare și lucrări viitoare | 1 + listă (6 direcții) + 1 | listă | 1.2 |

**Subtotal Capitolul 7: ~2 pagini** (~5-6 paragrafe + 1 listă)

---

## Sumar

| Capitol | Pagini est. | % din total |
|---|---|---|
| 1. Introducere | ~3.1 | 7% |
| 2. Analiza Cerințelor | ~3.0 | 7% |
| 3. Soluții Existente | ~6.7 | 15% |
| 4. Soluția Propusă | ~11.3 | 26% |
| 5. Detalii de Implementare | ~10.85 | 25% |
| 6. Evaluare | ~7.1 | 16% |
| 7. Concluzii | ~2.0 | 5% |
| **Total (Cap. 1-7)** | **~44.1** | **100%** |
| Bibliografie (24 intrări, APA) | ~1.5-2 (listă, nu paragrafe) | - |

~44 de pagini pentru Cap. 1-7 - față de estimarea anterioară (~43,6 pagini),
Cap. 6 a crescut cu ~0,5 pagini (6,3 extins cu testul de scalabilitate și
parametrii DP expliciți). Rămâne în marja rezonabilă față de target-ul de 40.
Distribuția e firească pentru o lucrare cu componentă de proiectare+implementare
FL: Cap. 4 și 5 (proiectare, implementare) domină, Cap. 1 și 7 (introducere,
concluzii) sunt scurte.

### Dacă vrei mai aproape de exact 40 de pagini

Cele mai ieftine reduceri, fără să sacrifice conținut central (toate sunt deja
marcate "opțional"/flexibile în `structureRO.md`):
- Renunță la tabelele opționale din 3.5.1/3.5.2 (rămân text) -> -~0.8 pagini.
- Fără schiță la 4.7 (te bazezi pe captura din 5.1.6) -> -~0.2 pagini.
- Fără tabel opțional la 2.4 și 7.1 -> -~0.5 pagini.
- 6.3: sari tabelul load test, menționezi doar concluzia textual -> -~0.4 pagini.
- 3.3 cu 2 paragrafe în loc de 3 (figura e adaptată, nu originală, necesită
  mai puțină explicație) -> -~0.25 pagini.
- 5.3 cu 1-2 figuri în loc de 1-3 (alegi cele mai relevante din
  `pretraining/output/charts/`) -> -~0.35 pagini.

Total reducere posibilă: ~2.4 pagini -> ~41.2 pagini, fără a elimina nimic din
conținutul "obligatoriu" (figurile/tabelele/listingurile primare rămân toate).
Diferența rămasă față de 40 (~1.2 pagini) e în continuare în marja "poate
varia" menționată inițial.
