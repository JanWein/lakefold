# A complete synthetic example, not a new package API.
# Sourcing this file defines functions only. To run the external workflow:
# library(tidyweave)
# source(system.file("examples", "relational-insurance.R", package = "tidyweave"))
# demo <- run_relational_insurance(executable = "/path/to/dbt")
# demo$initial$summary

insurance_inputs <- function() {
  brokers <- tibble::tibble(
    broker_id = c("B1", "B2", "B3"),
    broker_name = c("Pine Brokers", "Direct Desk", "Harbor Partners"),
    channel = c("broker", "direct", "partner")
  )
  policy_months <- tibble::tibble(
    policy_id = rep(paste0("P", 1:6), 2),
    month = rep(as.Date(c("2026-01-01", "2026-02-01")), each = 6),
    company = rep(
      c("Northstar", "Northstar", "Northstar", "Harbor", "Harbor", "Northstar"),
      2
    ),
    broker_id = rep(c("B1", "B1", "B2", "B3", "B3", "B1"), 2),
    status = c(
      rep("active", 5),
      "pending",
      "active",
      "active",
      "lapsed",
      rep("active", 3)
    ),
    premium_due = c(100, 200, 300, 400, 500, 0, 100, 200, 0, 400, 500, 150)
  )
  payments <- tibble::tibble(
    payment_id = paste0("T", 1:10),
    policy_id = c("P1", "P1", "P2", "P3", "P4", "P1", "P2", "P4", "P5", "P6"),
    month = rep(as.Date(c("2026-01-01", "2026-02-01")), each = 5),
    payment_date = as.Date(c(
      "2026-01-05",
      "2026-01-20",
      "2026-01-08",
      "2026-01-10",
      "2026-01-12",
      "2026-02-05",
      "2026-02-08",
      "2026-02-12",
      "2026-02-15",
      "2026-02-18"
    )),
    cash_amount = c(60, 40, 180, 300, 400, 100, 200, 350, 500, 150)
  )
  list(brokers = brokers, policy_months = policy_months, payments = payments)
}

insurance_corrected_inputs <- function(inputs = insurance_inputs()) {
  inputs$payments <- dplyr::bind_rows(
    inputs$payments,
    tibble::tibble(
      payment_id = "T11",
      policy_id = "P5",
      month = as.Date("2026-01-01"),
      payment_date = as.Date("2026-01-28"),
      cash_amount = 250
    )
  )
  inputs
}

insurance_contracts <- function() {
  policy_columns <- c(
    policy_id = "character",
    month = "Date",
    company = "character",
    broker_id = "character",
    status = "character",
    premium_due = "numeric"
  )
  payment_columns <- c(
    payment_id = "character",
    policy_id = "character",
    month = "Date",
    payment_date = "Date",
    cash_amount = "numeric"
  )
  dimension_columns <- c(
    company = "character",
    channel = "character",
    month = "Date"
  )
  policy_summary <- c(
    dimension_columns,
    active_policies = "integer",
    premium_due = "numeric"
  )
  payment_summary <- c(
    dimension_columns,
    payment_count = "integer",
    cash_collected = "numeric"
  )
  mart_columns <- c(
    policy_summary,
    payment_count = "integer",
    cash_collected = "numeric"
  )
  list(
    brokers = contract(
      "insurance.brokers.schema",
      columns = c(
        broker_id = "character",
        broker_name = "character",
        channel = "character"
      ),
      key = "broker_id",
      grain = "One row per broker; attributes are static in this example."
    ),
    policy_months = contract(
      "insurance.policy_months.schema",
      columns = policy_columns,
      key = c("policy_id", "month"),
      grain = "One monthly snapshot row per policy, including inactive policies."
    ),
    payments = contract(
      "insurance.payments.schema",
      columns = payment_columns,
      key = "payment_id",
      grain = "One cash transaction, assigned to its receipt month."
    ),
    enriched_policy_months = contract(
      "insurance.enriched_policy_months.schema",
      columns = c(
        policy_columns,
        broker_name = "character",
        channel = "character"
      ),
      key = c("policy_id", "month"),
      grain = "One policy-month, enriched with a single broker."
    ),
    enriched_payments = contract(
      "insurance.enriched_payments.schema",
      columns = c(
        payment_columns,
        company = "character",
        broker_id = "character",
        broker_name = "character",
        channel = "character",
        policy_status = "character"
      ),
      key = "payment_id",
      grain = "One payment, enriched through its policy-month and broker."
    ),
    core_policy_monthly = contract(
      "insurance.core_policy_monthly.schema",
      columns = policy_summary,
      grain = "One company-channel-month policy aggregate."
    ),
    core_cash_monthly = contract(
      "insurance.core_cash_monthly.schema",
      columns = payment_summary,
      grain = "One company-channel-month cash aggregate."
    ),
    mart_schema = contract(
      "insurance.monthly_performance.structure",
      columns = mart_columns,
      grain = "One company-channel-month, combining separately aggregated stocks and flows."
    ),
    mart = contract(
      "insurance.monthly_performance.schema",
      columns = mart_columns,
      key = c("company", "channel", "month"),
      rules = list(
        quality_rule(
          "non_negative_counts",
          ~ active_policies >= 0 & payment_count >= 0
        ),
        quality_rule(
          "non_negative_amounts",
          ~ premium_due >= 0 & cash_collected >= 0
        )
      ),
      grain = "One company-channel-month; all monetary values are synthetic EUR."
    )
  )
}

insurance_checks <- function() {
  list(
    brokers = pointblank_checks("known_channels", function(data) {
      pointblank::create_agent(tbl = data) |>
        pointblank::col_vals_in_set(
          columns = channel,
          set = c("broker", "direct", "partner")
        )
    }),
    policy_months = pointblank_checks("policy_values", function(data) {
      pointblank::create_agent(tbl = data) |>
        pointblank::col_vals_in_set(
          columns = status,
          set = c("active", "pending", "lapsed")
        ) |>
        pointblank::col_vals_gte(columns = premium_due, value = 0)
    }),
    payments = pointblank_checks("positive_cash", function(data) {
      pointblank::create_agent(tbl = data) |>
        pointblank::col_vals_gt(columns = cash_amount, value = 0)
    })
  )
}

insurance_setup <- function(
  path = tempfile("tidyweave-insurance-"),
  backend = "ducklake"
) {
  backend <- match.arg(backend, c("ducklake", "duckdb"))
  if (
    file.exists(path) &&
      (!dir.exists(path) ||
        length(list.files(path, all.files = TRUE, no.. = TRUE)))
  ) {
    stop("Choose a new or empty example directory.", call. = FALSE)
  }
  config <- lake_config(
    registry_duckdb(file.path(path, "metadata.ducklake")),
    storage_local(file.path(path, "data")),
    landing = file.path(path, "landing"),
    layers = c("raw", "staging", "core", "marts"),
    backend = backend
  )
  list(
    path = path,
    config = config,
    inputs = insurance_inputs(),
    contracts = insurance_contracts()
  )
}

insurance_ingest <- function(context, inputs = context$inputs) {
  checks <- insurance_checks()
  result <- lapply(names(inputs), function(name) {
    ingest(
      context$config,
      inputs[[name]],
      name = paste0("insurance.", name),
      contract = context$contracts[[name]],
      quality = checks[[name]]
    )
  })
  stats::setNames(result, names(inputs))
}

# dm_examine_constraints() reports violations; it does not stop execution itself.
insurance_dm <- function(tables, check = TRUE) {
  relational <- dm::dm(
    brokers = tables$brokers,
    policy_months = tables$policy_months
  ) |>
    dm::dm_add_pk(brokers, broker_id) |>
    dm::dm_add_pk(policy_months, c(policy_id, month)) |>
    dm::dm_add_fk(policy_months, broker_id, brokers, broker_id)
  if (!is.null(tables$payments)) {
    relational <- relational |>
      dm::dm(payments = tables$payments) |>
      dm::dm_add_pk(payments, payment_id) |>
      dm::dm_add_fk(
        payments,
        c(policy_id, month),
        policy_months,
        c(policy_id, month)
      )
  }
  checks <- dm::dm_examine_constraints(relational)
  if (check && any(!checks$is_key)) {
    rlang::abort(
      "Insurance relationships failed; inspect the dm constraint table before joining.",
      class = "insurance_relationship_error",
      checks = checks
    )
  }
  relational
}

insurance_enrich_policies <- function(tables) {
  insurance_dm(tables) |>
    dm::dm_flatten_to_tbl(.start = policy_months, .recursive = TRUE) |>
    dplyr::select(
      policy_id,
      month,
      company,
      broker_id,
      status,
      premium_due,
      broker_name,
      channel
    )
}

insurance_enrich_payments <- function(tables) {
  insurance_dm(tables) |>
    dm::dm_flatten_to_tbl(.start = payments, .recursive = TRUE) |>
    dplyr::transmute(
      payment_id,
      policy_id,
      month,
      payment_date,
      cash_amount,
      company,
      broker_id,
      broker_name,
      channel,
      policy_status = status
    )
}

insurance_products <- function(context, raw) {
  pinned <- function(name) {
    source_release(context$config, raw[[name]]$asset, raw[[name]]$release_id)
  }
  list(
    policies = product("insurance.policy_months.enriched") |>
      add_source(pinned("policy_months"), name = "policy_months") |>
      add_source(pinned("brokers"), name = "brokers") |>
      add_transform(insurance_enrich_policies, name = "enrich_with_broker") |>
      add_contract(context$contracts$enriched_policy_months) |>
      set_target(target_lake(context$config, layer = "staging")),
    payments = product("insurance.payments.enriched") |>
      add_source(pinned("payments"), name = "payments") |>
      add_source(pinned("policy_months"), name = "policy_months") |>
      add_source(pinned("brokers"), name = "brokers") |>
      add_transform(
        insurance_enrich_payments,
        name = "enrich_with_policy_and_broker"
      ) |>
      add_contract(context$contracts$enriched_payments) |>
      set_target(target_lake(context$config, layer = "staging"))
  )
}

# This example writes ordinary dbt source YAML for STAGING releases.
# dbt_sources() deliberately accepts RAW ingestion results only.
insurance_bind_products <- function(project, products) {
  if (!identical(sort(names(products)), c("payments", "policies"))) {
    stop(
      "Supply the successful policies and payments product results.",
      call. = FALSE
    )
  }
  catalog_identity <- lapply(products, function(result) {
    result$output_config[c("backend", "catalog", "storage")]
  })
  if (!identical(catalog_identity[[1]], catalog_identity[[2]])) {
    stop(
      "Both staging products must belong to the same configured lake.",
      call. = FALSE
    )
  }
  lake <- connect_lake(products[[1]]$output_config, read_only = TRUE)
  on.exit(close_lake(lake), add = TRUE)
  tables <- lapply(names(products), function(name) {
    result <- products[[name]]
    if (
      !result$status %in% c("published", "cached") || is.na(result$release_id)
    ) {
      stop("Bind only successful, qualified staging releases.", call. = FALSE)
    }
    history <- releases(lake, result$asset)
    reference <- history[history$release_id == result$release_id, ]
    if (nrow(reference) != 1L || reference$schema_name != "staging") {
      stop(
        "The exact staging release was not found in the registry.",
        call. = FALSE
      )
    }
    list(
      name = name,
      identifier = reference$table_name[[1]],
      config = list(
        meta = list(
          tidyweave = list(
            asset = result$asset,
            release_id = result$release_id,
            run_id = result$run_id
          )
        )
      )
    )
  })
  yaml::write_yaml(
    list(
      version = 2L,
      sources = list(list(
        name = "accepted_products",
        database = "lake",
        schema = "staging",
        quoting = list(database = TRUE, schema = TRUE, identifier = TRUE),
        tables = tables
      ))
    ),
    file.path(project$path, "models", "sources.yml")
  )
  invisible(project)
}

insurance_dbt_project <- function(context, products, executable = "dbt") {
  template <- system.file(
    "examples",
    "relational-insurance",
    "dbt",
    package = "tidyweave"
  )
  if (!nzchar(template)) {
    stop(
      "Install tidyweave with the relational-insurance example files.",
      call. = FALSE
    )
  }
  path <- file.path(context$path, "analytics")
  if (
    dir.exists(path) && length(list.files(path, all.files = TRUE, no.. = TRUE))
  ) {
    stop("The example's dbt directory must be new or empty.", call. = FALSE)
  }
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  for (file in list.files(
    template,
    recursive = TRUE,
    all.files = TRUE,
    no.. = TRUE
  )) {
    destination <- file.path(path, file)
    dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(file.path(template, file), destination)) {
      stop("Could not copy the dbt example.")
    }
  }
  config <- context$config
  attach <- list(path = config$catalog$path, alias = "lake")
  profile <- list(
    type = "duckdb",
    path = ":memory:",
    database = "lake",
    schema = "core",
    threads = 1L
  )
  if (config$backend == "ducklake") {
    attach$path <- paste0("ducklake:", config$catalog$path)
    attach$options <- list(DATA_PATH = paste0(config$storage$path, "/"))
    profile$extensions <- list("ducklake")
  }
  profile$attach <- list(attach)
  yaml::write_yaml(
    list(insurance = list(target = "dev", outputs = list(dev = profile))),
    file.path(path, "profiles.yml")
  )
  project <- dbt_project(
    path,
    profiles_dir = path,
    target = "dev",
    executable = executable
  )
  insurance_bind_products(project, products)
  # Keep the dbt schema bridge separate from R composite-key/business rules.
  properties <- list(
    version = 2L,
    models = c(
      dbt_contract(
        context$contracts$core_policy_monthly,
        "core_policy_monthly"
      )$models,
      dbt_contract(
        context$contracts$core_cash_monthly,
        "core_cash_monthly"
      )$models,
      dbt_contract(context$contracts$mart_schema, "monthly_performance")$models
    )
  )
  yaml::write_yaml(properties, file.path(path, "models", "contracts.yml"))
  project
}

insurance_metrics <- function() {
  list(
    active_policies = metric(
      "insurance.active_policies",
      "insurance.monthly_performance",
      expr = sum(active_policies),
      dimensions = c("company", "channel"),
      time_column = "month",
      time_behavior = "stock",
      unit = "policies",
      description = "Active policies in one monthly snapshot.",
      approved = TRUE,
      code_version = "insurance-example-v1"
    ),
    premium_due = metric(
      "insurance.premium_due",
      "insurance.monthly_performance",
      expr = sum(premium_due),
      dimensions = c("company", "channel"),
      time_column = "month",
      time_behavior = "flow",
      unit = "EUR",
      description = "Premium charges due during the selected months.",
      approved = TRUE,
      code_version = "insurance-example-v1"
    ),
    cash_collected = metric(
      "insurance.cash_collected",
      "insurance.monthly_performance",
      expr = sum(cash_collected),
      dimensions = c("company", "channel"),
      time_column = "month",
      time_behavior = "flow",
      unit = "EUR",
      description = "Cash received during the selected months.",
      approved = TRUE,
      code_version = "insurance-example-v1"
    ),
    cash_to_due = metric(
      "insurance.cash_to_due",
      "insurance.monthly_performance",
      expr = sum(cash_collected) / sum(premium_due),
      dimensions = c("company", "channel"),
      time_column = "month",
      time_behavior = "flow",
      unit = "ratio",
      description = "Synthetic cash-to-due ratio of sums; undefined if total due is zero. Not a regulatory arrears measure.",
      approved = TRUE,
      code_version = "insurance-example-v1"
    )
  )
}

insurance_measure <- function(context, release, report_id) {
  lake <- connect_lake(context$config)
  on.exit(close_lake(lake), add = TRUE)
  metrics <- insurance_metrics()
  january <- as.Date("2026-01-01")
  february <- as.Date("2026-02-01")
  pinned <- function(metric, at = NULL, by = character()) {
    measure(lake, metric, at = at, by = by, release = release$release_id)
  }
  measures <- list(
    active_jan = pinned(metrics$active_policies, january),
    active_feb = pinned(metrics$active_policies, february),
    due_jan = pinned(metrics$premium_due, january),
    due_feb = pinned(metrics$premium_due, february),
    cash_jan = pinned(metrics$cash_collected, january),
    cash_feb = pinned(metrics$cash_collected, february),
    ratio_jan = pinned(metrics$cash_to_due, january),
    ratio_feb = pinned(metrics$cash_to_due, february),
    cash_total = pinned(metrics$cash_collected, c(january, february)),
    ratio_total = pinned(metrics$cash_to_due, c(january, february)),
    cash_by_channel_jan = pinned(
      metrics$cash_collected,
      january,
      c("company", "channel")
    )
  )
  report <- report_release(
    lake,
    report_id,
    measures,
    code_version = "insurance-report-v1",
    params = list(currency = "EUR", months = c("2026-01", "2026-02"))
  )
  summary <- tibble::tibble(
    month = c(january, february),
    active_policies = c(measures$active_jan$value, measures$active_feb$value),
    premium_due = c(measures$due_jan$value, measures$due_feb$value),
    cash_collected = c(measures$cash_jan$value, measures$cash_feb$value),
    cash_to_due = c(measures$ratio_jan$value, measures$ratio_feb$value)
  )
  list(
    metrics = metrics,
    measures = measures,
    report = report,
    summary = summary
  )
}

run_relational_insurance <- function(
  path = tempfile("tidyweave-insurance-"),
  backend = "ducklake",
  executable = "dbt"
) {
  packages <- c("duckdb", "pointblank", "dm", "yaml", "processx")
  missing <- packages[
    !vapply(packages, requireNamespace, logical(1), quietly = TRUE)
  ]
  if (length(missing)) {
    stop(
      "Install example dependencies: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }
  if (!file.exists(executable) && !nzchar(Sys.which(executable))) {
    stop(
      "Install dbt-duckdb separately and supply its dbt executable.",
      call. = FALSE
    )
  }
  context <- insurance_setup(path, backend)
  raw <- insurance_ingest(context)
  tables <- lapply(raw, collect)
  relational <- insurance_dm(tables)
  dm_checks <- dm::dm_examine_constraints(relational)
  dm_preview <- list(
    policies = insurance_enrich_policies(tables),
    payments = insurance_enrich_payments(tables)
  )
  definitions <- insurance_products(context, raw)
  products <- lapply(definitions, run)

  # Pointblank rejects a negative cash transaction before RAW is persisted.
  bad_payments <- context$inputs$payments
  bad_payments$cash_amount[1] <- -60
  rejected <- ingest(
    context$config,
    bad_payments,
    name = "insurance.payments",
    contract = context$contracts$payments,
    quality = insurance_checks()$payments,
    stop_on_failure = FALSE
  )
  if (!identical(rejected$status, "blocked")) {
    rlang::abort(
      "The negative-payment example did not reach the expected blocked quality gate.",
      parent = rejected$error,
      result = rejected
    )
  }

  # A valid table shape does not establish relationships between tables.
  orphan <- context$inputs
  orphan$policy_months$broker_id[1] <- "B404"
  invalid_dm <- insurance_dm(orphan, check = FALSE)
  orphan_error <- tryCatch(insurance_enrich_policies(orphan), error = identity)
  stopifnot(inherits(orphan_error, "insurance_relationship_error"))
  orphan_definition <- definitions$policies |>
    add_source(orphan$policy_months, name = "policy_months", replace = TRUE)
  orphan_run <- run(orphan_definition, stop_on_failure = FALSE)
  current_policy_release <- attr(
    read_source(source_release(
      context$config,
      products$policies$asset
    )),
    "tw_input_reference"
  )$release_id
  stopifnot(
    orphan_run$status == "error",
    identical(current_policy_release, products$policies$release_id)
  )

  project <- insurance_dbt_project(context, products, executable)
  built <- dbt_build(project, echo = FALSE)
  approved <- dbt_publish(
    context$config,
    built,
    "monthly_performance",
    contract = context$contracts$mart,
    asset = "insurance.monthly_performance"
  )
  initial <- c(
    list(build = built, release = approved, data = collect(approved)),
    insurance_measure(context, approved, "insurance.report.initial")
  )

  # Full replacement snapshot: preserve the old transactions and add the correction.
  corrected_inputs <- insurance_corrected_inputs(context$inputs)
  corrected_raw <- raw
  corrected_raw$payments <- insurance_ingest(
    context,
    corrected_inputs["payments"]
  )$payments
  corrected_definitions <- insurance_products(context, corrected_raw)
  corrected_products <- products
  corrected_products$payments <- run(corrected_definitions$payments)
  insurance_bind_products(project, corrected_products)
  rebuilt <- dbt_build(project, echo = FALSE)
  corrected_release <- dbt_publish(
    context$config,
    rebuilt,
    "monthly_performance",
    contract = context$contracts$mart,
    asset = "insurance.monthly_performance"
  )
  corrected <- c(
    list(
      raw = corrected_raw,
      products = corrected_products,
      build = rebuilt,
      release = corrected_release,
      data = collect(corrected_release)
    ),
    insurance_measure(context, corrected_release, "insurance.report.corrected")
  )

  lake <- connect_lake(context$config, read_only = TRUE)
  on.exit(close_lake(lake), add = TRUE)
  preserved <- list(
    report = report_read(lake, "insurance.report.initial", values_only = TRUE),
    data = read_release(lake, approved$asset, release = approved$release_id)
  )
  expected <- list(
    initial = tibble::tibble(
      month = as.Date(c("2026-01-01", "2026-02-01")),
      active_policies = c(5L, 5L),
      premium_due = c(1500, 1350),
      cash_collected = c(980, 1300),
      cash_to_due = c(980 / 1500, 1300 / 1350)
    ),
    corrected = tibble::tibble(
      month = as.Date(c("2026-01-01", "2026-02-01")),
      active_policies = c(5L, 5L),
      premium_due = c(1500, 1350),
      cash_collected = c(1230, 1300),
      cash_to_due = c(1230 / 1500, 1300 / 1350)
    )
  )
  stopifnot(
    all(dm_checks$is_key),
    nrow(dm_preview$policies) == 12L,
    nrow(dm_preview$payments) == 10L,
    isTRUE(all.equal(
      initial$summary,
      expected$initial,
      check.attributes = FALSE
    )),
    isTRUE(all.equal(
      corrected$summary,
      expected$corrected,
      check.attributes = FALSE
    )),
    preserved$report$cash_jan$value == 980,
    sum(preserved$data$cash_collected[
      preserved$data$month == as.Date("2026-01-01")
    ]) ==
      980
  )
  list(
    context = context,
    raw = raw,
    definitions = definitions,
    products = products,
    dm_model = relational,
    dm_checks = dm_checks,
    dm_preview = dm_preview,
    project = project,
    initial = initial,
    corrected = corrected,
    failures = list(
      pointblank = rejected,
      dm = list(
        error = orphan_error,
        checks = dm::dm_examine_constraints(invalid_dm),
        result = orphan_run,
        previous_release = products$policies$release_id,
        current_release = current_policy_release
      )
    ),
    preserved = preserved,
    expected = expected
  )
}
