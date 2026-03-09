# This code checks the user's installed packages against the packages listed in `./utility/package-dependency-list.csv`.
#   These are necessary for the repository's R code to be fully operational.
#   CRAN packages are installed only if they're not already; then they're updated if available.
#   GitHub packages are installed regardless if they're already installed.
# If anyone encounters a package that should be on there, please add it to `./utility/package-dependency-list.csv`

# Clear memory from previous runs.
base::rm(list=base::ls(all=TRUE))

# Use Posit Package Manager to get latest CRAN packages
cran_repo <- "https://packagemanager.posit.co/cran/latest"

path_csv <- "utility/package-dependency-list.csv"

if (!file.exists(path_csv)) {
  base::stop("The path `", path_csv, "` was not found.  Make sure the working directory is set to the root of the repository.")
}

if (!base::requireNamespace("devtools", quietly = TRUE)) {
  utils::install.packages("devtools", repos = cran_repo)
}

if (!base::requireNamespace("remotes", quietly = TRUE)) {
  utils::install.packages("remotes", repos = cran_repo)
}

# Install/update OuhscMunge from GitHub (always refresh to get latest)
remotes::install_github("OuhscBbmc/OuhscMunge", quiet = TRUE)

# Install missing packages from CSV and update outdated CRAN packages
OuhscMunge:::package_janitor_remote(path_csv)

# Update all installed CRAN packages to latest available versions
cat("\n=========================================================\n")
cat("Updating installed packages to latest CRAN versions...\n")
cat("=========================================================\n")
utils::update.packages(ask = FALSE, checkBuilt = TRUE, repos = cran_repo)
cat("Package update complete.\n")
