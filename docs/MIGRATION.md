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

Die `dl_*`-Funktionsnamen, S3-Klassen und Registry-Struktur bleiben erhalten.
Vorhandene Kataloge können mit derselben expliziten Konfiguration geöffnet werden.
Der bestehende YAML-Formatbezeichner `dataloom-contract` bleibt als Format-ID
bestehen. Ebenso bleiben der bisherige S3-Standardpräfix und die bestehenden
`DATALOOM_*`-Variablen kompatibel. Der Name des R-Pakets verschiebt keine Daten.

Prüfe gespeicherte R-Funktionen oder RDS-Spezifikationen auf Referenzen auf den
alten Paket-Namespace und definiere sie bei Bedarf neu. Bei geänderter fachlicher
Logik bleiben Versionssprünge und neue `code_version` verpflichtend. Eine
allgemeine automatische Registry-Migration gibt es noch nicht.

Neue dbt-Projekte sind zusätzliche Spezifikationen, keine registrierten
`dl_product`-Definitionen. `dl_execute(project)` delegiert an `dl_dbt_build()`.
Die dbt-Ausgaben werden nicht automatisch als unveränderliche Releases registriert.
