# renv Initialization for Strict Reproducibility
# Run this script when you need exact package version reproducibility
# This is optional - the CSV system works fine for most use cases

cat("=========================================================\n")
cat("🔒 RENV INITIALIZATION FOR STRICT REPRODUCIBILITY\n")
cat("=========================================================\n")

# Function to check if we should proceed
check_user_consent <- function() {
  cat("\nThis will:\n")
  cat("  • Initialize renv (R environment management)\n") 
  cat("  • Install packages from package-dependency-list.csv\n")
  cat("  • Create renv.lock file with exact versions\n")
  cat("  • Set up project-local package library\n")
  cat("\n⚠️  WARNING: This changes how packages are managed in this project!\n")
  cat("\n📖 When to use renv:\n")
  cat("  ✅ Publishing research that needs exact reproducibility\n")
  cat("  ✅ Collaborating where everyone needs identical package versions\n")
  cat("  ✅ Long-term archival of analytical environments\n")
  cat("  ❌ Rapid prototyping or template development\n")
  cat("  ❌ Learning/educational environments\n")
  
  response <- readline(prompt = "\nProceed with renv initialization? (y/N): ")
  return(tolower(trimws(response)) %in% c("y", "yes"))
}

# Main initialization function
init_renv_environment <- function() {
  
  # Check if renv is already initialized
  if (file.exists("renv.lock") || dir.exists("renv")) {
    cat("⚠️  renv appears to already be initialized in this project.\n")
    response <- readline(prompt = "Reinitialize? This will overwrite existing renv setup (y/N): ")
    if (!tolower(trimws(response)) %in% c("y", "yes")) {
      cat("Cancelled.\n")
      return(FALSE)
    }
  }
  
  # Install renv if needed
  if (!requireNamespace("renv", quietly = TRUE)) {
    cat("📦 Installing renv...\n")
    install.packages("renv", repos = "https://packagemanager.posit.co/cran/latest")
  }
  
  # Initialize renv with Posit Package Manager for latest packages
  cat("🔧 Initializing renv...\n")
  options(
    repos = c(CRAN = "https://packagemanager.posit.co/cran/latest")
  )
  renv::init(force = TRUE, restart = FALSE)
  
  # Install packages from CSV dependency list
  cat("📦 Installing packages from CSV...\n")
  if (file.exists("utility/install-packages.R")) {
    source("utility/install-packages.R")
  } else {
    cat("❌ No package installation script found.\n")
    return(FALSE)
  }

  # Update all packages to latest versions before snapshotting
  cat("🔄 Updating packages to latest versions...\n")
  renv::update(prompt = FALSE)

  # Create renv snapshot
  cat("📸 Creating renv snapshot (renv.lock)...\n")
  renv::snapshot(prompt = FALSE)
  
  # Success message
  cat("\n=========================================================\n")
  cat("🎉 RENV INITIALIZATION COMPLETE!\n")
  cat("=========================================================\n")
  cat("✅ renv.lock created with exact package versions\n")
  cat("✅ Project-local package library established\n")
  cat("✅ Environment is now reproducible across machines\n")
  
  cat("\n📋 Next steps:\n")
  cat("  1. Commit renv.lock to version control\n")
  cat("  2. Share with collaborators\n")
  cat("  3. Others can restore with: renv::restore()\n")
  
  cat("\n🔧 renv commands you might need:\n")
  cat("  • renv::status()    - Check environment status\n")
  cat("  • renv::restore()   - Restore from renv.lock\n")  
  cat("  • renv::snapshot()  - Update renv.lock\n")
  cat("  • renv::deactivate() - Exit renv (if needed)\n")
  
  return(TRUE)
}

# Run interactively if called directly
if (interactive()) {
  if (check_user_consent()) {
    result <- init_renv_environment()
    if (!result) {
      cat("❌ renv initialization failed. Check messages above.\n")
    }
  } else {
    cat("renv initialization cancelled.\n")
    cat("💡 Your CSV-based package management continues to work normally!\n")
  }
} else {
  # Non-interactive mode - just initialize
  cat("Non-interactive mode: initializing renv...\n")
  init_renv_environment()
}