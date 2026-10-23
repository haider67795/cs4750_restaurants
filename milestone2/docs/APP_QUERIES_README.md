# App queries

Use `../sql/all_app_queries.sql` for the full app query list.

- Queries 1-24 retrieve data. The sample vendor ID is 1.
- User 13947 is a demo customer; user 13866 manages vendor 1.
- Queries 25-42 demonstrate writes using new practice records. The write
  section ends in ROLLBACK. Run it in full, or issue ROLLBACK if you stop midway.
- The `SET ... = LAST_INSERT_ID()` lines retain a new record's ID so the next
  query can connect records correctly. These replace the initial setup block.
- The registration hash is a disposable demo hash; the app must generate a
  fresh password hash for each actual registration.
- In the app, example IDs/text become prepared-statement inputs. User IDs
  come from the authenticated login session. Manager assignment is a trusted
  approval action, not a permission any visitor can grant themselves.
- PHP formats exports from returned rows and validates imported CSV/JSON.
  Menu imports reuse query 33; schedule imports reuse query 32 in a transaction.

`../sql/create_tables.sql` defines the schema, `../sql/advanced_sql.sql` defines the triggers,
and `../sql/populate_small.sql` is the smaller data loader for empty tables.
The report's query-number table maps app features to the current file.
