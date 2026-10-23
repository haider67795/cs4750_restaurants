# Populate all 16 tables

Run **complete_data/populate_all_tables.sql** against the existing `restaurants`
database. It contains all real subset data plus connected, explicitly synthetic
demo records. The database was inspected: all 16 tables existed and were empty.
No records were loaded during preparation or validation.

From your connected `mysql>` prompt, use:

```sql
SOURCE C:/Users/haide/OneDrive/Documents/UVA/CS4750/cs4750_restaurants/milestone2/complete_data/populate_all_tables.sql;
```

Do not run the previous `prepared_data/insert_data.sql` first. This is the
complete replacement population file, not an add-on to that earlier export.

## What it does

- Uses `restaurants`, preserves foreign-key checks, and sets the session to UTC.
- Requires all 16 target tables to be empty. If any contain rows, it refuses
  to insert instead of deleting or duplicating data.
- Uses ordinary SQL only, without DELIMITER commands or stored procedures.
  Guarded inserts skip all rows if any target table was already populated.
  At the end it checks every expected row count and same-vendor photo links,
  then commits on success or rolls back on a mismatch. No routine privileges
  are required. Run the entire file in a fresh connection.
- Restores session SQL mode, timezone, and autocommit after normal completion.
  If interrupted or stopped on an error, reconnect before retrying so pending
  work is rolled back. Do not manually COMMIT an incomplete import.
- Prints counts for all 16 tables when finished. It is a one-time seed, not
  a synchronization or upsert script. Run it while no other clients write data.

## Real data retained

- All 75 real businesses, 75 locations, 15,056 reviews, 13,864 distinct anonymous
  source authors, and 1,540 original review-photo records.
- Original real review text and ratings are unchanged. A rating-only review
  still has empty text; fictional words are not substituted into real reviews.
- Unknown source fields such as actual review update times remain NULL.
  Coordinates are rounded to match the database's six-decimal precision.
- Source weekly hours, cuisine tags, and their relationships are retained.
  Weekday values now use names (Monday, etc.) to match your actual ENUM.
- Imported profiles remain attribution records, with reserved placeholder emails
  and disabled password markers. They are not registered real-user accounts.
  Imported photo upload times still use the source review timestamp as a proxy.

## Synthetic additions and placeholders

- Six fictional mobile/pop-up vendors, all named `[DEMO] ...`.
- 81 demo owners and 12 demo customers, with actual PHP bcrypt cost-10 password
  hashes. `csv/demo_accounts.csv` contains their distinct, public demo passwords.
  These accounts use nonexistent `example.invalid` emails. They are for testing
  only; never use these published credentials for actual users or production.
- Three synthetic menu items per vendor and matched illustrative food photos.
  Names/descriptions/captions explicitly identify demo content. Prices and
  availability are fictional, not actual vendor menus or quotes.
- Two explicitly labeled demo reviews per vendor, with one illustrated review.
- Demo ownership/management permissions, favorites, and four dated visits per
  vendor. These do not identify real owners or actual attendance/events.
- One fictional permit per vendor. Every permit number begins `DEMO-NOT-VALID`
  and the authority explicitly says it is not real. Nothing is verified by it.
- Missing phone numbers use reserved fictional 202-555-01xx numbers; missing
  websites use nonexistent `example.invalid` addresses. Missing descriptions
  are labeled as placeholders. Missing full weekly schedules get demo hours.
- Vendors lacking a mapped cuisine are connected to an explicit `Unspecified`
  tag instead of having a geographic cuisine guessed.
- Optional unknown fields, such as future actual stop times and permit documents,
  remain NULL. Filling every table does not require inventing every optional field.

`json/provenance.json` identifies each added synthetic row and each filled placeholder
field by table/key. `json/completion_report.json` gives source/final counts and
assumptions. Every table also has a populated CSV and JSONL for inspection.

## Illustrative photo sources

The generic menu photos come from [TheMealDB](https://www.themealdb.com/).
`json/photo_sources.json` records the exact image URLs, recipe source pages, metadata
endpoints, and successful HTTP checks. These images illustrate dishes; they do
not depict food served by the real businesses. Remote image availability can change.

The original review-photo URLs remain unchanged and have not all been checked.

## Rebuild later

The original data and earlier importer are unchanged. From `milestone2`:

```powershell
python .\complete_subset_data.py --source .\prepared_data --schema .\complete_data\json\schema_snapshot.json --photos .\complete_data\json\photo_sources.json --output .\complete_data_v2
```

Requires Python, the neighboring `prepare_subset_inserts.py`, and XAMPP PHP at
`C:/xampp/php/php.exe` for password hashing (or pass `--php` with its location).
The output folder must be new. Demo bcrypt hashes use fresh salts on each rebuild.

## Validation

The live MySQL schema was inspected, and the original INSERT statements were
prepared without execution. The current plain INSERT/SELECT version was tested
against the full dataset in an isolated in-memory SQL database with key
constraints enabled, and its populated-table skip behavior was verified. Every
exported value matches the prepared records. Column types, ENUMs, required
fields, lengths, key relationships, domain rules, and same-vendor photo links
were also checked. The final file has not been executed against your remote database.
