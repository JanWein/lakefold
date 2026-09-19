# Funktionsabgleich 0.4.0

## Die Aufgabenverteilung

DuckDB/DuckLake speichern und verarbeiten Tabellen. dbt übernimmt SQL-DAG,
Materialisierung und Modelltests. pointblank übernimmt optionale fachliche
Eingangsgates und detaillierte Prüfungen. dm beschreibt explizite Beziehungen
in R. lakefold verbindet diese Komponenten mit Definitionen, Laufnachweisen und
unveränderlichen Releases. Keine Komponente wird als universeller Ersatz für
die anderen beworben.

## Vorher vorhanden und jetzt ergänzt

| Fähigkeit | Bereits in 0.3.0 | Ergänzung in 0.4.0 |
|---|---|---|
| Pointblank-Integration | Basisadapter mit einer Regelquote und Severity | Native Warn-/Abbruchschwellen, per-step Overrides und Segmentnachweise |
| Ingestion | Lokale Dateien, unverändertes Landing, Raw und Kandidat | Separate Prüfung vor Raw sowie direkte R-Data-Frame-Zulieferung |
| Contracts | Schema, Pflichtfelder, Schlüssel, R-Regeln, Owner | Typentwurf mit Bestätigung, Diff, Operator und Spaltenmetadaten |
| Diagnose | Rohe Registry-Tabellen und dbt-spezifische Accessors | Gemeinsame Status-/Qualitätssicht, Releasehistorie, rekursive Herkunft |
| Berichte | Quarto-/Connect-Vorlagen | Qualitäts-HTML/JSON, native pointblank-Berichte, testthat-Erwartung |
| dbt und Releases | Getrennte Lebenszyklen | Explizite, erneut geprüfte Snapshot-Veröffentlichung einer Relation |
| Ausbleibende Lieferungen | Fehlende Datei bei Jobstart, Altersanzeige | Erwarteter Stichtag mit Fälligkeit auch ohne Importversuch |
| Registry | Festes Schema | Versionierte, additive Migration von Qualitätsmetadaten |
| Aufbewahrung | Historie bleibt erhalten | Vorschau und sichere Auswahl alter unveröffentlichter Fehlversuche |

## Konkrete Nutzungsgrenzen

* Der Registry-Betrieb benötigt einen koordinierten Writer. Die Migration und
  Konfliktprüfung machen daraus keinen verteilten Multiwriter-Dienst.
* `dl_dbt_publish()` veröffentlicht eine Relation. Atomare mehrtabellige
  Release-Bündel mit gemeinsamem dm-Gate sind noch nicht implementiert.
* dbt v2/Fusion und automatisch erzeugte Remote-Profile für S3/PostgreSQL sind
  nicht nachgewiesen. Der geprüfte CLI-Weg verwendet dbt-core und dbt-duckdb.
* Das RDS-Landing nach API-/Excel-Aufbereitung archiviert das R-Ergebnis.
  Originaldateien werden nur über dateibasierte Quellen unverändert archiviert.
* Es gibt keinen allgemeinen Source-Pluginvertrag, keine inkrementelle
  Quell-CDC und keine automatische Schema-Migration fachlicher Nutzdaten.
* `dl_cleanup()` löscht keine veröffentlichten Releases, DuckLake-Snapshots oder
  Dateien im Objektspeicher. Es implementiert keine allgemeine Retention-Policy.
* Ein Scheduler bleibt extern. Ein `targets`-Adapter und ein gemischter
  R/dbt-Graph gehören nicht zum aktuellen Paketumfang.
* OpenMetadata, commons und data-dict werden nicht als vollständig integrierte
  Dienste ausgegeben. YAML-Exporte bleiben ausdrücklich begrenzte Schnittstellen.

## Warum diese Grenzen bestehen bleiben

Für diese Fähigkeiten fehlen entweder nachgewiesene externe Laufzeitumgebungen
oder ein zusätzlicher fachlicher Vertrag, etwa eine Lösch-/Retention-Policy und
Transaktionsgrenzen mehrerer Produkte. Sie als bereits vorhanden auszugeben wäre
irreführend. Das Paket bleibt ein nutzbarer, überprüfbarer R-Kern. Ein eigener
Scheduler, Berechtigungssystem, visueller ETL-Editor oder vollständige
Spalten-Lineage aus beliebigem R-Code sind weiterhin bewusste Nichtziele.

## Dokumentation und Referenzen

* [Ausführbarer Qualitätsleitfaden](https://janwein.github.io/lakefold/articles/quality-gates.html)
* [pointblank: Action Levels](https://rstudio.github.io/pointblank/reference/action_levels.html)
* [pointblank: Agent-Reports](https://rstudio.github.io/pointblank/reference/get_agent_report.html)
* [R Packages: Funktionsdokumentation](https://r-pkgs.org/man.html)
* [Posit Skills](https://github.com/posit-dev/skills)
