"""Combine the real prepared subset with explicitly identified demo records.

No database connection. Produces one atomic MySQL population script plus CSVs,
JSONL, provenance, schema checks, and a report. Requires the earlier importer.
"""
import argparse
import csv
import hashlib
import json
import math
import random
import subprocess
from collections import Counter
from datetime import datetime, timedelta
from pathlib import Path

from prepare_subset_inserts import SCHEMA, read_jsonl, sql_value

DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
ORDER = ['User', 'Vendor', 'Cuisine', 'Location', 'OperatingHours', 'Review',
         'Photo', 'VendorCuisine', 'VendorBase', 'OperatingStop', 'MenuItem',
         'FoodPermit', 'Manages', 'Favorites', 'ReviewPhoto', 'MenuItemPhoto']
PRIMARY = {'User':['user_id'], 'Vendor':['vendor_id'], 'Cuisine':['cuisine_id'],
           'Location':['location_id'], 'OperatingHours':['vendor_id','hours_number'],
           'Review':['review_id'], 'Photo':['photo_id'], 'VendorCuisine':['vendor_id','cuisine_id'],
           'VendorBase':['vendor_id'], 'OperatingStop':['stop_id'], 'MenuItem':['menu_item_id'],
           'FoodPermit':['permit_id'], 'Manages':['user_id','vendor_id'],
           'Favorites':['user_id','vendor_id'], 'ReviewPhoto':['photo_id'], 'MenuItemPhoto':['photo_id']}


def bcrypt_hashes(passwords, php):
    code = '$p=json_decode(stream_get_contents(STDIN),true); $r=[]; foreach($p as $s){$r[]=password_hash($s,PASSWORD_BCRYPT,["cost"=>10]);} echo json_encode($r);'
    result = subprocess.run([str(php), '-r', code], input=json.dumps(passwords),
                            capture_output=True, encoding='utf-8', check=True)
    values = json.loads(result.stdout)
    if len(values) != len(passwords) or not all(isinstance(v,str) and v.startswith('$2y$10$') for v in values):
        raise ValueError('Bcrypt hash generation failed')
    return values


def validate(tables, snapshot):
    schema = {(c['table'], c['column']):c for c in snapshot['schema'] if c['kind']=='column'}
    refs = [c for c in snapshot['schema'] if c['kind']=='foreign_key']
    for table, rows in tables.items():
        keys = [tuple(row[c] for c in PRIMARY[table]) for row in rows]
        assert len(keys)==len(set(keys)), f'Duplicate primary key: {table}'
        for row in rows:
            assert set(row)==set(SCHEMA[table]), f'Column mismatch: {table}'
            for column,value in row.items():
                spec = schema[table,column]
                assert value is not None or spec['nullable']=='YES', f'NULL: {table}.{column}'
                if isinstance(value,str) and spec['length']:
                    if spec['type'] in ('text','mediumtext','longtext'):
                        assert len(value.encode('utf-8')) <= spec['length'], f'Text bytes: {table}.{column}'
                    else:
                        assert len(value)<=spec['length'], f'Text length: {table}.{column}'
                if spec['type'].startswith('enum(') and value is not None:
                    allowed = [v.strip("'") for v in spec['type'][5:-1].split(',')]
                    assert value in allowed, f'Enum: {table}.{column}'
                if spec['type']=='timestamp' and value is not None:
                    assert '1970-01-01 00:00:01' <= value <= '2038-01-19 03:14:07', f'Timestamp: {table}.{column}'
    for fk in refs:
        parents={row[fk['parent_column']] for row in tables[fk['parent']]}
        assert all(row[fk['column']] in parents for row in tables[fk['table']]), str(fk)
    for table,columns in [('User',['email']),('Cuisine',['cuisine_name']),('FoodPermit',['issuing_authority','permit_number'])]:
        keys=[tuple(str(r[c]).casefold() for c in columns) for r in tables[table]]
        assert len(keys)==len(set(keys)), f'Duplicate unique value: {table}'
    for row in tables['Review']:
        assert type(row['rating']) is int and 1<=row['rating']<=5
    for row in tables['Location']:
        assert math.isfinite(row['latitude']) and -90<=row['latitude']<=90
        assert math.isfinite(row['longitude']) and -180<=row['longitude']<=180
    for row in tables['MenuItem']:
        assert row['price']>=0
    for row in tables['OperatingStop']:
        assert row['scheduled_end']>row['scheduled_start']
        assert row['actual_end'] is None or (row['actual_start'] and row['actual_end']>row['actual_start'])
    photo={r['photo_id']:r for r in tables['Photo']}
    review={r['review_id']:r for r in tables['Review']}
    item={r['menu_item_id']:r for r in tables['MenuItem']}
    for row in tables['ReviewPhoto']:
        assert photo[row['photo_id']]['vendor_id']==review[row['review_id']]['vendor_id']
    for row in tables['MenuItemPhoto']:
        assert photo[row['photo_id']]['vendor_id']==item[row['menu_item_id']]['vendor_id']
    assert all(tables[t] for t in SCHEMA), 'Every table must have records'


def sql_insert(table, rows):
    columns=SCHEMA[table]
    batch=[]
    byte_count=0
    for row in rows:
        value='('+', '.join(sql_value(row[c]) for c in columns)+')'
        if batch and (len(batch)>=100 or byte_count+len(value.encode('utf-8'))>250000):
            yield 'INSERT INTO `'+table+'` ('+', '.join('`'+c+'`' for c in columns)+') VALUES\n'+',\n'.join(batch)+';\n'
            batch=[]
            byte_count=0
        batch.append(value)
        byte_count+=len(value.encode('utf-8'))
    if batch:
        yield 'INSERT INTO `'+table+'` ('+', '.join('`'+c+'`' for c in columns)+') VALUES\n'+',\n'.join(batch)+';\n'


def guarded_inserts(table, rows):
    """Readable INSERT/SELECT batches, skipped if target tables were populated."""
    cols=SCHEMA[table]
    for offset in range(0,len(rows),100):
        batch=rows[offset:offset+100]
        selections=[]
        for i,row in enumerate(batch):
            selections.append('SELECT '+', '.join(sql_value(row[col])+(' AS `'+col+'`' if i==0 else '') for col in cols))
        yield ('INSERT INTO `'+table+'` ('+', '.join('`'+c+'`' for c in cols)+')\n'
               'SELECT batch.* FROM (\n'+'\nUNION ALL\n'.join(selections)+'\n) AS batch WHERE @cs4750_seed_allowed=1;\n')


def export_sql(output, tables, database):
    inserts=[statement for table in ORDER for statement in guarded_inserts(table,tables[table])]
    with output.open('w',encoding='utf-8',newline='\n') as f:
        f.write('-- Real subset plus labeled synthetic demo data. All 16 existing tables must be empty.\n'
                '-- Ordinary SQL only: no DELIMITER, routines, or table changes.\n'
                '-- Incomplete imports roll back if this entire file runs; if interrupted, reconnect to discard pending work.\n'
                'USE `'+database.replace('`','``')+'`;\nSET NAMES utf8mb4;\n'
                'SET @cs4750_saved_mode=@@SESSION.sql_mode;\n'
                'SET @cs4750_saved_timezone=@@SESSION.time_zone;\n'
                'SET @cs4750_saved_autocommit=@@SESSION.autocommit;\n'
                "SET SESSION time_zone='+00:00';\n"
                "SET SESSION sql_mode=CONCAT_WS(',',NULLIF(@@SESSION.sql_mode,''),'NO_BACKSLASH_ESCAPES','STRICT_ALL_TABLES');\n"
                'SET SESSION autocommit=0;\n'
                'SET @cs4750_seed_allowed=NOT ('+' OR '.join('EXISTS(SELECT 1 FROM `'+t+'` LIMIT 1)' for t in ORDER)+');\n'
                "SELECT IF(@cs4750_seed_allowed,'Empty tables confirmed; preparing import','CANCELLED: existing rows found; all inserts will be skipped') AS import_status;\n")
        for table in ORDER:
            f.write('-- '+table+': '+str(len(tables[table]))+' rows\n')
            for statement in guarded_inserts(table,tables[table]): f.write(statement)
        checks=['@cs4750_seed_allowed=1']+[f'(SELECT COUNT(*) FROM `{t}`)={len(tables[t])}' for t in ORDER]
        checks += ['NOT EXISTS(SELECT 1 FROM Photo p JOIN ReviewPhoto rp ON p.photo_id=rp.photo_id JOIN Review r ON rp.review_id=r.review_id WHERE p.vendor_id<>r.vendor_id)',
                   'NOT EXISTS(SELECT 1 FROM Photo p JOIN MenuItemPhoto mp ON p.photo_id=mp.photo_id JOIN MenuItem m ON mp.menu_item_id=m.menu_item_id WHERE p.vendor_id<>m.vendor_id)']
        f.write('SET @cs4750_seed_ok=('+' AND '.join(checks)+');\n'
                "SET @cs4750_finish_sql=IF(@cs4750_seed_ok,'COMMIT','ROLLBACK');\n"
                'PREPARE cs4750_finish FROM @cs4750_finish_sql;\nEXECUTE cs4750_finish;\nDEALLOCATE PREPARE cs4750_finish;\n'
                "SELECT IF(@cs4750_seed_ok,'SUCCESS: all tables populated and committed','NOT IMPORTED: existing data or failed checks; transaction rolled back') AS import_status;\n"
                'SET SESSION sql_mode=@cs4750_saved_mode;\nSET SESSION time_zone=@cs4750_saved_timezone;\n'
                'SET SESSION autocommit=@cs4750_saved_autocommit;\n')
        f.write(' UNION ALL\n'.join("SELECT '"+t+"' AS table_name, COUNT(*) AS row_count FROM `"+t+'`' for t in ORDER)+';\n')
    return inserts


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,required=True)
    parser.add_argument('--schema',type=Path,required=True)
    parser.add_argument('--photos',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--php',type=Path,default=Path('C:/xampp/php/php.exe'))
    args=parser.parse_args()
    if args.output.exists():
        parser.error('Output folder exists; refusing to overwrite')
    schema=json.loads(args.schema.read_text(encoding='utf-8'))
    source_json=args.source/'json' if (args.source/'json').is_dir() else args.source
    tables={t:list(read_jsonl(source_json/(t+'.jsonl'))) for t in SCHEMA}
    original_counts={t:len(rows) for t,rows in tables.items()}
    original_reviews=json.loads(json.dumps(tables['Review']))
    catalog=json.loads(args.photos.read_text(encoding='utf-8'))
    provenance=[]
    imported_at=json.loads((source_json/'import_report.json').read_text())['import_time_utc']
    now=datetime.strptime(imported_at,'%Y-%m-%d %H:%M:%S')
    rng=random.Random(4750)
    def next_id(table,column):
        return max((r[column] for r in tables[table]),default=0)+1
    def add(table,row,reason):
        tables[table].append(row)
        provenance.append({'table':table,'key':{c:row[c] for c in PRIMARY[table]},'kind':'synthetic','reason':reason})
    def fill(table,row,column,value,reason):
        if row[column] is None:
            row[column]=value
            provenance.append({'table':table,'key':{c:row[c] for c in PRIMARY[table]},'column':column,'kind':'synthetic_placeholder','reason':reason})
    # Preserve the real businesses, author identities, reviews, and review photos.
    for row in tables['OperatingHours']:
        row['day_of_week']=DAYS[row['day_of_week']-1]
    for row in tables['Location']:
        # Match the live DECIMAL(9,6) coordinate columns without truncation warnings.
        row['latitude']=round(row['latitude'],6)
        row['longitude']=round(row['longitude'],6)
    for v in tables['Vendor']:
        fill('Vendor',v,'description','[DEMO PLACEHOLDER] Profile description not supplied by source.','Not the actual business description')
        fill('Vendor',v,'phone_number',f'+1-202-555-{100+v["vendor_id"]:04}','Fictional reserved 555-01xx demonstration number')
        fill('Vendor',v,'website_url',f'https://vendor-{v["vendor_id"]:03}.example.invalid','Nonexistent placeholder website')
    for p in tables['Photo']:
        fill('Photo',p,'caption','[IMPORTED] Source review photo; no caption supplied.','Explanatory caption, not source wording')
    # Add six explicitly fictional mobile vendors, preserving all 75 real vendors.
    first_mobile=next_id('Vendor','vendor_id')
    for index in range(6):
        vid=first_mobile+index
        add('Vendor',dict(vendor_id=vid,name=f'[DEMO] Virginia Mobile Kitchen {index+1}',
            description='[DEMO] Fictional mobile vendor for testing dated stops, menus and management.',
            vendor_type='food_truck' if index<4 else 'pop_up',phone_number=f'+1-202-555-{100+vid:04}',
            website_url=f'https://demo-mobile-{index+1}.example.invalid',listing_status='demo',
            created_at=imported_at,timezone='America/New_York',submitted_by_user_id=1),'Fictional mobile vendor')
    # One demo owner per vendor plus 12 demo customers, with real bcrypt hashes.
    accounts=[]
    owners={}
    customers=[]
    first_user=next_id('User','user_id')
    specifications=[('owner',v['vendor_id']) for v in tables['Vendor']]+[('customer',i) for i in range(1,13)]
    passwords=[f'CS4750-Demo-Only!{first_user+i}' for i in range(len(specifications))]
    print('Hashing demo-account passwords...',flush=True)
    hashes=bcrypt_hashes(passwords,args.php)
    for i,((role,identifier),secret,hashed) in enumerate(zip(specifications,passwords,hashes)):
        uid=first_user+i
        email=f'demo.{role}.{identifier:03}@example.invalid'
        add('User',dict(user_id=uid,display_name=f'Demo {role.title()} {identifier:03}',email=email,
                       password_hash=hashed,joined_at=imported_at),'Fictional demo account, not an imported reviewer')
        accounts.append(dict(user_id=uid,email=email,password=secret,role=role))
        if role=='owner': owners[identifier]=uid
        else: customers.append(uid)
    cuisines={r['cuisine_id']:r['cuisine_name'] for r in tables['Cuisine']}
    vendor_cuisines={v['vendor_id']:[] for v in tables['Vendor']}
    for r in tables['VendorCuisine']: vendor_cuisines[r['vendor_id']].append(cuisines[r['cuisine_id']])
    fallback=next_id('Cuisine','cuisine_id')
    add('Cuisine',dict(cuisine_id=fallback,cuisine_name='Unspecified'),'Unknown cuisine placeholder; not an inferred geographic cuisine')
    for v in tables['Vendor']:
        vid=v['vendor_id']
        add('Manages',dict(user_id=owners[vid],vendor_id=vid,management_role='demo_owner',granted_at=imported_at),'Fictional management permission; does not identify actual business owner')
        if vid%10==0:
            add('Manages',dict(user_id=customers[0],vendor_id=vid,management_role='demo_co_manager',granted_at=imported_at),'Fictional shared management example')
        if not vendor_cuisines[vid]:
            add('VendorCuisine',dict(vendor_id=vid,cuisine_id=fallback),'Explicit unspecified cuisine fallback')
        # Add weekly hours only where the source supplied none at all.
        if not any(r['vendor_id']==vid for r in tables['OperatingHours']):
            for number,day in enumerate(DAYS,1):
                add('OperatingHours',dict(vendor_id=vid,hours_number=number,day_of_week=day,opening_time='11:00:00',closing_time='20:00:00'),'Synthetic weekly hours; not verified business hours')
        tags=' '.join(vendor_cuisines[vid]).lower()
        if any(x in tags for x in ['indian','eritrean','ethiopian']): genres=['curry','rice','dessert']
        elif any(x in tags for x in ['asian','chinese','thai','vietnamese','japanese','korean']): genres=['rice','beef','salad']
        elif any(x in tags for x in ['italian','greek','european','mediterranean']): genres=['pasta','pizza','cake']
        else: genres=['burger','breakfast','dessert']
        for genre in genres:
            sample=catalog[genre]
            mid=next_id('MenuItem','menu_item_id')
            price=round(rng.uniform(7,22),2)
            add('MenuItem',dict(menu_item_id=mid,vendor_id=vid,item_name='[DEMO] '+sample['dish'],
                description='[DEMO] Fictional menu item and price. Illustrative recipe photo; not an actual offering from this vendor.',
                price=price,category='Demo '+genre,availability_status='demo_available'),'Fictional menu offering; image reference from TheMealDB')
            pid=next_id('Photo','photo_id')
            add('Photo',dict(photo_id=pid,uploader_user_id=owners[vid],vendor_id=vid,image_url=sample['image_url'],
                caption='[DEMO] Illustrative '+sample['dish']+' photo (TheMealDB); not this vendor\'s dish.',uploaded_at=imported_at),'Generic online menu illustration, not a real vendor photo')
            add('MenuItemPhoto',dict(photo_id=pid,menu_item_id=mid),'Same-vendor illustrative menu/photo relationship')
        add('FoodPermit',dict(permit_id=next_id('FoodPermit','permit_id'),vendor_id=vid,
            permit_number=f'DEMO-NOT-VALID-{vid:04}',issuing_authority='DEMO AUTHORITY - NOT A REAL PERMIT',
            permit_type='demo_food_service',issued_date=now.strftime('%Y-%m-%d'),
            expiration_date=(now+timedelta(days=365)).strftime('%Y-%m-%d'),document_url=None),'Fictional permit for database testing; no regulatory or verification claim')
        # Every vendor participates in dated service examples; mobile vendors rotate sites.
        for offset in range(4):
            if vid<first_mobile:
                lid=next(r['location_id'] for r in tables['VendorBase'] if r['vendor_id']==vid)
            else:
                lid=1+(vid-first_mobile+offset)%len(tables['Location'])
            start=(now.replace(hour=15,minute=0,second=0)+timedelta(days=offset-2))
            end=start+timedelta(hours=4)
            done=offset<2
            add('OperatingStop',dict(stop_id=next_id('OperatingStop','stop_id'),vendor_id=vid,location_id=lid,
                scheduled_start=start.strftime('%Y-%m-%d %H:%M:%S'),scheduled_end=end.strftime('%Y-%m-%d %H:%M:%S'),
                actual_start=(start+timedelta(minutes=5)).strftime('%Y-%m-%d %H:%M:%S') if done else None,
                actual_end=(end-timedelta(minutes=5)).strftime('%Y-%m-%d %H:%M:%S') if done else None,
                stop_status='demo_completed' if done else 'demo_scheduled',
                notes='[DEMO] Fictional dated service visit at a source location; not actual attendance or an announced event.'),'Synthetic dated operating-stop example')
        # Two explicitly fictional reviews also connect customers to unrated businesses.
        for offset in range(2):
            rid=next_id('Review','review_id')
            author=customers[(vid+offset)%len(customers)]
            add('Review',dict(review_id=rid,author_user_id=author,vendor_id=vid,rating=3+(vid+offset)%3,
                review_text='[DEMO REVIEW] Fictional feedback for testing the application. This is not a real customer experience.',
                created_at=imported_at,updated_at=None),'Explicitly synthetic customer review')
            if offset==0:
                pid=next_id('Photo','photo_id')
                sample=catalog[genres[0]]
                add('Photo',dict(photo_id=pid,uploader_user_id=author,vendor_id=vid,image_url=sample['image_url'],
                    caption='[DEMO] Generic illustrative food photo; not taken by a real customer.',uploaded_at=imported_at),'Synthetic review illustration')
                add('ReviewPhoto',dict(photo_id=pid,review_id=rid),'Same-vendor synthetic review/photo relationship')
    for uid in customers:
        for vid in sorted(rng.sample([v['vendor_id'] for v in tables['Vendor']],12)):
            add('Favorites',dict(user_id=uid,vendor_id=vid,saved_at=imported_at),'Fictional saved-vendor activity by demo customer')
    assert tables['Review'][:len(original_reviews)]==original_reviews, 'Real reviews must not change'
    validate(tables,schema)
    args.output.mkdir(parents=True)
    inserts=export_sql(args.output/'populate_all_tables.sql',tables,schema['database'])
    (args.output/'csv').mkdir()
    (args.output/'json').mkdir()
    for table,rows in tables.items():
        with (args.output/'csv'/(table+'.csv')).open('w',encoding='utf-8',newline='') as f:
            writer=csv.DictWriter(f,fieldnames=SCHEMA[table]); writer.writeheader(); writer.writerows(rows)
        with (args.output/'json'/(table+'.jsonl')).open('w',encoding='utf-8') as f:
            for row in rows: f.write(json.dumps(row,ensure_ascii=False)+'\n')
    with (args.output/'csv'/'demo_accounts.csv').open('w',encoding='utf-8',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=['user_id','email','password','role']);writer.writeheader();writer.writerows(accounts)
    report={'database':schema['database'],'live_tables_were_empty':not any(schema['row_counts'].values()),
        'source_rows':original_counts,'final_rows':{t:len(r) for t,r in tables.items()},
        'added_rows':{t:len(r)-original_counts[t] for t,r in tables.items()},
        'synthetic_fields_and_rows':len(provenance),'all_tables_populated':all(tables.values()),
        'validation':'All keys, live-schema column lengths/nullability/enums, foreign keys, timestamp bounds, domain checks, and photo vendor consistency passed.',
        'original_reviews_preserved':len(original_reviews),'notes':[
            'Imported real-author profiles keep disabled password markers and anonymous names; these are attribution records, not registered accounts.',
            'Additional demo owners/customers have distinct published demo passwords and PHP bcrypt cost-10 hashes; never reuse them for a production account.',
            'Rating-only real reviews retain empty text. Unknown actual update times, future actual stop times and permit document URLs stay NULL rather than inventing facts.',
            'New mobile vendors, management permissions, menus, permits, reviews, favorites and stops are synthetic, not claims about the real businesses.',
            'Original source files and previous prepared_data files are unchanged.',
            'Coordinates are rounded to six decimal places to match the live DECIMAL(9,6) columns.',
        ]}
    for name,value in [('completion_report.json',report),('provenance.json',provenance),('photo_sources.json',catalog)]:
        (args.output/'json'/name).write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding='utf-8')
    # Read-only MySQL validation: PREPARE checks every generated INSERT.
    # These statements DO NOT EXECUTE inserts or create any database objects.
    with (args.output/'validate_syntax_read_only.sql').open('w',encoding='utf-8') as f:
        f.write('USE `'+schema['database']+'`;\nSET @cs4750_validation_mode=@@SESSION.sql_mode;\n'
                "SET SESSION sql_mode=CONCAT_WS(',',NULLIF(@@SESSION.sql_mode,''),'NO_BACKSLASH_ESCAPES','STRICT_ALL_TABLES');\n")
        for statement in inserts:
            f.write("SET @cs4750_check=CONVERT(X'"+statement.encode().hex()+"' USING utf8mb4);\nPREPARE cs4750_check_stmt FROM @cs4750_check;\nDEALLOCATE PREPARE cs4750_check_stmt;\n")
        f.write("SET SESSION sql_mode=@cs4750_validation_mode;\nSELECT 'All INSERT statements prepared successfully; no data inserted.';\n")
    print(json.dumps(report['final_rows'],indent=2))
    print('Prepared:',args.output.resolve())


if __name__=='__main__': main()
