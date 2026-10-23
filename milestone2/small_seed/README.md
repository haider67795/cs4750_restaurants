# Smaller dataset

25 real businesses and 3 fictional mobile/pop-up vendors, with connected records
in all 16 tables. CSV files are in `csv/`, JSON/JSONL files are in `json/`, and
counts are in `json/summary.json`. Synthetic data is identified in `json/provenance.json`.

The loader is `../sql/populate_small.sql`. It contains 16 multi-row INSERT
statements and is intended for empty tables. Do not rerun it on the populated
database. Stop on errors and roll back rather than committing a partial load.

Real review text and ratings are preserved. Demo content is labeled, and unknown
optional fields remain NULL.