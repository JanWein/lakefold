# Betrieb ab 0.3.0

## dbt-Aufrufe

Ein schreibender Prozess pro lokalem Katalog. R-Verbindungen vor dem dbt-Aufruf
schließen, danach erneut öffnen. Alle Aufgaben desselben Katalogs im Scheduler
serialisieren. Die Paket-Registry implementiert keine verteilten Locks.

dbt-Logs und Artefakte liegen pro Lauf unter `.lakefold/runs/<id>`. Sie enthalten
unter anderem SQL, Pfade und Datenbankdiagnosen und gehören nicht in öffentliche
Repositories. Die Umgebung des aufrufenden Prozesses wird vererbt; Credentials
werden über das dbt-Profil und Umgebungsvariablen verwaltet. Anonyme dbt-Telemetrie
wird für den Kindprozess ausdrücklich deaktiviert.

Bei Fehlschlag `result$success`, `dl_dbt_status(result)`, `result$stderr` und
`result$artifact_error` auswerten. `timeout` beendet einen hängenden Kindprozess;
es gibt keinen automatischen Retry. Ein dbt-Fehler rollt bereits gebaute Modelle
nicht pauschal zurück. Nach erfolgreichen ausgewählten Builds nur passende
Manifest-Nodes in `dl_dbt_model(tables = ...)` öffnen.

Artefaktaufbewahrung, Secrets, Backup und Restore bleiben Aufgaben des Betreibers.
Für S3/PostgreSQL und dbt v2 eine separat geprüfte Konfiguration einsetzen; der
Starter automatisiert lokale dbt-duckdb-Profile. R- und Python-DuckDB-Versionen
aufeinander abstimmen. Ungeprüfte Produktionsreife wird nicht behauptet.

# Betrieb

## Konfiguration

[setup_s3.R](../inst/examples/setup_s3.R) verwendet folgende Umgebungsvariablen:

| Variable | Inhalt |
|---|---|
| `DATALOOM_S3_BUCKET` | Vorhandener S3-Bucket, erforderlich |
| `DATALOOM_S3_ENDPOINT` | Endpoint mit `https://`, ohne Pfad, erforderlich |
| `DATALOOM_S3_PREFIX` | Prefix, Standard `lakefold/dev` |
| `AWS_DEFAULT_REGION` | Region, Standard `eu-central-1` |
| `AWS_ACCESS_KEY_ID` | Zugriffsschlüssel zur Laufzeit |
| `AWS_SECRET_ACCESS_KEY` | Geheimnis zur Laufzeit |
| `AWS_SESSION_TOKEN` | Optionaler Sitzungstoken |
| `DUCKLAKE_PG_CONNECTION` | libpq-Verbindungszeichenfolge bei PostgreSQL-Katalog |

Diese `DATALOOM_S3_*`-Variablen gehören zum Beispielskript, nicht zu einer
impliziten Konfigurationssuche des Pakets. Die Konstruktoren erhalten ihre Werte
explizit. Originaldateien benötigen `paws.storage`; Parquet verwendet DuckDB httpfs.
Der S3-Dienst muss bedingtes PutObject unterstützen, damit Originale nicht
überschrieben werden. Im Zielsystem mit einer Testdatei prüfen.

## PostgreSQL

Eine vorhandene Datenbank bereitstellen, TLS und Zugangsdaten im Betrieb
konfigurieren und `dl_catalog_postgres("DUCKLAKE_PG_CONNECTION")` verwenden.
Das erstellt keine PostgreSQL-Instanz und migriert keinen lokalen Katalog.
Datenbank-Metadaten und S3-Objekte zusammen sichern und die Wiederherstellung
praktisch erproben. Backups allein des Metadatenkatalogs enthalten keine Datenfiles.

## Jobs und Posit Connect

Die Vorlagen in `inst/templates/` trennen Definition, R-Job, Quarto-Bericht und
Shiny-App. Dateien mit stabilen absoluten Pfaden verwenden. Umgebungsvariablen
in der Laufzeit konfigurieren. Einen Git-Commit als `DATALOOM_CODE_VERSION`
übergeben und Paketabhängigkeiten im Einsatzprojekt sperren.

Es darf nur einen Writer für den gemeinsamen Lake geben. In einem dedizierten
GitHub-Betriebsrepository für alle entsprechenden Jobs dieselbe `concurrency.group`
mit `cancel-in-progress: false` verwenden. Die Gruppe koordiniert nur innerhalb
dieses Repositorys. Connect und GitHub Actions dürfen nicht gleichzeitig denselben
Lake beschreiben. Die Paket-CI benötigt keine produktiven Credentials und schreibt
nur isolierte Testdaten. GitHub-Concurrency ist keine dauerhafte Job-Warteschlange;
für jede erwartete Lieferung muss der Scheduler einen nachvollziehbaren Lauf sichern.

## Fehler und Wiederanlauf

Registry und Jobstatus überwachen. `dl_interrupted()` zeigt hinterlassene
`running`-Einträge. Ein erneuter identischer Lauf findet bereits committete Releases.
`dl_freshness()` prüft das Datenalter; für aktive Meldungen ist ein externer
Scheduler erforderlich. Transportfehler einer Benachrichtigung nicht verschlucken.
Bei Quarto kann nach einem Renderfehler weiterhin das letzte erfolgreiche HTML
angezeigt werden; die Registry ist für den aktuellen Lauf maßgeblich.

## Zugriff und Aufbewahrung

Contracts und Qualitätsgates ersetzen keine Speicherberechtigungen. Direkter
SQL-Zugriff kann Framework-Regeln umgehen. Snapshots können Quelldateipfade,
Beschreibungen und Kontaktdaten enthalten; nur bewusst freigegebene Snapshots
an Katalog-Nutzer verteilen. Das öffentliche Paket-Repository enthält keine
produktiven Snapshots. Historische Releases nicht manuell löschen, solange
Berichte auf sie verweisen. Automatische Retention ist noch nicht implementiert.
