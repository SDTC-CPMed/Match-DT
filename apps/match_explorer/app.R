#!/usr/bin/env Rscript
# Match explorer MVP: inspect MatchIt nearest neighbours for one exposed patient.
#
# From the project root:
#   Rscript -e 'shiny::runApp("apps/match_explorer")'
#
# Needs prepared dummy inputs from scripts/01_prepare_prong1_input.R.

suppressPackageStartupMessages({
  library(shiny)
  library(dplyr)
  library(ggplot2)
  library(MatchIt)
})

# Project root: parent of apps/
app_dir <- normalizePath(getwd())
if (basename(app_dir) == "match_explorer") {
  project_root <- normalizePath(file.path(app_dir, "..", ".."))
} else if (dir.exists(file.path(app_dir, "apps", "match_explorer"))) {
  project_root <- app_dir
} else {
  # runApp sets wd to the app directory
  project_root <- normalizePath(file.path(app_dir, "..", ".."))
}

source(file.path(project_root, "src", "prong1", "prepare_input.R"))
source(file.path(project_root, "src", "prong1", "trajectories.R"))

cfg <- prong1_load_config(project_root)
p1 <- cfg$prong1
prepared_dir <- prong1_resolve_path(p1$prepared_dir, cfg$project_root)

required <- c("participants.rds", "diagnoses_earliest.rds", "disease_n_patient.tsv")
missing <- required[!file.exists(file.path(prepared_dir, required))]
if (length(missing) > 0) {
  stop(
    "Prepared inputs missing in ", prepared_dir, ": ",
    paste(missing, collapse = ", "),
    ". Run scripts/01_prepare_prong1_input.R first."
  )
}

participants <- readRDS(file.path(prepared_dir, "participants.rds"))
diagnoses <- readRDS(file.path(prepared_dir, "diagnoses_earliest.rds"))
disease_n_patient <- readr::read_tsv(
  file.path(prepared_dir, "disease_n_patient.tsv"),
  show_col_types = FALSE
)
clinic <- prong1_build_clinic(participants, p1$censor_date)

match_ratio <- as.integer(p1$match_ratio)
year_caliper <- as.numeric(p1$assessment_year_caliper)

# D1 codes with enough patients for a useful demo.
d1_choices <- disease_n_patient %>%
  filter(n_patients >= as.integer(p1$n_patient_min)) %>%
  arrange(desc(n_patients)) %>%
  transmute(
    label = paste0(icd10, " — ", disease_name, " (n=", n_patients, ")"),
    value = icd10
  )
d1_labels <- setNames(d1_choices$value, d1_choices$label)

# Prefer planted demo D1s when present.
preferred <- c("I10", "E11", "J44", "D37")
default_d1 <- preferred[preferred %in% d1_choices$value][1]
if (is.na(default_d1)) default_d1 <- d1_choices$value[[1]]

#' Run the same MatchIt call as the trajectory pipeline for one D1.
run_d1_match <- function(d1_code) {
  df_d1 <- prong1_cases_for_code(diagnoses, d1_code)
  exposed_data <- clinic %>%
    filter(person_id %in% df_d1$person_id) %>%
    left_join(df_d1, by = "person_id") %>%
    mutate(exposed = 1L)
  control_pool <- clinic %>%
    filter(!(person_id %in% df_d1$person_id)) %>%
    mutate(diagnosis_date = as.Date(NA), exposed = 0L)

  match_data <- bind_rows(exposed_data, control_pool)
  rownames(match_data) <- match_data$person_id

  mod <- matchit(
    exposed ~ sex + age_band + assessment_year + assessment_centre,
    data = match_data,
    method = "nearest",
    ratio = match_ratio,
    caliper = c(assessment_year = year_caliper),
    std.caliper = FALSE
  )

  ps <- mod$distance
  names(ps) <- rownames(match_data)

  list(
    d1_code = d1_code,
    mod = mod,
    match_data = match_data,
    ps = ps,
    df_d1 = df_d1,
    n_exposed = nrow(exposed_data),
    n_control_pool = nrow(control_pool)
  )
}

#' Neighbours matched to one exposed person, plus nearest-by-PS candidates.
inspect_focal <- function(match_obj, focal_id, d2_code = NULL) {
  md <- match_obj$match_data
  ps <- match_obj$ps
  mod <- match_obj$mod

  if (!focal_id %in% rownames(mod$match.matrix)) {
    return(NULL)
  }

  focal <- md[focal_id, , drop = FALSE]
  focal_ps <- unname(ps[[focal_id]])

  matched_ids <- as.character(mod$match.matrix[focal_id, ])
  matched_ids <- matched_ids[!is.na(matched_ids) & nzchar(matched_ids)]

  has_d2 <- character(0)
  if (!is.null(d2_code) && nzchar(d2_code)) {
    has_d2 <- diagnoses$person_id[diagnoses$icd10 == d2_code]
  }

  matched_tbl <- md[matched_ids, , drop = FALSE] %>%
    mutate(
      propensity = as.numeric(ps[as.character(person_id)]),
      delta_ps = abs(propensity - focal_ps),
      year_diff = abs(as.numeric(assessment_year) - as.numeric(focal$assessment_year)),
      year_within_caliper = year_diff <= year_caliper,
      same_sex = as.character(sex) == as.character(focal$sex),
      same_age_band = as.character(age_band) == as.character(focal$age_band),
      same_centre = as.character(assessment_centre) == as.character(focal$assessment_centre),
      has_d2 = person_id %in% has_d2,
      selected = TRUE
    ) %>%
    arrange(delta_ps) %>%
    transmute(
      person_id,
      sex,
      age_band,
      assessment_year,
      assessment_centre,
      propensity,
      delta_ps = round(delta_ps, 6),
      year_diff,
      year_within_caliper,
      same_sex,
      same_age_band,
      same_centre,
      has_d2,
      selected
    )

  # Top controls by |Δ PS| among those who pass the year caliper (may include non-selected).
  control_ids <- rownames(md)[md$exposed == 0L]
  ctrl_ps <- ps[control_ids]
  year_ok <- abs(as.numeric(md[control_ids, "assessment_year"]) -
                   as.numeric(focal$assessment_year)) <= year_caliper
  ranked <- control_ids[year_ok][order(abs(ctrl_ps[year_ok] - focal_ps))]
  top_ids <- head(ranked, 20L)

  nearest_tbl <- md[top_ids, , drop = FALSE] %>%
    mutate(
      propensity = as.numeric(ps[as.character(person_id)]),
      delta_ps = round(abs(propensity - focal_ps), 6),
      year_diff = abs(as.numeric(assessment_year) - as.numeric(focal$assessment_year)),
      selected = person_id %in% matched_ids,
      has_d2 = person_id %in% has_d2
    ) %>%
    transmute(
      person_id,
      sex,
      age_band,
      assessment_year,
      assessment_centre,
      propensity,
      delta_ps,
      year_diff,
      selected,
      has_d2
    )

  list(
    focal = focal,
    focal_ps = focal_ps,
    matched = matched_tbl,
    nearest = nearest_tbl
  )
}

ui <- fluidPage(
  titlePanel("Match-DT MatchIt explorer (dummy data)"),
  tags$p(
    "Nearest-neighbour matching uses a logistic propensity score on ",
    tags$code("sex + age_band + assessment_year + assessment_centre"),
    ", with a hard ±", year_caliper, "-year caliper on assessment year ",
    "(same call as ", tags$code("prong1_run_rr_direction"), "). ",
    "Scores are fit on all D1-exposed people vs the rest of the clinic, then we zoom in on one patient."
  ),
  sidebarLayout(
    sidebarPanel(
      width = 3,
      selectInput(
        "d1", "D1 (exposure)",
        choices = d1_labels,
        selected = default_d1
      ),
      selectInput(
        "d2", "D2 (optional, for has_d2 column)",
        choices = c("(none)" = "", setNames(disease_n_patient$icd10, paste0(
          disease_n_patient$icd10, " — ", disease_n_patient$disease_name
        ))),
        selected = "C34"
      ),
      hr(),
      selectInput("filter_sex", "Filter sex", choices = c("Any", "female", "male")),
      selectInput(
        "filter_age", "Filter age band",
        choices = c("Any", levels(clinic$age_band))
      ),
      selectInput(
        "filter_centre", "Filter centre",
        choices = c("Any", sort(as.character(unique(clinic$assessment_centre))))
      ),
      sliderInput(
        "filter_year", "Filter assessment year",
        min = min(clinic$assessment_year, na.rm = TRUE),
        max = max(clinic$assessment_year, na.rm = TRUE),
        value = range(clinic$assessment_year, na.rm = TRUE),
        sep = ""
      ),
      selectizeInput(
        "focal_id",
        "Exposed patient",
        choices = NULL,
        options = list(
          placeholder = "Type person_id or covariates to search…",
          maxOptions = 50
        )
      ),
      textOutput("patient_count"),
      actionButton("run", "Run match for selected D1", class = "btn-primary"),
      helpText(
        "Matching can take a few seconds on the full dummy cohort. ",
        "Result is cached per D1 until you change D1 and click again."
      )
    ),
    mainPanel(
      width = 9,
      h4("Focal patient"),
      verbatimTextOutput("focal_summary"),
      h4("Matched neighbours (selected by MatchIt)"),
      tableOutput("matched_table"),
      h4("Propensity scores: focal vs matched controls"),
      plotOutput("ps_plot", height = "280px"),
      h4("Nearest 20 year-eligible controls by |Δ PS|"),
      tags$p("Includes people who passed the year caliper but were not chosen (competition / ratio limit)."),
      tableOutput("nearest_table")
    )
  )
)

server <- function(input, output, session) {
  match_cache <- reactiveVal(NULL)

  exposed_pool <- reactive({
    req(input$d1)
    ids <- prong1_cases_for_code(diagnoses, input$d1)$person_id
    clinic %>% filter(person_id %in% ids)
  })

  filtered_exposed <- reactive({
    df <- exposed_pool()
    if (!identical(input$filter_sex, "Any")) {
      df <- df %>% filter(as.character(sex) == input$filter_sex)
    }
    if (!identical(input$filter_age, "Any")) {
      df <- df %>% filter(as.character(age_band) == input$filter_age)
    }
    if (!identical(input$filter_centre, "Any")) {
      df <- df %>% filter(as.character(assessment_centre) == input$filter_centre)
    }
    df %>%
      filter(
        assessment_year >= input$filter_year[[1]],
        assessment_year <= input$filter_year[[2]]
      )
  })

  # Keep the large exposed-patient list on the server; selectize searches it.
  output$patient_count <- renderText({
    n <- nrow(filtered_exposed())
    if (n == 0L) {
      "No exposed patients match these filters."
    } else {
      paste0(n, " exposed patients (server-side search).")
    }
  })

  observe({
    df <- filtered_exposed()
    if (nrow(df) == 0L) {
      updateSelectizeInput(
        session, "focal_id",
        choices = character(0),
        selected = "",
        server = TRUE
      )
      return()
    }
    choices <- df %>%
      arrange(person_id) %>%
      transmute(
        label = paste0(
          person_id, " | ", sex, " | ", age_band, " | ",
          assessment_year, " | ", assessment_centre
        ),
        value = person_id
      )
    named <- setNames(choices$value, choices$label)
    # isolate so choosing a patient does not re-push the full choice list.
    keep <- isolate({
      cur <- input$focal_id
      if (!is.null(cur) && nzchar(cur) && cur %in% named) cur else named[[1]]
    })
    updateSelectizeInput(
      session, "focal_id",
      choices = named,
      selected = keep,
      server = TRUE
    )
  })

  observeEvent(input$run, {
    req(input$d1)
    withProgress(message = paste("Matching for D1 =", input$d1), value = 0.2, {
      res <- tryCatch(
        run_d1_match(input$d1),
        error = function(e) {
          showNotification(conditionMessage(e), type = "error", duration = 10)
          NULL
        }
      )
      incProgress(0.8)
      match_cache(res)
    })
  })

  inspection <- reactive({
    res <- match_cache()
    req(res, input$focal_id)
    if (!identical(res$d1_code, input$d1)) {
      return(NULL)
    }
    d2 <- if (is.null(input$d2) || !nzchar(input$d2)) NULL else input$d2
    inspect_focal(res, input$focal_id, d2)
  })

  output$focal_summary <- renderPrint({
    res <- match_cache()
    insp <- inspection()
    if (is.null(res)) {
      cat("Click “Run match for selected D1” to fit MatchIt.\n")
      return(invisible())
    }
    if (is.null(insp)) {
      cat(
        "Match is ready for D1 = ", res$d1_code,
        " (exposed n=", res$n_exposed, ", control pool n=", res$n_control_pool, ").\n",
        "Select an exposed patient who has this D1.\n",
        sep = ""
      )
      return(invisible())
    }
    f <- insp$focal
    d1_date <- res$df_d1$diagnosis_date[res$df_d1$person_id == rownames(f)]
    cat(
      "person_id:          ", rownames(f), "\n",
      "sex:                ", as.character(f$sex), "\n",
      "age_at_baseline:    ", f$age_at_baseline, " (band ", as.character(f$age_band), ")\n",
      "baseline_date:      ", as.character(f$baseline_date), "\n",
      "assessment_year:    ", f$assessment_year, "\n",
      "assessment_centre:  ", as.character(f$assessment_centre), "\n",
      "D1:                 ", res$d1_code, " onset ", as.character(d1_date), "\n",
      "propensity score:   ", signif(insp$focal_ps, 6), "\n",
      "matched controls:   ", nrow(insp$matched), " (ratio target ", match_ratio, ")\n",
      "distance:           logistic PS (glm/logit); year caliper ±", year_caliper, "\n",
      sep = ""
    )
  })

  output$matched_table <- renderTable({
    insp <- inspection()
    req(insp)
    insp$matched
  }, digits = 6)

  output$nearest_table <- renderTable({
    insp <- inspection()
    req(insp)
    insp$nearest
  }, digits = 6)

  output$ps_plot <- renderPlot({
    insp <- inspection()
    req(insp)
    plot_df <- bind_rows(
      tibble(
        person_id = rownames(insp$focal),
        propensity = insp$focal_ps,
        role = "focal"
      ),
      insp$matched %>% transmute(person_id, propensity, role = "matched control")
    )
    ggplot(plot_df, aes(x = propensity, y = role, color = role)) +
      geom_point(size = 3, alpha = 0.85) +
      scale_color_manual(values = c("focal" = "#D55E00", "matched control" = "#0072B2")) +
      labs(
        x = "Propensity score P(D1 | covariates)",
        y = NULL,
        title = paste("Focal", rownames(insp$focal), "and its MatchIt neighbours")
      ) +
      theme_classic(base_size = 12) +
      theme(legend.position = "none")
  })
}

shinyApp(ui, server)
