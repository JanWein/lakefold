# lakefold

**Daten ingestieren, mit dbt aufbauen und als relationale Modelle in R nutzen.**

lakefold verbindet DuckDB/DuckLake, dbt, dplyr und dm mit einer R-Schnittstelle.
Quellen, Verträge und Workflows sind explizite Spezifikationen; ausgeführt wird
erst mit einem eigenen Aufruf. Das Paket hieß bisher **dataloom**. Die bisherigen
`dl_*`-Funktionen bleiben erhalten.

> Entwicklungsstand 0.3.0: lokal einsetzbar und mit automatisierten Tests versehen.
> Der Paket-Registry benötigt einen einzelnen schreibenden Prozess. dbt-Ausgaben
> und unveränderliche Paket-Releases haben unterschiedliche Garantien.

## Installation

```r
install.packages("remotes")
remotes::install_github("JanWein/lakefold", build_vignettes = TRUE)
library(lakefold)
```

R >= 4.2 und DuckDB >= 1.5.5 sind erforderlich. Für Vignetten wird Pandoc benötigt
(in RStudio normalerweise enthalten). Ohne Pandoc: `build_vignettes = FALSE`.
Für dbt zusätzlich `install.packages(c("processx", "yaml", "dm"))` und eine
separate dbt-Installation. Für den reinen R-Workflow ist dbt nicht erforderlich.

## Der Einstieg in R

Das Beispiel schreibt ausschließlich in einen temporären Ordner und ist auch
ohne DuckLake-Erweiterung ausführbar.

```r
library(lakefold)
root <- tempfile("lakefold-")
config <- dl_config(
  dl_catalog_duckdb(file.path(root, "lake.duckdb")),
  dl_storage_local(file.path(root, "data")),
  landing = file.path(root, "landing"), backend = "duckdb"
)
lake <- dl_connect(config)

path <- file.path(root, "orders.csv")
utils::write.csv(data.frame(order_id = 1:3, amount = c(25, 75, 50)),
  path, row.names = FALSE)
source <- dl_source("orders.file", path, reader = utils::read.csv)
contract <- dl_contract(
  "orders.contract", "1.0.0", "Analytics", "Order amounts", "One order",
  c(order_id = "integer", amount = "numeric"), key = "order_id"
)

release <- dl_ingest(lake, source, contract, "orders", code_version = "v1")
dl_tbl(lake, "orders", release$release_id) |> dplyr::collect()
dl_disconnect(lake)
unlink(root, recursive = TRUE)
```

Ungültige Lieferungen werden protokolliert und blockieren die Veröffentlichung.
Der bisherige gültige Release bleibt erhalten. Identische Eingaben und
Definitionen können einen vorhandenen Release wiederverwenden.

## dbt aus R steuern

```r
# Für einen vorhandenen, konfigurierten dbt-Projektordner:
project <- dl_dbt_project("analytics", profiles_dir = "analytics")
result <- project |> dl_execute(select = "+customer_revenue")
dl_dbt_status(result)
dl_dbt_lineage(result)
```

`dl_dbt_init(path, config)` erstellt alternativ ein lokales Starterprojekt mit
synthetischen Daten und Tests. Der [dbt-Leitfaden](vignettes/dbt-workflows.Rmd)
zeigt Installation, DuckLake-Anbindung, Fehlerdiagnose und das anschließende
`dm`-Modell. R-Verbindungen zum lokalen Katalog vor dbt schließen und danach neu
öffnen. Jeder Lauf hat eigene Artefakte, Exitcode und strukturierte Ergebnisse.

## Aufgabenverteilung

| Aufgabe | Schnittstelle | Garantie oder Grenze |
|---|---|---|
| Spezifikationen definieren | `dl_config()`, `dl_pipeline()`, `dl_dbt_project()` | Konstruktion startet keine Datenverarbeitung |
| Quellen einlesen | `dl_ingest()`, Pipeline-Schritte | Originaldatei sichern, Vertrag prüfen, Release veröffentlichen |
| SQL-Modelle und Tests | `dl_dbt_build()`, `dl_dbt_test()` | dbt übernimmt DAG und Materialisierungen |
| R-Transformationen | `dl_step_transform()`, `dl_product()` | Normale R-Funktionen, lazy wo möglich |
| Relationale Analyse | `dl_model()`, `dl_dbt_model()` | `dm` mit ausdrücklich deklarierten Schlüsseln |
| Kennzahlen und Berichte | `dl_metric()`, `dl_measure()`, `dl_report_release()` | Versionierte Definitionen und Eingabereferenzen |
| Metadaten ansehen | `dl_registry()`, `dl_catalog()` | Register und lesender Shiny-Katalog |

## Wie ähnlich ist es tidymodels?

Die Bedienidee ist verwandt: **definieren, ansehen, ausführen, auswerten**.
Spezifikationen lassen sich per `|>` zusammensetzen und separat drucken;
`dl_execute()` ist der gemeinsame Ausführungseinstieg. Ergebnisse verwenden
Tibbles, dbplyr und dm statt eigener Tabellenformate.

Das Paket erreicht noch nicht die Reife und Erweiterbarkeit von tidymodels.
Es fehlen unter anderem ein einheitliches Diagnosesystem über beide Engines,
ein stabiler Adapter-Vertrag, Schema-Migrationen und koordinierte parallele
Schreibzugriffe. dbt deckt seinen SQL-DAG ab; einen gemeinsamen DAG für beliebige
R- und dbt-Aufgaben bietet das Paket noch nicht. Details und Prioritäten stehen
in der [Designbewertung](docs/DESIGN_REVIEW.md).

## Dokumentation

| Anliegen | Einstieg |
|---|---|
| In 10 Minuten loslegen | [Ausführbarer Einstieg](vignettes/getting-started.Rmd) |
| dbt, DuckLake und dm verbinden | [dbt-Workflow](vignettes/dbt-workflows.Rmd) |
| Pipeline erweitern | [Workflow-Konzept](vignettes/workflow-design.Rmd) |
| Qualitätsfehler und historische Daten | [Qualität und Historie](docs/QUALITY_AND_HISTORY.md) |
| Kennzahlen reproduzieren | [Produkte und Kennzahlen](docs/PRODUCTS_AND_METRICS.md) |
| Betrieb und Grenzen | [Betriebsleitfaden](docs/OPERATIONS.md) |
| Prüfstand nachvollziehen | [Validierung](docs/VALIDATION.md) |
| Von dataloom wechseln | [Migration](docs/MIGRATION.md) |

In R: `help(package = "lakefold")`, `?dl_ingest`, `?dl_dbt_build` und
`vignette(package = "lakefold")`. Die Funktionshilfe wird aus roxygen2-Kommentaren
generiert. Die GitHub-Workflows prüfen das Paket und bauen eine pkgdown-Website
und veröffentlichen sie auf GitHub Pages. Die Dokumentation ist zusätzlich
im installierten Paket verfügbar.

## Entwicklung

Die [Beitragsregeln](CONTRIBUTING.md) beschreiben Formatierung, Tests und den
vollständigen Paketcheck. Die Entwicklung folgt den Posit-Skills
[`r-package-development` und `testing-r-packages`](https://github.com/posit-dev/skills)
sowie den [R-Packages-Dokumentationsregeln](https://r-pkgs.org/man.html).

MIT-Lizenz. [English overview](README.en.md).
