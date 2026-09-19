# Von dataloom zu lakefold

Das R-Paket und GitHub-Projekt heißen ab Version 0.3.0 `lakefold`.

```r
remotes::install_github("JanWein/lakefold", build_vignettes = TRUE)
library(lakefold)
```

Ersetze `library(dataloom)`, `dataloom::` und Paketnamen in `renv.lock`, CI und
Deployments durch `lakefold`. Entferne das alte Paket bei Bedarf ausdrücklich;
beide Pakete sollten nicht gleichzeitig angehängt werden, weil die exportierten
Funktionen dieselben Namen tragen.

Die `dl_*`-Funktionsnamen und S3-Klassen bleiben erhalten.
Vorhandene Kataloge können mit derselben expliziten Konfiguration geöffnet werden.
Der bestehende YAML-Formatbezeichner `dataloom-contract` bleibt als Format-ID
bestehen. Ebenso bleiben der bisherige S3-Standardpräfix und die bestehenden
`DATALOOM_*`-Variablen kompatibel. Der Name des R-Pakets verschiebt keine Daten.

Prüfe gespeicherte R-Funktionen oder RDS-Spezifikationen auf Referenzen auf den
alten Paket-Namespace und definiere sie bei Bedarf neu. Bei geänderter fachlicher
Logik bleiben Versionssprünge und neue `code_version` verpflichtend. Version 0.4.0 ergänzt einen additiven, versionierten Registry-Migrationspfad.

Neue dbt-Projekte sind zusätzliche Spezifikationen, keine registrierten
`dl_product`-Definitionen. `dl_execute(project)` delegiert an `dl_dbt_build()`.
Die dbt-Ausgaben werden nicht automatisch als unveränderliche Releases registriert.

## Von 0.3.0 zu 0.4.0

Beim Verbinden legt lakefold die eigene Tabelle `_dl.schema_version` an und
migriert die Qualitätsmetadaten transaktional auf Schema 2. Hinzu kommen
`engine`, `stage`, `segment` und `details`. Alte Nachweise erhalten `legacy`
als Engine und `candidate` als Phase. Vorhandene Releases und Definitionen
werden nicht umgeschrieben. Wiederholtes Verbinden wiederholt die Migration nicht.
Eine neuere, unbekannte Schemaversion wird abgewiesen.

Verwende nach der Migration mindestens lakefold 0.4.0. Ein automatischer Downgrade
oder Migrationen fachlicher Nutzdatenschemas sind nicht enthalten.

Bestehende pointblank-Regeln behalten `policy = "rule"`. Für `policy = "agent"`
ist eine neue Contract-/Pipeline-Version nötig. Dort liefern die nativen
Action Levels den Gate-Entscheid. Neue Eingangsverträge und geänderte
Transformationslogik erfordern ebenfalls neue Definitionen und `code_version`.

`dl_dbt_publish()` ist eine explizite zusätzliche Veröffentlichung. Ein dbt-Build
allein schreibt weiterhin keinen lakefold-Release. Pointblank-Agenten bleiben
nur bei `keep_agents = TRUE` im Arbeitsspeicher und werden nie in die Registry
serialisiert. Metadatenexporte enthalten jetzt auch Segmentlabels.
