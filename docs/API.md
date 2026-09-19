# API ab 0.3.0

Alle exportierten Funktionen enthalten R-Hilfe und Beispiele. Die vollständige
Referenz beginnt mit `help(package = "lakefold")`. Die bisherigen `dl_*`-Namen
bleiben kompatibel. Der neue Name ändert keine vorhandenen Speicherpfade.

| Funktion | Eingabe | Ergebnis |
|---|---|---|
| `dl_ingest()` | Verbindung/Config, Quelle, Vertrag, Asset, Codeversion | Governed Run Result |
| `dl_dbt_project()` | Projektpfad, Profilordner, Target, Executable | Verbindungslos definierte dbt-Spezifikation |
| `dl_dbt_init()` | Neuer Ordner und lokales Config | Starterdateien und dbt-Spezifikation |
| `dl_dbt_build()` | Spezifikation, Select/Exclude, Vars, Timeout | Status, Node-Tibble, Manifest, Logs |
| `dl_dbt_test()` | Spezifikation und Testselektion | dbt-Ergebnis ohne Build-Aufruf |
| `dl_dbt_status()` | dbt-Ergebnis oder Artefaktordner | Tibble pro ausgeführtem Node |
| `dl_dbt_lineage()` | dbt-Ergebnis oder Artefaktordner | Abhängigkeitskanten |
| `dl_dbt_model()` | Verbindung, Manifest-Ergebnis, explizite PK/FK | Lazy dm aus aktuellen dbt-Relationen |
| `dl_execute()` | Pipeline, Produkt, Metric oder dbt-Projekt | Ergebnistyp der jeweiligen Operation |

Bei dbt übernimmt der externe Prozess seine Verbindungen selbst. Übergebe keine
R-Verbindung an `dl_execute(project)`. Verwende `dl_model()` für festgehaltene
lakefold-Releases, `dl_dbt_model()` für aktuelle dbt-Tabellen.

# API-Überblick

39 exportierte Funktionen, gruppiert nach Aufgabe. In R
`help(package = "lakefold")` oder `?dl_execute` aufrufen.
Die Funktionsreferenz dokumentiert Parameter und Rückgaben in Englisch;
die Tutorials zeigen zusammenhängende Abläufe.

## Konfiguration und Verbindungen

| Funktion | Hilfeseite |
|---|---|
| `dl_config()` | [dl_config.Rd](../man/dl_config.Rd) |
| `dl_setup()` | [dl_setup.Rd](../man/dl_setup.Rd) |
| `dl_connect()` | [dl_setup.Rd](../man/dl_setup.Rd) |
| `dl_disconnect()` | [dl_disconnect.Rd](../man/dl_disconnect.Rd) |
| `dl_catalog_duckdb()` | [dl_catalog_duckdb.Rd](../man/dl_catalog_duckdb.Rd) |
| `dl_catalog_postgres()` | [dl_catalog_duckdb.Rd](../man/dl_catalog_duckdb.Rd) |
| `dl_storage_local()` | [dl_catalog_duckdb.Rd](../man/dl_catalog_duckdb.Rd) |
| `dl_storage_s3()` | [dl_catalog_duckdb.Rd](../man/dl_catalog_duckdb.Rd) |
| `dl_capabilities()` | [dl_capabilities.Rd](../man/dl_capabilities.Rd) |

## Quelle und Workflow

| Funktion | Hilfeseite |
|---|---|
| `dl_source()` | [dl_source.Rd](../man/dl_source.Rd) |
| `dl_pipeline()` | [dl_pipeline.Rd](../man/dl_pipeline.Rd) |
| `dl_step_land()` | [dl_pipeline.Rd](../man/dl_pipeline.Rd) |
| `dl_step_extract()` | [dl_pipeline.Rd](../man/dl_pipeline.Rd) |
| `dl_step_transform()` | [dl_step_transform.Rd](../man/dl_step_transform.Rd) |
| `dl_step_validate()` | [dl_pipeline.Rd](../man/dl_pipeline.Rd) |
| `dl_step_publish()` | [dl_pipeline.Rd](../man/dl_pipeline.Rd) |
| `dl_plan()` | [dl_plan.Rd](../man/dl_plan.Rd) |
| `dl_execute()` | [dl_execute.Rd](../man/dl_execute.Rd) |
| `dl_run()` | [dl_run.Rd](../man/dl_run.Rd) |

## Contracts und Qualität

| Funktion | Hilfeseite |
|---|---|
| `dl_contract()` | [dl_contract.Rd](../man/dl_contract.Rd) |
| `dl_rule()` | [dl_rule.Rd](../man/dl_rule.Rd) |
| `dl_quality_counts()` | [dl_rule.Rd](../man/dl_rule.Rd) |
| `dl_pointblank()` | [dl_rule.Rd](../man/dl_rule.Rd) |
| `dl_validate()` | [dl_validate.Rd](../man/dl_validate.Rd) |
| `dl_contract_yaml()` | [dl_contract_yaml.Rd](../man/dl_contract_yaml.Rd) |

## Produkte, Modelle und Kennzahlen

| Funktion | Hilfeseite |
|---|---|
| `dl_product()` | [dl_product.Rd](../man/dl_product.Rd) |
| `dl_build()` | [dl_build.Rd](../man/dl_build.Rd) |
| `dl_tbl()` | [dl_tbl.Rd](../man/dl_tbl.Rd) |
| `dl_model()` | [dl_model.Rd](../man/dl_model.Rd) |
| `dl_metric()` | [dl_metric.Rd](../man/dl_metric.Rd) |
| `dl_measure()` | [dl_measure.Rd](../man/dl_measure.Rd) |
| `dl_report_release()` | [dl_report_release.Rd](../man/dl_report_release.Rd) |
| `dl_commons_yaml()` | [dl_commons_yaml.Rd](../man/dl_commons_yaml.Rd) |

## Beobachtung und Katalog

| Funktion | Hilfeseite |
|---|---|
| `dl_register()` | [dl_register.Rd](../man/dl_register.Rd) |
| `dl_registry()` | [dl_registry.Rd](../man/dl_registry.Rd) |
| `dl_freshness()` | [dl_freshness.Rd](../man/dl_freshness.Rd) |
| `dl_interrupted()` | [dl_interrupted.Rd](../man/dl_interrupted.Rd) |
| `dl_catalog_export()` | [dl_catalog_export.Rd](../man/dl_catalog_export.Rd) |
| `dl_catalog()` | [dl_catalog.Rd](../man/dl_catalog.Rd) |
