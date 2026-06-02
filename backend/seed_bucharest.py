#!/usr/bin/env python3
"""
Comprehensive Bucharest seed script.
Run from inside the backend container:
    docker exec culturequest_backend python /app/seed_bucharest.py
"""
import random
import math
import json
from datetime import datetime, timedelta
from bson import ObjectId
import bcrypt
from pymongo import MongoClient, GEOSPHERE

random.seed(42)

MONGO_URI = "mongodb://admin:secret@mongodb:27017/culturequest?authSource=admin"
client = MongoClient(MONGO_URI)
db = client["culturequest"]


def hpw(pw: str) -> str:
    return bcrypt.hashpw(pw.encode(), bcrypt.gensalt()).decode()


def haversine(lat1, lng1, lat2, lng2) -> float:
    R = 6_371_000
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lng2 - lng1)
    a = math.sin(dp/2)**2 + math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
    return 2 * R * math.asin(math.sqrt(a))


# ── Users ──────────────────────────────────────────────────────────────────────
USERS_DATA = [
    dict(name="Maria Popescu",     email="maria@example.com",   interests=["art","architecture","history"],    pw="pass1234"),
    dict(name="Andrei Constantin", email="andrei@example.com",  interests=["history","gastronomy"],            pw="pass1234"),
    dict(name="Elena Ionescu",     email="elena@example.com",   interests=["art","music"],                     pw="pass1234"),
    dict(name="Mihai Dumitrescu",  email="mihai@example.com",   interests=["architecture","nature"],           pw="pass1234"),
    dict(name="Ana Gheorghe",      email="ana@example.com",     interests=["nature","gastronomy"],             pw="pass1234"),
    dict(name="Radu Popa",         email="radu@example.com",    interests=["history","architecture","art"],    pw="pass1234"),
    dict(name="Cristina Stan",     email="cristina@example.com",interests=["music","art"],                     pw="pass1234"),
    dict(name="Florin Marin",      email="florin@example.com",  interests=["gastronomy","nature"],             pw="pass1234"),
]

ADMIN_DATA = dict(name="Admin", email="admin@culturequest.ro", pw="admin1234")

# ── 100 Bucharest Landmarks ────────────────────────────────────────────────────
# (name, type, lat, lng, description, [categories], [stories])
RAW_LANDMARKS = [
    # ── Old Town / Centru Vechi ────────────────────────────────────────────────
    ("Romanian Athenaeum",             "building",   44.4411, 26.0973,
     "A stunning concert hall and one of the most beautiful buildings in Romania, inaugurated in 1888.",
     ["architecture","music"], ["Built after a public fundraising campaign, citizens donated under the motto 'Give a penny for the Athenaeum'.", "George Enescu performed here for the first time as a student in 1897."]),
    ("National History Museum",        "museum",     44.4317, 26.0986,
     "Houses Romania's most significant historical artifacts, including a replica of Trajan's Column.",
     ["history","architecture"], ["The building was the headquarters of the Romanian Postal Service before 1970.", "The Treasury holds the Golden Helmet of Coțofenești, a 4th-century Geto-Dacian masterpiece."]),
    ("Stavropoleos Monastery",         "building",   44.4295, 26.0975,
     "A small 18th-century monastery in the heart of Old Town, known for its ornate Brâncovenesc porch.",
     ["architecture","history"], ["Founded in 1724 by a Greek monk, Ioannikios, who came to Bucharest as a merchant.", "The library preserves over 2,000 manuscripts and ancient religious texts."]),
    ("Curtea Veche",                   "museum",     44.4290, 26.1002,
     "Ruins of the Old Princely Court, residence of Vlad the Impaler and other Wallachian rulers.",
     ["history"], ["Vlad III 'the Impaler' (the inspiration for Dracula) ruled from this court in the 15th century.", "Excavations in the 1950s uncovered foundations dating to the 14th century."]),
    ("Hanul lui Manuc",                "restaurant", 44.4300, 26.0988,
     "A historic inn from 1808, one of the oldest functional hospitality venues in Romania.",
     ["gastronomy","history"], ["The Peace of Bucharest was signed here in 1812 after the Russo-Turkish War.", "Originally it had 107 rooms arranged around an open courtyard."]),
    ("CEC Palace",                     "building",   44.4330, 26.0970,
     "An elegant neoclassical-baroque palace built between 1894 and 1900, housing Romania's oldest bank.",
     ["architecture"], ["Designed by French architect Paul Gottereau who also created Bucharest's City Hall.", "The dome was deliberately made slightly smaller than that of the Romanian Athenaeum to preserve its primacy."]),
    ("Cercul Militar Național",        "building",   44.4325, 26.0968,
     "An opulent officers' club with lavish neoclassical interiors, open to the public for events.",
     ["architecture","music"], ["Built between 1911 and 1923, it was damaged by the 1940 earthquake and fully restored."]),
    ("Caru' cu Bere",                  "restaurant", 44.4308, 26.0970,
     "Bucharest's most famous restaurant, opened in 1879 in a Gothic Revival building.",
     ["gastronomy","architecture"], ["The stained-glass windows were crafted by Viennese artisans and shipped specially for the restaurant.", "Owned by the Mirescu family for three generations, it became a cultural landmark before nationalization."]),
    ("Lipscani Street",                "square",     44.4305, 26.0965,
     "The main pedestrian artery of Old Town, named after the Lipsca (Leipzig) merchants who traded here.",
     ["history","gastronomy"], ["In the 17th century, merchants from Vienna, Leipzig and Istanbul all kept shops along this lane."]),
    ("Kretzulescu Church",             "building",   44.4395, 26.0960,
     "A Brâncovenesc-style church built between 1720–22 at the corner of Revolution Square.",
     ["architecture","history"], ["Commissioned by Iordache Creţulescu and his wife Safta Brâncoveanu, daughter of the martyred prince."]),
    ("Revolution Square",              "square",     44.4408, 26.0962,
     "The symbolic heart of the 1989 Romanian Revolution, lined with communist-era and royal-era buildings.",
     ["history"], ["This is where Nicolae Ceaușescu delivered his last speech on 21 December 1989 before fleeing by helicopter.", "The Rebirth Memorial, a controversial spike of steel, stands here to commemorate those who died."]),
    ("National Museum of Art of Romania","museum",   44.4411, 26.0936,
     "Located in the former Royal Palace, it houses European and Romanian fine art masterpieces.",
     ["art","architecture"], ["The Royal Palace was heavily damaged by fire in 1926 and rebuilt in a monumental style.", "The collection includes 70,000 objects from Rembrandt to Grigorescu."]),
    ("University Square",              "square",     44.4375, 26.0985,
     "A major Bucharest intersection known for student protests and urban life.",
     ["history"], ["In 1990, the square was occupied for weeks by students in what became known as the Golaniad."]),
    ("National Theater of Bucharest",  "building",   44.4383, 26.0986,
     "Romania's main theater venue with brutalist architecture, rebuilt after its communist-era demolition.",
     ["architecture","music"], ["The original neoclassical theater was demolished by Ceaușescu in 1984 to make room for the current structure."]),
    ("Suțu Palace",                    "museum",     44.4323, 26.0960,
     "A Gothic-Renaissance palace that is home to the Bucharest City Museum.",
     ["history","architecture"], ["Built in 1834 for the Suțu noble family, it is one of the few surviving pre-modern mansions in the city."]),
    ("Museum of Jewish History",       "museum",     44.4290, 26.1010,
     "Chronicles the 2,000-year history of Jews in Romania with documents, artifacts and photographs.",
     ["history"], ["Romania once had the third-largest Jewish community in Europe; the museum preserves this heritage after the Holocaust."]),
    ("Romanian Academy",               "building",   44.4330, 26.0930,
     "Founded in 1866, the highest scientific forum in Romania, housing a vast library.",
     ["architecture","history"], ["The library holds over 13 million items, including manuscripts by Mihai Eminescu."]),
    ("National Bank of Romania",       "building",   44.4318, 26.0957,
     "The central bank of Romania, housed in a palatial neoclassical building from 1885.",
     ["architecture","history"], ["The vaults deep beneath the building once held Romania's entire gold reserve."]),
    ("Enea Church",                    "building",   44.4299, 26.0951,
     "A modest 17th-century church that survived centuries of fires and earthquakes in Old Town.",
     ["history","architecture"], []),
    ("Gabroveni Inn",                  "gallery",    44.4300, 26.0977,
     "A restored 18th-century inn now serving as a contemporary arts venue and creative hub.",
     ["art","architecture"], ["Named after the Bulgarian merchants from Gabrovo who traded silk here."]),

    # ── Calea Victoriei ────────────────────────────────────────────────────────
    ("George Enescu National Museum",  "museum",     44.4430, 26.0945,
     "The George Enescu Memorial Museum, set in the magnificent Cantacuzino Palace.",
     ["music","architecture","art"], ["The palace was built for Prince Gheorghe Grigore Cantacuzino in 1901-1903.", "Enescu's original Steinway piano and personal manuscripts are preserved in the rooms he occupied."]),
    ("Cantacuzino Palace",             "building",   44.4432, 26.0944,
     "A Beaux-Arts masterpiece on Calea Victoriei, considered one of Bucharest's finest buildings.",
     ["architecture"], ["The iron gates were crafted by Parisian artisans and shipped by train."]),
    ("Ion Mincu University of Architecture","building",44.4334,26.0954,
     "Romania's top architecture school, housed in a handsome early 20th-century building.",
     ["architecture"], []),
    ("Storck Museum",                  "museum",     44.4458, 26.0882,
     "A charming villa turned museum dedicated to the sculptor Frederic Storck and his wife Cecilia.",
     ["art"], ["The sculptor decorated his home with Art Nouveau and Symbolist motifs over three decades."]),
    ("Museum of Romanian Literature",  "museum",     44.4466, 26.0891,
     "Celebrates Romania's literary heritage with manuscripts, first editions and personal effects.",
     ["art","history"], []),
    ("Cantacuzino-Pașcanu House",      "building",   44.4420, 26.0937,
     "A 19th-century aristocratic residence with ornate eclectic façade on Calea Victoriei.",
     ["architecture"], []),
    ("Macca-Villacrosse Passage",      "building",   44.4358, 26.0946,
     "A covered 19th-century arcade with yellow glass ceiling, connecting two streets.",
     ["architecture","gastronomy"], ["Built in 1891, it was modeled on the Parisian covered passages."]),
    ("Pasajul Victoriei",              "building",   44.4365, 26.0952,
     "A bustling commercial passage beneath a historic building on Calea Victoriei.",
     ["architecture","gastronomy"], []),
    ("Telephone Palace (Palatul Telefoanelor)","building",44.4350,26.0940,
     "The first reinforced concrete high-rise in Bucharest, built 1929-1933 in Art Deco style.",
     ["architecture"], ["It survived the 1940 earthquake and WWII bombings largely intact."]),
    ("Calea Victoriei Promenade",      "square",     44.4380, 26.0952,
     "The grand boulevard known as 'Victory Avenue', the main promenade of Bucharest since 1692.",
     ["history","architecture"], ["Originally a dirt road through forests, it was paved with oak blocks in 1692 by order of Prince Constantin Brâncoveanu."]),

    # ── Parks & Nature ────────────────────────────────────────────────────────
    ("Cișmigiu Gardens",               "park",       44.4362, 26.0837,
     "Bucharest's oldest and most beloved public park, designed in 1847 by Wilhelm Friedrich Meyer.",
     ["nature"], ["The lake was formed artificially in the 19th century on the site of a marsh.", "In winter the lake transforms into a public ice-skating rink."]),
    ("Herăstrău Park",                 "park",       44.4713, 26.0790,
     "The largest park in Bucharest, surrounding the artificial Lake Herăstrău.",
     ["nature"], ["Created in the 1930s, the park required draining the Colentina River swamps."]),
    ("National Village Museum",        "museum",     44.4654, 26.0753,
     "An open-air museum with over 300 original peasant households from across Romania.",
     ["history","architecture"], ["Every building was disassembled piece by piece in its original village and reassembled in the park.", "Founded in 1936 by sociologist Dimitrie Gusti, it is the largest outdoor museum in Europe."]),
    ("Botanical Garden",               "park",       44.4402, 26.0712,
     "Founded in 1860 near Cotroceni Palace, containing over 10,000 plant species.",
     ["nature"], ["The garden's original collection of seeds was a gift from the Vienna Botanical Garden."]),
    ("Carol Park",                     "park",       44.4149, 26.0755,
     "A historic park created for the 1906 General Exhibition, featuring the Mausoleum of Romanian Heroes.",
     ["history","nature"], ["The Mausoleum was built in 1963 over an earlier monument, and contains the remains of 19 Romanian soldiers."]),
    ("Tineretului Park",               "park",       44.4105, 26.0866,
     "A large recreational park in southern Bucharest with open-air theatre and sports facilities.",
     ["nature"], []),
    ("Alexandru Ioan Cuza Park (IOR)", "park",       44.4103, 26.1426,
     "The second-largest park in Bucharest, surrounding Lake Titan.",
     ["nature"], ["Completed in the 1960s as part of a major urban expansion of the Titan neighborhood."]),
    ("Floreasca Park",                 "park",       44.4604, 26.1098,
     "A leafy park in northern Bucharest, popular for jogging and outdoor cafés.",
     ["nature","gastronomy"], []),
    ("Văcărești Nature Park",          "park",       44.3995, 26.1050,
     "An unexpected urban delta — a wetland that formed naturally in an abandoned reservoir.",
     ["nature"], ["Ceaușescu began a massive reservoir here in 1986 but abandoned it after the revolution. Nature reclaimed it.", "It is now officially Romania's first urban natural park and hosts over 130 bird species."]),
    ("Plumbuita Monastery Lake",       "park",       44.4750, 26.1380,
     "A tranquil lake and forest area in northeastern Bucharest surrounding a historic monastery.",
     ["nature","history"], []),

    # ── Herăstrău / Aviatorilor ────────────────────────────────────────────────
    ("Arc de Triomphe",                "monument",   44.4679, 26.0796,
     "Bucharest's triumphal arch, built in 1936 to commemorate Romania's role in World War I.",
     ["architecture","history"], ["The current arch replaced a temporary wooden structure erected after WWI.", "It was renovated extensively in 2016 and has viewing terraces at the top."]),
    ("Grigore Antipa Natural History Museum","museum",44.4513,26.0838,
     "Romania's premier natural history museum with an impressive dinosaur and biodiversity collection.",
     ["history","nature"], ["Named after Romanian naturalist Grigore Antipa who founded the modern collection in 1893.", "The blue whale skeleton in the main hall is one of only a handful on display in Europe."]),
    ("Romanian Peasant Museum",        "museum",     44.4520, 26.0842,
     "An award-winning museum celebrating traditional Romanian folk culture and craftsmanship.",
     ["art","history"], ["The museum was named European Museum of the Year in 1996.", "During communism the building housed the Museum of the Communist Party."]),
    ("Dimitrie Gusti Museum",          "museum",     44.4660, 26.0760,
     "Part of the Village Museum complex, dedicated to the sociologist and ethnographer Dimitrie Gusti.",
     ["history"], []),
    ("Casa Presei Libere",             "building",   44.4739, 26.0673,
     "A monumental Stalinist tower built in 1956 as the House of the Free Press.",
     ["architecture","history"], ["Built in the style of Stalinist architecture, it closely resembles Moscow's Seven Sisters skyscrapers.", "At 104 metres it was the tallest building in Romania for decades."]),
    ("Snagov Monastery",               "monument",   44.5683, 26.1570,
     "A monastery on an island in Snagov Lake, reputedly the burial place of Vlad the Impaler.",
     ["history","architecture"], ["Vlad III is said to be buried under the altar, though DNA evidence is still inconclusive.", "The lake was used as a prison island by communist authorities in the 1950s."]),
    ("Triumphal Way (Bulevardul Kiseleff)","square", 44.4690, 26.0800,
     "A grand tree-lined boulevard from the Arc de Triomphe toward the city center.",
     ["architecture"], ["Laid out in the 1830s by Pavel Kiseleff, the Russian general-governor of Wallachia."]),

    # ── Cotroceni / Grozăvești ─────────────────────────────────────────────────
    ("Cotroceni Palace",               "building",   44.4348, 26.0696,
     "The official residence of Romania's president, originally a 17th-century monastery rebuilt as a royal palace.",
     ["architecture","history"], ["Prince Mihnea III founded a monastery here in 1679.", "Queen Marie of Romania loved the palace and wrote her memoirs in its gardens."]),
    ("National Museum Cotroceni",      "museum",     44.4349, 26.0700,
     "Within Cotroceni Palace complex, exhibiting royal furniture, porcelain and decorative arts.",
     ["art","history"], []),
    ("Military Museum",                "museum",     44.4405, 26.0798,
     "Chronicles Romanian military history from ancient times to the present day.",
     ["history"], ["An entire courtyard is filled with Soviet-era tanks and artillery pieces donated after 1989."]),
    ("Bellu Cemetery",                 "monument",   44.4068, 26.0836,
     "Bucharest's most famous cemetery, a tranquil park-like space with monumental sculpture.",
     ["history","architecture"], ["Many of Romania's most celebrated writers, poets and politicians are buried here.", "The English-language sections host the graves of Allied airmen shot down over Romania in WWII."]),
    ("Grozăvești Student Campus",      "building",   44.4428, 26.0720,
     "One of the largest student campuses in Eastern Europe, home to tens of thousands of students.",
     ["architecture"], []),
    ("Polytehnică Library",            "building",   44.4396, 26.0741,
     "The main library of Bucharest Polytechnic University, a modernist architectural landmark.",
     ["architecture"], []),
    ("Radu Vodă Monastery",            "building",   44.4202, 26.0985,
     "A 16th-century monastery on a hill overlooking the Dâmbovița River, with spectacular city views.",
     ["history","architecture"], ["Mircea Ciobanul founded the monastery in 1568 on the ruins of an even earlier foundation."]),

    # ── Carol / Timpuri Noi ────────────────────────────────────────────────────
    ("Parliament Palace (Casa Poporului)","building",44.4273,26.0875,
     "The world's second-largest administrative building, built by Nicolae Ceaușescu from 1984.",
     ["architecture","history"], ["It has 1,100 rooms, 12 stories above ground and 8 underground, covering 330,000 square metres.", "Its construction required the demolition of one-fifth of historic Bucharest and displaced 40,000 residents.", "Ceaușescu never set foot inside the completed building."]),
    ("National Museum of Contemporary Art","gallery",44.4275,26.0875,
     "Located inside the Parliament Palace, it showcases Romanian and international contemporary art.",
     ["art"], []),
    ("Antim Monastery",                "building",   44.4220, 26.0920,
     "A stunning early 18th-century monastery with uniquely carved stone portals.",
     ["architecture","history"], ["Founded in 1715 by Metropolitan Antim Ivireanul, a Georgian-born printer and scholar who is now a saint."]),
    ("Patriarchal Cathedral",          "building",   44.4252, 26.0965,
     "The seat of the Romanian Orthodox Patriarchate, built between 1654 and 1658.",
     ["history","architecture"], ["The cathedral holds the relics of Saint Dimitrie the New, patron of Bucharest."]),
    ("Mihai Vodă Monastery",           "building",   44.4278, 26.0912,
     "One of the oldest standing buildings in Bucharest, moved 285 metres on rails in 1985 to preserve it.",
     ["history","architecture"], ["Ceaușescu ordered it moved rather than demolished—one of the few historic buildings to survive his urban renewal."]),
    ("Dâmbovița Riverfront",           "square",     44.4240, 26.0900,
     "A revitalized linear park along the Dâmbovița River, once heavily industrialized.",
     ["nature","architecture"], []),

    # ── Floreasca / Dorobanți ──────────────────────────────────────────────────
    ("Floreasca Market",               "square",     44.4610, 26.1090,
     "One of Bucharest's main covered markets, buzzing with fruit, vegetables and artisan products.",
     ["gastronomy"], []),
    ("Jean-Louis Calderon Square",     "square",     44.4470, 26.0980,
     "A leafy residential square in the elegant Dorobanți neighbourhood.",
     ["architecture"], []),
    ("Diplomatic Quarter Dorobanți",   "building",   44.4530, 26.0940,
     "An area of grand inter-war villas housing many of Bucharest's foreign embassies.",
     ["architecture","history"], []),
    ("Aviatorilor Square",             "square",     44.4662, 26.0842,
     "An elegant square in the northern city with the Monument of the Romanian Airmen.",
     ["history","architecture"], []),
    ("French Institute of Bucharest",  "gallery",    44.4490, 26.0900,
     "A cultural centre promoting French-Romanian artistic exchange with exhibitions and cinema.",
     ["art","music"], []),
    ("Goethe Institut Bucharest",      "gallery",    44.4466, 26.0930,
     "The German cultural centre, hosting concerts, art exhibitions and language courses.",
     ["art","music"], []),
    ("Verona Street (Street of Artists)","square",   44.4502, 26.0908,
     "A charming pedestrian street nicknamed 'the artists' street' for its galleries and workshops.",
     ["art"], ["In the early 20th century, many of Romania's most celebrated painters had studios along this street."]),

    # ── Titan / Pantelimon ────────────────────────────────────────────────────
    ("Alexandru Ioan Cuza Park Lake",  "park",       44.4110, 26.1440,
     "The central lake of IOR Park, offering pedal boats, fishing and lakeside cafés.",
     ["nature"], []),
    ("Pantelimon Museum",              "museum",     44.4620, 26.1250,
     "A local history museum preserving the traditions of the Pantelimon commune.",
     ["history"], []),
    ("Plumbuita Monastery",            "building",   44.4748, 26.1385,
     "A 16th-century monastery with a medieval printing press, the first in Wallachia.",
     ["history","architecture"], ["The monastery's printing press, established in 1582, produced the first books in Romanian."]),
    ("Titan Lake",                     "park",       44.4095, 26.1430,
     "A scenic artificial lake with walking paths and sports facilities.",
     ["nature"], []),
    ("Cernica Monastery",              "building",   44.3850, 26.2030,
     "A monastic complex on two islands in Cernica Lake, a popular pilgrimage destination.",
     ["history","architecture"], ["Founded in the 16th century, it was a major centre of Orthodox learning.", "The relics of Saint Calinic, a 19th-century bishop renowned for miracles, are kept here."]),
    ("Mogoșoaia Palace",               "museum",     44.5380, 25.9870,
     "A Brâncovenesc-style palace on a lake north of Bucharest, built by Constantin Brâncoveanu in 1702.",
     ["architecture","history"], ["The palace was confiscated by the Ottomans after Brâncoveanu's execution in Constantinople.", "It was restored by Princess Marthe Bibescu in the 20th century who made it her residence."]),

    # ── Additional central landmarks ───────────────────────────────────────────
    ("Elisabeta Palace",               "building",   44.4330, 26.0728,
     "A neoclassical palace used as the official residence of Princess Margareta of Romania.",
     ["architecture","history"], []),
    ("Theodor Pallady Museum",         "museum",     44.4288, 26.1012,
     "A museum in a 17th-century merchant house exhibiting works by Romanian Postimpressionist Theodor Pallady.",
     ["art","architecture"], []),
    ("Dinu Lipatti House",             "museum",     44.4403, 26.0873,
     "The home of Romanian piano legend Dinu Lipatti, preserved as a memorial museum.",
     ["music"], ["Lipatti died of Hodgkin's lymphoma at just 33, leaving behind recordings still considered the benchmark for Chopin."]),
    ("Ion Jalea Museum",               "museum",     44.4415, 26.0950,
     "A villa-museum dedicated to sculptor Ion Jalea, with sculptures in a garden setting.",
     ["art"], []),
    ("Museum of Recent Art",           "gallery",    44.4310, 26.0820,
     "Showcases Romanian and international art produced after 1960 in a converted villa.",
     ["art"], []),
    ("Kalinderu Library",              "building",   44.4455, 26.0875,
     "A literary salon and reading room in a historic villa, host to author talks and poetry evenings.",
     ["art","music"], []),
    ("Titan–Balta Albă Market",        "square",     44.4180, 26.1270,
     "A large open-air market serving the eastern neighborhoods, lively on weekends.",
     ["gastronomy"], []),
    ("Obor Market",                    "square",     44.4545, 26.1108,
     "Bucharest's largest traditional market, a sensory feast of produce, flowers and street food.",
     ["gastronomy"], ["In the 19th century, Obor was the city's livestock fair, where cattle from all of Wallachia were traded."]),
    ("Therme Bucharest",               "park",       44.5183, 26.0855,
     "The largest wellness and thermal spa complex in Europe, just north of Bucharest.",
     ["nature"], []),
    ("Băneasa Forest",                 "park",       44.5050, 26.0830,
     "A large forested area north of Bucharest used for walking, cycling and weekend picnics.",
     ["nature"], []),
    ("Tei Lake",                       "park",       44.4770, 26.1230,
     "A quiet lake in northeastern Bucharest, popular with fishermen and joggers.",
     ["nature"], []),
    ("Floreasca Lake",                 "park",       44.4620, 26.1050,
     "An urban lake surrounded by cafés, restaurants and sports facilities.",
     ["nature","gastronomy"], []),
    ("Romanian Opera House",           "building",   44.4432, 26.0823,
     "Bucharest's main opera and ballet venue, built in 1953 in a neoclassical-socialist style.",
     ["music","architecture"], ["The building was constructed in just six years under communist rule, mobilizing thousands of workers."]),
    ("National Circus",                "building",   44.4528, 26.0782,
     "Romania's main circus venue, a modernist dome built in 1960, still hosting performances.",
     ["music","architecture"], []),
    ("Sports Palace",                  "building",   44.4280, 26.0860,
     "A large indoor arena hosting basketball, concerts and major sporting events.",
     ["architecture"], []),
    ("Izvor Park",                     "park",       44.4270, 26.0820,
     "A park near the Parliament Palace with fountains and views of the building's façade.",
     ["nature","architecture"], []),
    ("Cișmigiu Lake",                  "park",       44.4367, 26.0835,
     "The lake at the heart of Cișmigiu Gardens, where rowboats can be rented in summer.",
     ["nature"], []),
    ("Piața Unirii Fountain",          "square",     44.4263, 26.1023,
     "The largest public fountain in Romania, at Unirii Square in the heart of Bucharest.",
     ["architecture"], ["The fountain was designed to rival those on the Champs-Élysées and was a signature project of Ceaușescu."]),
    ("Unirii Boulevard",               "square",     44.4265, 26.1020,
     "A wide Haussmanian boulevard built in the 1980s, often called 'Romania's Champs-Élysées'.",
     ["architecture","history"], ["Three kilometres long and 120 metres wide, it required demolishing more than 40,000 apartments."]),
    ("Dealul Mitropoliei",             "monument",   44.4248, 26.0968,
     "The Metropolitain Hill, the oldest continuously inhabited area of Bucharest.",
     ["history","architecture"], ["Archaeological digs have uncovered settlements here dating to the Bronze Age."]),
    ("National Library of Romania",    "building",   44.4270, 26.1037,
     "The main national library, holding over 13 million documents and manuscripts.",
     ["history","architecture"], []),
    ("Bucharest Financial District",   "building",   44.4350, 26.0760,
     "A cluster of glass and steel towers in Grozăvești, Bucharest's emerging financial hub.",
     ["architecture"], []),
    ("Splaiul Independenței Promenade","square",     44.4220, 26.0750,
     "A riverside walk along the Dâmbovița, recently revitalized with bike lanes and green spaces.",
     ["nature"], []),
    ("Berthelot Street",               "square",     44.4432, 26.0898,
     "A quiet residential street lined with early 20th-century villas and embassies.",
     ["architecture"], []),
    ("Dorobanți Quarter",              "square",     44.4525, 26.0975,
     "An upmarket residential and commercial area with tree-lined streets and boutique shops.",
     ["architecture","gastronomy"], []),
    ("Floreasca Restaurant Row",       "restaurant", 44.4615, 26.1088,
     "A stretch of acclaimed restaurants along Lake Floreasca serving everything from sushi to sarmale.",
     ["gastronomy"], []),
    ("Lacrimi și Sfinți Restaurant",   "restaurant", 44.4522, 26.0942,
     "A celebrated restaurant blending Romanian traditions with modern gastronomy.",
     ["gastronomy"], ["Awarded best restaurant in Romania multiple years, known for reinventing traditional dishes."]),
    ("Vatra Veche Restaurant",         "restaurant", 44.4308, 26.0963,
     "A rustic Old Town tavern serving traditional Wallachian recipes in clay pots.",
     ["gastronomy","history"], []),
    ("Berăria H",                      "restaurant", 44.4300, 26.0960,
     "A large craft beer hall and restaurant with over 100 beers on tap.",
     ["gastronomy"], []),
    ("Shift Pub",                      "restaurant", 44.4302, 26.0968,
     "A beloved Old Town pub with live music and a cosy underground atmosphere.",
     ["gastronomy","music"], []),
    ("Gradina Verona Gallery",         "gallery",    44.4505, 26.0912,
     "An outdoor sculpture garden doubling as a contemporary art gallery.",
     ["art","nature"], []),
    ("Galateca Gallery",               "gallery",    44.4365, 26.0948,
     "A leading contemporary art gallery on Calea Victoriei showcasing emerging Romanian artists.",
     ["art"], []),
    ("Annart Gallery",                 "gallery",    44.4460, 26.0970,
     "A mid-century villa converted into an intimate art gallery with a sculpture garden.",
     ["art"], []),
]

assert len(RAW_LANDMARKS) >= 100, f"Only {len(RAW_LANDMARKS)} landmarks"


# ── Quest templates ────────────────────────────────────────────────────────────
def quests_for(name: str, ltype: str, cats: list) -> list[dict]:
    """Return 2-3 quest documents for this landmark."""
    q = []

    if ltype == "museum":
        q.append(dict(type="educational", title="Test Your Knowledge",
                      description=f"What makes {name} historically or culturally significant?",
                      points=30,
                      options=["It holds ancient artifacts", "It was built in the 18th century",
                               "It hosts regular exhibitions", "All of the above"],
                      correct_option_index=3))
        q.append(dict(type="challenge", title="Deep Dive",
                      description=f"Find the oldest object on display at {name} and note its approximate date.",
                      points=50, options=[], correct_option_index=None))
        q.append(dict(type="virtual_note", title="Your Impression",
                      description="Write two sentences describing what surprised you most about this museum.",
                      points=15, options=[], correct_option_index=None))

    elif ltype == "monument":
        q.append(dict(type="educational", title="Behind the Monument",
                      description=f"What event or person does {name} commemorate?",
                      points=25,
                      options=["A military victory", "A national hero", "An architectural achievement", "A royal dynasty"],
                      correct_option_index=1))
        q.append(dict(type="mission", title="Full Circle",
                      description="Walk a complete circuit around the monument and count any inscriptions.",
                      points=20, options=[], correct_option_index=None))

    elif ltype == "park":
        q.append(dict(type="mission", title="Spot the Wildlife",
                      description="Identify and photograph (or note) three different plant or animal species in the park.",
                      points=25, options=[], correct_option_index=None))
        q.append(dict(type="educational", title="Park History",
                      description=f"When was {name} established or officially opened to the public?",
                      points=20,
                      options=["Before 1900", "1900–1950", "1950–1990", "After 1990"],
                      correct_option_index=random.randint(0, 3)))
        q.append(dict(type="virtual_note", title="Favourite Spot",
                      description="Describe your favourite corner of this park and why it stands out.",
                      points=15, options=[], correct_option_index=None))

    elif ltype == "building":
        q.append(dict(type="educational", title="Architectural Style",
                      description=f"Which architectural style best describes {name}?",
                      points=25,
                      options=["Gothic", "Baroque / Neoclassical", "Modernist / Brutalist", "Brâncovenesc"],
                      correct_option_index=random.randint(0, 3)))
        q.append(dict(type="mission", title="Detail Hunt",
                      description="Find and note one architectural detail (carvings, windows, inscriptions) that you would not notice at a glance.",
                      points=20, options=[], correct_option_index=None))

    elif ltype == "square":
        q.append(dict(type="educational", title="Square Significance",
                      description=f"What is {name} best known for in Bucharest's history?",
                      points=20,
                      options=["Commercial trade", "Political protests / events", "Cultural festivals", "Royal ceremonies"],
                      correct_option_index=random.randint(0, 3)))
        q.append(dict(type="virtual_note", title="People Watching",
                      description="Spend 5 minutes observing the square and write what you see.",
                      points=15, options=[], correct_option_index=None))

    elif ltype == "restaurant":
        q.append(dict(type="educational", title="Signature Dish",
                      description=f"What category of cuisine is {name} primarily known for?",
                      points=20,
                      options=["Traditional Romanian", "International / Fusion", "Street food", "Craft beer & pub food"],
                      correct_option_index=random.randint(0, 3)))
        q.append(dict(type="virtual_note", title="Your Order",
                      description="What did you try here? Would you recommend it?",
                      points=15, options=[], correct_option_index=None))

    elif ltype == "gallery":
        q.append(dict(type="educational", title="Gallery Focus",
                      description=f"What period or movement does {name} primarily exhibit?",
                      points=20,
                      options=["Classical / Old Masters", "19th-century Realism", "Modern (1900–1970)", "Contemporary (post-1970)"],
                      correct_option_index=random.randint(0, 3)))
        q.append(dict(type="challenge", title="Most Striking Work",
                      description="Choose one work that resonates with you and write the artist's name and why it stands out.",
                      points=35, options=[], correct_option_index=None))
        q.append(dict(type="virtual_note", title="Your Review",
                      description="Rate the gallery experience and note one thing you would change.",
                      points=10, options=[], correct_option_index=None))

    else:
        q.append(dict(type="mission", title="Explore",
                      description=f"Spend at least 10 minutes exploring {name} and its surroundings.",
                      points=15, options=[], correct_option_index=None))

    return q[:3]  # cap at 3


# ── Named routes ───────────────────────────────────────────────────────────────
NAMED_ROUTES = [
    dict(name="Historic Heart of Bucharest",
         interests=["history","architecture"],
         stop_names=["Revolution Square","National History Museum","Curtea Veche",
                     "Stavropoleos Monastery","Caru' cu Bere","CEC Palace"],
         user_idx=0),
    dict(name="Green Bucharest Walk",
         interests=["nature"],
         stop_names=["Cișmigiu Gardens","Botanical Garden","Izvor Park","Carol Park","Tineretului Park"],
         user_idx=4),
    dict(name="Art & Culture Trail",
         interests=["art","music"],
         stop_names=["National Museum of Art of Romania","Romanian Athenaeum",
                     "George Enescu National Museum","Romanian Peasant Museum",
                     "Galateca Gallery"],
         user_idx=2),
    dict(name="Royal & Presidential Bucharest",
         interests=["architecture","history"],
         stop_names=["Parliament Palace (Casa Poporului)","Cotroceni Palace",
                     "Romanian Academy","Cantacuzino Palace","Elisabeta Palace"],
         user_idx=5),
    dict(name="Gastronomy & Old Town",
         interests=["gastronomy","history"],
         stop_names=["Hanul lui Manuc","Caru' cu Bere","Lipscani Street",
                     "Obor Market","Lacrimi și Sfinți Restaurant"],
         user_idx=1),
]


# ══════════════════════════════════════════════════════════════════════════════
#  SEED
# ══════════════════════════════════════════════════════════════════════════════
print("🗑  Clearing existing data …")
for col in ["users","landmarks","quests","visits","ratings","routes","stories","events"]:
    db[col].drop()

# ── Create 2dsphere index ──────────────────────────────────────────────────────
db.landmarks.create_index([("location", GEOSPHERE)])

# ── Insert users ───────────────────────────────────────────────────────────────
print("👤 Inserting users …")
user_docs = []
for u in USERS_DATA:
    doc = dict(
        email=u["email"], name=u["name"],
        password_hash=hpw(u["pw"]),
        interests=u["interests"],
        points=0, completed_quests=0,
        created_at=datetime.utcnow() - timedelta(days=random.randint(10, 90)),
    )
    user_docs.append(doc)
res = db.users.insert_many(user_docs)
user_ids = [str(oid) for oid in res.inserted_ids]

# Admin account (separate insert so it's clearly identifiable)
db.users.insert_one(dict(
    email=ADMIN_DATA["email"], name=ADMIN_DATA["name"],
    password_hash=hpw(ADMIN_DATA["pw"]),
    interests=[], points=0, completed_quests=0,
    is_admin=True,
    created_at=datetime.utcnow(),
))
admin_id = str(db.users.find_one({"is_admin": True})["_id"])
print(f"   ✓ {len(user_ids)} users + 1 admin created")

# ── Insert landmarks ───────────────────────────────────────────────────────────
LANDMARK_WEBSITES = {
    "Romanian Athenaeum":        "https://www.fge.org.ro",
    "National History Museum":   "https://www.mnir.ro",
    "Cotroceni Palace":          "https://www.muzeulcotroceni.ro",
    "National Museum of Art":    "https://www.mnar.arts.ro",
    "Village Museum":            "https://muzeul-satului.ro",
    "Natural History Museum":    "https://www.grigore-antipa.ro",
    "National Opera":            "https://www.operanb.ro",
    "Biblioteca Națională":      "https://www.bibnat.ro",
    "Herăstrău Park":            "https://www.herastraupark.ro",
    "Cișmigiu Garden":           "https://www.cismigiu.ro",
}

print("📍 Inserting 100 Bucharest landmarks …")
landmark_docs = []
for name, ltype, lat, lng, desc, cats, stories in RAW_LANDMARKS:
    landmark_docs.append(dict(
        name=name, type=ltype,
        location={"type":"Point","coordinates":[lng, lat]},
        description=desc, categories=cats, stories=stories[:5],  # max 5 stories
        website=LANDMARK_WEBSITES.get(name),
        rating=0.0, visit_count=0,
        has_active_quest=True,
        submitted_by=admin_id,   # all Bucharest landmarks attributed to admin
        status="approved",
    ))
res = db.landmarks.insert_many(landmark_docs)
landmark_ids = [str(oid) for oid in res.inserted_ids]
name_to_id   = {doc["name"]: lid for doc, lid in zip(landmark_docs, landmark_ids)}
name_to_lat  = {doc["name"]: doc["location"]["coordinates"][1] for doc in landmark_docs}
name_to_lng  = {doc["name"]: doc["location"]["coordinates"][0] for doc in landmark_docs}
print(f"   ✓ {len(landmark_ids)} landmarks created")

# ── Insert quests ──────────────────────────────────────────────────────────────
print("🗺  Inserting quests …")
quest_docs = []
for raw, lid in zip(RAW_LANDMARKS, landmark_ids):
    name, ltype, _, _, _, cats, _ = raw
    for q in quests_for(name, ltype, cats)[:5]:  # max 5 quests per landmark
        quest_docs.append(dict(
            landmark_id=lid,
            type=q["type"], title=q["title"], description=q["description"],
            points=q["points"], options=q["options"],
            correct_option_index=q["correct_option_index"],
        ))
res = db.quests.insert_many(quest_docs)
quest_ids = [str(oid) for oid in res.inserted_ids]

# Build lookup: landmark_id → list of (quest_id, quest_doc)
from collections import defaultdict
lm_quests: dict[str, list] = defaultdict(list)
for qid, qdoc in zip(quest_ids, quest_docs):
    lm_quests[qdoc["landmark_id"]].append((qid, qdoc))
print(f"   ✓ {len(quest_ids)} quests created")

# ── Simulate visits, ratings, quest completions ────────────────────────────────
print("🚶 Simulating user activity …")

# How many landmarks each user visits (realistic spread)
visits_per_user = [28, 22, 18, 20, 14, 32, 12, 10]

# Per-landmark counters (anonymous — no user_id stored)
visit_counts  = {lid: 0 for lid in landmark_ids}   # total visit count
rating_sums   = {lid: 0 for lid in landmark_ids}   # sum of ratings
rating_counts = {lid: 0 for lid in landmark_ids}   # number of raters

# Track per-user points and completed quest info
user_points   = [0] * len(user_ids)
user_completed_quests = [0] * len(user_ids)
user_completed_quest_ids = [[] for _ in user_ids]

total_visits = 0
total_ratings = 0

# Landmarks referenced in community review pending items — every user must visit at least one
COMMUNITY_REVIEW_NAMES = [
    "Romanian Athenaeum", "Stavropoleos Monastery", "Curtea Veche",
    "Herăstrău Park", "Village Museum", "National History Museum",
    "Cotroceni Palace", "Old Town Square",
]
community_review_ids = [name_to_id[n] for n in COMMUNITY_REVIEW_NAMES if n in name_to_id]

for ui, (uid, n_visits) in enumerate(zip(user_ids, visits_per_user)):
    # Ensure at least one community-review landmark is included
    guaranteed = [random.choice(community_review_ids)] if community_review_ids else []
    remaining_pool = [lid for lid in landmark_ids if lid not in guaranteed]
    extra = random.sample(remaining_pool, min(n_visits - len(guaranteed), len(remaining_pool)))
    visited_lids = guaranteed + extra

    for lid in visited_lids:
        # Anonymous visit counter
        visit_counts[lid] += 1
        total_visits += 1

        # Anonymous rating contribution (70% chance)
        if random.random() < 0.70:
            r = random.choices([3, 4, 4, 5, 5, 5], k=1)[0]
            rating_sums[lid] += r
            rating_counts[lid] += 1
            total_ratings += 1

        # Complete 0, 1, or 2 quests for this landmark
        quests_here = lm_quests.get(lid, [])
        n_to_do = random.choices([0, 1, 2], weights=[15, 45, 40])[0]
        chosen = random.sample(quests_here, min(n_to_do, len(quests_here)))
        for qid, qdoc in chosen:
            if qdoc["type"] == "educational" and random.random() < 0.30:
                continue
            pts = qdoc["points"]
            user_points[ui] += pts
            user_completed_quests[ui] += 1
            user_completed_quest_ids[ui].append(qid)

print(f"   visits: {total_visits}  ratings: {total_ratings}")

# ── Aggregate visit_count and rating on each landmark (anonymous) ──────────────
print("📊 Aggregating visit counts and ratings …")
for lid in landmark_ids:
    vc = visit_counts[lid]
    r_sum = rating_sums[lid]
    r_count = rating_counts[lid]
    avg_r = round(r_sum / r_count, 2) if r_count > 0 else 0.0
    from bson import ObjectId as OID
    db.landmarks.update_one(
        {"_id": OID(lid)},
        {"$set": {"visit_count": vc, "rating": avg_r, "rating_sum": r_sum, "rating_count": r_count}},
    )

# ── Update user stats ──────────────────────────────────────────────────────────
print("💰 Updating user points and completed quests …")
for ui, uid in enumerate(user_ids):
    from bson import ObjectId as OID
    db.users.update_one({"_id": OID(uid)}, {"$set": {
        "points": user_points[ui],
        "completed_quests": user_completed_quests[ui],
        # completed_quest_ids not stored server-side — tracked locally on device
    }})

# ── Insert routes ──────────────────────────────────────────────────────────────
print("🛣  Inserting routes …")
route_count = 0
for route_def in NAMED_ROUTES:
    uid = user_ids[route_def["user_idx"]]
    stop_ids = []
    for sn in route_def["stop_names"]:
        lid = name_to_id.get(sn)
        if lid:
            stop_ids.append(lid)

    if len(stop_ids) < 2:
        continue

    # Compute approximate distance chain
    coords = [(name_to_lat.get(sn, 44.43), name_to_lng.get(sn, 26.09))
              for sn in route_def["stop_names"] if name_to_id.get(sn)]
    total_dist = sum(haversine(coords[i][0], coords[i][1], coords[i+1][0], coords[i+1][1])
                     for i in range(len(coords)-1))
    total_min  = int(total_dist / 83 + len(stop_ids) * 25)

    generated_at = (datetime.utcnow() - timedelta(days=random.randint(1, 30))).isoformat()
    db.routes.insert_one(dict(
        user_id=admin_id,          # curated routes attributed to admin
        is_global=True,            # visible to all users
        name=route_def["name"],
        stop_ids=stop_ids,
        interests=route_def["interests"],
        total_distance_m=round(total_dist),
        total_duration_minutes=total_min,
        generated_at=generated_at,
    ))
    route_count += 1

print(f"   ✓ {route_count} routes created")

# ── Insert events ──────────────────────────────────────────────────────────────
print("🎉 Inserting events …")
now = datetime.utcnow()

def future(days, hour=18, minute=0):
    d = now + timedelta(days=days)
    return datetime(d.year, d.month, d.day, hour, minute).isoformat()

def past(days, hour=10, minute=0):
    d = now - timedelta(days=days)
    return datetime(d.year, d.month, d.day, hour, minute).isoformat()

EVENTS_DATA = [
    # ── Ongoing ──────────────────────────────────────────────────────────────
    ("Romanian Athenaeum",        "George Enescu Festival",
     "Annual classical music festival celebrating Romania's greatest composer.",
     past(0, 10), future(3, 22)),
    ("National History Museum",   "Special Exhibition: Dacian Gold",
     "Temporary exhibition showcasing rare Dacian gold artefacts.",
     past(1, 9), future(10, 19)),
    ("Stavropoleos Monastery",    "Orthodox Choir Concert",
     "Weekly sacred music performance by the Stavropoleos choir.",
     past(0, 18), past(0, 20)),
    ("Old Town Square",           "Bucharest Street Performers Festival",
     "Live music, juggling, mime and dance acts throughout the day.",
     past(0, 12), future(1, 22)),
    ("Unirii Boulevard",          "Street Art Week",
     "Local and international street artists transform the boulevard walls.",
     past(2, 9), future(5, 20)),
    ("Cișmigiu Garden",           "Sunday Farmers Market",
     "Weekly organic produce and artisan food market in the park.",
     past(0, 9), past(0, 14)),

    # ── Upcoming ─────────────────────────────────────────────────────────────
    ("Herăstrău Park",            "Bucharest Jazz in the Park",
     "Free outdoor jazz festival with local and international artists.",
     future(4, 16), future(4, 22)),
    ("Cotroceni Palace",          "Guided Night Tour",
     "Special evening guided tour of the royal palace and gardens.",
     future(7, 20), future(7, 23)),
    ("National Museum of Art",    "Contemporary Art Opening Night",
     "Vernissage for the new contemporary Romanian art collection.",
     future(5, 19), future(5, 22)),
    ("Cișmigiu Garden",           "Outdoor Theatre: A Midsummer Night's Dream",
     "Shakespeare in the park performed by the National Theatre company.",
     future(10, 19, 30), future(10, 22)),
    ("Village Museum",            "Traditional Crafts Workshop",
     "Hands-on workshop: pottery, weaving and embroidery with master craftsmen.",
     future(2, 10), future(2, 17)),
    ("Arcul de Triumf",           "National Day Parade Rehearsal",
     "Watch the parade rehearsal from the public viewing area — free entry.",
     future(14, 9), future(14, 13)),
    ("Floreasca Park",            "Outdoor Yoga & Wellness Morning",
     "Free community yoga session followed by a guided meditation walk.",
     future(3, 8), future(3, 10)),
    ("Old Town Square",           "Bucharest History Walk",
     "Free guided walking tour of medieval Bucharest led by local historians.",
     future(1, 11), future(1, 13)),
    ("National History Museum",   "Night at the Museum",
     "After-hours access with torchlight tours and live historical re-enactments.",
     future(8, 20), future(8, 23)),
    ("Romanian Athenaeum",        "Piano Recital: Chopin Evening",
     "An intimate recital of Chopin's nocturnes and ballades.",
     future(6, 19), future(6, 21, 30)),
    ("Herăstrău Park",            "Rowing Regatta",
     "Annual amateur rowing competition on Herăstrău lake — spectators welcome.",
     future(12, 9), future(12, 17)),
    ("Curtea Veche",              "Medieval Bucharest Re-enactment",
     "Costumed actors recreate life in 15th-century Bucharest.",
     future(9, 11), future(9, 18)),
    ("Village Museum",            "Photography Exhibition: Rural Romania",
     "Outdoor photo exhibition documenting disappearing village traditions.",
     future(15, 10), future(30, 19)),
    ("National Opera",            "La Traviata — Opening Night",
     "Verdi's masterpiece performed by the Romanian National Opera.",
     future(11, 19), future(11, 22, 30)),
    ("Floreasca Park",            "Food Truck Rally",
     "Twenty food trucks serving street food from around the world.",
     future(5, 12), future(5, 21)),
    ("Parcul Carol",              "Rock the Park Festival",
     "Two-day indie and rock music festival with camping.",
     future(20, 12), future(21, 23)),
    ("Biblioteca Națională",      "Book Fair & Author Signings",
     "Publishers and authors gather for the annual Bucharest book fair.",
     future(7, 10), future(9, 19)),
    ("Piața Romană",              "Open-Air Cinema Night",
     "Classic Romanian films screened outdoors — bring a blanket.",
     future(4, 21), future(4, 23, 30)),
]

event_docs = []
for lname, title, desc, start, end in EVENTS_DATA:
    lid = name_to_id.get(lname)
    if lid:
        event_docs.append(dict(
            landmark_id=lid,
            title=title,
            description=desc,
            start_time=start,
            end_time=end,
            created_by=admin_id,
        ))

if event_docs:
    db.events.insert_many(event_docs)
print(f"   ✓ {len(event_docs)} events created")

# ── Pending community items (stories + quests awaiting peer review) ────────────
print("⏳ Inserting pending community items …")
pending_stories = [
    ("Romanian Athenaeum",   "I once heard a pianist rehearsing alone at midnight — the sound echoed through the empty hall like a ghost performance."),
    ("Stavropoleos Monastery","The monks still hand-copy manuscripts in the library. I watched one work for an hour without looking up once."),
    ("Curtea Veche",          "Legend says the ghost of Vlad the Impaler walks the ruins on foggy nights. A guard told me he heard footsteps with no source."),
    ("Herăstrău Park",        "Every Sunday a group of elderly men play chess under the same oak tree — they've been meeting there for forty years."),
    ("Village Museum",        "A craftsman showed me a loom that belonged to his great-grandmother. He still uses it to weave the same pattern she did."),
]
pending_quests_data = [
    ("Romanian Athenaeum",   "educational", "Who composed the 'Romanian Rhapsodies'?",
     "Name the composer who performed his debut here and went on to become Romania's most celebrated musician.",
     60, ["George Enescu", "Ciprian Porumbescu", "Dinu Lipatti", "Paul Constantinescu"], 0),
    ("National History Museum","challenge", "Find the Trajan Column Replica",
     "Locate the full-scale replica of Trajan's Column inside the museum and note the scene depicted at eye level.",
     50, [], None),
    ("Cotroceni Palace",     "mission", "Sketch the Throne Room",
     "Draw or photograph the decorative motif above the main entrance to the throne room.",
     40, [], None),
    ("Herăstrău Park",       "virtual_note", "Your Park Memory",
     "Leave a note about your favourite spot in the park and why it feels special.",
     20, [], None),
    ("Old Town Square",      "educational", "What century was the Old Town founded?",
     "Based on the archaeological evidence visible in the square, identify the founding century.",
     50, ["14th century", "15th century", "16th century", "17th century"], 1),
]

pending_story_count = 0
for lname, text in pending_stories:
    lid = name_to_id.get(lname)
    if lid:
        # Random user as submitter for realism
        submitter = random.choice(user_ids)
        db.stories.insert_one({"landmark_id": lid, "submitted_by": submitter, "text": text, "status": "pending", "community_vote_count": 0})
        pending_story_count += 1

pending_quest_count = 0
for lname, qtype, title, desc, pts, opts, correct in pending_quests_data:
    lid = name_to_id.get(lname)
    if lid:
        submitter = random.choice(user_ids)
        db.quests.insert_one({
            "landmark_id": lid, "submitted_by": submitter,
            "type": qtype, "title": title, "description": desc,
            "points": pts, "options": opts, "correct_option_index": correct,
            "status": "pending", "community_vote_count": 0,
        })
        pending_quest_count += 1

# Also add one pending landmark suggestion
pending_landmark = {
    "name": "Hidden Garden of Văcărești",
    "type": "park",
    "location": {"type": "Point", "coordinates": [26.1050, 44.3850]},
    "description": "An unofficial urban delta park that formed naturally in an abandoned reservoir — one of Europe's unexpected urban nature reserves.",
    "categories": ["nature"], "stories": [], "rating": 0.0, "visit_count": 0,
    "has_active_quest": False, "submitted_by": random.choice(user_ids),
    "status": "pending", "community_vote_count": 0,
}
db.landmarks.insert_one(pending_landmark)
db.landmarks.create_index([("location", GEOSPHERE)])  # ensure index after insert

print(f"   ✓ {pending_story_count} pending stories, {pending_quest_count} pending quests, 1 pending landmark")

# ── Summary ────────────────────────────────────────────────────────────────────
print("\n" + "="*55)
print("✅  Seed complete!")
print(f"   Users:     {db.users.count_documents({})}")
print(f"   Landmarks: {db.landmarks.count_documents({})}")
print(f"   Quests:    {db.quests.count_documents({})}")
print(f"   Visits:    {total_visits}  (anonymous counters on landmarks)")
print(f"   Ratings:   {total_ratings}  (anonymous sum/count on landmarks)")
print(f"   Routes:    {db.routes.count_documents({})}")
print(f"   Events:    {db.events.count_documents({})}")
print()
for ui, uid in enumerate(user_ids):
    u = USERS_DATA[ui]
    print(f"   {u['name']:<22} pts={user_points[ui]:>4}  quests={user_completed_quests[ui]:>2}  interests={u['interests']}")
print("="*55)
