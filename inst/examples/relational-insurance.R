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
  policy_contract <- tw_contract(
    "insurance.policy_months.schema",
    columns = policy_columns,
    key = c("policy_id", "month"),
    grain = "One monthly snapshot row per policy, including inactive policies."
  )
  payment_contract <- tw_contract(
    "insurance.payments.schema",
    columns = payment_columns,
    key = "payment_id",
    grain = "One cash transaction, assigned to its receipt month."
  )
  mart_structure <- tw_contract(
    "insurance.monthly_performance.structure",
    columns = mart_columns,
    grain = "One company-channel-month; all monetary values are synthetic EUR."
  )
  list(
    brokers = tw_contract(
      "insurance.brokers.schema",
      columns = c(
        broker_id = "character",
        broker_name = "character",
        channel = "character"
      ),
      key = "broker_id",
      grain = "One row per broker; attributes are static in this example."
    ),
    policy_months = policy_contract,
    payments = payment_contract,
    enriched_policy_months = tw_contract_update(
      policy_contract,
      id = "insurance.enriched_policy_months.schema",
      columns = c(broker_name = "character", channel = "character"),
      required = c(policy_contract$required, "broker_name", "channel")
    ),
    enriched_payments = tw_contract_update(
      payment_contract,
      id = "insurance.enriched_payments.schema",
      columns = c(
        company = "character",
        broker_id = "character",
        broker_name = "character",
        channel = "character",
        policy_status = "character"
      ),
      required = c(
        payment_contract$required,
        "company",
        "broker_id",
        "broker_name",
        "channel",
        "policy_status"
      )
    ),
    core_policy_monthly = tw_contract(
      "insurance.core_policy_monthly.schema",
      columns = policy_summary,
      grain = "One company-channel-month policy aggregate."
    ),
    core_cash_monthly = tw_contract(
      "insurance.core_cash_monthly.schema",
      columns = payment_summary,
      grain = "One company-channel-month cash aggregate."
    ),
    mart_schema = mart_structure,
    mart = tw_contract_update(
      mart_structure,
      id = "insurance.monthly_performance.schema",
      key = c("company", "channel", "month"),
      rules = list(
        non_negative_counts = ~ active_policies >= 0 & payment_count >= 0,
        non_negative_amounts = ~ premium_due >= 0 & cash_collected >= 0
      )
    )
  )
}

insurance_metrics <- function() {
  tw_metric_set(
    "insurance.monthly_performance",
    active_policies = sum(active_policies, na.rm = TRUE),
    premium_due = sum(premium_due, na.rm = TRUE),
    cash_collected = sum(cash_collected, na.rm = TRUE),
    cash_to_due = sum(cash_collected, na.rm = TRUE) /
      sum(premium_due, na.rm = TRUE),
    dimensions = c("company", "channel"),
    time_column = "month",
    time_behavior = c(
      active_policies = "stock",
      premium_due = "flow",
      cash_collected = "flow",
      cash_to_due = "flow"
    ),
    units = c(
      active_policies = "policies",
      premium_due = "EUR",
      cash_collected = "EUR",
      cash_to_due = "ratio"
    ),
    approved = TRUE,
    code_version = "insurance-example-v3"
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
    stop("Install example dependencies: ", paste(missing, collapse = ", "))
  }
  if (!file.exists(executable) && !nzchar(Sys.which(executable))) {
    stop("Install dbt-duckdb and supply its dbt executable.")
  }
  backend <- match.arg(backend, c("ducklake", "duckdb"))
  if (
    file.exists(path) &&
      (!dir.exists(path) ||
        length(list.files(path, all.files = TRUE, no.. = TRUE)))
  ) {
    stop("Choose a new or empty example directory.")
  }

  inputs <- insurance_inputs()
  vapply(inputs, nrow, integer(1))

  config <- tw_lake_config(
    path = file.path(path, "lake"),
    backend = backend,
    layers = c("raw", "staging", "core", "marts")
  )
  execution <- tw_execution_config(
    quality = "pointblank",
    relationships = "dm",
    to = config
  )

  contracts <- insurance_contracts()

  deliveries <- list(
    brokers = tw_product(
      "insurance.brokers",
      inputs$brokers,
      execution = execution
    ) |>
      tw_add_contract(contracts$brokers) |>
      tw_add_quality(~ channel %in% c("broker", "direct", "partner")),
    policy_months = tw_product(
      "insurance.policy_months",
      inputs$policy_months,
      execution = execution
    ) |>
      tw_add_contract(contracts$policy_months) |>
      tw_add_quality(
        ~ status %in% c("active", "pending", "lapsed") & premium_due >= 0
      ),
    payments = tw_product(
      "insurance.payments",
      inputs$payments,
      execution = execution
    ) |>
      tw_add_contract(contracts$payments) |>
      tw_add_quality(~ cash_amount > 0)
  )
  raw <- lapply(deliveries, tw_ingest)
  tw_quality(raw$payments)

  policy_product <- tw_product(
    "insurance.policy_months.enriched",
    raw$policy_months,
    source_name = "policy_months",
    execution = execution
  ) |>
    tw_add_lookup(raw$brokers, by = dplyr::join_by(broker_id)) |>
    tw_add_contract(contracts$enriched_policy_months)

  policy_attributes <- tw_product(
    "insurance.payment_policy_attributes",
    raw$policy_months
  ) |>
    dplyr::select(policy_id, month, company, broker_id, policy_status = status)

  payment_product <- tw_product(
    "insurance.payments.enriched",
    raw$payments,
    source_name = "payments",
    execution = execution
  ) |>
    tw_add_lookup(policy_attributes, by = dplyr::join_by(policy_id, month)) |>
    tw_add_lookup(raw$brokers, by = dplyr::join_by(broker_id)) |>
    tw_add_contract(contracts$enriched_payments)

  published <- list(
    policies = policy_product |> tw_publish(layer = "staging"),
    payments = payment_product |> tw_publish(layer = "staging")
  )
  stopifnot(
    nrow(tw_collect(published$policies)) == 12L,
    nrow(tw_collect(published$payments)) == 10L
  )

  template <- system.file(
    "examples",
    "relational-insurance",
    "dbt",
    package = "tidyweave"
  )
  project_path <- file.path(path, "analytics")
  dir.create(project_path, recursive = TRUE, showWarnings = FALSE)
  stopifnot(all(file.copy(
    list.files(template, full.names = TRUE, all.files = TRUE, no.. = TRUE),
    project_path,
    recursive = TRUE
  )))

  properties <- list(
    version = 2L,
    models = c(
      tw_dbt_contract(
        contracts$core_policy_monthly,
        "core_policy_monthly"
      )$models,
      tw_dbt_contract(contracts$core_cash_monthly, "core_cash_monthly")$models,
      tw_dbt_contract(contracts$mart_schema, "monthly_performance")$models
    )
  )
  yaml::write_yaml(
    properties,
    file.path(project_path, "models", "contracts.yml")
  )

  project <- tw_dbt_project(
    project_path,
    lake = config,
    sources = published,
    executable = executable
  )
  built <- project |> tw_run(echo = FALSE)
  approved <- built |>
    tw_publish(
      "monthly_performance",
      contract = contracts$mart,
      asset = "insurance.monthly_performance",
      layer = "marts"
    )

  metrics <- insurance_metrics()
  january <- as.Date("2026-01-01")
  february <- as.Date("2026-02-01")

  measures <- tw_measure(
    approved,
    metrics = metrics,
    at = c(january, february),
    period = "each"
  )
  summary <- tw_collect(measures)
  totals <- tw_measure(
    approved,
    metrics = metrics[c("cash_collected", "cash_to_due")],
    at = c(january, february),
    period = "aggregate"
  )
  by_channel <- tw_measure(
    approved,
    metrics = metrics["cash_collected"],
    at = january,
    by = c("company", "channel")
  )
  tw_collect(by_channel)

  report <- tw_report_release(
    measures,
    "insurance.report.initial",
    to = config,
    code_version = "insurance-report-v1",
    params = list(currency = "EUR", months = c("2026-01", "2026-02"))
  )
  initial <- list(
    build = built,
    release = approved,
    data = tw_collect(approved),
    metrics = metrics,
    measures = measures,
    totals = totals,
    by_channel = by_channel,
    report = report,
    summary = summary
  )

  bad_payments <- inputs$payments
  bad_payments$cash_amount[1] <- -60
  rejected <- tw_product("insurance.payments", bad_payments) |>
    tw_add_contract(contracts$payments) |>
    tw_add_quality(~ cash_amount > 0) |>
    tw_ingest(execution = execution, stop_on_failure = FALSE)
  stopifnot(tw_status(rejected)$outcome == "blocked")

  orphan_policies <- inputs$policy_months
  orphan_policies$broker_id[1] <- "B404"
  orphan_run <- policy_product |>
    tw_publish(
      sources = list(policy_months = orphan_policies),
      layer = "staging",
      stop_on_failure = FALSE
    )
  stopifnot(tw_status(orphan_run)$outcome == "failed")
  lake <- tw_connect_lake(config, read_only = TRUE)
  current_policy_release <- tw_releases(
    lake,
    published$policies$asset
  )$release_id[[1]]
  tw_close_lake(lake)
  stopifnot(identical(current_policy_release, published$policies$release_id))

  two_month_stock <- tryCatch(
    tw_measure(
      approved,
      metrics = metrics["active_policies"],
      at = c(january, february),
      period = "aggregate"
    ),
    error = identity
  )
  undefined_ratio <- tryCatch(
    tw_measure(
      approved,
      metrics$cash_to_due,
      at = february,
      filters = list(company = "Northstar", channel = "direct")
    ),
    error = identity
  )
  stopifnot(
    inherits(two_month_stock, "error"),
    inherits(undefined_ratio, "error")
  )

  monthly <- tw_workflow(
    received = function(payments) {
      deliveries$payments |>
        tw_replace_sources(insurance.payments = payments) |>
        tw_ingest()
    },
    enriched = function(received) {
      payment_product |>
        tw_publish(sources = list(payments = received), layer = "staging")
    },
    built = function(enriched) {
      project |> tw_run(sources = list(payments = enriched), echo = FALSE)
    },
    released = function(built) {
      built |>
        tw_publish(
          "monthly_performance",
          contract = contracts$mart,
          asset = "insurance.monthly_performance",
          layer = "marts"
        )
    },
    measures = function(released) {
      tw_measure(
        released,
        metrics = metrics,
        at = c(january, february),
        period = "each"
      )
    },
    inputs = list(payments = inputs$payments),
    code_version = "insurance-workflow-v1"
  )
  corrected_inputs <- insurance_corrected_inputs(inputs)
  correction <- tw_run(
    monthly,
    inputs = list(payments = corrected_inputs$payments)
  )
  tw_status(correction)
  corrected_raw <- raw
  corrected_raw$payments <- correction$results$received
  corrected_products <- published
  corrected_products$payments <- correction$results$enriched
  rebuilt <- correction$results$built
  corrected_release <- correction$results$released

  corrected_measures <- correction$results$measures
  corrected_totals <- tw_measure(
    corrected_release,
    metrics = metrics[c("cash_collected", "cash_to_due")],
    at = c(january, february),
    period = "aggregate"
  )

  corrected_report <- tw_report_release(
    corrected_measures,
    "insurance.report.corrected",
    to = config,
    code_version = "insurance-report-v1",
    params = list(currency = "EUR", months = c("2026-01", "2026-02"))
  )
  preserved <- list(
    report = tw_report_read(config, report$id, values_only = TRUE),
    data = tw_collect(approved)
  )
  corrected_summary <- tw_collect(corrected_measures)
  corrected <- list(
    raw = corrected_raw,
    products = corrected_products,
    build = rebuilt,
    release = corrected_release,
    data = tw_collect(corrected_release),
    metrics = metrics,
    measures = corrected_measures,
    totals = corrected_totals,
    report = corrected_report,
    summary = corrected_summary
  )
  stopifnot(
    isTRUE(all.equal(preserved$report, summary)),
    identical(
      dplyr::filter(summary, .metric == "cash_collected")$value,
      c(980, 1300)
    ),
    identical(
      dplyr::filter(corrected_summary, .metric == "cash_collected")$value,
      c(1230, 1300)
    ),
    dplyr::filter(
      tw_collect(corrected_totals),
      .metric == "cash_to_due"
    )$value ==
      2530 / 2850,
    sum(preserved$data$cash_collected[preserved$data$month == january]) == 980
  )

  list(
    context = list(
      path = path,
      config = config,
      inputs = inputs,
      contracts = contracts
    ),
    raw = raw,
    definitions = list(policies = policy_product, payments = payment_product),
    products = published,
    project = project,
    initial = initial,
    corrected = corrected,
    failures = list(
      pointblank = rejected,
      dm = list(
        result = orphan_run,
        current_release = current_policy_release,
        previous_release = published$policies$release_id
      )
    ),
    preserved = preserved
  )
}
