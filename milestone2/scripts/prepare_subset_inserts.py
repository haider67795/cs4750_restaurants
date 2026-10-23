"""Split UCSD Google Local subset JSONL into Milestone 1 rows and SQL inserts.

Python standard library only. This script never connects to a database.
See the accompanying README for assumptions and import requirements.
"""
import argparse
import csv
import hashlib
import json
import math
import re
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path


# Order matters: referenced rows must be inserted before their children.
SCHEMA = {
    'User': 'user_id display_name email password_hash joined_at',
    'Vendor': 'vendor_id name description vendor_type phone_number website_url listing_status created_at timezone submitted_by_user_id',
    'Cuisine': 'cuisine_id cuisine_name',
    'Location': 'location_id location_name street_address city state postal_code latitude longitude',
    'OperatingHours': 'vendor_id hours_number day_of_week opening_time closing_time',
    'Review': 'review_id author_user_id vendor_id rating review_text created_at updated_at',
    'Photo': 'photo_id uploader_user_id vendor_id image_url caption uploaded_at',
    'VendorCuisine': 'vendor_id cuisine_id',
    'VendorBase': 'vendor_id location_id',
    'ReviewPhoto': 'photo_id review_id',
    'OperatingStop': 'stop_id vendor_id location_id scheduled_start scheduled_end actual_start actual_end stop_status notes',
    'MenuItem': 'menu_item_id vendor_id item_name description price category availability_status',
    'FoodPermit': 'permit_id vendor_id permit_number issuing_authority permit_type issued_date expiration_date document_url',
    'Manages': 'user_id vendor_id management_role granted_at',
    'Favorites': 'user_id vendor_id saved_at',
    'MenuItemPhoto': 'photo_id menu_item_id',
}
SCHEMA = {name: columns.split() for name, columns in SCHEMA.items()}
CUISINES = {
    'american restaurant': 'American', 'new american restaurant': 'New American',
    'asian restaurant': 'Asian', 'asian fusion restaurant': 'Asian Fusion',
    'pan-asian restaurant': 'Pan-Asian', 'brazilian restaurant': 'Brazilian',
    'chinese restaurant': 'Chinese', 'eritrean restaurant': 'Eritrean',
    'ethiopian restaurant': 'Ethiopian', 'european restaurant': 'European',
    'greek restaurant': 'Greek', 'indian restaurant': 'Indian',
    'italian restaurant': 'Italian', 'japanese restaurant': 'Japanese',
    'korean restaurant': 'Korean', 'latin american restaurant': 'Latin American',
    'mediterranean restaurant': 'Mediterranean', 'mexican restaurant': 'Mexican',
    'southeast asian restaurant': 'Southeast Asian',
    'southern restaurant (us)': 'Southern US', 'thai restaurant': 'Thai',
    'vietnamese restaurant': 'Vietnamese', 'barbecue restaurant': 'Barbecue',
}
DAYS = {day: i for i, day in enumerate(
    ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'], 1)}


def read_jsonl(path):
    with path.open(encoding='utf-8-sig') as source:
        for number, line in enumerate(source, 1):
            if line.strip():
                value = json.loads(line)
                if not isinstance(value, dict):
                    raise ValueError(f'{path}:{number}: expected a JSON object')
                yield value


def utc_time(milliseconds):
    return datetime.fromtimestamp(int(milliseconds) / 1000, timezone.utc).strftime('%Y-%m-%d %H:%M:%S')


def clock(text, inherited=None):
    match = re.fullmatch(r'(\d{1,2})(?::(\d{2}))?(AM|PM)?', text.upper().replace(' ', ''))
    if not match:
        raise ValueError(f'Unrecognized clock: {text}')
    hour, minute, marker = int(match[1]), int(match[2] or 0), match[3] or inherited
    if marker is None or not 1 <= hour <= 12 or not 0 <= minute < 60:
        raise ValueError(f'Invalid or ambiguous clock: {text}')
    return (hour % 12 + (12 if marker == 'PM' else 0)) * 60 + minute


def time_text(minutes):
    return f'{minutes // 60:02}:{minutes % 60:02}:00'


def parse_hours(text):
    """Return intervals, recording Google shorthand as an explicit assumption."""
    text = str(text).replace('\u202f', '').replace('\xa0', '').strip()
    if text.lower() == 'closed':
        return [], False
    if text.lower() == 'open 24 hours':
        # Split at noon to avoid losing 24-hour meaning with equal endpoints.
        return [('00:00:00', '12:00:00'), ('12:00:00', '00:00:00')], False
    result, inferred = [], False
    for interval in text.split(','):
        parts = re.split(r'[\u2013\u2014\u2212-]', interval.strip())
        if len(parts) != 2:
            raise ValueError(f'Unrecognized interval: {text}')
        start, end = parts
        end_minutes = clock(end)
        if not re.search(r'(AM|PM)', start, re.I):
            # Choose the shortest positive interval; matches 4–9PM and 12–5PM.
            candidates = [clock(start, marker) for marker in ('AM', 'PM')]
            start_minutes = min(candidates, key=lambda n: (end_minutes - n) % 1440 or 1440)
            inferred = True
        else:
            start_minutes = clock(start)
        if start_minutes == end_minutes:
            raise ValueError(f'Equal endpoints without explicit 24-hour label: {text}')
        result.append((time_text(start_minutes), time_text(end_minutes)))
    return result, inferred


def address_parts(business):
    address = business.get('address') or ''
    name = business.get('name') or ''
    if address.startswith(name + ','):
        address = address[len(name) + 1:].strip()
    match = re.fullmatch(r'(?:(.*),\s*)?([^,]+),\s*([A-Z]{2})\s+(\d{5}(?:-\d{4})?)(?:,\s*(?:USA|United States))?', address)
    return (match.groups() if match else (None, None, None, None)), bool(match)


def sql_value(value):
    if value is None:
        return 'NULL'
    if isinstance(value, (int, float)):
        if not math.isfinite(value):
            raise ValueError('Non-finite number cannot be inserted')
        return str(value)
    text = str(value)
    # Hex preserves control characters without embedding them in the SQL script.
    if any(ord(c) < 32 for c in text):
        return "CONVERT(X'" + text.encode('utf-8').hex() + "' USING utf8mb4)"
    return "'" + text.replace("'", "''") + "'"


def write_sql(path, tables):
    with path.open('w', encoding='utf-8', newline='\n') as out:
        out.write('-- Generated inserts only. Select your database before running.\n'
                  '-- Requires existing EMPTY target tables, InnoDB, and utf8mb4.\n'
                  '-- IDs start at 1. Do not rerun against populated tables.\n'
                  '-- Stop on any error and ROLLBACK; do not continue to COMMIT.\n'
                  'SET NAMES utf8mb4;\n'
                  'SET @subset_saved_sql_mode = @@SESSION.sql_mode;\n'
                  "SET SESSION sql_mode = CONCAT_WS(',', NULLIF(@@SESSION.sql_mode, ''), 'NO_BACKSLASH_ESCAPES', 'STRICT_ALL_TABLES');\n"
                  'START TRANSACTION;\n\n')
        for table, columns in SCHEMA.items():
            rows = tables[table]
            out.write(f'-- {table}: {len(rows)} rows\n')
            # Bound both row count and statement bytes for ordinary server limits.
            batch, size = [], 0
            def flush():
                if batch:
                    out.write('INSERT INTO `' + table + '` (' + ', '.join('`' + c + '`' for c in columns) + ') VALUES\n')
                    out.write(',\n'.join(batch) + ';\n')
            for row in rows:
                literal = '(' + ', '.join(sql_value(row[c]) for c in columns) + ')'
                length = len(literal.encode('utf-8'))
                if batch and (len(batch) >= 100 or size + length > 250_000):
                    flush()
                    batch, size = [], 0
                batch.append(literal)
                size += length
            flush()
            out.write('\n')
        out.write('COMMIT;\nSET SESSION sql_mode = @subset_saved_sql_mode;\n')


def validate(tables):
    """Check keys, required values and foreign-key paths before exporting."""
    keys = {'User': ['user_id'], 'Vendor': ['vendor_id'], 'Cuisine': ['cuisine_id'],
            'Location': ['location_id'], 'OperatingHours': ['vendor_id', 'hours_number'],
            'Review': ['review_id'], 'Photo': ['photo_id'],
            'VendorCuisine': ['vendor_id', 'cuisine_id'], 'VendorBase': ['vendor_id'],
            'ReviewPhoto': ['photo_id']}
    for table, columns in keys.items():
        values = [tuple(row[c] for c in columns) for row in tables[table]]
        assert len(values) == len(set(values)), f'Duplicate keys in {table}'
    users = {r['user_id'] for r in tables['User']}
    vendors = {r['vendor_id'] for r in tables['Vendor']}
    locations = {r['location_id'] for r in tables['Location']}
    cuisines = {r['cuisine_id'] for r in tables['Cuisine']}
    reviews = {r['review_id']: r for r in tables['Review']}
    photos = {r['photo_id']: r for r in tables['Photo']}
    assert len({r['email'] for r in tables['User']}) == len(users)
    assert len({r['cuisine_name'].casefold() for r in tables['Cuisine']}) == len(cuisines)
    for row in tables['Vendor']:
        assert row['submitted_by_user_id'] in users and row['name']
    for row in tables['Location']:
        assert -90 <= row['latitude'] <= 90 and -180 <= row['longitude'] <= 180
    for row in tables['Review']:
        assert row['author_user_id'] in users and row['vendor_id'] in vendors
        assert 1 <= row['rating'] <= 5 and row['review_text'] is not None
    for row in tables['Photo']:
        assert row['uploader_user_id'] in users and row['vendor_id'] in vendors and row['image_url']
    for row in tables['ReviewPhoto']:
        assert photos[row['photo_id']]['vendor_id'] == reviews[row['review_id']]['vendor_id']
        assert photos[row['photo_id']]['uploader_user_id'] == reviews[row['review_id']]['author_user_id']
    for row in tables['VendorBase']:
        assert row['vendor_id'] in vendors and row['location_id'] in locations
    for row in tables['VendorCuisine']:
        assert row['vendor_id'] in vendors and row['cuisine_id'] in cuisines
    for row in tables['OperatingHours']:
        assert row['vendor_id'] in vendors and row['day_of_week'] in range(1, 8)
        assert row['opening_time'] != row['closing_time']


def main():
    base = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--businesses', type=Path, default=base.parent / 'food_subset/json/businesses.jsonl')
    parser.add_argument('--reviews', type=Path, default=base.parent / 'food_subset/json/reviews.jsonl')
    parser.add_argument('--output', type=Path, default=base / 'prepared_data')
    parser.add_argument('--import-time', help='UTC YYYY-MM-DD HH:MM:SS; defaults to current UTC time')
    args = parser.parse_args()
    if args.output.exists():
        parser.error('Output already exists; use --output to choose a new folder.')
    imported_at = args.import_time or datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')
    datetime.strptime(imported_at, '%Y-%m-%d %H:%M:%S')
    tables = {table: [] for table in SCHEMA}
    issues, counters = [], Counter()
    mapping = {'vendors': {}, 'users': {}, 'review_source_lines': {}}

    def add(table, **values):
        if set(values) != set(SCHEMA[table]):
            raise ValueError(f'Wrong columns for {table}')
        tables[table].append(values)

    def add_user(identifier, display_name, email):
        user_id = len(tables['User']) + 1
        # Deliberately invalid password-hash format: no password is provisioned.
        # App login/reset code must reject these reserved imported accounts.
        disabled = '!IMPORTED_NO_LOGIN!' + hashlib.sha256(identifier.encode()).hexdigest()
        add('User', user_id=user_id, display_name=display_name, email=email,
            password_hash=disabled, joined_at=imported_at)
        return user_id

    importer = add_user('subset-importer', 'Dataset Importer', 'dataset-importer@example.invalid')
    cuisine_ids = {}
    for business in read_jsonl(args.businesses):
        source_id = business['gmap_id']
        if source_id in mapping['vendors']:
            raise ValueError(f'Duplicate business ID: {source_id}')
        vendor_id = len(tables['Vendor']) + 1
        mapping['vendors'][source_id] = vendor_id
        category = business.get('category') or []
        category = [category] if isinstance(category, str) else category
        lower = {c.lower() for c in category}
        kind = 'food_truck' if any('food truck' in c for c in lower) else ('caterer' if 'caterer' in lower else 'restaurant')
        status = 'inactive' if 'permanently closed' in str(business.get('state') or '').lower() else 'imported'
        add('Vendor', vendor_id=vendor_id, name=business['name'], description=business.get('description'),
            vendor_type=kind, phone_number=None, website_url=None, listing_status=status,
            created_at=imported_at, timezone='America/New_York', submitted_by_user_id=importer)
        (street, city, state, postal), parsed = address_parts(business)
        if not parsed:
            issues.append({'type': 'unparsed_address', 'vendor_id': vendor_id, 'value': business.get('address')})
        lat, lon = business.get('latitude'), business.get('longitude')
        if isinstance(lat, (int, float)) and isinstance(lon, (int, float)) and math.isfinite(lat) and math.isfinite(lon) and -90 <= lat <= 90 and -180 <= lon <= 180:
            location_id = len(tables['Location']) + 1
            add('Location', location_id=location_id, location_name=business['name'], street_address=street,
                city=city, state=state, postal_code=postal, latitude=lat, longitude=lon)
            # Do not infer a permanent base for a mobile vendor.
            if kind != 'food_truck':
                add('VendorBase', vendor_id=vendor_id, location_id=location_id)
        else:
            issues.append({'type': 'missing_or_invalid_coordinates', 'vendor_id': vendor_id})
        tags = sorted({CUISINES[c] for c in lower if c in CUISINES})
        for tag in tags:
            if tag not in cuisine_ids:
                cuisine_ids[tag] = len(cuisine_ids) + 1
                add('Cuisine', cuisine_id=cuisine_ids[tag], cuisine_name=tag)
            add('VendorCuisine', vendor_id=vendor_id, cuisine_id=cuisine_ids[tag])
        hours_number = 0
        for entry in business.get('hours') or []:
            try:
                day, text = entry
                day_id = DAYS[day]
                intervals, inferred = parse_hours(text)
                if inferred:
                    issues.append({'type': 'inferred_hours_meridiem', 'vendor_id': vendor_id, 'day': day, 'value': text})
                for opening, closing in intervals:
                    hours_number += 1
                    add('OperatingHours', vendor_id=vendor_id, hours_number=hours_number,
                        day_of_week=day_id, opening_time=opening, closing_time=closing)
            except (ValueError, KeyError, TypeError) as error:
                issues.append({'type': 'unparsed_hours', 'vendor_id': vendor_id, 'value': entry, 'reason': str(error)})

    for line_number, review in enumerate(read_jsonl(args.reviews), 1):
        counters['source_reviews'] += 1
        vendor_id = mapping['vendors'].get(review.get('gmap_id'))
        try:
            source_user = str(review['user_id'])
            if not source_user or source_user == 'None' or vendor_id is None:
                raise ValueError('Missing author or matching business')
            rating = review['rating']
            if isinstance(rating, bool) or not isinstance(rating, (int, float)) or rating != int(rating) or not 1 <= rating <= 5:
                raise ValueError('Invalid rating')
            created = utc_time(review['time'])
        except (ValueError, KeyError, TypeError, OverflowError, OSError) as error:
            issues.append({'type': 'skipped_review', 'source_line': line_number, 'reason': str(error)})
            continue
        if source_user not in mapping['users']:
            anonymous_number = len(mapping['users']) + 1
            email_key = hashlib.sha256(source_user.encode()).hexdigest()[:32]
            mapping['users'][source_user] = add_user(source_user, f'Imported User {anonymous_number:05}', f'imported.google.{email_key}@example.invalid')
        author = mapping['users'][source_user]
        review_id = len(tables['Review']) + 1
        mapping['review_source_lines'][str(review_id)] = line_number
        text = review.get('text')
        if text is None:
            text = ''
            counters['rating_only_reviews_with_empty_text'] += 1
        add('Review', review_id=review_id, author_user_id=author, vendor_id=vendor_id,
            rating=int(rating), review_text=text, created_at=created, updated_at=None)
        seen_urls = set()
        for picture in review.get('pics') or []:
            urls = picture.get('url') or []
            urls = [urls] if isinstance(urls, str) else urls
            for url in urls:
                if not isinstance(url, str) or not url.startswith(('https://', 'http://')) or url in seen_urls:
                    continue
                seen_urls.add(url)
                photo_id = len(tables['Photo']) + 1
                add('Photo', photo_id=photo_id, uploader_user_id=author, vendor_id=vendor_id,
                    image_url=url, caption=None, uploaded_at=created)
                add('ReviewPhoto', photo_id=photo_id, review_id=review_id)
    validate(tables)
    args.output.mkdir(parents=True)
    (args.output / 'csv').mkdir()
    (args.output / 'json').mkdir()
    for table, rows in tables.items():
        with (args.output / 'json' / f'{table}.jsonl').open('w', encoding='utf-8') as out:
            for row in rows:
                out.write(json.dumps(row, ensure_ascii=False) + '\n')
        with (args.output / 'csv' / f'{table}.csv').open('w', encoding='utf-8', newline='') as out:
            writer = csv.DictWriter(out, fieldnames=SCHEMA[table])
            writer.writeheader()
            writer.writerows(rows)
    write_sql(args.output / 'insert_data.sql', tables)
    report = {'import_time_utc': imported_at, 'rows_per_table': {t: len(rows) for t, rows in tables.items()},
              'source_counts': dict(counters), 'issue_counts': dict(Counter(i['type'] for i in issues)),
              'empty_tables': [t for t, rows in tables.items() if not rows],
              'assumptions': [
                  'Explicit sequential IDs starting at 1; target tables must be empty. Not a repeatable/upsert database import.',
                  'Anonymous profiles preserve distinct source authors; emails are placeholders. Password fields contain deliberately invalid disabled markers, not usable password hashes. App must reject login and reset for these accounts.',
                  'User joined_at and vendor created_at are import timestamps, not historical registration dates.',
                  'All datetimes are UTC; Virginia vendors use America/New_York for local operating hours.',
                  'day_of_week uses Monday=1 through Sunday=7. Existing table definitions must accept this convention.',
                  'Vendor types: restaurant, caterer, food_truck. Listing status: imported or inactive. Check your table constraints before executing SQL.',
                  'Google Maps URLs are not vendor websites; website_url and phone_number remain NULL.',
                  'Cuisine tags use a conservative explicit category mapping; broad categories and dietary/service labels are not cuisines.',
                  'Null review text is stored as empty text; rating-only reviews are retained.',
                  'Photo uploaded_at uses its review timestamp as a proxy; actual photo upload time is not supplied. Photo URLs were not checked for availability.',
                  'Closed days have no hours rows. Open 24 hours becomes two adjacent 12-hour intervals. Missing AM/PM is inferred using the shortest positive interval and logged.',
                  'No menus, permits, ownership, favorites, dated stops or dish/photo associations are invented. Business responses are not mapped because the schema has no corresponding table.',
                  'CSV is for inspection; SQL/JSONL preserve NULL distinctly from empty text. Original JSONL retains unmapped source fields.',
              ]}
    for name, value in [('import_report.json', report), ('source_id_map.json', mapping), ('issues.json', issues)]:
        (args.output / 'json' / name).write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(report['rows_per_table'], indent=2))
    print(f"Issues: {report['issue_counts']}")
    print(f'Prepared files: {args.output.resolve()}')


if __name__ == '__main__':
    main()
