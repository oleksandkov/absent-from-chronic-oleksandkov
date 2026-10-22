rm(list = ls(all.names = TRUE)) # Clear the memory of variables from previous run.
cat("\014") # Clear the console
cat("Working directory: ", getwd()) # Must be set to Project Directory

# Self-sufficient QC demonstration: the joint frequency distribution of the
# three CCHS household child-presence flags.
#
#   dhhgle5 - any child aged 0-5  in household (0/1)
#   dhhg611 - any child aged 6-11 in household (0/1)
#   dhhgl12 - any child aged < 12 in household (0/1)
#
# The point of the script: dhhgl12 is not a third measurement. Of the eight
# logically possible (le5, 611, l12) combinations only four ever occur, and the
# four that occur are exactly those satisfying l12 == (le5 | 611). Run it and
# read the last table.
#
# Sources nothing from the project. Run with:  Rscript scripts/qc-child-presence-flags.R

# ---- load-packages -----------------------------------------------------------
library(dplyr)
requireNamespace("arrow")
requireNamespace("tidyr")
requireNamespace("config")

# ---- declare-globals ---------------------------------------------------------
config_cchs <- config::get("database")$cchs
path_analytic <- paste0(config_cchs$ellis_parquet_dir, "cchs_analytic.parquet")

child_flags <- c("dhhgle5", "dhhg611", "dhhgl12")
weight_var <- "wts_m_pooled"

# ---- load-data ---------------------------------------------------------------
ds0 <- arrow::read_parquet(path_analytic)

cat("\n---- SECTION: Source ---------------------------------------------------\n")
cat("  file:", path_analytic, "\n")
cat("  rows:", format(nrow(ds0), big.mark = ","),
    " columns:", ncol(ds0), "\n")

# ---- tweak-data-0 ------------------------------------------------------------
# Keep only what the demonstration needs. No recoding: the flags are already 0/1.
ds_flags <- ds0 %>%
  select(all_of(c(child_flags, weight_var)))

# ---- marginals ---------------------------------------------------------------
# Each flag on its own. Note the complete coverage: zero missing in all three.
t_marginal <- lapply(child_flags, function(v) {
  ds_flags %>%
    count(.data[[v]], name = "n") %>%
    rename(value = 1) %>%
    mutate(
      variable = v,
      pct      = round(100 * n / sum(n), 1)
    )
}) %>%
  bind_rows() %>%
  select(variable, value, n, pct) %>%
  mutate(value = ifelse(is.na(value), "MISSING", as.character(value)))

cat("\n---- SECTION: Marginal distributions -----------------------------------\n")
print(as.data.frame(t_marginal), row.names = FALSE)

# ---- joint-distribution ------------------------------------------------------
# The eight logically possible combinations, whether or not they are observed.
# Cells that never occur are the evidence: they are not rare, they are impossible.
grid_all <- expand.grid(
  dhhgle5 = c(0, 1),
  dhhg611 = c(0, 1),
  dhhgl12 = c(0, 1),
  KEEP.OUT.ATTRS = FALSE
)

t_observed <- ds_flags %>%
  count(dhhgle5, dhhg611, dhhgl12, name = "n") %>%
  mutate(w = NA_real_)

t_weighted <- ds_flags %>%
  filter(!is.na(.data[[weight_var]])) %>%
  group_by(dhhgle5, dhhg611, dhhgl12) %>%
  summarise(w = sum(.data[[weight_var]]), .groups = "drop")

t_joint <- grid_all %>%
  left_join(t_observed %>% select(-w), by = child_flags) %>%
  left_join(t_weighted, by = child_flags) %>%
  mutate(
    n   = tidyr::replace_na(n, 0L),
    w   = tidyr::replace_na(w, 0),
    pct = round(100 * n / sum(n), 2),
    pct_wtd = round(100 * w / sum(w), 2),
    implied_l12 = as.numeric(dhhgle5 == 1 | dhhg611 == 1),
    verdict = case_when(
      n > 0 & dhhgl12 == implied_l12 ~ "observed  (consistent with l12 = le5 OR 611)",
      n > 0 & dhhgl12 != implied_l12 ~ "OBSERVED CONTRADICTION",
      n == 0 & dhhgl12 != implied_l12 ~ "never occurs (forbidden by l12 = le5 OR 611)",
      TRUE ~ "never occurs (unexpected)"
    )
  ) %>%
  arrange(dhhgle5, dhhg611, dhhgl12)

cat("\n---- SECTION: Joint distribution, all 8 possible combinations ----------\n")
print(
  as.data.frame(
    t_joint %>%
      select(dhhgle5, dhhg611, dhhgl12, n, pct, pct_wtd, verdict)
  ),
  row.names = FALSE
)

# ---- readable-crosstab -------------------------------------------------------
# The same thing as a 2 x 2 of the two component flags, showing that dhhgl12
# carries no cell of its own: it is fully determined by the row and column.
t_crosstab <- ds_flags %>%
  count(dhhgle5, dhhg611, dhhgl12, name = "n") %>%
  mutate(
    cell = paste0(
      "le5=", dhhgle5, " / 611=", dhhg611,
      "  ->  l12=", dhhgl12
    )
  ) %>%
  select(cell, n) %>%
  mutate(pct = round(100 * n / sum(n), 2))

cat("\n---- SECTION: Observed cells only --------------------------------------\n")
print(as.data.frame(t_crosstab), row.names = FALSE)

# ---- validate ----------------------------------------------------------------
n_total <- nrow(ds_flags)
n_discordant <- sum(
  (ds_flags$dhhgle5 == 1 | ds_flags$dhhg611 == 1) != (ds_flags$dhhgl12 == 1),
  na.rm = TRUE
)
n_cells_observed <- sum(t_joint$n > 0)
r_le5 <- cor(ds_flags$dhhgle5, ds_flags$dhhgl12)
r_611 <- cor(ds_flags$dhhg611, ds_flags$dhhgl12)

cat("\n---- SECTION: Verdict --------------------------------------------------\n")
cat("  rows examined:                    ", format(n_total, big.mark = ","), "\n")
cat("  missing in any of the three flags:",
    sum(!complete.cases(ds_flags[, child_flags])), "\n")
cat("  cells occupied (of 8 possible):   ", n_cells_observed, "\n")
cat("  rows where l12 != (le5 OR 611):   ", n_discordant, "\n")
cat("  cor(dhhgle5, dhhgl12):            ", round(r_le5, 3), "\n")
cat("  cor(dhhg611, dhhgl12):            ", round(r_611, 3), "\n")

if (n_discordant == 0L) {
  cat("\n  dhhgl12 is a DETERMINISTIC function of the other two flags.\n")
  cat("  It contributes no information of its own; in a model containing both\n")
  cat("  dhhgle5 and dhhg611 it merely re-expresses their interaction.\n")
} else {
  cat("\n  dhhgl12 is NOT deterministic here - investigate the",
      n_discordant, "discordant rows.\n")
}

# ---- demonstrate-column-space ------------------------------------------------
# Formal statement of the same fact: the design matrix built from the three
# main effects spans exactly the space of the two-way interaction model.
X_three <- model.matrix(~ dhhgle5 + dhhg611 + dhhgl12, data = ds_flags)
X_inter <- model.matrix(~ dhhgle5 * dhhg611, data = ds_flags)
max_resid <- max(abs(residuals(lm(X_three[, "dhhgl12"] ~ X_inter - 1))))

cat("\n  rank of ~ le5 + 611 + l12 :", qr(X_three)$rank, "of", ncol(X_three), "columns\n")
cat("  rank of ~ le5 * 611       :", qr(X_inter)$rank, "of", ncol(X_inter), "columns\n")
cat("  max |residual| of l12 regressed on the interaction basis:",
    format(max_resid, scientific = TRUE, digits = 3), "\n")
cat("  => the two models span the same column space.\n\n")
