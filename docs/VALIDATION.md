# Prüfstand lakefold 0.4.0

Prüfdatum: 19. September 2026. Lokal Ubuntu 24.04 und R 4.3.3.

| Prüfung | Ergebnis |
|---|---|
| Vollständiger `R CMD check --no-manual` | 0 Errors, 0 Warnings, 0 Notes |
| Einzelprüfungen im abschließenden Paketcheck | 263 bestanden, 0 fehlgeschlagen, 0 Warnungen, 0 übersprungen |
| Separater vollständiger DuckLake-Lauf | Bestanden, einschließlich realem dbt und Snapshot-Veröffentlichung |
| Beispiele und Vignetten | Alle Paketbeispiele geprüft; sieben Vignetten gebaut und deren R-Code ausgeführt |
| API und Referenz | 62 exportierte Funktionen, 52 Hilfethemen, vollständiger pkgdown-Index |
| Tests | 56 Testfälle; neue Regressionen für Qualitätsgates, Migration, Berichte und dbt-Veröffentlichung |

Die GitHub-Workflows prüfen jeden veröffentlichten Stand zusätzlich mit R 4.5.1
auf DuckDB und DuckLake und bauen/deployen die Website. Ihr Ergebnis ist unter
[GitHub Actions](https://github.com/JanWein/lakefold/actions) nachvollziehbar.
Die folgenden lokalen Ergebnisse sind kein vorweggenommener CI-Status.

## Neue fachliche Nachweise

* Native pointblank-Schwellen warnen oder blockieren je Segment. Kleine Segmente
  werden nicht durch eine globale Fehlerquote verdeckt.
* Fehlende Action Levels, inaktive Schritte und Auswertungsfehler blockieren.
* Gleichzeitig vorhandene pointblank-Abbruchspalten `S`, `E` und `C` werden
  gemeinsam ausgewertet. Acht Berichtsvarianten sichern diese Regel ab.
* Ein fehlgeschlagenes Eingangsgate erhält Landing und alten Release, schreibt
  aber keine neue Raw-Tabelle. Das abschließende Kandidatengate bleibt aktiv.
* Data-Frame-Zulieferungen erhalten Datumstypen und wiederverwenden identische
  Lieferungen über den bestehenden Cache.
* Qualitätsberichte zeigen den Gate-Entscheid, escapen HTML-Inhalte und enthalten
  keine Fehlzeilen-Extrakte oder Samples.
* Contract-Drafts benötigen explizite Bestätigung; der Vergleich zeigt
  strukturelle Verschärfungen und semantisch zu prüfende Änderungen.
* Diagnose-Accessors unterscheiden letzten Versuch, festgehaltenen Release und
  Cache-Herkunft. Ein dbt-Prozessfehler bleibt neben erfolgreichen Nodes sichtbar.
* dbt-Relationen werden erneut kopiert und geprüft. Spätere Änderungen an einer
  Relation verändern keinen früher veröffentlichten Release.
* Fehlende fachliche Stichtage werden ohne Importversuch erkannt. Erfolgreiche
  Benachrichtigungen werden dedupliziert; Transportfehler bleiben retryfähig.
* Die additive Registry-Migration erhält alte Nachweise und kann wiederholt
  aufgerufen werden; unbekannte neuere Schemata werden abgewiesen.
* Cleanup startet mit einer Vorschau und lässt veröffentlichte Tabellen und
  Qualitätsnachweise auch bei tatsächlicher Bereinigung unverändert.

Geprüfte Kernkombination: DuckDB 1.5.5 in R und Python, pointblank 0.12.4,
dbt-core 1.12.5, dbt-duckdb 1.10.1 und dm 1.1.2. dbt-Telemetrie ist deaktiviert.
Produktives S3, PostgreSQL, dbt v2/Fusion, parallele Writer, Windows/macOS und
Last-/Dauerbetrieb werden weiterhin nicht als nachgewiesen ausgegeben.

## Historischer Prüfstand 0.3.0


Prüfdatum: 19. September 2026. Ubuntu 24.04, R 4.3.3.

| Prüfung | Ergebnis |
|---|---|
| Vollständige Testsuite mit DuckDB | Bestanden, keine Testfehler oder Warnungen |
| Vollständige Testsuite mit DuckLake | Bestanden, keine Testfehler oder Warnungen |
| Echte dbt-Integration auf beiden Backends | Build, fünf dbt-Datentests, separater Test-Aufruf und dm-Abfrage bestanden |
| `R CMD build` einschließlich Vignetten | Erfolgreich |
| `R CMD check --no-manual` | Status OK: 0 Errors, 0 Warnings, 0 Notes |
| R-Beispiele und alle sechs Vignetten | Im Paketcheck ausgeführt bzw. neu gebaut |
| `pkgdown::check_pkgdown()` | Keine Probleme, vollständiger Referenzindex |
| `pkgdown::build_site()` | Vollständige Website mit Referenz und Artikeln gebaut |

38 Tests sind definiert. Der abschließende lokale Paketcheck mit aktiviertem
dbt-Integrationstest besteht **165 Einzelprüfungen**, ohne Fehler, Warnungen oder
übersprungene Tests. Ein zusätzlicher Check ohne externe CLI bestand 161
Einzelprüfungen und übersprang genau den opt-in geschalteten Integrationstest.

Die dbt-Integration verwendet `dbt-core 1.12.5`, `dbt-duckdb 1.10.1` und
Python-DuckDB 1.5.5. R-DuckDB ist ebenfalls 1.5.5. Telemetrie ist in allen neuen
CLI-Aufrufen ausdrücklich deaktiviert. Die normale Paketprüfung benötigt keine
dbt-Installation und überspringt genau diesen externen Integrationstest;
die beiden gesonderten Backend-Läufe führten ihn tatsächlich aus.

Zusätzliche Regressionstests prüfen isolierte Artefaktordner, fehlende Dateien,
abweichende Invocation-IDs, beschädigte skalare Ergebnisfelder, fehlgeschlagene
Nodes trotz Exitcode 0, Argumentübergabe ohne Shell, Schutz vor Überschreiben,
dm-Schlüssel sowie unveränderte Cache-/Release-Semantik bei `dl_ingest()`.

Nicht als geprüft gelten dbt v2/Fusion, produktives S3, PostgreSQL-Kataloge,
parallele Writer, Windows/macOS und Last-/Dauerbetrieb. Der lokale Starter
unterstützt das dbt-duckdb-Profilformat, keine automatische v2-Kataloggenerierung.
Der GitHub-Actions-Status ist separat von lokalen Ergebnissen zu betrachten.

## Historischer Prüfstand 0.2.0

Version 0.2.0 bestand jeweils 26 Tests mit 126 erfolgreichen Einzelprüfungen.
Diese historischen Ergebnisse sind kein Nachweis für 0.3.0. Lokale Session- und
Rohlogs werden nicht veröffentlicht; die Ergebnisse sind hier zusammengefasst.

## Historischer Prüfstand 0.1.0


Prüfdatum: 18. September 2026. Umgebung: Ubuntu 24.04, R 4.3.3.

## Ergebnisse

| Prüfung | Ergebnis |
|---|---|
| Gesamte Suite mit lokalem DuckDB-Backend und zusätzlichem DuckLake-Test | 21 Tests, 97 erfolgreiche Einzelprüfungen |
| Gesamte Suite mit echtem DuckLake als Standardbackend | 21 Tests, 97 erfolgreiche Einzelprüfungen |
| Fehlgeschlagene, übersprungene oder warnende Tests | jeweils 0 |
| `R CMD build` | erfolgreich |
| `R CMD check --no-manual --no-build-vignettes`, DuckLake-Test aktiviert | Status OK: 0 Errors, 0 Warnings, 0 Notes |
| Mitgeliefertes End-to-End-Beispiel auf DuckLake | erfolgreich |
| Shiny-Reaktivität, Suche, Definitionen, Qualitätsausgabe und Graph | automatisch geprüft |
| Shiny im Chromium-Browser: Übersicht und Herkunftsgraph | gerendert, 0 Shiny-Ausgabefehler; Screenshots geprüft |
| S3-Landing gegen lokalen HTTP-Testserver mit paws.storage | Originalbytes exakt erhalten; Wiederholung über bedingtes PUT ohne Überschreiben |

Die damaligen Rohlogs und Screenshots gehören nicht zum öffentlichen Quellbaum;
die verwendeten Testdaten waren synthetisch.

## Abgedeckte Fehlerfälle

* Gute, fehlerhafte, fehlende und korrigierte Lieferungen.
* Keine Änderung des freigegebenen Datenstands durch ein fehlgeschlagenes Gate.
* Wiederanlauf ohne doppelte Veröffentlichung und ohne Reaktivierung alter Releases.
* Zugriff auf historische Releases nach Korrektur und nach Neuverbindung.
* Fehlende Spalten, Dubletten, fehlerhafte/ausgelassene Regeln und leere Kandidaten.
* Toleranzgrenzen und explizite Warnungsregeln.
* Definitionen mit geändertem Inhalt bei gleicher Version.
* Benachrichtigungs-Deduplizierung, erneutes Auftreten nach Behebung und Transportfehler.
* Datenalter ohne neuen Job sowie stabile Pfade nach Arbeitsverzeichniswechsel.
* Partitionskorrekturen mit unveränderten übrigen Perioden.
* Simulierter Fehler vor Transaktions-Commit: Release und Erfolgsstatus werden zurückgerollt.
* Produkte mit festgehaltenen Eingabeversionen.
* Nicht freigegebene Metrics, unerlaubte Dimensionen und mehrere Stichtage bei Stock-Metrics.
* Nachträglich veränderte Kennzahlenwerte bei der Report-Freigabe.
* pointblank-Prüfungen inklusive inaktiver Schritte.
* dm-Primär- und Fremdschlüssel inklusive verwaister Referenzen.
* Expliziter YAML-Export und unzulässige Bezeichner.

## Verwendete Hauptversionen

| Paket | Version |
|---|---|
| duckdb | 1.5.5 |
| DBI | 1.2.2 |
| dplyr | 1.2.1 |
| dbplyr | 2.4.0 |
| pointblank | 0.12.4 |
| dm | 1.1.2 |
| shiny | 1.8.0 |
| bslib | 0.12.0 |
| paws.storage | 0.10.0 |

Dies ist eine geprüfte Kombination, keine Aussage, dass jede ältere oder
künftige Paketversion kompatibel ist. Abhängigkeiten im Einsatzprojekt sperren.

## Noch nicht praktisch geprüft

* Ein produktiver S3-Endpunkt einschließlich Authentifizierung und dessen vollständiger
  Unterstützung von Conditional PutObject. Der HTTP-Testserver ist kein Ersatz dafür.
* Ein echter PostgreSQL-Katalog, dessen Backups oder ein Katalogumzug.
* Betrieb auf Workbench, Connect und GitHub. Die Vorlagen wurden nicht dort deployed.
* Rendering mit Quarto auf Connect und produktive Benachrichtigungszustellung.
* Ein geladenes commons-/data-dict-Projekt. Der Export orientiert sich an der
  dokumentierten Syntax und bleibt eine begrenzte Schnittstelle.
* Große Produktionsdaten, parallele Writer, Last-/Dauerbetrieb sowie Windows/macOS.

Die Tests begründen einen funktionierenden ersten Stand. Sie ersetzen keine
betriebliche Abnahme. Das Paket meldet `multi_writer = FALSE` und bereinigt
historische Daten nicht automatisch.
