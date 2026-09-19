library(lakefold)
source("definitions.R")
lake <- dl_connect(pipeline$config)
tryCatch(
  {
    dl_run(
      pipeline,
      lake,
      business_date = business_date,
      notify = get0("notify", ifnotfound = NULL)
    )
  },
  finally = {
    dl_catalog_export(lake, "catalog.json")
    dl_disconnect(lake)
  }
)
