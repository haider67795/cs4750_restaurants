# Milestone 2

The report is `../milestone2.qmd`. Screenshots are in `../media/milestone2/`.

- `sql/`: current table definitions, app queries, triggers, tests, and smaller dataset inserts.
- `scripts/`: Python preparation scripts and the database export script.
- `small_seed/`: current dataset CSV/JSON and its counts.
- `query_tests/`: recorded test results.
- `docs/`: query notes and submission checklist.
- `exports/`: database dumps, created when you run the export script.
- `archive/`: superseded SQL and earlier report versions. Do not use these as the current submission.
- `prepared_data/` and `complete_data/`: earlier dataset stages, retained for reference.

## Current SQL

| File | Purpose |
|---|---|
| sql/create_tables.sql | All 16 table definitions and CHECK constraints |
| sql/populate_small.sql | Current smaller dataset; load into empty tables only |
| sql/all_app_queries.sql | Current app query list; write examples end in ROLLBACK |
| sql/advanced_sql.sql | Seven same-vendor photo triggers |
| sql/trigger_tests.sql | Valid and invalid trigger tests |
| sql/report_queries.sql | Table descriptions, counts, and samples |

The older `app_queries.sql`, initial partial loader, and larger loader are archived.
The current SQL was compared with the report. This cleanup did not recheck the live database.

## Export the GCP database

Open PowerShell in this folder and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\export_database.ps1
```

Enter the database password at the prompt. A successful export creates a dated
`.sql` file in `exports/`, containing table definitions, rows, and triggers.
This exports the database; it does not change its rows. App SELECT queries remain
in `sql/all_app_queries.sql` because a database dump does not save application queries.
A restore test is still needed to confirm the dump can recreate the database.

Google's managed SQL export omits triggers and stored procedures, so use the
included mysqldump script for this project:
https://docs.cloud.google.com/sql/docs/mysql/import-export/import-export-sql