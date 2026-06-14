# Stilul de scris al lui Andrei (Română)

Acest document descrie stilul în care Andrei scrie în limba română, pentru a
fi imitat la redactarea paragrafelor de teză (`structureRO.md`,
`bibliography_sourcesRO.md`, capitolele din `diploma-project-template.tex`).
Stilul combină un ton personal-reflexiv cu argumentare structurată: propoziții
compuse lungi, construite din clauze relative înlănțuite, markeri frecvenți de
opinie la persoana I și un tipar recurent problemă -> recomandare. Nu e nevoie
de o potrivire exactă, ci de o imitație rezonabilă - vezi și
`thesis_writing_conventions.md` pentru regulile formale de teză care se aplică
peste acest stil.

## Vocabular tehnic vs. stil
Tiparele din acest document privesc doar structura propozițiilor, conectorii
și formulările - nu vocabularul. `Plan_Managerial_Evrika.txt` e un document
non-tehnic; termenii tehnici (FedAvg, MLP, staleness, DP, FedAsync etc.) vin
mereu din sursele proiectului (`structureRO.md`, `FL.md`, bibliografie), nu
din registrul sursei de stil.

## Abordarea traducerii: evitarea "mot-a-mot"
Când traduci material sursă în engleză (de ex. idei/rezumate din articolele
din Bibliografie, sau \AbstractEN -> \AbstractRO) în română, evită traducerile
literale/calc. Înlocuiește expresiile, conectorii sau formulările cu variante
care sună mai natural în română, chiar dacă nu corespund cuvânt cu cuvânt
originalului. Fidelitatea față de sens contează mai mult decât fidelitatea
față de forma propoziției.

## Structura propozițiilor
- Propoziții lungi formate prin înlănțuirea clauzelor relative/subordonate:
  "...unde...", "...pe care...", "...de la care...", "...ceea ce...". Exemplu:
  "Fac parte din LSAC și din departamentul de IT încă din anul 1, două locuri
  unde am descoperit oameni faini, pe care i-am admirat pentru dorința lor de
  implicare și de la care am avut mereu ce învăța."
- "ceea ce" înlănțuie o consecință de clauza anterioară: "ceea ce a permis
  ca...", "ceea ce conduce inevitabil la...", "ceea ce recomand și
  următoarei echipe...".
- Topicalizare ocazională pentru accent: "Ce este cert, ...", "Ce a fost
  important este că ...".
- Liste redate ca proză (separate prin virgulă în interiorul unei propoziții),
  nu ca bullet-uri: "...precum cele din domeniul IT, escape room-uri, muzee,
  restaurante și cafenele etc."

## Conectori de început de paragraf (foarte frecvenți)
Așadar, Astfel, Prin urmare, De aceea, Totodată, Mai mult, În plus,
Bineînțeles, Din păcate, Pe de altă parte, Însă. Aceștia deschid majoritatea
paragrafelor și leagă ideile consecutive aditiv sau cauzal.

## Markeri de opinie/recomandare
"Cred că ...", "Consider că ...", "Am observat că ..." - aproape mereu la
începutul propoziției, folosiți pentru a trece de la descriere la o judecată
personală sau o recomandare.

## Tiparul recurent problemă -> recomandare
Fiecare secțiune de "aspect negativ" urmează: (1) descrie ce s-a întâmplat/
problema, la perfect compus ("a fost", "am încercat", "nu au fost
respectate"), apoi (2) "Cred că ..." / "Am putea ..." / "O soluție ar fi ..."
propunând o soluție la conditional ("ar fi", "ar putea", "ar trebui", "ar
rezulta", "ar ajuta"). Acest tipar se mapează direct pe secțiunile de teză
"Limitări" / "Probleme întâmpinate în implementare" (`structureRO.md` 5.5) și
"Lucrări viitoare" (7.2) - oglindește această structură în doi timpi acolo.

## Hedging / atenuare
"poate", "oarecum", "este posibil să", "anumite", "câteva", "într-un fel",
"este puțin spus că". Afirmațiile sunt rareori formulate ca absoluturi
directe - sunt atenuate cu unul dintre acești termeni.

## Numere precise țesute în text
Cifre exacte date inline, deseori marcate cu "mai exact": "14 mai exact",
"mai exact formatul gândit fiind de 24 de echipe...". Se potrivește bine
secțiunilor de evaluare a tezei (6.2/6.3) care raportează metrici concrete
(valori de loss, îmbunătățiri procentuale, număr de runde).

## Inserții parantetice
Inserții (...) frecvente pentru un exemplu clarificator sau o digresiune
colocvială/idiomatică, de ex. "(Gastronomia)", "(un exemplu la care mă gândesc
este categoria de gramatică)", "(steagurile medievale au fost cireașa de pe
tort)".

## Note de registru pentru teză
Documentul sursă (`Plan_Managerial_Evrika.txt`) este un raport personal
semi-formal - nu toate tiparele se transferă ca atare. Potrivește tiparul cu
tipul secțiunii:

- **Secțiuni reflexive/de discuție** (Concluzii 7.1, Limitări/Probleme
  întâmpinate 5.5, Lucrări viitoare 7.2, Comparație și discuții 6.4): stilul
  complet se transferă bine - formulările "Cred că"/"Consider că", hedging-ul
  ("poate", "este posibil să", "într-un fel") și tiparul problemă ->
  recomandare (perfect compus -> conditional) sunt toate naturale aici.
- **Secțiuni tehnice/obiective** (Implementare cap. 5, Arhitectură cap. 4,
  Rezultate 6.1-6.3): elimină formulările subiective la persoana I și
  hedging-ul - preferă construcții impersonale/obiective și afirmații
  susținute direct de date (de ex. "rezultatele arată o reducere de 30.87%"
  în loc de "cred că rezultatele sunt mai bune"). Păstrează: conectorii de
  paragraf (Așadar, Astfel, Totodată etc.), obiceiul numerelor precise cu "mai
  exact" și clarificările parentetice.
- **Lungimea propozițiilor**: cele mai lungi propoziții din documentul sursă
  (4+ clauze relative înlănțuite) sunt potrivite pentru proză
  narativă/reflexivă, dar pot afecta claritatea în secțiunile tehnice -
  moderează înlănțuirea acolo, chiar dacă e caracteristică vocii lui Andrei
  în alte secțiuni.
- **Elimină peste tot**: cuvintele colocviale/afective ("omuleți", "oameni
  faini") și idiomurile ("cireașa de pe tort") - potrivite pentru un raport
  personal, nu pentru o teză, în nicio secțiune.
- Distincția de mod verbal (se transferă peste tot): perfect compus pentru ce
  s-a făcut/observat/implementat, conditional pentru recomandări, ipoteze și
  lucrări viitoare.
