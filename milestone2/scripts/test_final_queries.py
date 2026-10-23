"""Run the final catalogue with rolled-back practice writes and state checks."""
import hashlib,json,os,re,subprocess,threading,tkinter as tk
from pathlib import Path
from datetime import datetime,timezone
from tkinter import ttk
ROOT=Path(r'C:\Users\haide\OneDrive\Documents\UVA\CS4750\cs4750_restaurants\milestone2')
OUT=Path(__file__).resolve().parent/'final_query_results';OUT.mkdir(exist_ok=True)
BIN=Path(r'C:\Program Files\MySQL\MySQL Server 26.10\bin')
SOURCE=ROOT/'sql/all_app_queries.sql'
window=tk.Tk();window.title('Test final Milestone 2 queries');window.geometry('610x255');window.attributes('-topmost',True)
panel=ttk.Frame(window,padding=20);panel.pack(fill='both',expand=True)
ttk.Label(panel,text='restaurants on 35.245.147.165',font=('Segoe UI',12)).pack(anchor='w')
ttk.Label(panel,text='Runs the final 42 query groups. Practice writes end in ROLLBACK.\nYour password stays in memory and is not saved.').pack(anchor='w',pady=10)
entry=ttk.Entry(panel,show='*',width=55);entry.pack(anchor='w')
status=tk.StringVar(value='Enter your root database password.');ttk.Label(panel,textvariable=status,wraplength=560).pack(anchor='w',pady=10)

def perform(secret):
    result={'tested_at_utc':datetime.now(timezone.utc).isoformat(),'source':str(SOURCE)}
    try:
        env=os.environ.copy();env['MYSQL_PWD']=secret
        def query(sql):
            p=subprocess.run([str(BIN/'mysql.exe'),'-h','35.245.147.165','-u','root','--ssl-mode=REQUIRED','--connect-timeout=15','--database=restaurants','--batch','--raw','--skip-column-names','--default-character-set=utf8mb4'],input=sql,capture_output=True,encoding='utf-8',env=env,creationflags=subprocess.CREATE_NO_WINDOW,timeout=180)
            if p.returncode:raise RuntimeError(p.stderr.strip())
            return p.stdout
        schema=[json.loads(line) for line in query("SELECT JSON_OBJECT('table',TABLE_NAME,'column',COLUMN_NAME,'engine',t.ENGINE) FROM information_schema.COLUMNS c JOIN information_schema.TABLES t USING(TABLE_SCHEMA,TABLE_NAME) WHERE c.TABLE_SCHEMA='restaurants' AND t.TABLE_TYPE='BASE TABLE' ORDER BY TABLE_NAME,ORDINAL_POSITION;").splitlines()]
        tables={}
        for r in schema:
            if r['engine']!='InnoDB':raise RuntimeError('Expected InnoDB tables')
            tables.setdefault(r['table'],[]).append(r['column'])
        if len(tables)!=16:raise RuntimeError('Expected 16 tables')
        def state():
            sql=''
            for table,cols in tables.items():
                sql+=f"SELECT '{table}', SHA2(CAST(JSON_ARRAY("+','.join('`'+c+'`' for c in cols)+f") AS CHAR),256) FROM `{table}`;\n"
            hashes={t:[] for t in tables}
            for line in query(sql).splitlines():
                table,digest=line.split('\t');hashes[table].append(digest)
            return {t:{'rows':len(v),'sha256':hashlib.sha256('\n'.join(sorted(v)).encode()).hexdigest()} for t,v in hashes.items()}
        before=state();result['before']=before
        source=SOURCE.read_text(encoding='utf-8');result['source_sha256']=hashlib.sha256(SOURCE.read_bytes()).hexdigest()
        assert source.strip().endswith('ROLLBACK;') and 'COMMIT;' not in source and 'CREATE ' not in source
        checks={
        25:"EXISTS(SELECT 1 FROM User WHERE user_id=@new_user_id AND display_name='Query Demo User')",
        26:"EXISTS(SELECT 1 FROM User WHERE user_id=@new_user_id AND display_name='Updated Query Demo User')",
        27:"EXISTS(SELECT 1 FROM Vendor WHERE vendor_id=@new_vendor_id AND submitted_by_user_id=@new_user_id)",
        28:"EXISTS(SELECT 1 FROM Manages WHERE vendor_id=@new_vendor_id AND user_id=@new_user_id)",
        29:"EXISTS(SELECT 1 FROM VendorBase WHERE vendor_id=@new_vendor_id AND location_id=@new_location_id)",
        30:"EXISTS(SELECT 1 FROM VendorCuisine WHERE vendor_id=@new_vendor_id AND cuisine_id=@existing_cuisine_id)",
        31:"EXISTS(SELECT 1 FROM OperatingHours WHERE vendor_id=@new_vendor_id AND hours_number=1)",
        32:"EXISTS(SELECT 1 FROM OperatingStop WHERE stop_id=@new_stop_id AND stop_status='demo_completed' AND notes='[DEMO] Updated practice stop') AND EXISTS(SELECT 1 FROM OperatingHours WHERE vendor_id=@new_vendor_id AND opening_time='12:00:00')",
        33:"EXISTS(SELECT 1 FROM MenuItem WHERE menu_item_id=@new_item_id AND price=11.50)",
        34:"EXISTS(SELECT 1 FROM Vendor WHERE vendor_id=@new_vendor_id AND phone_number='+1-202-555-0199')",
        35:"EXISTS(SELECT 1 FROM Review WHERE review_id=@new_review_id AND rating=5 AND review_text='[DEMO] Updated practice review')",
        36:"EXISTS(SELECT 1 FROM ReviewPhoto WHERE photo_id=@new_photo_id AND review_id=@new_review_id) AND EXISTS(SELECT 1 FROM MenuItemPhoto WHERE photo_id=@new_photo_id AND menu_item_id=@new_item_id)",
        37:"NOT EXISTS(SELECT 1 FROM Favorites WHERE user_id=@new_user_id AND vendor_id=@new_vendor_id)",
        38:"EXISTS(SELECT 1 FROM FoodPermit WHERE permit_id=@new_permit_id AND expiration_date=UTC_DATE()+INTERVAL 2 YEAR)",
        39:"NOT EXISTS(SELECT 1 FROM Review WHERE review_id=@new_review_id) AND NOT EXISTS(SELECT 1 FROM ReviewPhoto WHERE review_id=@new_review_id)",
        40:"NOT EXISTS(SELECT 1 FROM MenuItem WHERE menu_item_id=@new_item_id) AND NOT EXISTS(SELECT 1 FROM MenuItemPhoto WHERE menu_item_id=@new_item_id)",
        41:"EXISTS(SELECT 1 FROM Vendor WHERE vendor_id=@new_vendor_id AND listing_status='inactive')",
        42:"NOT EXISTS(SELECT 1 FROM Photo WHERE photo_id=@new_photo_id) AND NOT EXISTS(SELECT 1 FROM ReviewPhoto WHERE photo_id=@new_photo_id) AND NOT EXISTS(SELECT 1 FROM MenuItemPhoto WHERE photo_id=@new_photo_id)"}
        pieces=re.split(r'(?m)^-- Query (\d+)\s*\n',source);sql=pieces[0]
        for i in range(1,len(pieces),2):
            n=int(pieces[i]);body=pieces[i+1]
            assertion=f"\nSELECT 'CS4750_ASSERT', {n}, ({checks[n]});\n" if n in checks else ''
            if n==42:body=body.replace('ROLLBACK;',assertion+'ROLLBACK;');assertion=''
            sql+=f"\nSELECT 'CS4750_QUERY', {n};\n"+body+assertion
        sql+="\nSELECT 'CS4750_FINISHED', 42;\n"
        window.after(0,status.set,'Running all 42 query groups and checking practice writes...')
        output=query(sql);(OUT/'final_app_query_output.txt').write_text(output,encoding='utf-8')
        assertions=[line.split('\t')[1:] for line in output.splitlines() if line.startswith('CS4750_ASSERT\t')]
        if len(assertions)!=18 or any(value!='1' for n,value in assertions):raise RuntimeError('A practice write did not produce the expected result: '+repr(assertions))
        if 'CS4750_FINISHED\t42' not in output:raise RuntimeError('Query run did not reach the end')
        after=state();result['after']=after
        if before!=after:raise RuntimeError('Stored table data differs after rollback')
        if hashlib.sha256(SOURCE.read_bytes()).hexdigest()!=result['source_sha256']:raise RuntimeError('Query file changed during testing')
        result.update(success=True,query_groups_passed=42,write_assertions_passed=18,stored_data_unchanged=True)
        (OUT/'final_app_query_result.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
        window.after(0,status.set,'Passed: 42 query groups, 18 write checks. Stored data unchanged.')
        window.after(1800,window.destroy)
    except Exception as e:
        result.update(success=False,error=str(e));(OUT/'final_app_query_result.json').write_text(json.dumps(result,indent=2),encoding='utf-8');window.after(0,status.set,str(e))

def run():
    secret=entry.get();entry.delete(0,'end');button.config(state='disabled');threading.Thread(target=perform,args=(secret,),daemon=True).start()
button=ttk.Button(panel,text='Test final queries',command=run);button.pack(anchor='w');entry.focus_set();window.mainloop()
