# Quick Start Template for AI-Augmented Reproducible Research

> [No one beginning a data science project should start from a blinking cursor.](https://towardsdatascience.com/better-collaborative-data-science-d2006b9c0d39) <br/>...Templatization is a best practice for things like using common directory structure across projects...<br/> -[Megan Risdal](https://towardsdatascience.com/@meganrisdal) Kaggle Product Lead.

This template provides a comprehensive foundation for **AI-augmented reproducible research projects**. It combines the best practices of reproducible research with  AI support infrastructure, which levereges generative LLMs and agent customization to construct and manage analytic pipelines. 

Refer to [RAnalysisSkeleton](https://github.com/wibeasley/RAnalysisSkeleton) for a deeper dive into reproducible research best practices.

---

## About This Project

**Project**: `absent-from-chronic` — Analysis of work absenteeism using the Canadian Community Health Survey (CCHS) PUMF microdata.

**Goal**: Understand how chronic health conditions relate to workplace absenteeism, using two pooled CCHS survey cycles (2010-2011 and 2013-2014).

**Data source**: CCHS PUMF (`.sav`) files stored in `data-private/raw/`. These files are not committed to the repository. Contact the project lead to obtain them.

### Where to find the data

| Location | Contents |
|----------|----------|
| `data-private/raw/2026-02-19/` | Raw CCHS `.sav` files (CCHS2010_LOP.sav, CCHS_2014_EN_PUMF.sav) |
| `data-private/derived/cchs-1.sqlite` | Ferry staging database (all raw columns) |
| `data-private/derived/cchs-1-raw/` | Parquet backup of raw tables |
| `data-private/derived/cchs-2-tables/` | Ellis analysis-ready Parquet files (`cchs_analytical.parquet`, `sample_flow.parquet`) |
| `data-private/derived/cchs-2.sqlite` | Ellis SQLite output (same data, factors as character) |
| `data-private/derived/cchs-3-tables/` | Clarity-layer splits: `cchs_employed.parquet`, `cchs_unemployed.parquet`, `data_dictionary.parquet` |
| `data-private/derived/cchs-3.sqlite` | SQLite version of Lane 3 outputs |

See `data-private/contents.md` and `data-public/metadata/CACHE-manifest.md` for detailed descriptions.

### Running the data pipeline (`manipulation/`)

The pipeline follows the **Ferry → Ellis → Test** pattern. All paths are relative to the project root.

```r
# Option 1: Run full pipeline
source("flow.R")

# Option 2: Run individual scripts
source("manipulation/1-ferry.R")            # Import CCHS .sav → cchs-1.sqlite
source("manipulation/2-ellis.R")            # Transform → cchs-2-tables/ Parquet
source("manipulation/2-test-ellis-cache.R") # Validate Ellis ↔ CACHE-manifest alignment
```

```powershell
# Option 3: Interactive runner (recommended for first-time or flag-sensitive runs)
powershell -ExecutionPolicy Bypass -File scripts/ps1/run-interactive-flow.ps1
```

See `manipulation/pipeline.md` for the full pipeline reference including input/output tables, white-list design, exclusion criteria, and troubleshooting.

### Running the analysis scripts (`analysis/`)

Analysis scripts live in numbered subdirectories under `analysis/`. Each folder contains an `.R` script (data loading and modeling) and a `.qmd` Quarto report.

```r
# EDA-1: broad exploratory analysis of the analytical dataset
source("analysis/eda-1/eda-1.R")

# EDA-2: focused exploration of ferry and ellis outputs
source("analysis/eda-2/eda-2.R")
```

```powershell
# Render EDA-1 report
quarto render analysis/eda-1/eda-1.qmd

# Or use the dedicated script runner
powershell -ExecutionPolicy Bypass -File scripts/ps1/run-eda-1.ps1
powershell -ExecutionPolicy Bypass -File scripts/ps1/run-eda-2.ps1
```

---
## 🎭 AI Persona System

This project template includes 9 specialized AI personas, each optimized for different research tasks:

### **Core Personas**
- **🔧 Developer** - Technical infrastructure and reproducible code
- **📊 Project Manager** - Strategic oversight and coordination
- **🔬 Research Scientist** - Statistical analysis and methodology

### **Specialized Personas**  
- **💡 Prompt Engineer** - AI optimization and prompt design
- **⚡ Data Engineer** - Data pipelines and quality assurance
- **📈 Grapher** - Data visualization and display of informatioin
- **📝 Reporter** - Analysis communication and storytelling
- **🚀 DevOps Engineer** - Deployment and operational excellence
- **🎨 Frontend Architect** - User interfaces and visualization

You can switch between personas in VSCode:
- `Ctrl+Shift+P` → "Tasks: Run Task" → "Activate [Persona Name] Persona"  
- Instruct the chat agent to switch to the specific persona you name  

You can define persona's default context in `get_persona_configs()` function of `ai/scripts/dynamic-context-builder.R`:

```r
"project-manager" = list(
  file = "./ai/personas/project-manager.md",
  default_context = c("project/mission", "project/method", "project/glossary")
)
```

You can define what context files get a shortcut alias, so they can be integrated into the chat calls easily. See `get_file_map()` function in `ai/scripts/dynamic-context-builder.R`.



## 🧠 Memory System

The template includes an intelligent memory system that maintains project continuity:

- **`ai/memory/memory-human.md`** - Your decisions and reasoning, only humans can edit
- **`ai/memory/memory-ai.md`** - AI-maintained technical status, only AI can edit
- **`ai/memory/log/YYYY-MM-DD.md** - dedicated folder in which one file = one log entry. Helps to isolate large changes to a single file for easier tracking.

# 🚀 Quick Start Guide

## Step 1: Standard Setup

1. **Install Prerequisites**
   - [R (4.0+)](https://cran.r-project.org/)
   - [RStudio](https://rstudio.com/products/rstudio/) or [VS Code](https://code.visualstudio.com/)
   - [Git](https://git-scm.com/)
   - [Quarto](https://quarto.org/) (for reports)

2. **Clone and Open Project**
   ```bash
   git clone [your-repo-url]
   cd quick-start-template
   ```
   - Open `quick-start-template.Rproj` in RStudio, or
   - Open folder in VS Code

3. **Install R Dependencies** 
   
   **Choose your preferred approach** (see `docs/environment-management.md` for detailed comparison):

   **Option A: Enhanced CSV System (Default - Flexible)**
   ```r
   # Enhanced system with version constraints
   Rscript utility/enhanced-install-packages.R
   
   # Or original system (backward compatible)
   Rscript utility/install-packages.R
   ```
   
   **Option B: renv (Strict Reproducibility)**
   ```r
   # For exact reproducibility (research publication)
   Rscript utility/init-renv.R
   ```
   
   **Option C: Conda (Cross-Language Projects)**
   ```bash
   # For R + Python workflows
   conda env create -f environment.yml
   conda activate quick-start-template
   ```

## Step 2: AI Support System Setup

4. **Initialize AI System**
   - **In VS Code**: `Ctrl+Shift+P` → "Tasks: Run Task" → "Show AI Context Status"

5. **Assign the active persona**
   - In VS Code: `Ctrl+Shift+P` → "Tasks: Run Task" → "Activate [default] Persona"

5. **Customize Your Project**

Each personal could be customized by adding specific documents to the dynamic part of the copilot-instructions.md (Section 3). Some personas may have some documents loaded by default (e.g. Project Manager and Grapher load mission, method, and glossary). 

   - Edit `ai/mission.md` - What you wan to do: goals and deliverables
   - Edit `ai/method.md` - How you want to do it: tecniques and processes 
   - Edit `ai/glossary.md` - Encyclopedia of domain-specific terms
   - Update `config.yml` - To set project-specific configurations
