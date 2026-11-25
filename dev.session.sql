SELECT
    job_salary,
    salary_min,
    salary_max,
    salary_avg,
    salary_period,
    salary_currency
FROM dev.staging.stg_job_postings
WHERE job_salary IS NOT NULL
LIMIT 20;