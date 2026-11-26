# Production Job Postings Pipeline (v2) -dbt + Databricks

![P2 pipeline architecture](img/p2_pipeline.png)

A production dbt pipeline on **Databricks** over 843,097 raw job-posting scrapes, rebuilt nightly by a scheduled job with zero secrets.

- Shapes medallion layers into a tested star schema - 491,140 jobs at a declared grain
- Tracks a year of salary history with SCD2 snapshots - 504,591 version rows
- Loads incrementally and runs itself on a scheduled Databricks Job - no tokens anywhere

> **v2 of this pipeline** -[v1](https://github.com/Smartlyfe21/dbt-duckdb-pipeline) built the foundations on DuckDB + Github Actions. V2 moves the same dataset to a real warehouse: Databricks, SCD2 history, incremental loads, a scheduled job.

| What I Built                                | How I Implemented It                                                                                                                               | Where to Look                                                                                                                                    |
| ------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Star schema**                             | Built a job-postings fact table, company and skill dimensions, and a bridge that links each posting to its skills.                                 | [Mart models](analytics/models/marts/)                                                                                                           |
| **SCD Type 2 snapshots**                    | Tracked changes across 13 posting attributes and reconstructed historical versions from daily scrapes.                                             | [Snapshot definition](analytics/snapshots/snapshots.yml) · [Historical backfill](scripts/backfill_job_postings_snapshot.sql)                     |
| **Incremental fact table**                  | Used `job_id` as the merge key and `search_date` to identify new scrape days.                                                                      | [fct_job_postings.sql](analytics/models/marts/fct_job_postings.sql)                                                                              |
| **Reusable SQL macros**                     | Parsed salary ranges with `parse_salary` and controlled schema naming with `generate_schema_name`.                                                 | [Macros](analytics/macros/)                                                                                                                      |
| **Data quality tests**                      | Checked keys, relationships, accepted values, and salary bounds. Unit-tested the salary parser with a range, a single amount, and a missing value. | [SQL tests](analytics/tests/) · [Staging properties](analytics/models/staging/staging.yml) · [Mart properties](analytics/models/marts/marts.yml) |
| **Development and production environments** | Used separate `dev` and `prod` Unity Catalog catalogs. Verified **491,140 rows** in the production fact table.                                     | `prod.default.fct_job_postings`                                                                                                                  |
| **Databricks orchestration**                | Configured the production job in Databricks Jobs & Pipelines using a SQL warehouse and the `prod` catalog.                                         | Databricks → Jobs & Pipelines                                                                                                                    |
| **Skill-demand analysis**                   | Ranked skills by the number and percentage of distinct postings that mention them for a selected role.                                             | [in_demand_skills.sql](analytics/analyses/in_demand_skills.sql)                                                                                  |

---

## ⚙️ The dbt Pipeline

The raw data records what the scraper saw each day. A job can appear on several days, and one posting can mention several skills. The staging models preserve those observations. The fact table keeps the latest observation per job, while the snapshot preserves changes over time.

| Layer            | What happens                                                                                                                                  |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| **Sources**      | `raw.jobs.raw_job_postings` supplies posting observations. `raw.jobs.raw_job_skills` supplies the job-to-skill associations.                  |
| **Staging**      | Filters scraper errors, trims company names, cleans platform labels, parses salary ranges, and extracts four flags from `job_extensions_raw`. |
| **Intermediate** | `int_skill_observations` counts distinct jobs per skill so multiple keywords for the same skill do not inflate demand.                        |
| **Marts**        | `fct_job_postings`, `dim_company`, `dim_skill`, and `bridge_job_skills` support analysis at the job, company, and skill levels.               |
| **Snapshots**    | A separate branch reads from staging and records a new version when a tracked posting attribute changes.                                      |

[View the course lineage diagram](https://github.com/lukebarousse/dbt_Analytics_Engineering_Course/blob/main/project_2/img/lineage.png)

| dbt Feature             | How I Used It                                                                                                                                          |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Declared sources        | Referenced raw tables with `source('jobs', 'raw_job_postings')` and `source('jobs', 'raw_job_skills')`.                                                |
| Jinja                   | Generated flags for health insurance, dental insurance, paid time off, and postings that mention no degree requirement.                                |
| Custom macro            | Used `parse_salary()` for both ends of a salary range. For example, `100k–186k a year` becomes `100000` and `186000`.                                  |
| dbt package             | Used `dbt_utils.get_column_values()` to read the available search terms for a Jinja analysis.                                                          |
| Schema naming           | Overrode `generate_schema_name` to control where dbt materializes models.                                                                              |
| Seeds                   | Loaded the skill taxonomy from the version-controlled [skill_categories.csv](analytics/seeds/skill_categories.csv).                                    |
| Tests                   | Checked fact-table grain with `unique` and `not_null` tests on `job_id`. Relationship tests verify that bridge rows point to existing jobs and skills. |
| Persisted documentation | Used `persist_docs` to publish model and column descriptions to Unity Catalog.                                                                         |

---

## 🚀 Production

The production fact table is **`prod.default.fct_job_postings`**. In the verified run, it contained **491,140 rows**. The filtered staging view contained **691,950 scrape observations**. These counts measure different things: staging retains repeat observations, while the fact table represents one row per job.

```sql
SELECT COUNT(*) AS total_job_postings
FROM prod.default.fct_job_postings;
```

The recorded development build processed **8 models, 17 data tests, 1 snapshot, 7 seeds, and 1 unit test**. It finished with **31 successes, 2 warnings, 1 no-op, and 0 errors**. The warnings came from the salary sanity check and the accepted-values test for schedule types. The salary-parsing unit test passed.

---

## 📸 Snapshots

A salary correction can disappear from a latest-only fact table. The snapshot preserves the earlier version so an analyst can see what changed and when.

The snapshot uses the `check` strategy with `job_id` as its key and `searched_at` as the version timestamp. It watches 13 attributes, including salary bounds, currency, location, work arrangement, and benefit flags.

The project currently uses two destinations:

| Table                                 | Purpose                                                                                                                                  |
| ------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `dev.string.job_postings_snapshot`    | The dbt-managed snapshot, as configured in [snapshots.yml](analytics/snapshots/snapshots.yml).                                           |
| `dev.snapshots.job_postings_snapshot` | Historical versions reconstructed by the [backfill script](scripts/backfill_job_postings_snapshot.sql) from the full staging scrape log. |

The backfill takes the latest observation for each job on each scrape day, compares the tracked attributes with the previous observation, and keeps the rows where a version begins. This query ranks companies by the number of distinct jobs with at least one closed version. A posting that changed three times counts as one changed job.

```sql
SELECT
    company_name,
    COUNT(DISTINCT job_id) AS jobs_changed
FROM dev.snapshots.job_postings_snapshot
WHERE dbt_valid_to IS NOT NULL
GROUP BY company_name
ORDER BY jobs_changed DESC;
```

---

## 📖 Docs

The project’s YAML files document model grain, column meanings, and tests. Generate the docs from the `analytics/` directory to explore the lineage for this checkout:

```bash
dbt docs generate
dbt docs serve
```

Open the local URL printed in the terminal. Press **Ctrl + C** to stop the docs server.

Course references: [Luke Barousse’s Project 2 README](https://github.com/lukebarousse/dbt_Analytics_Engineering_Course/tree/main/project_2) · [Course-hosted dbt docs](https://lukebarousse.github.io/dbt_Analytics_Engineering_Course/project2/)

---

## 💻 Run It Yourself

Start from the **repository root**. You’ll need `uv`, a Databricks SQL warehouse, read access to the two source tables under `raw.jobs`, and permission to create objects in your target catalog. Configure your own `databricks` profile in `~/.dbt/profiles.yml`.

```bash
uv sync
source .venv/bin/activate
cd analytics

dbt deps
dbt debug --target dev
dbt build --target dev
```

To preview the skill-demand analysis for a selected role:

```bash
dbt show --select in_demand_skills --vars '{"job_title": "data engineer"}'
```

To run the snapshot for a specific scrape cutoff:

```bash
dbt snapshot --select job_postings_snapshot --target dev --vars '{"as_of": "2025-09-11"}'
```

To reconstruct the full history, run [backfill_job_postings_snapshot.sql](scripts/backfill_job_postings_snapshot.sql) in a Databricks SQL editor after building staging and creating the `dev.snapshots` schema.

---

## 📁 Project Layout

```text
.
├── analytics/
│   ├── dbt_project.yml
│   ├── packages.yml
│   ├── package-lock.yml
│   ├── analyses/                     # Skill-demand queries and Jinja examples
│   ├── macros/                       # Salary parsing, schema naming, and SQL helpers
│   ├── models/
│   │   ├── staging/                  # Cleaned posting and skill observations
│   │   ├── intermediate/             # Per-skill observation counts
│   │   └── marts/                    # Fact, dimensions, and job-to-skill bridge
│   ├── seeds/                        # Skill taxonomy and starter CSVs
│   ├── snapshots/                    # SCD Type 2 snapshot definition
│   └── tests/                        # Salary sanity and custom generic tests
└── scripts/
    └── backfill_job_postings_snapshot.sql
```
