# Kritisches Design-Review: Wie nah ist lakefold an tidymodels?

Review des Codes und der Bedienabläufe, 18. September 2026. Grundlage ist die
ursprüngliche Version 0.1.0; die daraus umgesetzten Änderungen bilden 0.2.0.

## Stand 0.4.0: die konkreten Lücken geschlossen

Das Grundkonzept aus 0.3.0 bleibt erhalten. Die jetzt umgesetzten Ergänzungen
schließen folgende Bedienungs- und Nachweislücken:

| Anforderung | Umsetzung in 0.4.0 |
|---|---|
| Eingangskontrolle vor Raw | `input_contract` und `dl_step_precheck()`; Original bleibt im Landing |
| Gestaffelte DQ-Entscheidung | Native pointblank-Action-Levels über `policy = "agent"` |
| Kleine Segmente nicht verdecken | Eigener Nachweis je pointblank-Segment |
| Qualitätsberichte und R-Tests | HTML/JSON, nativer pointblank-Report und `dl_expect_quality()` |
| Nutzung vorhandener R-Daten | `dl_ingest_data()` mit unveränderlichem RDS-Landing und Cache |
| Contract-Entwurf ohne Scheinsicherheit | Typentwurf, explizite Bestätigung und Änderungsvergleich |
| Fachliche und technische Verantwortung | Separater Operator sowie Spaltenbeschreibung und Einheit |
| Diagnose ohne Registry-Interna | Status, Qualität, Releases und rekursive Dataset-Lineage |
| dbt-Ergebnis für reproduzierbare Reports | Neue Kopie, Contract-Prüfung und expliziter Release pro Relation |
| Fehlende Lieferung ohne Importlauf | Stichtags-/Fälligkeitsprüfung mit Ereignissen und Deduplizierung |
| Bestehende Metadaten weiterverwenden | Additive Migration auf Registry-Schema 2 |
| Speicherpflege ohne Historienverlust | Vorschau und Bereinigung unveröffentlichter Fehlversuch-Tabellen |

Die folgenden Bewertungen für 0.3.0 und früher sind historische Befunde. Der
aktuelle Funktionsumfang und die verbleibenden Grenzen stehen außerdem in
[FEATURES.md](https://github.com/JanWein/lakefold/blob/main/docs/FEATURES.md).

## Ergänzung für 0.3.0: dbt als Build-Engine

Die Architektur wurde am 19. September 2026 um dbt ergänzt. `dl_dbt_project()`
trennt Konfiguration von Ausführung, `dl_execute()` unterstützt die Spezifikation,
`dl_dbt_status()` liefert Tibbles und `dl_dbt_model()` ein echtes lazy `dm`.
Das ist im Bedienkonzept näher an tidymodels, ohne ein eigenes SQL-DAG-System
aufzubauen. Neue Funktionen sind in roxygen2 dokumentiert und erhalten Beispiele.

| Erwartung eines erfahrenen R-Nutzers | Stand 0.3.0 | Nächster sinnvoller Schritt |
|---|---|---|
| Ein konsistenter Ausführungseinstieg | S3-Generic für Pipeline, Produkt, Metric und dbt-Projekt | Einheitliche Diagnose-Accessors über beide Engines |
| Start ohne Infrastrukturwissen | Lokaler Starter mit Daten und Tests | Automatisierte, geprüfte Remote-Provisionierung |
| Fehler ehrlich erkennen | Exitcode, fehlende Artefakte, Invocation-ID und Node-Status prüfen | Einheitliche strukturierte Qualitätsbedingungen |
| SQL-Abhängigkeiten bauen | dbt übernimmt seinen DAG und Incremental Models | Gemischte R/dbt-Orchestrierung über vorhandene Scheduler |
| Relational arbeiten | Native dm-Objekte, explizite PK/FK | Optionaler Import ausdrücklich deklarierter Schlüsselmetadaten |
| Reproduzierbar berichten | Governed Releases weiterhin vorhanden | Explizite geprüfte Übernahme von dbt-Outputs in Releases |
| Gute Paketdokumentation | Paket-Hilfe, Funktionsreferenz, Beispiele, Vignetten, pkgdown | Zusätzliche Produktionsfallstudien nach Remote-Tests |

### Im Review berücksichtigte Fehlerfälle

Jeder dbt-Aufruf erhält einen eigenen Artefaktordner. Alte Erfolge können damit
nicht einen fehlgeschlagenen Lauf überdecken. Run Results und Manifest müssen
dieselbe Invocation-ID tragen. CLI-Argumente werden ohne Shell übergeben;
Selektoren dürfen nicht als zusätzliche Flags interpretiert werden. Der Starter
überschreibt keine bestehenden Projektdateien. `dm`-Schlüssel werden nicht aus
SQL-Abhängigkeiten erfunden. Lokale Katalogverbindungen werden vor dem externen
Prozess ausdrücklich geschlossen.

### Verbleibende Grenzen

* dbt-Builds sind nicht atomar und erzeugen nicht automatisch lakefold-Releases.
* Der Starter erzeugt das dbt-duckdb-Profilformat. dbt v2 `catalogs.yml`, S3 und
  PostgreSQL benötigen eigene, separat geprüfte Konfigurationen.
* Ein dbt-Manifest kann nicht beweisen, dass eine Relation noch dem Build entspricht.
* Es gibt keine universelle Source-Plugin-API, keine Registry-Migrationen und
  keine vom Paket koordinierte parallele Veröffentlichung.

Die folgenden Abschnitte dokumentieren das ursprüngliche Review und die
Änderungen von 0.1.0 auf 0.2.0. Aussagen über den damals fehlenden DAG beziehen
sich auf den R-Kern; dbt übernimmt seit 0.3.0 die SQL-Seite.

## Urteil

**Ein brauchbarer, fokussierter Kern für dateibasierte Datenprodukte. Noch kein
universelles, ausgereiftes Framework auf dem Niveau von tidymodels.** Die
Pipe-Schreibweise allein reicht für diesen Anspruch nicht. Entscheidend sind
vorhersagbare Objekte, getrennte Definition und Ausführung, überprüfbare Pläne,
eine konsistente Erweiterungsschnittstelle, hilfreiche Fehler und gute Beispiele.

Der Kern ist fachlich sinnvoll: Original sichern, Kandidat prüfen, nur dann
veröffentlichen; Kennzahlen rechnen auf festgehaltenen Releases. R-Funktionen,
Tibbles, Lazy Tables, pointblank und dm werden weiterverwendet. Es gibt keine
zweite eigene Tabellen- oder Ausdruckssprache.

Für einen erfahrenen R-Nutzer ist das für kleine bis mittlere, dateibasierte
Strecken mit einem Writer gut nachvollziehbar. Beim Übertragen auf beliebige
Datenquellen, mehrere abhängige Produkte und regulären Mehrbenutzerbetrieb muss
er derzeit noch zu viel Betriebslogik selbst ergänzen.

## Was aus dem Review direkt verbessert wurde

| Lücke in 0.1.0 | Änderung in 0.2.0 | Bedeutung |
|---|---|---|
| Pipeline-Definition verlangt eine offene Verbindung | `dl_config()` plus `dl_pipeline(id, config, ...)` | Definition und Code-Review funktionieren ohne Infrastrukturzugriff |
| Listen werden nahezu ungefiltert ausgegeben | Kompakte Print-Methoden für die zentralen Spezifikationen | Objektzustand, Inputs und Freigaben sind direkt sichtbar |
| Kein lesbarer Ausführungsplan | `dl_plan()` liefert ein Tibble, auch für unvollständige Definitionen | Struktur kontrollieren, bevor Daten gelesen werden |
| Transformationen verstecken sich im Reader | Beliebig viele benannte `dl_step_transform()`-Schritte | Lesen, Aufbereiten und Prüfen sind sichtbar getrennt |
| Unterschiedliche erste Argumente für Run, Build und Measure | `dl_execute()` als S3-Generic mit Objekt zuerst | Alle drei Spezifikationen lassen sich gleichartig pipen |
| Fehlerhafte Schrittreihenfolge fällt spät auf | Prüfung beim Anfügen eines Schritts | Früher verständliche Rückmeldung |
| Custom Metric kann trotz vorhandener Eingabe ein leeres Ergebnis liefern | Leere Ergebnisse werden abgewiesen | Kein scheinbar gültiges leeres Reportergebnis |
| CI-Matrix setzt den Demo-Schalter statt des Test-Schalters | `DATALOOM_TEST_BACKEND` wird korrekt gesetzt | Die gesamte Suite läuft tatsächlich auf beiden Backends |

Die bisherigen `dl_setup()`, `dl_run()`, `dl_build()` und `dl_measure()` bleiben
verfügbar. 0.2.0 erweitert die Bedienung, ersetzt aber keine Datenbankarchitektur.
Definitionen mit Transformationsschritten benötigen 0.2.0 oder neuer.

## Vergleich der Denkmodelle

Die Zuordnung ist eine Designanalogie, keine API- oder Funktionsgleichheit.

| Prinzip aus tidymodels | Entsprechung in lakefold | Grenze |
|---|---|---|
| Spezifikation vor Ausführung | Contract, Quelle, Produkt, Metric und Pipeline sind R-Objekte | Keine vollständige portable Deserialisierung ausführbarer R-Definitionen |
| Schritte als explizite Rezeptur | `dl_step_*()` und benannte Transformationen | Keine trainierbaren Schritte mit `prep()`/`bake()`-Semantik |
| Workflow bündelt Komponenten | Pipeline verbindet Quelle, Reader, Schritte, Contract und Veröffentlichung | Ein Import, keine automatische Ausführung eines ganzen Produktgraphen |
| Einheitlicher Ausführungsaufruf | `dl_execute()` | Resultate unterscheiden sich bewusst: Run-Ergebnis oder Kennzahl-Tibble |
| Inspektion über strukturierte Ausgaben | Print-Methoden, `dl_plan()`, Registry und Katalog | Noch keine einheitlichen `tidy()`/`glance()`-/`augment()`-Methoden |
| Austauschbare Engines und Erweiterungen | Konstruktoren, normale R-Callbacks und optionale Adapter | Kein stabiler allgemeiner Backend-/Source-/Step-Pluginvertrag |
| Komposition mit R-Werkzeugen | Base Pipe, dplyr/dbplyr, dm, pointblank | Keine umfassende tidyselect-Oberfläche für Contracts und Rollen |

Transformationsfunktionen sind normale Verarbeitungsschritte. Ein ML-Rezept
lernt dagegen je nach Schritt Parameter aus Trainingsdaten und wendet sie später
auf neue Daten an. Für ein Datenprodukt sollte man dieses Verhalten nicht
unbeabsichtigt übernehmen. Ein `prep()`-Alias ohne solche Semantik wäre irreführend.

## Was ein erfahrener R-Nutzer als Nächstes erwarten würde

| Priorität | Fähigkeit | Aktueller Stand | Konkreter nächster Schritt |
|---|---|---|---|
| P1 | Gute Diagnose ohne Registry-Interna | Run-Ergebnis und rohe Metadatentabellen vorhanden | Run-/Release-/Quality-Accessors und konsistente Condition-Klassen |
| P1 | Contract-Entwurf aus Beispieldaten | Spalten und Typen werden von Hand deklariert | `dl_contract_from()` als ausdrücklich ungeprüfter Entwurf, keine automatische Freigabe |
| P1 | Regelbausteine für typische Qualitätsprüfungen | Struktur/Nullwerte/Schlüssel eingebaut; übrige Regeln per Callback | Bereiche, Wertemengen, Referenzen und Periodenvollständigkeit mit klarer NA-Semantik |
| P1 | Definitionen sicher ändern | Version/Fingerprint blockiert stilles Überschreiben | Dokumentierte Update-/Remove-Funktionen und Änderungsvergleich |
| P1 | Produktionsnachweis der vorgesehenen Infrastruktur | Konfiguration vorhanden, externe Endpunkte ungetestet | S3/PostgreSQL-Integrationstests einschließlich Neustart und Restore |
| P1 | Große Dateiimporte | Reader lädt üblicherweise in R; Produkte bleiben lazy | Datenbankseitige CSV-/Parquet-Reader mit explizitem Laufzeitkontext |
| P2 | Mehrere Produkte in Abhängigkeitsreihenfolge | Inputs und Lineage vorhanden; Aufrufe manuell | Optionaler `targets`-Adapter mit Release-Fingerprints und Zyklusprüfung |
| P2 | Datenbank- und API-Quellen | Nur lokale Quelldateien sind erstklassige Sources | Source-Protokoll mit Snapshot, Fingerprint, Wiederholbarkeit und Credentials zur Laufzeit |
| P2 | Append/Upsert und inkrementelle Verarbeitung | Replace und Partitionsersatz; letzterer kopiert vollständigen Bestand | Explizite Schlüssel-/Lösch-/Korrektursemantik vor Implementierung |
| P2 | Schema-Evolution und Registry-Migrationen | Kein Migrationsmechanismus | Registry-Schemaversion, Migrationsplan, Vorwärts-/Rückwärtskompatibilität |
| P2 | Sichere parallele Writer | Ausdrücklich nicht unterstützt | Sperren/Eindeutigkeit und Konflikttests, erst danach Multiwriter bewerben |
| P2 | Retention und Speicherpflege | Keine automatische Bereinigung | Referenzzählung aus Reports/Releases und Vorschau vor Löschung |
| P3 | Portabler Contract-Standard und echter commons-Adapter | Begrenzte YAML-Exporte | Versionierte Zielschemata und Ende-zu-Ende-Vertragstests |
| P3 | Weitere Backends und grafischer Editor | Nicht implementiert | Erst bei einem konkreten Bedarf und nach stabiler Kern-API |

P1 bedeutet: hoher Nutzen für die unmittelbar nächste nutzbare Version. P2
betrifft breiteren oder belastbareren Betrieb. P3 erweitert das Ökosystem.
Die Priorität hängt vom Einsatz ab: Für parallele Writer ist die Sperrstrategie
vor der ersten produktiven Nutzung zwingend und nicht erst irgendwann relevant.

## Bewusste Grenzen, die nicht zu eigenen Subsystemen werden sollten

* Scheduling, Identity und Secret-Verwaltung an bestehende Plattformen anbinden.
* Standardtransformationen dplyr/dbplyr überlassen.
* Relationale Modelle mit dm abbilden; fachliche Join-Kardinalität ausdrücklich prüfen.
* Eine eigene Visual-ETL-Plattform erst bei belegtem Bedarf bauen.
* Das Paket zunächst modular im Code halten. Viele kleine R-Pakete würden
  Versions- und Schnittstellenpflege erhöhen, bevor die API stabil ist.

## Weitere Befunde, die im Betrieb zählen

* `approved = TRUE` ist Metadatenzustand, kein Vier-Augen-Freigabeworkflow.
* API-Unveränderlichkeit schützt nicht gegen SQL-Zugriffe mit Schreibrechten.
* `code_version` muss auch geänderte Closure-Werte und Abhängigkeiten erfassen.
  Nur Funktionscode zu hashen erkennt nicht jede Verhaltensänderung.
* Ein historischer Cache-Treffer setzt den aktuellen Release nicht zurück.
* Qualitätsregeln mit `collect()` können große Datenmengen in R laden.
* Auch Kennzahlberechnung registriert Definitionen und Lineage. Sie ist daher
  kein rein lesender Betrieb und gehört zur Single-Writer-Koordination.
* Der Registry fehlt eine Schemaversion. 0.2.0 verändert deren Schema nicht;
  künftige Änderungen benötigen einen echten Migrationspfad.

## Referenzen zum Vergleich

* [tidymodels: Rezepte und modulare Vorverarbeitung](https://www.tidymodels.org/start/recipes/)
* [workflows: Spezifikationen zusammenstellen](https://workflows.tidymodels.org/reference/workflow.html)

Die Bewertung von lakefold beruht auf dem hier vorliegenden Quellcode. Die
Referenzen erklären die Vergleichsprinzipien und sind keine Bestätigung dieses Pakets.
