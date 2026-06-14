# Convenții de redactare a tezei

Reguli de formatare/citare/structură de tip "facultate" pentru teza
CultureQuest. Unele reguli pot fi exagerate pentru acest caz, dar sunt ținute
minte ca implicite/tipare la redactarea sau revizuirea conținutului de teză.
Aplică-le cu discernământ, nu ca mandate absolute.

Regulile au fost date inițial cu exemple în engleză, dar teza este scrisă în
română (vezi `style_romanian.md`) - echivalentele românești sunt notate mai
jos unde contează.

## Ordinea capitolelor
Scrie capitolul de Introducere ultimul, după ce restul tezei e scris - nu ca
punct de plecare.

## Vocea: activă, nu pasivă
Descrie deciziile/acțiunile la diateza activă: "am ales/am proiectat/am
implementat/am analizat/am evaluat". Evită pasivul ("a fost proiectat X") -
sună deresponsabilizant (nimeni nu își asumă decizia).

Notă: aceasta privește *descrierea a ceea ce s-a făcut*, distinct de
formulările de opinie la persoana I "Cred că/Consider că" din
`style_romanian.md` - acelea sunt pentru *recomandări/discuții* (5.5, 6.4,
7.2), în timp ce vocea "am făcut X" e pentru metodologie/implementare/
rezultate (cap. 4-6). Ambele sunt la persoana I, dar sunt acte de vorbire
diferite; coexistă în secțiuni diferite.

## Evită formulările informale
Nu "putem vedea în imagine", "vom trece la capitolul următor". În loc de asta:
"Figura de mai sus prezintă...", "Figura X ilustrează...".

## Evită formulările generice de încadrare
Nu "Această lucrare își propune să...", "În această lucrare dorim să...".
Spune direct ce s-a făcut.

## Acronime
Extinde la prima utilizare: "FL (Federated Learning)", "DP (Differential
Privacy)", "MLP (Multi-Layer Perceptron)" etc. CultureQuest are multe dintre
acestea (FL, DP, MLP, API, SGD, LDP, NbAFL, MSE, R², HFL/VFL/FTL, SecAgg) -
urmărește punctul primei utilizări per capitol la redactare.

Tiparul de glosare confirmat în `diploma-project-template.tex` (3.2, 3.5.3,
3.5.4, 4.4.5) e unic, indiferent dacă termenul românesc e "consacrat" sau nu:
termenul românesc primul, apoi (ABREVIERE, Termen englezesc în \textit{})
într-o singură paranteză - "Termen românesc (ABREVIERE, Termen englezesc)".
Exemple din `.tex`:
- "învățarea federată (FL, \textit{Federated Learning})"
- "Perceptron multi-strat (MLP, \textit{Multi-Layer Perceptron})"
- "Confidențialitate diferențială (DP, \textit{Differential Privacy})"
- caz particular OSRM (abrevierea e deja parte din numele românesc, fără
  ABREVIERE separată în paranteză): "Motorul de Rutare OSRM
  (\textit{Open Source Routing Machine})"

Evită stivuirea a două paranteze separate. După prima glosare completă,
folosește abrevierea simplă ("FL", "DP", "MLP").

## Citări
- Plasează citarea inline lângă afirmația la care se referă: "FedAvg [1]
  calculează o medie ponderată...", nu "așa cum este menționat în [12]".
- Afirmațiile despre scară/importanță ("sunt numeroase", "au crescut
  exponențial", "sunt printre cele mai folosite", "sunt un subiect
  important") trebuie susținute de citări, date concrete și analize
  comparative - relevant pentru afirmațiile de tip Context din 1.1 (creșterea
  aplicațiilor bazate pe locație, adopția FL etc.).
- Mai ales în capitolele de tip introducere/"stadiul actual"/"related
  work"/"background" (cap. 1 și 3 pentru CultureQuest), argumentează prin
  citări - fii autocritic și gândește-te dacă o afirmație are nevoie de
  citare, chiar și cele care par evidente. Cea mai mare parte a citărilor se
  vor concentra în aceste capitole.
- Toate intrările bibliografice trebuie citate în text, nu doar listate la
  final.
- Nu copia/traduce niciodată mai mult de o propoziție dintr-o sursă. Dacă o
  propoziție merită păstrată ad litteram, citează-o între ghilimele și indică
  sursa.
- Ideile parafrazate au nevoie tot de o citare/notă de subsol către sursă.
- Fără "mai multe detalii aici [1]" - referința stă în propoziția despre ideea
  respectivă.
- Fără referințe la Wikipedia sau alte surse fără autor asumat.
- Pentru referințe web (linkuri), notează și data accesării.

## Note de subsol vs. referințe bibliografice
- **Notă de subsol** - link mai puțin semnificativ, referit o singură dată
  (ex. documentația oficială Flutter/FastAPI/MongoDB/Redis/OSRM, OpenAI
  Moderation API); include și data accesării. Candidați listați în
  `footnotesRO.md`.
- **Referință bibliografică** - sursă citată de mai multe ori, sau articol/
  dataset relevant pentru argumentare (tabelele din `structureRO.md`).
- **Imagini/figuri/tabele nerealizate de Andrei** - trebuie citată sursa;
  preferabil ca notă de subsol.

## Stil de citare
Stil ales: **APA** (bibme.org/citation-guide/apa/) - pentru formatul
intrărilor bibliografice (Autor, A. (An). Titlu. Sursă.), inclusiv pentru
sursele web/notele de subsol (formatul APA pentru website include data
accesării). Marcatorii din text rămân numerotați "[1]", "[12]" etc., conform
`\bibliographystyle{plain}` deja configurat în `diploma-project-template.tex`
(stil alfabetic-numerotat, gen ACM).

## Caption-uri
Toate figurile, tabelele și listările de cod au caption - obligatoriu, nu
opțional. Caption-urile sunt centrate în text. Pentru cod: "Listing N:
<descriere>" dedesubt (pachetul `listings`); pentru figuri/tabele, caption
standard LaTeX (`\caption{}`, centrat implicit pentru `figure`/`table`).

## Figuri
Folosește figuri/diagrame/tabele oriunde e posibil. Preferă formate vectoriale
(PDF/EPS/SVG) în locul celor raster; dacă raster, PNG (fără pierderi) în locul
JPEG (cu pierderi), rezoluție minimă 600 DPI - suficient de mare cât să fie
lizibilă, fără să fie neclară. O figură nu ar trebui să ocupe niciodată o
pagină întreagă - maxim 1/3-1/2 din pagină, restul fiind folosit pentru
explicație.

Fiecare figură se referă explicit în text ("Figura X ilustrează/prezintă...")
și se explică ce reprezintă - nu se lasă să "vorbească de la sine" cu o
mențiune vagă ("vezi figura de mai jos").

Diagramele de flux au săgețile numerotate (1, 2, 3...) pentru a indica ordinea
pașilor.

Relevant pentru CultureQuest: diagrame de arhitectură (4.1-4.3), grafice de
loss/drift/staleness (6.2.2), capturi de ecran din aplicație (5.1, 6.1).

## Listări de cod
Cât mai puține - un listing justifică o DECIZIE de proiectare/implementare, nu
explică cod de dragul explicației. Dacă un fragment nu argumentează o alegere
concretă, nu merită un listing dedicat (poate rămâne text sau o formulă).

15-30 de linii, numerotate, font monospace, încadrate sau cu fundal gri
deschis. Explică rolul fragmentului și evidențiază liniile importante - același
tratament ca pentru o figură (nu doar lipit și mers mai departe). Relevant
pentru câteva listinguri punctuale din 4.4/5.1/5.2 care justifică o decizie
(ex. `clipped_fedavg` pentru limitarea actualizărilor, zgomotul DP adăugat
client-side) și pentru fragmentele extinse din Anexe (forward/backprop complet
pentru clientul FL).

## Tabele și unități
Folosește unități la scară umană: "0.1s, 1s, 10s" nu "100ms, 1000ms, 10000ms".
LaTeX: `booktabs` pentru tabele, `listings` pentru cod.

## Anexe
Conțin elemente care ocupă mai mult de o pagină și ar întrerupe firul textului
dacă ar fi inline: diagrame complete/detaliate (ex. `db.svg` cu toate
colecțiile și câmpurile - în text rămâne doar o variantă simplificată, la nivel
înalt), fragmente de cod extinse (ex. `_trainLocally` complet), tabele mari,
seturi de capturi de ecran suplimentare, grafice complete de simulare (din
`backend/federated/results/` și `backend/pretraining/output/charts/`), fișiere
de configurare/build de exemplu.

## Încadrarea capitolelor
Niciodată o secțiune imediat după titlul unui capitol. Fiecare capitol începe
cu un paragraf scurt de prezentare (ce conține capitolul, de ce, ca
succesiunea secțiunilor să nu fie o surpriză) și se închide cu un rezumat a
ceea ce a fost prezentat și relevanța acestuia - ideal făcând legătura cu
capitolul următor.
