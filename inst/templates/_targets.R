library(targets)
library(tidyweave)
source("definitions.R")

# File inputs and product dependencies are tracked automatically.
# Use targets::tar_cue(mode = "always") for externally changing API/DB inputs.
tw_as_targets(
  definition,
  evidence = Sys.getenv("TIDYWEAVE_EVIDENCE", ".tidyweave/evidence")
)
