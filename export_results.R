#export_results
# Checkpoint 9 (docs/ROADMAP.md): persisted output layer so the research doc's "drafting findings"
# step (Part 1 §VI) has something to work from besides console scrollback. Every existing analysis
# function already returns invisible(list(...)) -- this walks whatever heterogeneous structure is
# passed in and exports each recognizable piece: a ggplot to PNG, a data frame (including
# etable()'s table output) to CSV, recursing into plain lists. Raw fixest/lm model objects are
# skipped -- they're internally lists too, but exporting them would either error or just duplicate
# the already-exported etable() table sitting next to them in the same result.
library(ggplot2)

export_all_results <- function(results_list, output_dir = "outputs") {
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  exported <- character(0)

  export_one <- function(x, name_path) {
    if (inherits(x, "ggplot")) {
      file <- file.path(output_dir, paste0(name_path, ".png"))
      ggsave(file, plot = x, width = 8, height = 5, dpi = 150)
      exported <<- c(exported, file)
    } else if (is.data.frame(x)) {
      file <- file.path(output_dir, paste0(name_path, ".csv"))
      write.csv(as.data.frame(x), file, row.names = FALSE)
      exported <<- c(exported, file)
    } else if (is.list(x) && !inherits(x, "fixest") && !inherits(x, "lm")) {
      for (nm in names(x)) {
        child_name <- if (!is.null(nm) && nzchar(nm)) paste0(name_path, "_", nm) else name_path
        export_one(x[[nm]], child_name)
      }
    }
    # fixest/lm model objects, NULL, atomic vectors, etc. are silently skipped -- not
    # export-ready results in their own right.
  }

  for (nm in names(results_list)) {
    export_one(results_list[[nm]], nm)
  }

  invisible(exported)
}
