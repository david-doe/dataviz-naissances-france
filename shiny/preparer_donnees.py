"""Prépare les données légères de l'application Shiny.

Lit les fichiers détail de l'INSEE (donnees/) et le contour des départements (IGN),
puis écrit de petites tables agrégées dans shiny/donnees_app/ : l'application
n'a ainsi jamais besoin de charger les 5 millions de naissances.

Usage (depuis la racine du dépôt) : python shiny/preparer_donnees.py
"""
import csv
import struct
from collections import defaultdict
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
DONNEES = RACINE / "donnees"
SORTIE = RACINE / "shiny" / "donnees_app"
SORTIE.mkdir(exist_ok=True)

FICHIERS = {2018: "Nais2018.csv", **{a: f"FD_NAIS_{a}.csv" for a in range(2019, 2025)}}


def ent(v):
    try:
        return int(v)
    except (TypeError, ValueError):
        return None


# ---------------------------------------------------------------- naissances
dep_annee = defaultdict(lambda: {"n": 0, "age_m": 0, "n_age_m": 0, "age_m_35": 0, "garcons": 0, "n_sexe": 0,
                                 "maries": 0, "n_mar": 0, "nom_pere": 0, "nom_double": 0, "n_nom": 0})
mois = defaultdict(int)
age_mere = defaultdict(int)
noms = defaultdict(int)

for annee, nom in FICHIERS.items():
    with open(DONNEES / nom, encoding="latin-1", newline="") as f:
        lecteur = csv.DictReader(f, delimiter=";")
        for r in lecteur:
            # Département de résidence de la mère (et non de la maternité) : une naissance compte
            # là où vit la famille, même si la maternité la plus proche est dans le département voisin.
            dep = (r.get("DEPDOM") or r.get("DEPDOMM") or "").strip()
            if not dep or dep == "99":       # 99 : mère résidant à l'étranger
                continue
            d = dep_annee[(annee, dep)]
            d["n"] += 1
            am = ent(r.get("AGEMERE"))
            if am and 12 <= am <= 60:
                d["age_m"] += am
                d["n_age_m"] += 1
                d["age_m_35"] += am >= 35
                age_mere[(annee, am)] += 1
            sexe = (r.get("SEXE") or "").strip()
            if sexe in ("1", "2", "M", "F"):
                d["n_sexe"] += 1
                d["garcons"] += sexe in ("1", "M")
            amar = r.get("AMAR")                  # année du mariage des parents (2018 à 2021 seulement)
            if amar is not None:
                d["n_mar"] += 1
                d["maries"] += ent(amar) not in (None, 0)
            orig = ent(r.get("ORIGINOM"))
            if orig in (1, 2, 3, 4, 5):
                d["n_nom"] += 1
                d["nom_pere"] += orig == 1
                d["nom_double"] += orig in (3, 4)
                noms[(annee, orig)] += 1
            m = ent(r.get("MNAIS"))
            if m and 1 <= m <= 12:
                mois[(annee, m)] += 1
    print("lu :", nom)

with open(SORTIE / "departements_annees.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["annee", "dep", "naissances", "age_moyen_mere", "part_meres_35_plus", "part_garcons",
                "part_parents_maries", "part_nom_pere", "part_double_nom"])
    for (annee, dep), d in sorted(dep_annee.items()):
        w.writerow([annee, dep, d["n"],
                    round(d["age_m"] / d["n_age_m"], 2) if d["n_age_m"] else "",
                    round(d["age_m_35"] / d["n_age_m"], 4) if d["n_age_m"] else "",
                    round(d["garcons"] / d["n_sexe"], 4) if d["n_sexe"] else "",
                round(d["maries"] / d["n_mar"], 4) if d["n_mar"] else "",
                    round(d["nom_pere"] / d["n_nom"], 4) if d["n_nom"] else "",
                    round(d["nom_double"] / d["n_nom"], 4) if d["n_nom"] else ""])

with open(SORTIE / "naissances_mois.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["annee", "mois", "naissances"])
    for (annee, m), n in sorted(mois.items()):
        w.writerow([annee, m, n])

with open(SORTIE / "age_mere.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["annee", "age", "naissances"])
    for (annee, a), n in sorted(age_mere.items()):
        w.writerow([annee, a, n])

with open(SORTIE / "origine_nom.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["annee", "origine", "naissances"])
    for (annee, o), n in sorted(noms.items()):
        w.writerow([annee, o, n])


# ---------------------------------------------------------------- contours (sans sf)
def lire_dbf(chemin):
    with open(chemin, "rb") as f:
        n, lg_entete, lg_enreg = struct.unpack("<xxxxIHH20x", f.read(32))
        champs = []
        while True:
            b = f.read(32)
            if b[0] == 0x0D:
                break
            champs.append((b[:11].split(b"\x00")[0].decode("latin-1"), b[16]))
        f.seek(lg_entete)
        lignes = []
        for _ in range(n):
            enreg = f.read(lg_enreg)[1:]
            pos, ligne = 0, {}
            for nom, taille in champs:
                ligne[nom] = enreg[pos:pos + taille].decode("latin-1").strip()
                pos += taille
            lignes.append(ligne)
    return lignes


def lire_shp(chemin):
    formes = []
    with open(chemin, "rb") as f:
        f.seek(100)
        while True:
            entete = f.read(8)
            if len(entete) < 8:
                break
            _, lg = struct.unpack(">ii", entete)
            contenu = f.read(lg * 2)
            if struct.unpack("<i", contenu[:4])[0] != 5:
                formes.append([])
                continue
            n_parts, n_pts = struct.unpack("<ii", contenu[36:44])
            parts = list(struct.unpack(f"<{n_parts}i", contenu[44:44 + 4 * n_parts]))
            debut = 44 + 4 * n_parts
            pts = [struct.unpack("<dd", contenu[debut + 16 * i: debut + 16 * i + 16]) for i in range(n_pts)]
            parts.append(n_pts)
            formes.append([pts[parts[k]:parts[k + 1]] for k in range(n_parts)])
    return formes


attributs = lire_dbf(DONNEES / "DEPARTEMENT.dbf")
formes = lire_shp(DONNEES / "DEPARTEMENT.shp")
cle = next(k for k in attributs[0] if k.upper().startswith("CODE_DEP") or k.upper() == "INSEE_DEP")
cle_nom = next((k for k in attributs[0] if k.upper().startswith("NOM_DEP") or k.upper() == "NOM"), None)

with open(SORTIE / "contours_departements.csv", "w", newline="", encoding="utf-8") as f, \
        open(SORTIE / "departements.csv", "w", newline="", encoding="utf-8") as g:
    w = csv.writer(f)
    w.writerow(["dep", "morceau", "ordre", "x", "y"])
    wg = csv.writer(g)
    wg.writerow(["dep", "nom"])
    for attr, parties in zip(attributs, formes):
        dep = attr[cle]
        wg.writerow([dep, attr.get(cle_nom, dep) if cle_nom else dep])
        for k, partie in enumerate(parties):
            if len(partie) < 30:          # on écarte les îlots minuscules
                continue
            pas = max(1, len(partie) // 150)  # on simplifie : environ 150 points par contour
            garde = partie[::pas] + [partie[0]]
            for i, (x, y) in enumerate(garde):
                w.writerow([dep, f"{dep}_{k}", i, round(x / 1000, 2), round(y / 1000, 2)])
print("ok :", sorted(p.name for p in SORTIE.glob("*.csv")))
