# Build Report

## Issues observed during contract execution

- **Missing contracted source**: `analysis/eda-5/eda-5.html` was not found.
  - **Fallback applied**: `analysis/eda-5/eda-5-fixed.html` was used as the redirect target content for `EDA-5`.
  - **Severity**: Warning

- **Potential dependency gap for EDA-5 fallback HTML**: `eda-5-fixed.html` references an `eda-5-fixed_files` bundle that is not present in source.
  - **Fallback applied**: post-render script attempts to provide compatible `libs/` assets from `analysis/eda-2/eda-2_files/libs` when needed.
  - **Severity**: Warning

## Suggested resolution

- Prefer publishing a canonical `analysis/eda-5/eda-5.html` with its matching dependency bundle (`eda-5_files/` or equivalent), then remove fallback logic.
