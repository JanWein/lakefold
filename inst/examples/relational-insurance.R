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

insurance_metrics <- function() {
  list(
    active_policies = metric(
      "insurance.active_policies",
      "insurance.monthly_performance",
      expr = sum(active_policies, na.rm = TRUE),
      dimensions = c("company", "channel"),
      time_column = "month",
      time_behavior = "stock",
      unit = "policies",
      description = "Active policies in one monthly snapshot.",
      approved = TRUE,
      code_version = "insurance-example-v2"
    ),
    premium_due = metric(
      "insurance.premium_due",
      "insurance.monthly_performance",
      expr = sum(premium_due, na.rm = TRUE),
      dimensions = c("company", "channel"),
      time_column = "month",
      time_behavior = "flow",
      unit = "EUR",
      description = "Premium charges due during the selected months.",
      approved = TRUE,
      code_version = "insurance-example-v2"
    ),
    cash_collected = metric(
      "insurance.cash_collected",
      "insurance.monthly_performance",
      expr = sum(cash_collected, na.rm = TRUE),
      dimensions = c("company", "channel"),
      time_column = "month",
      time_behavior = "flow",
      unit = "EUR",
      description = "Cash received during the selected months.",
      approved = TRUE,
      code_version = "insurance-example-v2"
    ),
    cash_to_due = metric(
      "insurance.cash_to_due",
      "insurance.monthly_performance",
      expr = sum(cash_collected, na.rm = TRUE) / sum(premium_due, na.rm = TRUE),
      dimensions = c("company", "channel"),
      time_column = "month",
      time_behavior = "flow",
      unit = "ratio",
      description = "Synthetic cash-to-due ratio of sums; undefined if total due is zero. Not a regulatory arrears measure.",
      approved = TRUE,
      code_version = "insurance-example-v2"
    )
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

  config <- lake_config(
    path = file.path(path, "lake"),
    backend = backend,
    layers = c("raw", "staging", "core", "marts")
  )

  contracts <- insurance_contracts()

  raw <- list(
    brokers = product("insurance.brokers", inputs$brokers) |>
      add_contract(contracts$brokers) |>
      add_quality(
        ~ channel %in% c("broker", "direct", "partner"),
        engine = "pointblank"
      ) |>
      ingest(to = config),
    policy_months = product("insurance.policy_months", inputs$policy_months) |>
      add_contract(contracts$policy_months) |>
      add_quality(
        ~ status %in% c("active", "pending", "lapsed") & premium_due >= 0,
        engine = "pointblank"
      ) |>
      ingest(to = config),
    payments = product("insurance.payments", inputs$payments) |>
      add_contract(contracts$payments) |>
      add_quality(~ cash_amount > 0, engine = "pointblank") |>
      ingest(to = config)
  )
  quality(raw$payments)

  policy_product <- product(
    "insurance.policy_months.enriched",
    raw$policy_months
  ) |>
    add_lookup(raw$brokers, by = dplyr::join_by(broker_id), engine = "dm") |>
    add_contract(contracts$enriched_policy_months)

  policy_attributes <- product(
    "insurance.payment_policy_attributes",
    raw$policy_months
  ) |>
    dplyr::select(policy_id, month, company, broker_id, policy_status = status)

  payment_product <- product("insurance.payments.enriched", raw$payments) |>
    add_lookup(
      policy_attributes,
      by = dplyr::join_by(policy_id, month),
      engine = "dm"
    ) |>
    add_lookup(raw$brokers, by = dplyr::join_by(broker_id), engine = "dm") |>
    add_contract(contracts$enriched_payments)

  published <- list(
    policies = policy_product |> publish(to = config, layer = "staging"),
    payments = payment_product |> publish(to = config, layer = "staging")
  )
  stopifnot(
    nrow(collect(published$policies)) == 12L,
    nrow(collect(published$payments)) == 10L
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
      dbt_contract(contracts$core_policy_monthly, "core_policy_monthly")$models,
      dbt_contract(contracts$core_cash_monthly, "core_cash_monthly")$models,
      dbt_contract(contracts$mart_schema, "monthly_performance")$models
    )
  )
  yaml::write_yaml(
    properties,
    file.path(project_path, "models", "contracts.yml")
  )

  project <- dbt_project(
    project_path,
    lake = config,
    sources = published,
    executable = executable
  )
  built <- project |> run(echo = FALSE)
  approved <- built |>
    publish(
      "monthly_performance",
      contract = contracts$mart,
      asset = "insurance.monthly_performance",
      layer = "marts"
    )

  metrics <- insurance_metrics()
  january <- as.Date("2026-01-01")
  february <- as.Date("2026-02-01")

  measures <- list(
    active_jan = measure(approved, metrics$active_policies, at = january),
    active_feb = measure(approved, metrics$active_policies, at = february),
    due_jan = measure(approved, metrics$premium_due, at = january),
    due_feb = measure(approved, metrics$premium_due, at = february),
    cash_jan = measure(approved, metrics$cash_collected, at = january),
    cash_feb = measure(approved, metrics$cash_collected, at = february),
    ratio_jan = measure(approved, metrics$cash_to_due, at = january),
    ratio_feb = measure(approved, metrics$cash_to_due, at = february),
    cash_total = measure(
      approved,
      metrics$cash_collected,
      at = c(january, february)
    ),
    ratio_total = measure(
      approved,
      metrics$cash_to_due,
      at = c(january, february)
    ),
    cash_by_channel_jan = measure(
      approved,
      metrics$cash_collected,
      at = january,
      by = c("company", "channel")
    )
  )

  lake <- connect_lake(config)
  report <- report_release(
    lake,
    "insurance.report.initial",
    measures,
    code_version = "insurance-report-v1",
    params = list(currency = "EUR", months = c("2026-01", "2026-02"))
  )
  close_lake(lake)
  summary <- tibble::tibble(
    month = c(january, february),
    active_policies = c(measures$active_jan$value, measures$active_feb$value),
    premium_due = c(measures$due_jan$value, measures$due_feb$value),
    cash_collected = c(measures$cash_jan$value, measures$cash_feb$value),
    cash_to_due = c(measures$ratio_jan$value, measures$ratio_feb$value)
  )
  initial <- list(
    build = built,
    release = approved,
    data = collect(approved),
    metrics = metrics,
    measures = measures,
    report = report,
    summary = summary
  )

  bad_payments <- inputs$payments
  bad_payments$cash_amount[1] <- -60
  rejected <- product("insurance.payments", bad_payments) |>
    add_contract(contracts$payments) |>
    add_quality(~ cash_amount > 0, engine = "pointblank") |>
    ingest(to = config, stop_on_failure = FALSE)
  stopifnot(rejected$status == "blocked")

  orphan_policies <- inputs$policy_months
  orphan_policies$broker_id[1] <- "B404"
  orphan_run <- policy_product |>
    add_source(orphan_policies, replace = TRUE) |>
    publish(to = config, layer = "staging", stop_on_failure = FALSE)
  stopifnot(orphan_run$status == "error")
  lake <- connect_lake(config, read_only = TRUE)
  current_policy_release <- releases(
    lake,
    published$policies$asset
  )$release_id[[1]]
  close_lake(lake)
  stopifnot(identical(current_policy_release, published$policies$release_id))

  two_month_stock <- tryCatch(
    measure(approved, metrics$active_policies, at = c(january, february)),
    error = identity
  )
  undefined_ratio <- tryCatch(
    measure(
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

  corrected_inputs <- insurance_corrected_inputs(inputs)
  corrected_raw <- raw
  corrected_raw$payments <- product(
    "insurance.payments",
    corrected_inputs$payments
  ) |>
    add_contract(contracts$payments) |>
    add_quality(~ cash_amount > 0, engine = "pointblank") |>
    ingest(to = config)
  corrected_products <- published
  corrected_payment_product <- payment_product |>
    add_source(corrected_raw$payments, replace = TRUE)
  corrected_products$payments <- corrected_payment_product |>
    publish(to = config, layer = "staging")
  project <- dbt_project(
    project_path,
    lake = config,
    sources = corrected_products,
    executable = executable
  )
  rebuilt <- project |> run(echo = FALSE)
  corrected_release <- rebuilt |>
    publish(
      "monthly_performance",
      contract = contracts$mart,
      asset = "insurance.monthly_performance",
      layer = "marts"
    )

  corrected_measures <- list(
    active_jan = measure(
      corrected_release,
      metrics$active_policies,
      at = january
    ),
    active_feb = measure(
      corrected_release,
      metrics$active_policies,
      at = february
    ),
    due_jan = measure(corrected_release, metrics$premium_due, at = january),
    due_feb = measure(corrected_release, metrics$premium_due, at = february),
    cash_jan = measure(corrected_release, metrics$cash_collected, at = january),
    cash_feb = measure(
      corrected_release,
      metrics$cash_collected,
      at = february
    ),
    ratio_jan = measure(corrected_release, metrics$cash_to_due, at = january),
    ratio_feb = measure(corrected_release, metrics$cash_to_due, at = february),
    cash_total = measure(
      corrected_release,
      metrics$cash_collected,
      at = c(january, february)
    ),
    ratio_total = measure(
      corrected_release,
      metrics$cash_to_due,
      at = c(january, february)
    ),
    cash_by_channel_jan = measure(
      corrected_release,
      metrics$cash_collected,
      at = january,
      by = c("company", "channel")
    )
  )

  lake <- connect_lake(config)
  corrected_report <- report_release(
    lake,
    "insurance.report.corrected",
    corrected_measures,
    code_version = "insurance-report-v1",
    params = list(currency = "EUR", months = c("2026-01", "2026-02"))
  )
  preserved <- list(report = report_read(lake, report$id, values_only = TRUE))
  close_lake(lake)
  preserved$data <- collect(approved)
  corrected_summary <- tibble::tibble(
    month = c(january, february),
    active_policies = c(
      corrected_measures$active_jan$value,
      corrected_measures$active_feb$value
    ),
    premium_due = c(
      corrected_measures$due_jan$value,
      corrected_measures$due_feb$value
    ),
    cash_collected = c(
      corrected_measures$cash_jan$value,
      corrected_measures$cash_feb$value
    ),
    cash_to_due = c(
      corrected_measures$ratio_jan$value,
      corrected_measures$ratio_feb$value
    )
  )
  corrected <- list(
    raw = corrected_raw,
    products = corrected_products,
    build = rebuilt,
    release = corrected_release,
    data = collect(corrected_release),
    metrics = metrics,
    measures = corrected_measures,
    report = corrected_report,
    summary = corrected_summary
  )
  stopifnot(
    preserved$report$cash_jan$value == 980,
    corrected$measures$cash_jan$value == 1230,
    corrected$measures$cash_feb$value == 1300,
    corrected$measures$ratio_total$value == 2530 / 2850,
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
