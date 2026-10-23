# Milestone 2: SQL and report

There is no fixed number of app queries. Cover the application's planned actions.
The catalogue is grouped by feature; one feature may use multiple statements.
This is the SQL layer. The later PHP/Python backend executes individual queries
with bound parameters and implements authentication, uploads and downloads.

## Files to work with

| File | Purpose |
|---|---|
| ../sql/create_tables.sql | All 16 table definitions, keys, relationships and CHECK constraints |
| ../sql/populate_small.sql | Current smaller real/synthetic dataset, 16 multi-row inserts; empty tables only |
| ../sql/all_app_queries.sql | Planned app SELECT/INSERT/UPDATE/DELETE operations; writes are demonstrated in a rolled-back transaction |
| ../sql/advanced_sql.sql | Existing CHECK constraints plus same-vendor photo triggers |
| report_queries.sql | Separate DESC, row-count and sample queries for each table |

Do not rerun the seed on the populated database. App query examples do not need
the tables recreated. The trigger-definition file uses a short // delimiter for its compound bodies.

## Proposal feature coverage

The report's query-number table is the current feature index for
`../sql/all_app_queries.sql`. Queries 1-24 cover browsing, search/filter/sort, profiles,
reviews, photos, schedules, saved vendors, login lookup and export records.
Queries 25-42 cover registration, vendor/location/menu/review operations,
management assignments, photo links, favorites, permits and removals.

The file uses sample IDs and text directly. Bind real inputs in the app and
obtain acting user IDs from the server-side session. The write section creates
new practice records and rolls back its changes. Read APP_QUERIES_README.md for
these execution details. File parsing and CSV/JSON downloads belong in the app;
menu imports reuse query 33 and schedule imports reuse query 32.

## Advanced requirement

The assignment requires at least two DIFFERENT types. Use:

1. CHECK constraints already defined for ratings, nonnegative prices,
   coordinates and operating-stop time ordering.
2. Same-vendor photo-link triggers, which automatically reject incompatible attachments and vendor changes.

Multiple CHECK constraints still count as one type. Primary/foreign keys,
NOT NULL, UNIQUE, AUTO_INCREMENT and ordinary indexes do not count for this
advanced requirement. Test both accepted and rejected input. Triggers compare related vendor IDs; ordinary foreign keys alone cannot enforce that rule. App authentication is still separate.

## PDF report evidence

- Include all team members' names/computing IDs and the database hosting details.
- Include the final ER diagram and normalized schemas. Explain any changes from
  Milestone 1 and how feedback was addressed.
- For EVERY table: capture its schema, exact count and representative sample
  data. report_queries.sql provides separate statements for this evidence.
- Explain data practicality/sufficiency in context. No fixed row minimum is
  specified; nonempty tables alone are not proof of adequate data. Describe
  coverage (e.g. multiple reviews per vendor, mobile stops, favorites) honestly.
- State the actual source is UCSD Google Local (2021), filtered to Virginia,
  instead of the proposal's tentative Yelp source. The smaller seed has 25 real
  businesses and 3 explicitly fictional mobile/pop-up vendors.
- Distinguish real source rows and synthetic menus/permits/owners/activity.
  Cite UCSD and TheMealDB; use small_seed/json/provenance.json for exact synthetic
  rows and placeholder fields. Do not describe demonstration permits as verified.
- Include the regular and advanced SQL, explain the business purpose, and show
  test results for retrieval/insertion/update/deletion and advanced commands.
- The stated milestone purpose mentions query performance. Include useful
  EXPLAIN/timing observations for representative queries if your report discusses
  performance; no specific timing-results count is stated in the supplied rubric.
- Save the report as PDF. The report itself has not been created by these SQL files.

## SQL submission

Submit a .sql file containing the implemented schema, populated data, advanced
definitions and planned app SQL. A genuine database export provides schema,
data and triggers (include triggers in export options), but it will not
usually contain standalone application SELECT/UPDATE/DELETE examples. Include
those separately within the submission SQL after setup. Keep example writes
rolled back so they do not damage the seeded database.

Do not concatenate several alternative seed files. Use only the current smaller
dataset. Test a reconstruction on a separate database before calling the final
submission reproducible. The final combined export and PDF remain to be made.

This checklist tracks technical deliverables; it is not a claim that generated
SQL satisfies the course's own-work policy.
