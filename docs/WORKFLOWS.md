# Definition, Inspektion und Ausführung

## Verbindung erst zur Ausführung

```r
library(lakefold)
config <- dl_config(
  catalog = dl_catalog_duckdb("metadata.ducklake"),
  storage = dl_storage_local("data"),
  landing = "landing"
)
config
```

Bis hier werden keine Ordner angelegt, Erweiterungen geladen oder Verbindungen
geöffnet. Pfade werden gegen das aktuelle Arbeitsverzeichnis aufgelöst. Eine
Definition kann mit `saveRDS()` gespeichert werden; referenzierte Dateien,
Packages und Closure-Umgebungen müssen in der ausführenden Umgebung verfügbar
sein. Das ist kein plattformunabhängiges Austauschformat.

`dl_setup(...)` bleibt der bequeme Aufruf für Konfiguration plus Verbindung.
`dl_connect(config)` öffnet eine vorhandene Konfiguration erneut.

## Objekt zuerst

| Definition | Einheitliche API | Bestehende API |
|---|---|---|
| Pipeline | `pipeline |> dl_execute(lake)` | `dl_run(pipeline, lake)` |
| Produkt | `product |> dl_execute(lake)` | `dl_build(lake, product)` |
| Metric | `metric |> dl_execute(lake, at = date)` | `dl_measure(lake, metric, at = date)` |

Eine Pipeline kennt ihre Konfiguration: `pipeline |> dl_execute()` genügt.
Produkte und Metrics benötigen eine Verbindung oder `dl_config`. Übergebene
Verbindungen bleiben offen. Von `dl_execute()` geöffnete Verbindungen werden
auch bei Fehlern geschlossen. Für mehrere zusammengehörige Aufrufe ist eine
explizite Verbindung meist effizienter.

```r
lake <- dl_connect(config)
# In einer Funktion: on.exit(dl_disconnect(lake), add = TRUE)
# ... Ausführungen ...
dl_disconnect(lake)
```

## Transformationen

```r
pipeline <- dl_pipeline("finance.import", config, code_version = "git-sha") |>
  dl_step_land(source) |>
  dl_step_extract() |>
  dl_step_transform(
    function(data) dplyr::mutate(data, amount = amount * 1000),
    id = "amount_in_eur"
  ) |>
  dl_step_transform(
    function(data) dplyr::select(data, id, date, amount),
    id = "select_contract_columns"
  ) |>
  dl_step_validate(contract) |>
  dl_step_publish("finance.validated")

dl_plan(pipeline)
```

`source` und `contract` sind zuvor definierte Objekte; ein vollständiges Beispiel
steht im [Schnellstart](GETTING_STARTED.md). Schritte dürfen beliebige R-Funktionen
nutzen. Ihre Rückgabe muss ein Data Frame oder eine Lazy Table sein. Bei Lazy
Tables bleibt SQL-fähige Verarbeitung in DuckDB. R-spezifische Funktionen müssen
explizit `collect()` verwenden und benötigen entsprechenden Arbeitsspeicher.

Der Reader verarbeitet ausschließlich die gesicherte Originaldatei. Die
Transformationen verändern den Raw-Stand nicht; sie bilden den Kandidateneingang.
Bei Partitionsersatz wird daraus zusammen mit den unveränderten alten Partitionen
der vollständige Kandidat gebildet. Der Contract prüft den gesamten Kandidaten.

`dl_plan()` ist eine Inspektion der deklarierten Struktur. Es prüft weder echte
Quelldaten noch SQL-Übersetzbarkeit, Zugriffsrechte oder Speicherverfügbarkeit.
`attr(dl_plan(pipeline), "complete")` bezeichnet lediglich einen vollständigen,
strukturell gültigen Ablauf. Die Lineage bleibt auf Dataset-/Release-Ebene;
Transformationsnamen erzeugen keine automatische Spalten-Lineage.

## Versionen richtig ändern

Eine ID und Version bezeichnen eine unveränderliche Definition. Wenn sich eine
Quelle oder ein Contract inhaltlich ändert, dessen Version erhöhen. Da die
Pipeline diese Definitionen enthält, auch ihre Version erhöhen. Verhalten von
Transforms, Closures oder Abhängigkeiten über eine neue `code_version` erfassen.

```r
# Während der Entwicklung vor der ersten Registrierung:
pipeline$version <- "1.1.0"
pipeline$code_version <- "new-git-sha"
```

Noch fehlen komfortable Update-Funktionen. Deshalb Definitionen bevorzugt in
einem R-Skript neu konstruieren und versionieren. Mutable Listen sind hier ein
praktischer Anfang, aber noch kein stabiler Vertrag für beliebige Fremd-Plugins.
