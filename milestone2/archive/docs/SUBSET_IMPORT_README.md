# Preparing the subset for Milestone 1 tables

`prepare_subset_inserts.py` reads the two subset JSONL files and writes rows
for the existing Milestone 1 schema. It does not create tables, connect to
MySQL, or change the original files. It uses only Python's standard library.

From the repository's `milestone2` folder:

```powershell
python .\prepare_subset_inserts.py
```

The default inputs are `../food_subset/businesses.jsonl` and
`../food_subset/reviews.jsonl`. The default output is `prepared_data/`.
To regenerate, choose a new folder instead of overwriting an existing export:

```powershell
python .\prepare_subset_inserts.py --output prepared_data_v2
```

## Outputs

- `insert_data.sql`: inserts in foreign-key dependency order, using explicit
  column names and batches. This is the database import file.
- One JSONL and CSV file per table: readable views of the split records.
  Empty tables get empty JSONL files and CSV headers. CSV represents both
  NULL and empty text as blank cells; use SQL/JSONL for exact values.
- `import_report.json`: counts, conventions, and assumptions.
- `issues.json`: skipped/ambiguous fields and hours inferred from shorthand.
- `source_id_map.json`: original business/user IDs mapped to new integer IDs,
  plus the source line for each review. Keep it to trace records to the inputs.

## How the split works

1. Create a disabled Dataset Importer profile as the submitter of all listings.
2. Give each business an integer vendor ID; extract its location and base link.
3. Map recognized cuisine categories to shared Cuisine and VendorCuisine rows.
4. Split each business's weekly hours into OperatingHours rows.
5. Give every distinct source reviewer one anonymous imported User profile.
6. Insert reviews using the vendor and user ID maps.
7. Extract review picture URLs into Photo and ReviewPhoto rows, preserving
   their connection to the review author and business.

## Important conventions to match to your table definitions

Milestone 1 does not define SQL column lengths or enum values. This export
follows its columns and relationships, with these explicit choices:

- **Existing empty tables only.** Integer IDs start at 1. This is a one-time
  seed, not an upsert; do not rerun against populated tables. It never deletes
  existing rows or disables foreign-key checks.
- Use InnoDB and utf8mb4 columns so transactions and Unicode review text work.
  Review text should be TEXT or a sufficiently large equivalent; image URLs
  need enough space (VARCHAR(2048) is a practical choice).
- `day_of_week`: Monday=1 through Sunday=7. Hours are local Virginia times.
  Earlier closing times mean the following day, as specified in Milestone 1.
  Open-24-hours days become midnight-to-noon and noon-to-midnight rows.
- `vendor_type`: `restaurant`, `caterer`, or `food_truck`. Cafe/bakery/other
  fixed food establishments use `restaurant` in this broad classification.
  `listing_status`: `inactive` for explicitly permanently closed businesses;
  otherwise `imported`, which does not claim they are currently open.
- Datetimes are UTC, without timezone suffixes. `created_at` for listings and
  `joined_at` for imported profiles are import times, not original creation dates.
- Profiles have anonymous display names and unique `example.invalid` emails.
  **`password_hash` contains an intentionally invalid `!IMPORTED_NO_LOGIN!`
  marker, not a usable password hash.** No passwords are created. Your eventual
  application must reject login and password reset for these imported profiles.
  This is a placeholder convention within the unchanged schema; importing SQL
  does not implement application authentication or disable endpoints itself.
- Missing review text becomes an empty string; no review wording is invented.
  Missing phone, business website, captions, and review-update dates stay NULL.
  Google Maps listing links are not treated as business-owned websites.
- Photo upload time is unavailable, so its review timestamp is used as a
  documented proxy. Picture URLs are copied, not downloaded or checked.
- Only explicitly mapped geographic cuisines and Barbecue become cuisine tags.
  Generic Restaurant, service categories, and dietary labels are not cuisine tags.
- No data is invented for OperatingStop, MenuItem, FoodPermit, Manages,
  Favorites, or MenuItemPhoto. Those require other sources or app activity.
  Responses, rating summaries, and other unsupported fields stay in original JSON.

## Running the SQL later

Review the report and ensure table types/constraints accept the conventions
above. Select your project database, then execute the complete `insert_data.sql`
using your MySQL client. The script deliberately does not include a database
name or table-creation statements.

It temporarily enables strict checks and NO_BACKSLASH_ESCAPES to preserve
quoted text, starts a transaction, inserts rows, commits, and restores SQL mode.
Use a client that stops on errors; if any statement fails, stop and ROLLBACK
instead of continuing to COMMIT. A client that continues after errors can
otherwise commit partial results. Do not use a force/continue-on-error option.

The prepared data was checked for unique keys and consistent references.
It has not been loaded into or verified against your actual MySQL table definitions.
