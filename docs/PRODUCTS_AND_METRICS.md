# Products, relational models, metrics and reports

This is an advanced reference with illustrative snippets that assume your own
connected lake, contracts and registered assets. For a complete runnable example,
start with the [monthly reporting walkthrough](https://janwein.github.io/lakefold/articles/getting-started.html),
which introduces products and metrics only after a working import and quality check.

## Build a product from releases

```r
product <- dl_product(
  "finance.reporting", inputs = c(reserves = "finance.reserves"),
  build = function(inputs) inputs$reserves,
  contract = contract, code_version = "reporting-v1"
)
product |> dl_execute(lake)
```

`inputs` is a named vector of asset IDs. The builder receives a named list of
lazy tables. Specific input releases are resolved before the build and recorded
in lineage. A later source release does not automatically rebuild the product.
Pin every input when explicit repeatability is required:

```r
dl_build(lake, product, releases = c(reserves = input_release_id))
```

The product contract describes the output, which may differ from the source
schemas. Join multiple inputs with dplyr inside the builder. Review grain,
cardinality and potential row multiplication as part of the business logic.
A product currently publishes one result table, not an atomic multi-table bundle.

## Declare relationships with dm

```r
model <- dl_model(
  lake, tables = c(reserves = "finance.reserves"),
  primary_keys = list(reserves = c("id", "date"))
)
```

The optional dm integration returns a native model containing lazy tables and
pinned releases. Declared primary and foreign keys are checked. The product
function still determines joins and the desired grain. Power BI/DAX semantics
are not emulated.

## Define metric semantics

| Definition | Rule |
|---|---|
| `time_behavior = "stock"` | Exactly one non-missing business date in the selected input |
| `time_behavior = "flow"` | Multiple dates are allowed; the formula determines aggregation |
| `dimensions` | Only these columns are permitted in `by` and filters |
| `na_policy = "reject"` | Missing relevant inputs block calculation |
| `na_policy = "expression"` | The expression determines how missing values are handled |
| `approved = FALSE` | Calculation is blocked |

Using `expr = sum(amount, na.rm = TRUE)` with `na_policy = "reject"` still blocks
missing inputs at the preceding check. Choose `na_policy = "expression"`
explicitly when ignoring missing values is justified. Missing or non-finite
numeric outputs and empty custom outputs are rejected in either case.

```r
value <- metric |> dl_execute(lake,
  by = "company", at = as.Date("2026-08-31"),
  filters = list(company = c("Alpha", "Beta"))
)
```

This example assumes a metric with `company` as an approved dimension.
Use `compute = function(data, dimensions, params) ...` for ratios, weighted means
or more complex metrics. The callback must implement the requested grouping and
return the required columns. The framework cannot establish the economic
correctness of a formula.

## Record a report release

`dl_measure()` attaches a `dl_manifest` to its result. It contains the definition,
input release, parameters, input quality and result hash. `dl_report_release()`
stores the manifest and values. Later changes to those values are rejected;
an existing report identifier cannot be reused with different contents.

A new calculation of the same metric may carry a different calculation time in
its manifest. For an idempotent report-publication retry, reuse the same result
object or assign a new report version. PDF/Word rendering is a separate concern.

## Integrate with AI tools explicitly

The package calculates metrics without an LLM. The commons YAML export is a
limited declarative interface. It does not provide a tested chat/agent server,
authentication, a protected SQL endpoint or automatic validation of LLM queries.
Those components must be supplied separately for an authenticated chat service.


## Simpler metrics and reusable reports

Owner, description and unit are optional. Without `time_column` a metric defaults
to flow; with a time column it defaults to stock. Approval and `code_version`
remain explicit. `input_columns` declares inputs for unresolved selection or
custom functions. The default missing-value gate checks static data pronouns as
well as ordinary column symbols.

Use `dl_measure(..., record = FALSE)` for an exploratory calculation without
registry writes, or open the lake with `read_only = TRUE`. Result manifests still
contain full formula identity and pinned inputs. Identical recorded measurements
reuse their lineage edge. Use `dl_build(..., cache = FALSE)` to re-evaluate a
product builder that consults external state.

`dl_report_read(lake, "report-id", values_only = TRUE)` returns saved result
tables without recalculating. Identical retries of `dl_report_release()` keep
the original timestamps; a changed release, definition, parameter or value
requires a new report ID. See [Everyday workflows](https://janwein.github.io/lakefold/articles/everyday-workflows.html)
for an executable example and the migration guide for pre-0.6.0 metric versions.
