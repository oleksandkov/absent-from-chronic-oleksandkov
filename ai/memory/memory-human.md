# Human Memory

Human decisions and reasoning.

---
# 2026-03-11
Review the flowr.r,1-ferry and 2-ellis scripts. Udpated README.md, pipeline.md. Created some tasks to do the pipeline manageing easier. 
# 2026-03-05
Restructuring the ellis pipeline, and the logic of the eda folders. Creating eda report where will be described the completed tasks from the `statistics_insturcitons_v3.md` file. In the eda-2.qmd will be described the completed taks from 2-1 to 3-2.
# 2026-03-01
Created EDA-3 to observe the same relationships as in EDA-2 (g1-g7 graph families, same demographic breakdowns) but using `absence_days_chronic` (days missed due to a chronic condition) instead of `absence_days_total`. Source: `cchs_employed` table in `cchs-3.sqlite`. Files created: `analysis/eda-3/eda-3.R`, `analysis/eda-3/eda-3.qmd`, `analysis/eda-3/README.md`.
# 2026-02-25

We are going to complete the flow.R, add some tasks to be able to run each eda-\*.R files. Creating the UI and UX desing in format of the website which will contain all main pages, information about the data, analyzing sections (eda) and author etc. Setting the workflow tasks.

# 2026-02-22

We want to complete the existed 2-ellis.R script that it will get the full sample in the output .sqlite. Create a new 3-ellis.R, which will produce clearer data in the ccsh-3.sqlite and in a new tables cchs-3-tables/ folder in the data-private/folder.In a new table will be deleted usesless columns. WIll be filtered by separeted on 2 tables (employed and unemployed). Renamed columns for better understanding.

# 2026-02-19

Let's create 1-ferry.R and 2-ellis.R following the example in ./manipulation of caseload-forecast-demo (its ferry and ellis and related files). Convert file to SQLite after ferry and create parquet file with formatted factors after ellis. We loading all supporting docs in a NotebookLM as requested to extract componets from data dictionaries relevant to the research project ( as described in `data-private\raw\2026-02-19\stats_instructions_v3.md`), the product was stored in (`data-public\derived\required-variables-and-sample.md`)

# 2025-11-11

Removed ai_memory_check() function - unnecessary wrapper that just called memory_status(), quick_intent_scan(), and show_memory_help() in sequence. Users should call these directly. Renamed wrapper script from run-ai-memory-check.R to show-memory-status.R for clarity. Result: 312 lines reduced to 293 lines (6% further reduction). Total cleanup: 377 -> 293 lines (22% reduction overall).
