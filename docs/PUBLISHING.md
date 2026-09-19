# GitHub-Veröffentlichung und CI

Projekt: [JanWein/lakefold](https://github.com/JanWein/lakefold).
Die Maintainer-Metadaten verwenden die GitHub-No-Reply-Adresse.
Fehlerberichte und Verbesserungsvorschläge bitte über die Projekt-Issues melden.

## Entwicklung

```sh
git clone https://github.com/JanWein/lakefold.git
cd lakefold
```

In R `remotes::install_local(".", dependencies = TRUE)` ausführen. Änderungen
über einen Branch und Pull Request beitragen; Hinweise in [CONTRIBUTING.md](../CONTRIBUTING.md).

## Automatische Prüfung

`.github/workflows/R-CMD-check.yaml` prüft bei Pushes auf `main` und bei Pull
Requests beide Backends unter Ubuntu mit R 4.5.1. Die Actions richten R,
Systemabhängigkeiten und alle optionalen Test-Pakete ein. `rcmdcheck` lässt Fehler
und Warnungen den Job fehlschlagen. Logs werden als Actions-Artefakte aufgehoben.
DuckLake benötigt Zugriff auf sein Erweiterungsrepository.

R-Pakete und Erweiterungen werden zur Laufzeit bezogen; dies ist kein vollständig
eingefrorenes Build-Image. Der tatsächliche aktuelle Status steht im Actions-Tab.
Die historischen lokalen Prüfergebnisse stehen in [VALIDATION.md](VALIDATION.md).

## Dokumentation bauen

Der Workflow `Documentation` baut eine pkgdown-Website und lädt `site/` als
Pages-Artefakt hoch. Der nachgelagerte Deploy-Job veröffentlicht es auf
`https://janwein.github.io/lakefold/`. README, Guides und R-Hilfe bleiben
im Repository und installierten Paket nutzbar.
Lokal: `install.packages("pkgdown")`, danach `pkgdown::build_site()`.

## Release

Vor einem Release die Versionsnummer und `NEWS.md` aktualisieren und die
Prüfpipeline abwarten. Erst dann einen Tag erstellen:

```sh
git tag v0.3.0
git push origin v0.3.0
```

Im GitHub-Release die Betriebsgrenzen nennen. Die erste Version unterstützt
exakt einen Writer. Produktive S3-/PostgreSQL-Endpunkte brauchen eigene
Integrationstests. Ein erfolgreicher Paketcheck ersetzt diese Tests nicht.
