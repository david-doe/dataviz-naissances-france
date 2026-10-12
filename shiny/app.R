# Application Shiny : « Naître en France, 2018-2024 »
# Roman Delbare et David Doe · Master SIAD, Université de Lille
#
# L'application lit uniquement les petites tables de donnees_app/, préparées
# par preparer_donnees.py à partir des fichiers détail de l'INSEE.
# Lancement : shiny::runApp("shiny")

library(shiny)
library(bslib)
library(dplyr)
library(tidyr)
library(ggplot2)
library(scales)

# ------------------------------------------------------------------ données
lire <- function(f) read.csv(file.path("donnees_app", f), colClasses = c(dep = "character"),
                             encoding = "UTF-8", check.names = FALSE)

en_titre <- function(x) {
  x <- tolower(x)
  gsub("(^|[ '-])([[:alpha:]])", "\\1\\U\\2", x, perl = TRUE) |>
    gsub(pattern = "([ -])((?:De|Du|Des|Et|La|Le|Les|Sur|En)(?=[ -])|D'|L')",
         replacement = "\\1\\L\\2", perl = TRUE) |>
    remettre_accents()
}

# Le fichier de l'IGN donne les noms sans accents : on les remet mot par mot
remettre_accents <- function(x) {
  accents <- c(Ardeche = "Ardèche", Ariege = "Ariège", Correze = "Corrèze", Cote = "Côte", Cotes = "Côtes",
               Sevres = "Sèvres", Drome = "Drôme", Finistere = "Finistère", Saone = "Saône", Pyrenees = "Pyrénées",
               Herault = "Hérault", Isere = "Isère", Lozere = "Lozère", Nievre = "Nièvre", Vendee = "Vendée",
               Dome = "Dôme", Rhone = "Rhône")
  for (m in names(accents)) x <- gsub(paste0("\\b", m, "\\b"), accents[[m]], x, perl = TRUE)
  x
}

noms_dep <- lire("departements.csv") |>
  mutate(nom = en_titre(nom)) |>
  bind_rows(tibble(dep = c("971", "972", "973", "974", "976"),
                   nom = c("Guadeloupe", "Martinique", "Guyane", "La Réunion", "Mayotte")))

dep_annee <- lire("departements_annees.csv") |> left_join(noms_dep, by = "dep")
contours  <- lire("contours_departements.csv")
mois      <- read.csv(file.path("donnees_app", "naissances_mois.csv"))
age_mere  <- read.csv(file.path("donnees_app", "age_mere.csv"))
origine   <- read.csv(file.path("donnees_app", "origine_nom.csv"))

annees <- sort(unique(dep_annee$annee))

# Évolution depuis 2018 (base 100), calculée pour chaque département
dep_annee <- dep_annee |>
  group_by(dep) |>
  mutate(indice_2018 = naissances / first(naissances[annee == 2018], default = NA) * 100) |>
  ungroup()

france <- dep_annee |>
  group_by(annee) |>
  summarise(age_moyen_mere = weighted.mean(age_moyen_mere, naissances, na.rm = TRUE),
            part_meres_35_plus = weighted.mean(part_meres_35_plus, naissances, na.rm = TRUE),
            part_garcons = weighted.mean(part_garcons, naissances, na.rm = TRUE),
            part_parents_maries = if (all(is.na(part_parents_maries))) NA_real_ else
              weighted.mean(part_parents_maries, naissances, na.rm = TRUE),
            naissances = sum(naissances),
            .groups = "drop") |>
  mutate(indice_2018 = naissances / naissances[annee == 2018] * 100)

INDICATEURS <- c(
  "Évolution des naissances depuis 2018 (base 100)" = "indice_2018",
  "Âge moyen de la mère" = "age_moyen_mere",
  "Part des mères de 35 ans ou plus" = "part_meres_35_plus",
  "Part des enfants de parents mariés (2018-2021)" = "part_parents_maries",
  "Nombre de naissances" = "naissances"
)
FORMATS <- list(indice_2018 = function(x) number(x, accuracy = 0.1, decimal.mark = ","),
                age_moyen_mere = function(x) paste(number(x, accuracy = 0.1, decimal.mark = ","), "ans"),
                part_meres_35_plus = function(x) percent(x, accuracy = 0.1, decimal.mark = ","),
                part_parents_maries = function(x) percent(x, accuracy = 0.1, decimal.mark = ","),
                naissances = function(x) number(x, big.mark = " "))

NOMS_MOIS <- c("janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc.")
BLEU <- "#1F4E79"; BLEU_CLAIR <- "#A6C8E0"; ROUGE <- "#C0504D"; GRIS <- "#7F7F7F"

theme_app <- theme_minimal(base_size = 14) +
  theme(plot.title = element_text(face = "bold"), panel.grid.minor = element_blank(),
        plot.caption = element_text(colour = GRIS, hjust = 0), legend.position = "bottom")

choix_dep <- noms_dep |> filter(dep %in% contours$dep) |> arrange(dep)
choix_dep <- setNames(choix_dep$dep, paste(choix_dep$dep, "-", choix_dep$nom))

# ------------------------------------------------------------------ interface
ui <- page_navbar(
  title = "Naître en France, 2018-2024",
  theme = bs_theme(version = 5, primary = BLEU, base_font = font_collection("Segoe UI", "Helvetica Neue", "Arial", "sans-serif")),
  fillable = FALSE,
  # Barre de défilement toujours présente : sinon la largeur change quand un graphique s'affiche,
  # ce qui relance le graphique en boucle
  header = tags$style("html { overflow-y: scroll; }"),

  nav_panel(
    "La carte",
    layout_sidebar(
      sidebar = sidebar(
        width = 320,
        selectInput("indicateur", "Ce que montre la carte", INDICATEURS),
        sliderInput("annee", "Année", min = min(annees), max = max(annees), value = max(annees),
                    step = 1, sep = "", animate = animationOptions(interval = 1500)),
        selectInput("dep_carte", "Mettre un département en évidence", c("Aucun" = "", choix_dep)),
        helpText("Chaque naissance est comptée dans le département où vit la mère, pas dans celui de la maternité.",
                 "Le nombre brut de naissances suit surtout la population : l'évolution depuis 2018 et l'âge des mères",
                 "se comparent mieux d'un département à l'autre.")
      ),
      card(full_screen = TRUE, card_header(textOutput("titre_carte")),
           plotOutput("carte", height = "560px")),
      layout_columns(
        col_widths = c(6, 6),
        card(card_header("Les 5 valeurs les plus hautes"), tableOutput("haut")),
        card(card_header("Les 5 valeurs les plus basses"), tableOutput("bas"))
      )
    )
  ),

  nav_panel(
    "Mon département",
    layout_sidebar(
      sidebar = sidebar(
        width = 320,
        selectInput("dep", "Département", choix_dep, selected = "59"),
        helpText("Chaque indicateur est comparé à la France entière, outre-mer compris.")
      ),
      uiOutput("chiffres_dep"),
      layout_columns(
        col_widths = c(6, 6),
        card(full_screen = TRUE, card_header("Naissances, base 100 en 2018"), plotOutput("courbe_dep", height = "340px")),
        card(full_screen = TRUE, card_header("Âge moyen de la mère"), plotOutput("age_dep", height = "340px"))
      )
    )
  ),

  nav_panel(
    "Les saisons",
    layout_sidebar(
      sidebar = sidebar(
        width = 320,
        checkboxGroupInput("annees_mois", "Années affichées", annees, selected = c(2019, 2021, 2024)),
        checkboxInput("par_jour", "Ramener au nombre de jours du mois", TRUE),
        helpText("Février compte moins de jours : sans correction, il paraît toujours creux.")
      ),
      card(full_screen = TRUE, card_header("Naissances par mois"), plotOutput("saisons", height = "480px")),
      card(card_body(
        p(strong("Ce qu'on voit."), "Les naissances culminent en juillet-octobre et creusent au printemps.",
          "En janvier et février 2021, elles chutent nettement : ces enfants auraient été conçus pendant le premier",
          "confinement, d'avril à mai 2020. Le rattrapage arrive dès mars 2021.")
      ))
    )
  ),

  nav_panel(
    "L'âge des mères",
    layout_sidebar(
      sidebar = sidebar(
        width = 320,
        checkboxGroupInput("annees_age", "Années comparées", annees, selected = c(2018, 2024))
      ),
      card(full_screen = TRUE, card_header("Répartition des naissances selon l'âge de la mère"),
           plotOutput("age", height = "420px")),
      layout_columns(
        col_widths = c(6, 6),
        card(full_screen = TRUE, card_header("Âge moyen de la mère, France"), plotOutput("age_moyen", height = "300px")),
        card(full_screen = TRUE, card_header("D'où vient le nom de l'enfant ?"), plotOutput("noms", height = "300px"))
      )
    )
  ),

  nav_panel(
    "À propos",
    card(card_body(
      h4("Les données"),
      p("Fichiers détail des naissances de l'INSEE (état civil), de 2018 à 2024 : une ligne par naissance, soit 5,1 millions de lignes.",
        "Les contours des départements viennent de l'IGN."),
      p("Les naissances sont rattachées au département de résidence de la mère. C'est plus juste que le lieu de",
        "l'accouchement : quand une maternité ferme, les naissances partent dans le département voisin sans que la natalité change."),
      p("Certaines variables ne sont publiées que jusqu'en 2021 (année du mariage des parents) ou 2022 (origine du nom) :",
        "les graphiques concernés s'arrêtent à ces années."),
      h4("La méthode"),
      p("Un script Python agrège les fichiers bruts en petites tables (par département et année, par mois, par âge).",
        "L'application ne lit que ces tables : elle se charge en une seconde et peut être hébergée gratuitement."),
      h4("Les auteurs"),
      p("Roman Delbare et David Doe, Master SIAD, Université de Lille. Le code est sur",
        a("GitHub", href = "https://github.com/david-doe/dataviz-naissances-france", target = "_blank"), ".")
    ))
  )
)

# ------------------------------------------------------------------ serveur
server <- function(input, output, session) {

  donnees_carte <- reactive({
    dep_annee |> filter(annee == input$annee) |>
      transmute(dep, nom, valeur = .data[[input$indicateur]])
  })

  output$titre_carte <- renderText({
    paste0(names(INDICATEURS)[INDICATEURS == input$indicateur], " · ", input$annee)
  })

  output$carte <- renderPlot({
    d <- donnees_carte()
    validate(need(any(!is.na(d$valeur)), "Cet indicateur n'est pas publié par l'INSEE pour cette année."))
    fmt <- FORMATS[[input$indicateur]]
    g <- contours |> left_join(d, by = "dep") |>
      ggplot(aes(x, y, group = morceau, fill = valeur)) +
      geom_polygon(colour = "white", linewidth = 0.15) +
      coord_equal() + theme_void(base_size = 14) +
      theme(legend.position = "right", legend.key.height = unit(1.2, "cm")) +
      labs(fill = NULL, caption = "Source : INSEE, état civil · France métropolitaine")
    g <- if (input$indicateur == "indice_2018") {
      g + scale_fill_gradient2(low = ROUGE, mid = "#F2F2F2", high = BLEU, midpoint = 100, labels = fmt)
    } else {
      g + scale_fill_gradient(low = BLEU_CLAIR, high = BLEU, labels = fmt)
    }
    if (nzchar(input$dep_carte)) {
      g <- g + geom_polygon(data = filter(contours, dep == input$dep_carte), fill = NA,
                            colour = "#E8A33D", linewidth = 1.2)
    }
    g
  })

  tableau <- function(d, n = 5, decroissant = TRUE) {
    fmt <- FORMATS[[input$indicateur]]
    d <- d |> filter(!is.na(valeur))
    d <- if (decroissant) arrange(d, desc(valeur)) else arrange(d, valeur)
    d |> head(n) |> transmute(Département = paste(dep, "-", nom), Valeur = fmt(valeur))
  }
  output$haut <- renderTable(tableau(donnees_carte(), decroissant = TRUE), striped = TRUE, width = "100%")
  output$bas  <- renderTable(tableau(donnees_carte(), decroissant = FALSE), striped = TRUE, width = "100%")

  # --- Mon département
  donnees_dep <- reactive(dep_annee |> filter(dep == input$dep))

  output$chiffres_dep <- renderUI({
    d <- donnees_dep(); fr <- france
    dern <- d |> filter(annee == max(annee)); fr_dern <- fr |> filter(annee == max(annee))
    evol <- dern$indice_2018 - 100; evol_fr <- fr_dern$indice_2018 - 100
    layout_columns(
      col_widths = c(4, 4, 4),
      value_box(title = paste("Naissances en", dern$annee), value = number(dern$naissances, big.mark = " "),
                p(paste0(ifelse(evol >= 0, "+", ""), number(evol, accuracy = 0.1, decimal.mark = ","),
                         " % depuis 2018 (France : ", number(evol_fr, accuracy = 0.1, decimal.mark = ","), " %)")),
                theme = "primary"),
      value_box(title = "Âge moyen de la mère", value = FORMATS$age_moyen_mere(dern$age_moyen_mere),
                p(paste("France :", FORMATS$age_moyen_mere(fr_dern$age_moyen_mere)))),
      value_box(title = "Mères de 35 ans ou plus", value = FORMATS$part_meres_35_plus(dern$part_meres_35_plus),
                p(paste("France :", FORMATS$part_meres_35_plus(fr_dern$part_meres_35_plus))))
    )
  })

  courbe_comparee <- function(variable, fmt) {
    bind_rows(donnees_dep() |> transmute(annee, valeur = .data[[variable]], qui = unique(paste(dep, "-", nom))),
              france |> transmute(annee, valeur = .data[[variable]], qui = "France")) |>
      ggplot(aes(annee, valeur, colour = qui)) +
      geom_line(linewidth = 1.2) + geom_point(size = 2.5) +
      scale_colour_manual(values = setNames(c(BLEU, GRIS), c(unique(paste(donnees_dep()$dep, "-", donnees_dep()$nom)), "France"))) +
      scale_x_continuous(breaks = annees) + scale_y_continuous(labels = fmt) +
      labs(x = NULL, y = NULL, colour = NULL) + theme_app
  }
  output$courbe_dep <- renderPlot(courbe_comparee("indice_2018", FORMATS$indice_2018) +
                                    geom_hline(yintercept = 100, linetype = "dashed", colour = GRIS))
  output$age_dep <- renderPlot(courbe_comparee("age_moyen_mere", function(x) number(x, accuracy = 0.1, decimal.mark = ",")))

  # --- Les saisons
  output$saisons <- renderPlot({
    validate(need(length(input$annees_mois) > 0, "Choisissez au moins une année."))
    d <- mois |> filter(annee %in% input$annees_mois) |>
      mutate(jours = c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)[mois] +
               (mois == 2 & annee %% 4 == 0),
             valeur = if (input$par_jour) naissances / jours else naissances,
             annee = factor(annee))
    ggplot(d, aes(mois, valeur, colour = annee)) +
      geom_line(linewidth = 1.2) + geom_point(size = 2.5) +
      scale_x_continuous(breaks = 1:12, labels = NOMS_MOIS) +
      scale_y_continuous(labels = label_number(big.mark = " ")) +
      scale_colour_manual(values = setNames(colorRampPalette(c(BLEU_CLAIR, BLEU, ROUGE))(length(annees)), annees)) +
      labs(x = NULL, y = if (input$par_jour) "Naissances par jour" else "Naissances dans le mois", colour = NULL,
           caption = "Source : INSEE, état civil") +
      theme_app
  })

  # --- L'âge des mères
  output$age <- renderPlot({
    validate(need(length(input$annees_age) > 0, "Choisissez au moins une année."))
    age_mere |> filter(annee %in% input$annees_age, age >= 15, age <= 50) |>
      group_by(annee) |> mutate(part = naissances / sum(naissances)) |> ungroup() |>
      mutate(annee = factor(annee)) |>
      ggplot(aes(age, part, colour = annee)) +
      geom_line(linewidth = 1.2) +
      scale_y_continuous(labels = label_percent(accuracy = 1)) +
      scale_colour_manual(values = setNames(colorRampPalette(c(BLEU_CLAIR, BLEU, ROUGE))(length(annees)), annees)) +
      labs(x = "Âge de la mère à la naissance", y = "Part des naissances", colour = NULL,
           caption = "Source : INSEE, état civil") +
      theme_app
  })

  output$age_moyen <- renderPlot({
    ggplot(france, aes(annee, age_moyen_mere)) +
      geom_line(colour = BLEU, linewidth = 1.2) + geom_point(colour = BLEU, size = 2.5) +
      geom_text(aes(label = number(age_moyen_mere, accuracy = 0.01, decimal.mark = ",")), vjust = -1, size = 4) +
      scale_x_continuous(breaks = annees) + scale_y_continuous(expand = expansion(mult = 0.2)) +
      labs(x = NULL, y = "Âge moyen (ans)") + theme_app
  })

  output$noms <- renderPlot({
    libelles <- c("1" = "Père", "2" = "Mère", "3" = "Père puis mère", "4" = "Mère puis père", "5" = "Autre")
    origine |> group_by(annee) |> mutate(part = naissances / sum(naissances)) |> ungroup() |>
      filter(origine %in% 2:4) |>
      mutate(origine = factor(libelles[as.character(origine)], levels = libelles[c("3", "2", "4")])) |>
      ggplot(aes(annee, part, colour = origine)) +
      geom_line(linewidth = 1.2) + geom_point(size = 2.5) +
      scale_y_continuous(labels = label_percent(accuracy = 1)) +
      scale_x_continuous(breaks = annees) +
      scale_colour_manual(values = c(BLEU, ROUGE, BLEU_CLAIR)) +
      labs(x = NULL, y = NULL, colour = NULL, caption = "Le nom du père seul (environ 80 %) n'est pas tracé.") +
      theme_app
  })
}

shinyApp(ui, server)
