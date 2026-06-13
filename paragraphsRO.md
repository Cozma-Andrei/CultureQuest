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
- Paragraful de încadrare a capitolului (introducere/rezumat, conform
  "Încadrarea capitolelor") e inclus în prima, respectiv ultima secțiune a
  fiecărui capitol - nu apare ca rând separat.
- Coloana "Resursă" reia, prescurtat, adnotările `*Resurse:*` din
  `structureRO.md` - pentru detalii (fișier/linii exacte), vezi acolo.
- "Pagini est." = (paragrafe x 0.25) + spațiul resurselor vizuale, rotunjit la
  0.1.

---

## Capitolul 1 - Introducere (narativ, fără figuri/tabele)

| Secțiune | Paragrafe | Resursă | Pagini est. |
|---|---|---|---|
| 1.1 Context | 3 | - | 0.8 |
| 1.2 Definirea problemei | 2 | - | 0.5 |
| 1.3 Obiective | 2 (+ listă a/b/c) | - | 0.5 |
| 1.4 Soluția propusă | 2 | opțional preview fig. 4.1 | 0.5 |
| 1.5 Rezultatele obținute | 2 | opțional preview `loss_curve.png` | 0.5 |
| 1.6 Structura lucrării | ~7 paragrafe scurte (1-2 propoziții/capitol) | - | 0.6 |

**Subtotal Capitolul 1: ~3 pagini** (~14 paragrafe, din care 7 foarte scurte)

---

## Capitolul 2 - Analiza Cerințelor / Motivație

| Secțiune | Paragrafe | Resursă | Pagini est. |
|---|---|---|---|
| 2.1 Utilizatori țintă și cazuri de utilizare | 2 | - | 0.5 |
| 2.2 Cerințe funcționale | 2-3 | Tabel FR-1..N | 1.0 |
| 2.3 Cerințe non-funcționale | 1-2 | Tabel NFR-1..N | 0.7 |
| 2.4 Domeniul de aplicare | 1-2 | opțional tabel Inclus/Exclus | 0.6 |

**Subtotal Capitolul 2: ~3 pagini** (~7-9 paragrafe + 2-3 tabele)

---

## Capitolul 3 - Studiu de Piață / Soluții Existente

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

| Secțiune | Paragrafe | Resursă | Pagini est. |
|---|---|---|---|
| 4.1 Prezentare generală a sistemului | 2 | Figură arhitectură (centrală) | 1.0 |
| 4.2 Arhitectura aplicației mobile | 2 | Figură module Flutter | 0.8 |
| 4.3 Arhitectura serviciilor backend | 2-3 | Figură ER simplificată (+ opțional tabel) | 1.0 |
| 4.4 (intro proiectare FL) | 1 | - | 0.2 |
| 4.4.1 Arhitectura modelului (MLP) | 2-3 | Figură MLP + Tabel 22 caracteristici | 1.3 |
| 4.4.2 Antrenarea locală (FedAvg client) | 2 | Ecuație SGD | 0.5 |
| 4.4.3 Agregare asincronă (FedAsync) | 1-2 | Figură curbă `1/(1+staleness)` | 0.6 |
| 4.4.4 Agregare cu limitare (clipping) | 2 | Ecuație normă L2 | 0.5 |
| 4.4.5 Confidențialitate diferențială (DP) | 2 | Ecuație mecanism NbAFL | 0.5 |
| 4.4.6 Controlul concurenței (lock Redis) | 1-2 | Figură secvență, săgeți numerotate | 0.7 |
| 4.5 Fluxul de generare a rutelor | 2 | Figură flux, săgeți numerotate | 0.9 |
| 4.6 Proiectarea elementelor de gamificare | 2 | Figură stări quest + Tabel etichete engagement | 1.1 |
| 4.7 Hartă și navigare | 1 | opțional schiță geofencing | 0.4 |
| 4.8 Arhitectura de confidențialitate | 2 | Figură flux date, săgeți numerotate + Tabel | 1.1 |

**Subtotal Capitolul 4: ~10.6 pagini** (~23-27 paragrafe + 9 figuri + 4 tabele + 3 ecuații) - **cel mai mare capitol**, cum e firesc pentru proiectare.

---

## Capitolul 5 - Detalii de Implementare (cod selectiv, 5 listinguri principale)

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
| 5.5 Dificultăți întâmpinate | 2 | - | 0.5 |

**Subtotal Capitolul 5: ~10.75 pagini** (~21-25 paragrafe + 5 listinguri + 3 capturi + 1-3 figuri + 2 tabele)

---

## Capitolul 6 - Evaluare

| Secțiune | Paragrafe | Resursă | Pagini est. |
|---|---|---|---|
| 6.1 Corectitudinea funcțională | 2-3 | Figură multi-panel (capturi FR) | 1.3 |
| 6.2 (intro performanță model FL) | 1 | - | 0.2 |
| 6.2.1 Rezultate pre-antrenare | 2-3 | 2 figuri + Tabel înainte/după fine-tuning | 1.5 |
| 6.2.2 Rezultate simulare FL | 2-3 | 3 figuri (`loss_curve`, `fedasync_effect`, `staleness_distribution`) | 1.8 |
| 6.3 Evaluare confidențialitate/robustețe | 2-3 | (de verificat `stats.json`) | 0.8 |
| 6.4 Analiză comparativă și discuții | 2-3 | Tabel extins din 3.4 | 1.0 |

**Subtotal Capitolul 6: ~6.6 pagini** (~13-16 paragrafe + ~6 figuri + 2 tabele)

---

## Capitolul 7 - Concluzii (narativ)

| Secțiune | Paragrafe | Resursă | Pagini est. |
|---|---|---|---|
| 7.1 Concluzii generale | 3 | opțional tabel recapitulativ obiectiv->rezultat | 1.0 |
| 7.2 Direcții de cercetare și lucrări viitoare | 3-4 | - | 1.0 |

**Subtotal Capitolul 7: ~2 pagini** (~6-7 paragrafe)

---

## Sumar

| Capitol | Pagini est. | % din total |
|---|---|---|
| 1. Introducere | ~3.0 | 7% |
| 2. Analiza Cerințelor | ~3.0 | 7% |
| 3. Studiu de Piață | ~6.7 | 16% |
| 4. Soluția Propusă | ~10.6 | 25% |
| 5. Detalii de Implementare | ~10.75 | 25% |
| 6. Evaluare | ~6.6 | 15% |
| 7. Concluzii | ~2.0 | 5% |
| **Total (Cap. 1-7)** | **~42.6** | **100%** |
| Bibliografie (24 intrări, APA) | ~1.5-2 (listă, nu paragrafe) | - |

~42-43 de pagini pentru Cap. 1-7 e foarte apropiat de target-ul de 40 (în
marja de variație menționată). Distribuția e firească pentru o lucrare cu
componentă de proiectare+implementare FL: Cap. 4 și 5 (proiectare,
implementare) domină, Cap. 1 și 7 (introducere, concluzii) sunt scurte.

### Dacă vrei mai aproape de exact 40 de pagini

Cele mai ieftine reduceri, fără să sacrifice conținut central (toate sunt deja
marcate "opțional" în `structureRO.md`):
- Renunță la tabelele opționale din 3.5.1/3.5.2 (rămân text) -> -~0.8 pagini.
- Fără schiță la 4.7 (te bazezi pe captura din 5.1.6) -> -~0.2 pagini.
- Fără tabel opțional la 2.4 și 7.1 -> -~0.5 pagini.
- 6.3 cu 2 paragrafe, fără figură nouă (dacă `stats.json` nu are date) ->
  -~0.3 pagini.

Total reducere posibilă: ~1.8 pagini -> ~40.8 pagini, fără a elimina nimic din
conținutul "obligatoriu" (figurile/tabelele/listingurile primare rămân toate).
