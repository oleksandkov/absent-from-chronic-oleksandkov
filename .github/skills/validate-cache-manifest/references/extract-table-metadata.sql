-- ============================================================================
-- CACHE Manifest Validation - SQL Template
-- ============================================================================
-- Purpose: Extract metadata from the canonical validation target
-- Usage: Replace the placeholders with values from manipulation/pipeline-validation.dcf
-- ============================================================================

-- Replace these placeholders before running manually:
--   [TARGET_OBJECT]    Example: [P20250821].[ds_analysis_2]
--   [EXCLUDE_QUERY]    Optional query returning one column named column_name
--   [PROVENANCE_QUERY] Optional query returning provenance fields

-- ----------------------------------------------------------------------------
-- QUERY 1: All columns from the target object
-- ----------------------------------------------------------------------------
SELECT 
    c.name AS column_name,
    t.name AS data_type,
    c.max_length,
    c.precision,
    c.scale,
    c.is_nullable,
    c.column_id AS ordinal_position
FROM sys.columns c
JOIN sys.types t ON c.user_type_id = t.user_type_id
WHERE c.object_id = OBJECT_ID('[TARGET_OBJECT]')
ORDER BY c.column_id;

-- ----------------------------------------------------------------------------
-- QUERY 2: Optional excluded columns query
-- ----------------------------------------------------------------------------
-- Paste the project-specific exclusion query here if the binding defines one.
-- It must return one column named column_name.
-- [EXCLUDE_QUERY]

-- ----------------------------------------------------------------------------
-- QUERY 3: Optional provenance query
-- ----------------------------------------------------------------------------
-- Paste the project-specific provenance query here if the binding defines one.
-- [PROVENANCE_QUERY]
