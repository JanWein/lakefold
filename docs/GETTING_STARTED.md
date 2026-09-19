# In zehn Minuten zum ersten Datenprodukt

Dieses Beispiel ist vollständig, benötigt keine Zugangsdaten und verwendet
synthetische Daten. Es läuft standardmäßig auf dem lokalen DuckDB-Testbackend.
Für DuckLake im `dl_config()` den Backendwert auf `"ducklake"` ändern; dann wird
die passende Erweiterung beim Verbinden geladen.

## Installation

```r
install.packages("remotes")
remotes::install_github("JanWein/lakefold")
library(lakefold)
library(dplyr)
```

R >= 4.2 ist nötig. Für vollständige Reproduzierbarkeit die Abhängigkeiten im
eigenen Projekt sperren. Das Repository ist eine Entwicklungsversion; die
Prüfnachweise stehen in [VALIDATION.md](VALIDATION.md).

## 1. Eine Lieferung erstellen

```r
root <- tempfile("lakefold-tutorial-")
dir.create(root)
input <- file.path(root, "reserves.csv")
write.csv(data.frame(
  id = c("A", "B"),
  date = c("2026-08-31", "2026-08-31"),
  amount = c(100, 200)
), input, row.names = FALSE)
```

## 2. Konfiguration und Contract definieren

```r
config <- dl_config(
  dl_catalog_duckdb(file.path(root, "metadata.duckdb")),
  dl_storage_local(file.path(root, "data")),
  landing = file.path(root, "landing"),
  backend = "duckdb"
)

contract <- dl_contract(
  id = "finance.reserves_contract", version = "1.0.0",
  owner = "Finance", description = "Reserve in EUR je Vertrag und Stichtag",
  grain = "Ein Vertrag an einem Stichtag",
  columns = c(id = "character", date = "Date", amount = "numeric"),
  key = c("id", "date"),
  rules = list(dl_rule("nonnegative", function(data) {
    counts <- data |>
      summarise(total = n(), failed = sum(as.integer(amount < 0), na.rm = TRUE)) |>
      collect()
    dl_quality_counts(counts$failed, counts$total)
  }))
)
```

`columns` beschreibt erwartete R-Typen. Der Reader muss sie herstellen; der
Contract konvertiert fehlerhafte Eingaben nicht stillschweigend. Standardmäßig
sind alle deklarierten Spalten erforderlich und nicht-null, zusätzliche Spalten
und leere Lieferungen sind nicht erlaubt.

## 3. Quelle und Ablauf zusammenstellen

```r
source <- dl_source("finance.csv", input, reader = function(path) {
  read.csv(path, colClasses = c("character", "Date", "numeric"))
})

pipeline <- dl_pipeline("finance.import", config, code_version = "tutorial-v1") |>
  dl_step_land(source) |>
  dl_step_extract() |>
  dl_step_transform(function(data) mutate(data, amount = amount * 1000),
                    id = "thousand_eur_to_eur") |>
  dl_step_validate(contract) |>
  dl_step_publish("finance.reserves")

pipeline
dl_plan(pipeline)
```

Hier werden Definitionen zusammengesetzt. Erst der nächste Aufruf öffnet den
Lake und liest die Quelldatei. Die Originaldatei enthält weiterhin 100 und 200;
der veröffentlichte Kandidat wird 100.000 und 200.000 EUR enthalten.

## 4. Ausführen und lesen

```r
run <- pipeline |> dl_execute(business_date = "2026-08-31")
run

lake <- dl_connect(config)
dl_tbl(lake, "finance.reserves") |> collect()
```

Erwartet: Status `published`, zwei Zeilen, Summe 300.000 EUR. Für Reproduzierbarkeit
explizit mit `dl_tbl(lake, "finance.reserves", release = run$release_id)` lesen.
`collect()` lädt das Resultat in R; vorher möglichst in DuckDB filtern/aggregieren.

## 5. Eine freigegebene Kennzahl berechnen

```r
reserve <- dl_metric(
  "finance.total_reserve", "finance.reserves",
  expr = sum(amount), time_column = "date", time_behavior = "stock",
  unit = "EUR", owner = "Finance", description = "Gesamte Reserve am Stichtag",
  approved = TRUE, code_version = "tutorial-v1"
)
value <- reserve |> dl_execute(lake, at = as.Date("2026-08-31"))
value
# value: 300000

dl_report_release(lake, "report-2026-08", list(reserve = value),
                  code_version = "tutorial-v1")
```

`approved = TRUE` erklärt eine fachliche Freigabe; es löst keinen Genehmigungsprozess
aus. Das Report-Release speichert Werte und Herkunft, rendert aber kein PDF oder Word.

## 6. Qualität und Wiederholung nachvollziehen

```r
again <- pipeline |> dl_execute(lake, business_date = "2026-08-31")
stopifnot(again$status == "cached", again$release_id == run$release_id)

dl_registry(lake, "runs")
dl_registry(lake, "quality_results")
dl_catalog_export(lake, file.path(root, "catalog.json"))
dl_disconnect(lake)
```

Der gleiche Input mit gleichen Definitionen und gleichem fachlichem Stichtag
wird nicht erneut veröffentlicht. Ein Cache-Treffer hat selbst kein neues
Quality-Tibble; die ursprünglichen Ergebnisse stehen unter dem ursprünglichen
Run in der Registry. Eine fehlgeschlagene Lieferung ersetzt keine freigegebenen Daten.

## Weiterführende Beispiele

* [Fehler, Korrekturen und historische Releases](QUALITY_AND_HISTORY.md)
* [Produkte, Joins, Kennzahlen und Reports](PRODUCTS_AND_METRICS.md)
* [Definition und Ausführung im Detail](WORKFLOWS.md)
* Vollständige Demo: `source(system.file("examples", "end_to_end.R", package = "lakefold"))`
* Katalog: `install.packages(c("shiny", "bslib"))`, danach
  `dl_catalog(snapshot = file.path(root, "catalog.json"))`

Für die Nutzung in eigenen Jobs eine Funktion um den Ablauf legen und geöffnete
Verbindungen mit `on.exit(dl_disconnect(lake), add = TRUE)` schließen.
