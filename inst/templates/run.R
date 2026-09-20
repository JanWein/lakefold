source("definitions.R")

result <- run(
  definition,
  evidence = Sys.getenv("TIDYWEAVE_EVIDENCE", ".tidyweave/evidence")
)
saveRDS(collect(result), "output.rds")
print(result)
