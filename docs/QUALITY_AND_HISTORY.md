# Qualität, Fehler und historische Datenstände

## Die vier Zeit- und Versionsbegriffe

| Begriff | Beantwortet |
|---|---|
| Fachlicher Stichtag (`business_date`) | Für welchen Zeitpunkt gilt die Lieferung? |
| Eingang (`received_at`) | Wann wurde das Original gesichert? |
| Veröffentlichung (`published_at`) | Wann wurde der geprüfte Datenstand freigegeben? |
| Definitionsversion und `code_version` | Welche fachlichen Regeln und welcher Code wurden verwendet? |

`business_date` ersetzt keine Datumsspalte in den Fachdaten. Stock-Metrics wählen
ihren Stichtag über `time_column` und `at`. Eine neue Lieferung für denselben
Stichtag ist eine Korrektur mit eigenem Release, keine Überschreibung der Historie.

## Qualitätsstatus

| Status | Bedeutung | Darf veröffentlicht werden? |
|---|---|---|
| `passed` | Prüfung abgeschlossen, innerhalb der Toleranz | Ja |
| `warning` | Nicht-blockierende fachliche Regel verletzt | Ja, mit Warnungsstatus |
| `failed` | Blockierende Regel verletzt | Nein |
| `error` | Prüfung technisch gescheitert | Nein |
| `not_checked` | Keine auswertbare Prüfung, etwa inaktiver Schritt | Nein |

Nullwerte werden unabhängig von einer Regel geprüft. `na.rm = TRUE` in einer
Regel hebt den Contract nicht auf. Toleranzen beziehen sich auf Testeinheiten,
nicht zwangsläufig auf Zeilen. `dl_quality_counts(2, 100)` bedeutet zwei
fehlgeschlagene von 100 Einheiten. `max_failure = 0.02` lässt das noch zu.

`pointblank`-Actions bestimmen nicht die Veröffentlichung. Der Adapter liest
die tatsächlichen Resultate; inaktive oder leere Prüfpläne werden nicht als
Erfolg behandelt. Es gibt keinen allgemeinen Schalter zum Erzwingen der Publikation.

## Fehler diagnostizieren

```r
out <- dl_execute(pipeline, lake, stop_on_failure = FALSE)
out$status
out$quality
out$error   # bei technischen Fehlern, nur lokal untersuchen

runs <- dl_registry(lake, "runs")
quality <- dl_registry(lake, "quality_results")
quality[quality$run_id == out$run_id, ]
```

Ein Job sollte den Standard `stop_on_failure = TRUE` beibehalten. Dann wird nach
der Speicherung der Diagnose ein Fehler ausgelöst, damit der Scheduler den Lauf
als fehlgeschlagen erkennt. Bei abgefangenen Conditions ist das Run-Ergebnis
unter `condition$result` verfügbar. Exception-Texte können private Inhalte
enthalten und werden deshalb nicht unverändert in Registry oder Meldungen kopiert.

## Historie und Cache

```r
old <- dl_tbl(lake, "finance.reserves", release = first_run$release_id)
current <- dl_tbl(lake, "finance.reserves")
```

Die API verändert alte Releases nicht. Ein identischer Wiederholungslauf verweist
als `cached` auf den vorhandenen Release. Wird eine ältere Lieferung nach einer
neueren wiederholt, bleibt der neuere Release aktuell. Ein Cache-Treffer ist
keine fachliche Rücksetzung.

## Replace oder Partitionsersatz?

* `mode = "replace"`: Die Lieferung ist der vollständige neue Bestand.
* `mode = "replace_partition"`: Alle in der Lieferung enthaltenen Partitionen
  ersetzen diese Partitionen vollständig. Andere Partitionen bleiben erhalten.

Ein Partitionsersatz ist kein Zeilen-Upsert. Ein unvollständiger Monatsbestand
würde die übrigen Zeilen dieses Monats entfernen. Nullwerte in Partitionsschlüsseln
und leere Partitionslieferungen sind nicht erlaubt. Die Implementierung
materialisiert den vollständigen neuen Bestand und ist noch nicht speicheroptimal.

## Benachrichtigungen

Ein Callback `notify = function(event) ...` bindet bestehenden Mail-/Tickettransport
an. Ohne Callback stehen Ereignisse auf `pending`; es wird nichts versendet.
Transportfehler erzeugen `delivery_failed`. Derselbe bereits zugestellte Vorfall
wird unterdrückt, ein Wiederauftreten nach erfolgreicher Erholung erneut gemeldet.
Für externe Idempotenz die `event_id` verwenden. Prozessabbruch zwischen externer
Zustellung und Registry-Update kann weiterhin doppelte Nachrichten verursachen.
