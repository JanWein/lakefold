# tidyweave 0.12.0.9000

* Development releases support only the current API and stored formats. Automatic
  registry and local-configuration upgrades and legacy metric checksums have
  been removed. There is no backward-compatibility commitment before 1.0.

* Documentation now has nine focused guides and the function reference.
  Superseded tutorials, migration pages and completed design plans are removed.

* All exported functions use the `tw_` prefix. Product specifications, recipes
  and workflows are independently reusable components.

* Lake publications preserve immutable releases and quality evidence.
  PostgreSQL catalogs coordinate package writers with advisory locks.

* `tw_add_product()` and `tw_add_recipe()` assemble a workflow. Update, remove
  and extract helpers manage its components independently.

* `tw_measure()` supports individual metrics and metric sets. Approved results
  from published inputs can be saved with `tw_report_release()`.

* `tw_product()` accepts tables and dm models. Model publication commits member
  tables and the model manifest together.

* `tw_publish(previous = )` rejects stale corrections.

* `tw_set_engine()` selects native, pointblank or dm implementations where
  supported. Targets select storage independently.
