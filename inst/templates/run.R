source("definitions.R")

result <- tw_run(
  definition,
  evidence = Sys.getenv("TIDYWEAVE_EVIDENCE", ".tidyweave/evidence")
)
saveRDS(tw_collect(result), "output.rds")
print(result)
