# Discurs prezentare — CultureQuest (~8 minute)

---

## [Slide 1 — Titlu] (~15s)

Bună ziua. Mă numesc Andrei Cozma și vă prezint CultureQuest, o platformă mobilă de explorare urbană cu recomandări personalizate prin învățare federată.

---

## [Slide 2 — Motivație] (~55s)

Aplicațiile de tip city-guide de astăzi funcționează în una din două moduri: fie oferă aceleași recomandări tuturor, indiferent de interese, fie personalizează, dar cu prețul colectării centralizate a datelor. GPS-ul, obiectivele vizitate, orele de activitate — ajung pe un server și formează un profil detaliat al fiecărui utilizator. Problema e că utilizatorul nu are de ales: ori acceptă să fie urmărit, ori renunță la personalizare.

Există și un efect secundar mai puțin vizibil: fără personalizare reală, recomandările se bazează pe popularitate. Obiectivele deja populare sunt recomandate tot mai mult, ceea ce amplifică aglomerarea și lasă locurile mai puțin cunoscute complet ignorate.

Propunerea mea e că confidențialitatea și personalizarea nu se exclud — soluția e să antrenăm modelul local, direct pe dispozitivul utilizatorului.

---

## [Slide 3 — State of the art] (~55s)

Dacă ne uităm la ce există deja: Google Maps și TripAdvisor personalizează, dar centralizat. izi.TRAVEL și GetYourGuide oferă rute fixe, fără nicio adaptare la utilizator. Niciuna nu combină rute generate dinamic cu privacy by design.

Pe partea de Federated Learning în sisteme de recomandare: FedAvg e algoritmul standard, dar cere ca toți clienții dintr-o rundă să fie disponibili simultan — o constrângere greu de îndeplinit pe telefoane mobile cu conectivitate intermitentă. FedAsync rezolvă asta printr-un model asincron. NbAFL adaugă confidențialitate diferențială prin zgomot Gaussian.

Golul pe care îl adresez e aplicarea FL asincron cu DP la turism cultural — o combinație neabordată în literatură.

---

## [Slide 4 — Soluție propusă] (~40s)

CultureQuest integrează patru componente: obiective culturale pe hartă, quest-uri activate prin geofencing la mai puțin de 100 de metri de un obiectiv, rute generate dinamic și personalizate prin FL, și o componentă comunitară cu recenzii, povești și propuneri de obiective noi.

Principiul fundamental e privacy by design: interesele utilizatorului sunt deduse din interacțiunile locale, fără ca datele să părăsească niciodată dispozitivul.

---

## [Slide 5 — Arhitectura sistemului] (~45s)

Sistemul are patru straturi: aplicația Flutter care rulează pe Android și iOS dintr-o singură bază de cod Dart, un backend FastAPI în Python, MongoDB pentru date persistente și Redis pentru starea FL. Rutarea reală a traseelor e asigurată de OSRM.

Există trei fluxuri principale: harta și rutele, unde obiectivele din MongoDB sunt evaluate prin modelul stocat în Redis; agregarea FL, unde delta de ponderi de la client actualizează modelul global; și componenta comunitară, cu moderare a conținutului propus de utilizatori.

---

## [Slide 6 — Modelul de personalizare] (~65s)

Nucleul personalizării e un MLP cu 1.281 de parametri și arhitectura 22 → 32 → 16 → 1. Cele 22 de intrări sunt împărțite în patru grupe: interesele utilizatorului ca vectori one-hot pe 6 categorii, tipul obiectivului pe 8 categorii, trei caracteristici temporale — dacă obiectivul e deschis, dacă e weekend și ora normalizată — și cinci caracteristici spațiale care includ rangul de distanță față de ceilalți candidați, potrivirea cu interesele și contextul poziției în rută.

Ieșirea e un scor între 0 și 1 care alimentează categoria de potrivire afișată în fișa obiectivului: scăzut sub 0,4, mediu, ridicat peste 0,7. Modelul rulează atât pe server la generarea rutei, cât și pe dispozitiv pentru afișarea scorului în timp real. Latența de inferență e de aproximativ 39 de microsecunde.

---

## [Slide 7 — Generarea rutelor] (~50s)

Algoritmul de generare rulează pe server în cinci pași. Mai întâi colectează candidații în raza de 10 km. Îi scorează combinând 80% scor MLP cu 20% proximitate față de start și păstrează top 10. Construiește traseul greedy: la fiecare pas alege obiectivul cu cost minim, unde costul e distanța curentă minus un factor lambda înmulțit cu potrivirea de interese. Lambda e configurat de utilizator și controlează cât de mult contează personalizarea față de distanță. Scalează durata per oprire plus-minus 25% în funcție de scorul MLP. În final, OSRM calculează traseul real pe jos sau cu mașina.

---

## [Slide 8 — Pre-antrenarea] (~55s)

La prima utilizare a aplicației, niciun dispozitiv nu a contribuit încă la modelul global — asta e problema cold-start. Am pre-antrenat modelul pe 741.000 de înregistrări din Foursquare și Yelp pentru a oferi recomandări utile de la bun început.

Problema a apărut după pre-antrenare: modelul prezice aproape exclusiv valori între 0,595 și 0,850, indiferent de input. Cauza e dublă: seturile reale conțin numai obiective deschise, deci caracteristica isOpen=0 nu apare niciodată în antrenare, iar recenziile Yelp sunt 60% de 4-5 stele, deci etichetele sunt concentrate spre valori mari.

Fine-tuning-ul a rezolvat ambele probleme: am adăugat 16.000 de exemple sintetice cu isOpen=0 și am suprareprezent de trei ori înregistrările cu scor sub 0,4. Rezultatul: intervalul de predicție s-a lărgit cu 211%.

---

## [Slide 9 — Antrenare locală] (~55s)

Pe dispozitiv, fiecare interacțiune cu un obiectiv generează o etichetă de engagement: deschiderea fișei obiectivului dă 0,3, adăugarea la rută 0,5, navigația pornită 0,6, completarea unui quest 0,9, iar rating-ul explicit e direct stele împărțit la 5.

Aceste interacțiuni se acumulează într-un buffer persistat local în SharedPreferences. La 15 interacțiuni, antrenarea se declanșează automat: 5 epoci de SGD cu rata de învățare 0,01 și clipping de gradient L2 pentru stabilitate. La final, clientul trimite pe server doar delta ponderilor față de modelul global — nu interacțiunile brute.

---

## [Slide 10 — Agregare asincronă, concurență și confidențialitate] (~60s)

Agregarea pe server e asincronă. Delta primită de la client e ponderată cu factorul 1 asupra 1 plus staleness: dacă un client a antrenat pe un model cu două runde în urmă, contribuția lui are impact mai mic decât a unui client cu modelul la zi.

Concurența e gestionată printr-un lock Redis cu SET NX PX — garantează că un singur client se află în ciclul read-aggregate-write la un moment dat, cu TTL de 5 secunde în caz de crash.

Confidențialitatea diferențială e implementată prin NbAFL: pe client, delta e clampată per coordonată în intervalul [-1, +1] și se adaugă zgomot Gaussian cu sigma 0,1 — astfel serverul primește ponderi perturbate din care delta reală nu poate fi reconstituită. Pe server, delta mai e clippată și la norma L2 mai mică sau egală cu 1 pentru robustețe față de actualizări extreme.

---

## [Slide 11 — Evaluare] (~50s)

Am evaluat pe trei axe. Corectitudinea funcțională a fost verificată printr-un demo complet — toate cele șapte cerințe funcționale sunt implementate, inclusiv teste unitare pentru modelul FL.

Performanța FL: simulare cu 10.000 de clienți sintetici pe 600 de runde la aproximativ 23 de milisecunde per rundă. FedAsync cu discount de staleness reduce pierderea BCE finală cu 30,9%, față de 27,2% în varianta fără discount — confirmând că ignorarea vechimii actualizărilor afectează convergența.

Scalabilitate: zero erori la maximum 10 cereri FL simultane; degradare la 20 din cauza timeout-ului lock-ului Redis.

---

## [Slide 12 — Probe scores] (~20s)

Graficul arată scorurile pentru perechi potrivite și nepotrivite de interes utilizator și tip obiectiv după 600 de runde. Se observă că modelul separă clar obiectivele relevante de cele irelevante pentru un utilizator dat.

---

## [Slide 13 — Limitări] (~30s)

Principalele limitări: validarea a fost pe clienți sintetici, nu pe date reale de producție; geofencing-ul funcționează numai în foreground din cauza limitărilor GPS pe mobil; lock-ul Redis cedează la concurență mai mare de 10 cereri simultane; și personalizarea per utilizator prin FedPer nu a fost implementată.

---

## [Slide 14 — Concluzii] (~30s)

CultureQuest demonstrează că personalizarea bazată pe FL și confidențialitatea datelor nu se exclud, chiar și în limitele unui proiect academic. Am construit un flux FL complet end-to-end, de la pre-antrenare la agregare asincronă cu DP, cu o aplicație mobilă funcțională pe ambele platforme.

Ca direcții viitoare: validare pe utilizatori reali, FedPer pentru straturi personalizate per utilizator, și FedBuff ca alternativă scalabilă la lock-ul Redis.

Vă mulțumesc. Sunt disponibil pentru întrebări.

---

*Total estimat: ~8 minute la ritm normal de prezentare.*
