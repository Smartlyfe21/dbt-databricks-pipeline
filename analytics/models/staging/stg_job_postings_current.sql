{{ config(materialized='ephemeral') }}

SELECT
     job_id,
     job_title,
     company_name,
     job_location,
     job_schedule_type,
     job_work_from_home,
     salary_min, 
     salary_max,
     salary_period,
     salary_currency,
     has_health_insurance,
     has_dental_insurance,
     has_paid_time_off,
     has_no_degree_mentioned,
     searched_at
FROM {{ ref('stg_job_postings') }}
WHERE job_title = 'Senior Data Engineer'
    AND company_name = 'Fraser Health'
    AND search_date <= CAST('{{ var("as_of", run_started_at)}}' AS DATE)
QUALIFY ROW_NUMBER() OVER (
     PARTITION BY job_id
     ORDER BY searched_at DESC
) = 1  

