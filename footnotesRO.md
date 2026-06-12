# Note de subsol

Candidați de note de subsol per capitol/secțiune/subsecțiune, în aceeași
ordine ca `structureRO.md`. O notă de subsol se folosește pentru un link mai
puțin semnificativ, referit o singură dată (ex. documentație tehnică
oficială). Dacă o sursă e citată de mai multe ori sau e centrală pentru
argumentare, ea aparține bibliografiei din `structureRO.md`, nu aici (vezi
distincția din `thesis_writing_conventions.md`).

## Format
`\footnote{Descriere scurtă a ce reprezintă link-ul. \url{https://...}
(accesat ZZ.LL.AAAA).}` - data accesării se completează cu data reală la care
secțiunea respectivă e scrisă/verificată, nu cu o dată fixă dinainte.

---

## Capitolul 1 - Introducere
Nicio notă de subsol anticipată. 1.1 se bazează pe referințe bibliografice
(citate de mai multe ori / centrale pentru argumentare - vezi auditul de
bibliografie), nu pe linkuri punctuale. Dacă, la redactare, apare o singură
sursă web pentru "apariția aplicațiilor mobile bazate pe locație" care nu
merită o intrare în bibliografie, poate deveni notă de subsol aici.

## Capitolul 2 - Analiza Cerințelor / Motivație
Nicio notă de subsol anticipată - conținut specific proiectului.

## Capitolul 3 - Studiu de Piață / Soluții Existente
- **3.1 Aplicații existente pentru explorare urbană** - paginile oficiale de
  funcționalități/confidențialitate ale aplicațiilor menționate, ca dovadă
  pentru afirmațiile despre modul lor de personalizare/colectare a datelor:
  - Google Maps - pagina despre recomandările personalizate ("Pentru tine")
    și/sau politica de confidențialitate Google (verifică URL-ul exact și
    adaugă data accesării).
  - TripAdvisor - pagina despre cum funcționează recomandările/politica de
    confidențialitate (verifică URL-ul exact și adaugă data accesării).
  - Notă: acestea acoperă și lacuna 1.1/3.1 identificată în auditul de
    bibliografie - sunt dovada citată pentru "personalizarea presupune
    încărcarea istoricului pe server".
- **3.2 Analiză comparativă centralizat vs. FL** - "filtrarea
  colaborativă/bazată pe conținut" e mai probabil o lacună de
  **bibliografie** (concept central, posibil reluat în 3.1) decât o notă de
  subsol - vezi auditul. Notă de subsol doar dacă rămâne o mențiune
  tangențială, o singură dată.
- **3.3 FL: Stadiul actual** - dacă se include o diagramă adaptată din Yang et
  al. 2019 (taxonomia HFL/VFL/FTL) sau Kairouz et al. 2021, sursa imaginii e
  deja acoperită de citarea bibliografică existentă - nu e nevoie de notă de
  subsol separată, dar menționează explicit "Adaptat din [N]" în caption.
- **3.5.1 Flutter și Riverpod** - documentația oficială:
  - Flutter - https://flutter.dev (accesat ZZ.LL.AAAA)
  - Riverpod - https://riverpod.dev (accesat ZZ.LL.AAAA)
  - (opțional, pentru comparație) React Native - https://reactnative.dev
    (accesat ZZ.LL.AAAA)
- **3.5.2 FastAPI, MongoDB și Redis** - documentația oficială:
  - FastAPI - https://fastapi.tiangolo.com (accesat ZZ.LL.AAAA)
  - MongoDB - https://www.mongodb.com/docs/ (accesat ZZ.LL.AAAA)
  - Redis - https://redis.io/docs/ (accesat ZZ.LL.AAAA)
- **3.5.3 Motorul de Rutare OSRM** - https://project-osrm.org (accesat
  ZZ.LL.AAAA)
- **3.5.4 MLP propriu vs. TFLite/PyTorch Mobile** - documentația oficială
  pentru alternativele comparate:
  - TensorFlow Lite - https://www.tensorflow.org/lite (accesat ZZ.LL.AAAA)
  - PyTorch Mobile - https://pytorch.org/mobile/home/ (accesat ZZ.LL.AAAA;
    verifică dacă pagina e încă activă - PyTorch Mobile e parțial înlocuit de
    ExecuTorch în versiunile recente)

## Capitolul 4 - Soluția Propusă
- **4.7 Hartă și navigare** - dacă geofencing-ul se bazează pe un pachet
  Flutter specific (ex. `geolocator`, `flutter_compass`), pagina pachetului
  de pe pub.dev poate fi notă de subsol la prima menționare (verifică
  pachetul efectiv din `pubspec.yaml` și adaugă URL + data accesării). Dacă
  pachetul e deja footnote-uit în 5.1.6, nu se repetă aici.
- Restul secțiunilor (4.1-4.6, 4.8) - conținut specific proiectului sau deja
  acoperit de bibliografie (4.4, 4.8); nicio notă de subsol anticipată.

## Capitolul 5 - Detalii de Implementare
- **5.1.2 Adăugarea de zgomot pentru DP (transformata Box-Muller)** - dacă
  transformata e explicată în detaliu, o sursă matematică ne-Wikipedia (ex.
  Wolfram MathWorld sau un curs/manual de statistică) poate susține
  descrierea ca notă de subsol; alternativ, citarea originală Box & Muller
  (1958) ca referință bibliografică, dacă se discută pe larg.
- **5.1.3 Bufferul local de interacțiuni (SharedPreferences)** -
  https://pub.dev/packages/shared_preferences (accesat ZZ.LL.AAAA)
- **5.1.6 Sistemul de misiuni și geofencing** - pachetul Flutter folosit
  pentru geofencing/locație (ex. `geolocator`) - pagina pub.dev, cu URL + data
  accesării (verifică pachetul efectiv din `pubspec.yaml`).
- **5.2.3 Sistemul de recenzii și moderarea conținutului** - OpenAI Moderation
  API - https://platform.openai.com/docs/guides/moderation (accesat
  ZZ.LL.AAAA); folosită o singură dată, candidat clar de notă de subsol.
- **5.3 Fluxul etapei de pre-antrenare** - seturile de date au deja referințe
  bibliografice (TSMC2014/TIST2015/ubicomp2013/Yelp); dacă se leagă explicit
  și pagina/licența de descărcare (ex. pagina Yelp Open Dataset), aceasta
  poate fi notă de subsol separată, complementară citării academice (verifică
  URL + data accesării).
- **5.1.1, 5.1.4, 5.1.5, 5.2.1, 5.2.2, 5.4, 5.5** - conținut specific
  proiectului sau deja acoperit de bibliografie; nicio notă de subsol
  anticipată. (5.5 "regresia către medie" - concept statistic consacrat,
  similar cu Box-Muller la 5.1.2 dacă se dorește o sursă ne-Wikipedia.)

## Capitolul 6 - Evaluare
Nicio notă de subsol anticipată - secțiuni de rezultate proprii; "problema
clienților întârziați" (straggler problem, 6.4) e acoperită de referințe
bibliografice (vezi auditul).

## Capitolul 7 - Concluzii
Nicio notă de subsol anticipată - FedPer/FedBuff/SecAgg (7.2) au deja
referințe bibliografice.

## Anexe
Nicio notă de subsol anticipată.
