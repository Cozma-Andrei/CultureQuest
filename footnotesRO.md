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
- **1.1** - Business of Apps, *Travel App Report 2025* (pentru statistica "850
  de milioane de utilizatori de aplicații de călătorit în 2023").
  \url{https://www.businessofapps.com/data/travel-app-report/} (accesat 19.06.2026)

## Capitolul 2 - Analiza Cerințelor / Motivație
Nicio notă de subsol anticipată - conținut specific proiectului.

## Capitolul 3 - Studiu de Piață / Soluții Existente
- **3.1 Aplicații existente pentru explorare urbană** - paginile oficiale de
  funcționalități/confidențialitate ale aplicațiilor menționate:
  - Google Maps - \url{https://support.google.com/websearch/answer/17025248?hl=en} (accesat 19.06.2026)
  - TripAdvisor - \url{https://tripadvisor.mediaroom.com/US-privacy-policy} (accesat 19.06.2026)
  - GetYourGuide - \url{https://www.getyourguide.com/c/privacy-policy} (accesat 19.06.2026)
  - izi.TRAVEL - pagina oficială. \url{https://izi.travel/} (accesat 19.06.2026)
  - Geocaching (Groundspeak Inc.) - termeni și politică de confidențialitate.
    \url{https://www.geocaching.com/account/documents/privacypolicy} (accesat 19.06.2026)
  - Organic Maps - "no tracking, no data collection".
    \url{https://organicmaps.app/privacy/} (accesat 19.06.2026)
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
  - Flutter - \url{https://flutter.dev} (accesat 19.06.2026)
  - Riverpod - \url{https://riverpod.dev} (accesat 19.06.2026)
  - Flutter performanță/compilare nativă ARM - \url{https://docs.flutter.dev/perf} (accesat 19.06.2026)
- **3.5.2 FastAPI, MongoDB și Redis** - documentația oficială:
  - FastAPI - \url{https://fastapi.tiangolo.com} (accesat 19.06.2026)
  - MongoDB - \url{https://www.mongodb.com/docs/} (accesat 19.06.2026)
  - Redis - \url{https://redis.io/docs/} (accesat 19.06.2026)
  - FastAPI async - \url{https://fastapi.tiangolo.com/async/} (accesat 19.06.2026)
- **3.5.3 Motorul de Rutare OSRM** - documentația oficială și surse suplimentare:
  - OSRM - \url{https://project-osrm.org} (accesat 19.06.2026)
  - Google Maps Directions API pricing (pentru comparația "facturează per cerere") -
    \url{https://developers.google.com/maps/documentation/directions/usage-and-billing} (accesat 19.06.2026)
  - Luxen, D., \& Vetter, C. (2011). Real-time routing with OpenStreetMap data.
    \textit{Proceedings of the 19th ACM SIGSPATIAL}.
    \url{https://doi.org/10.1145/2093973.2094062} (pentru afirmația de performanță OSRM)
- **3.5.4 MLP propriu vs. TFLite/PyTorch Mobile** - documentația oficială:
  - TensorFlow Lite - \url{https://www.tensorflow.org/lite} (accesat 19.06.2026)
  - TFLite binary size (~1,3 MB APK arm64) - \url{https://www.tensorflow.org/lite/guide/reduce_binary_size} (accesat 19.06.2026)
  - PyTorch Mobile/ExecuTorch (~30 MB) - \url{https://docs.pytorch.org/executorch/stable/index.html} (accesat 19.06.2026);
    pagina veche PyTorch Mobile: \url{https://pytorch.org/mobile/home/} (parțial înlocuit de ExecuTorch)

## Capitolul 4 - Soluția Propusă
- **4.7 Hartă și navigare** - ambele pachete sunt footnote-uite direct în tex:
  - `geolocator` - \url{https://pub.dev/packages/geolocator} (accesat 19.06.2026)
  - `flutter_compass` - \url{https://pub.dev/packages/flutter_compass} (accesat 19.06.2026)
  Nu se repetă în 5.1.6.
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
Nicio notă de subsol anticipată - FedPer/FedBuff (7.2) au deja
referințe bibliografice.

## Anexe
Nicio notă de subsol anticipată.
