SELECT
    company_name,
    salary_min,
    salary_max,
    dbt_valid_from,
    dbt_valid_to,
    CASE WHEN dbt_valid_to IS NULL THEN 'current' ELSE 'closed' END AS version_status
FROM dev.string.job_postings_snapshot
ORDER BY dbt_valid_from;