# Architektur ab 0.3.0

lakefold hat zwei bewusst getrennte Ausführungswege. R-Pipelines und Produkte
landen Originale, validieren Kandidaten und veröffentlichen immutable Releases.
dbt-Projekte bauen SQL-Modelle und führen Tests unter dbts eigenen Semantiken aus.
Beide beginnen mit einer Spezifikation und können `dl_execute()` verwenden.

`dl_dbt_status()` und `dl_dbt_lineage()` lesen veröffentlichte dbt-Artefaktformate.
`dl_dbt_model()` verbindet daraus aktuelle Tabellen mit dm. PK/FK werden vom
Anwender angegeben, da ein SQL-DAG keine relationalen Schlüssel beweist.
Eine automatische dbt-zu-Release-Promotion gibt es noch nicht.

# Architektur und bewusste Entscheidungen

## Definition, Ausführung, Beobachtung

Definitionen sind kleine Listen mit Klassen: `dl_contract`, `dl_source`,
`dl_pipeline`, `dl_product`, `dl_metric`. Funktionen sind normale R-Funktionen.
Tabellen bleiben Tibbles oder `dbplyr`-Lazy-Tables. Modelle bleiben `dm`-Objekte.

Die Pipeline speichert die Verbindungskonfiguration und löst sie zur Laufzeit
auf. Eine Registry liegt im eigenen Schema `lake._dl`; interne
DuckLake-Metadatentabellen werden nicht verändert.

| Modul | Aufgabe |
|---|---|
| workflow.R | Objektbasierte Ausführung, Pläne, Transformationen und kompakte Print-Methoden |
| setup.R | Lokales oder S3-Setup, DuckDB- oder PostgreSQL-Katalog |
| sources.R | Unverändertes Landing, SHA-256, optionale S3-Originale |
| contracts.R | Struktur, Schlüssel, R-Regeln und pointblank-Gate |
| pipeline.R | Kandidat, Wiederholung, Veröffentlichung, Ereignisse |
| products.R | Auf feste Releases aufbauende Produkte und dm-Modelle |
| metrics.R | Freigegebene Kennzahlen und Report-Manifeste |
| registry.R | Versionierte Definitionen, Releases und Metadatenzugriff |
| catalog.R | Aktualität und lesende Shiny-App |
| adapters.R | Explizite YAML-Exporte und Capability-Angaben |

## Transaktionsgrenze

Der unveränderliche Kandidat wird vor der Veröffentlichung gespeichert und
geprüft. Nur freigegebene Kandidaten erhalten einen Eintrag in `releases`.
Dieser Marker, die zugehörige Lineage und `runs.status = published` stehen in
derselben Transaktion im selben Lake. Ein Abbruch vor Commit macht keinen
neuen Release sichtbar. Ein Abbruch danach hinterlässt einen auffindbaren
Release für einen Wiederanlauf.

`dl_tbl()` löst ausschließlich Releases auf. Raw-Daten und abgelehnte Kandidaten
sind über direkten SQL-Zugriff weiterhin erreichbar. Das Qualitätsgate ist eine
Prozessregel, keine Zugriffsschutzschicht.

Unveränderlichkeit bedeutet hier: Die Framework-API überschreibt veröffentlichte
Tabellen nicht. Sie schützt nicht gegen Administratoren oder beliebige direkte
SQL-Schreibzugriffe mit denselben Credentials.

## Qualitätssemantik

| Ergebnis | Veröffentlichung |
|---|---|
| passed | erlaubt |
| warning | erlaubt, Qualitätsstatus des Release bleibt warning |
| failed | blockiert |
| error | blockiert, auch bei nicht-blockierender fachlicher Regel |
| not_checked | blockiert |

Die explizite Fehlerquote einer Regel bestimmt ihre Toleranz. `pointblank`-
Actions steuern nicht die Freigabe; der Adapter liest die tatsächlichen
Prüfergebnisse. Inaktive Schritte und leere Prüfpläne zählen nicht als bestanden.
Keine automatischen Zeilenverwerfungen und kein allgemeiner `force`-Schalter.

## Versionen

* Definition: Asset-ID, Versionsnummer und Fingerprint.
* Original: SHA-256 der tatsächlich gesicherten Bytes.
* Lauf: eigene ID und Start-/Endzeit.
* Release: eigene ID, Kandidatentabelle, Contract-Version und Vorgänger.
* Produkt: festgehaltene Eingabe-Releases.
* Metric: Definitionsversion, Input-Release, Parameter und Ergebnis-Hash.
* Report: feste Kombination aus Metric-Manifests und Ergebniswerten.

Ein Produkt wird nicht heimlich neu gebaut, wenn seine Quelle einen neueren
Release erhält. Den nächsten `dl_build()` steuert der vorhandene Scheduler.

## Betriebsmodell 0.2

Genau ein Writer. Das lokale Backend ist pro Prozess gedacht. PostgreSQL
ermöglicht eine spätere gemeinsame Umgebung, doch die Registry braucht vor
parallelen Veröffentlichungen eine serverseitige Sperr-/Eindeutigkeitsstrategie.
Die Prüfung des zuletzt gelesenen Parent-Release erkennt bereits abgeschlossene
Änderungen, ersetzt aber keine verteilte Sperre bei gleichzeitig laufenden
Transaktionen.

Die App kann auf einem exportierten Snapshot laufen und hält dann keine
Schreibverbindung offen. Snapshot-Zeit und Datenalter werden getrennt angezeigt.
Metadatenexporte enthalten keine Reportwerte, aber fachliche Beschreibungen,
Kontaktangaben, Quelldateinamen und Herkunftspfade. Sie sind intern zu behandeln.

## Nächste sinnvolle Ausbauschritte

1. PostgreSQL/S3-Integrationstest in der tatsächlichen Umgebung und gesperrte
   Writer-Ausführung im Betriebsprojekt.
2. Externen Notification-Adapter anbinden und Zustellungsfehler überwachen.
3. Inkrementelle Speicherung von Partitionskorrekturen statt vollständiger Kopie.
4. Aufbewahrung und Wiederherstellung einschließlich Reportnachweisen definieren.
5. Relationale Produkte mit mehreren Tabellen gemeinsam veröffentlichen.
6. Geprüften Adapter zur konkret eingesetzten commons-/data-dict-Version ergänzen.

Die ersten vier Schritte betreffen Belastbarkeit und Betrieb. Sie sollten vor
einer Erweiterung um neue Speicher-Backends priorisiert werden.

## Ergänzungen in 0.2.0

`dl_config()` trennt die Konfiguration von I/O. `dl_execute()` vereinheitlicht die
Aufrufkonvention und delegiert an die bestehenden Ausführungsfunktionen.
Transformationen werden nach der Raw-Materialisierung auf dem Kandidateneingang
angewendet. Die Publikationstransaktion und das Registry-Schema bleiben gleich.
Die Spezifikationen sind S3-Listen; das neue Generic ist kein vollständiger
Engine-/Step-Erweiterungsvertrag. Siehe [Design-Review](DESIGN_REVIEW.md).
