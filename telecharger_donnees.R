# Télécharge les fichiers détail « naissances » de l'INSEE (2018 à 2024)
# et les range dans le dossier donnees/, avec les noms attendus par le Rmd.
# Les fichiers pèsent environ 360 Mo une fois décompressés.

dir.create("donnees", showWarnings = FALSE)
options(timeout = 600)

fichiers <- list(
  "Nais2018.csv"     = "https://www.insee.fr/fr/statistiques/fichier/4215180/etatcivil2018_nais2018_csv.zip",
  "FD_NAIS_2019.csv" = "https://www.insee.fr/fr/statistiques/fichier/4768335/etatcivil2019_nais2019_csv.zip",
  "FD_NAIS_2020.csv" = "https://www.insee.fr/fr/statistiques/fichier/5419785/FD_NAIS_2020_csv.zip",
  "FD_NAIS_2021.csv" = "https://www.insee.fr/fr/statistiques/fichier/6652024/FD_NAIS_2021_csv.zip",
  "FD_NAIS_2022.csv" = "https://www.insee.fr/fr/statistiques/fichier/7708070/FD_NAIS_2022_csv.zip",
  "FD_NAIS_2023.csv" = "https://www.insee.fr/fr/statistiques/fichier/8285987/FD_NAIS_2023_csv.zip",
  "FD_NAIS_2024.csv" = "https://www.insee.fr/fr/statistiques/fichier/8610295/FD_NAIS_2024_csv.zip"
)

for (nom in names(fichiers)) {
  cible <- file.path("donnees", nom)
  if (file.exists(cible)) next
  zip <- tempfile(fileext = ".zip")
  download.file(fichiers[[nom]], zip, mode = "wb")
  dossier <- tempfile()
  unzip(zip, exdir = dossier)
  # Dans chaque archive, le fichier de données est le plus gros CSV (l'autre décrit les variables)
  csv <- list.files(dossier, pattern = "\\.csv$", full.names = TRUE, recursive = TRUE)
  csv <- csv[which.max(file.size(csv))]
  file.copy(csv, cible)
  message("OK : ", nom)
}
