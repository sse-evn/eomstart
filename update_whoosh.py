import pandas as pd
import psycopg2
from datetime import datetime, date
import sys

def main():
    db_params = {
        'host': '10.10.10.1',
        'user': 'eom_user',
        'password': 'd_85GcwS6[4E*8|IR,y2',
        'dbname': 'eom_db',
    }
    
    try:
        conn = psycopg2.connect(**db_params)
    except Exception as e:
        print(f"Error connecting to db: {e}")
        return
    
    cur = conn.cursor()
    
    # 1. Delete or expire old unassigned WHOOSH promos
    cur.execute("DELETE FROM promo_codes WHERE brand = 'WHOOSH' AND assigned_to_user_id IS NULL;")
    print(f"Deleted {cur.rowcount} old unassigned WHOOSH promo codes.")
    
    df = pd.read_excel('SD-130242.xlsx')
    
    # Each column header is a date.
    inserted_count = 0
    for col in df.columns:
        # try to parse column as date
        # if it's already a datetime object, use it directly
        try:
            if isinstance(col, datetime):
                dt = col.date()
            elif isinstance(col, str):
                # example format '03.06.20260' wait, we saw '03.06.20260', probably a typo for '03.06.2026'
                s = col.replace('20260', '2026')
                dt = datetime.strptime(s, '%d.%m.%Y').date()
            else:
                continue
        except Exception as e:
            print(f"Skipping column {col}: {e}")
            continue
            
        print(f"Processing column for date {dt}")
        
        # Ensure daily_promos exists for this date
        promo_id = f"WHOOSH_{dt.strftime('%Y%m%d')}"
        cur.execute("INSERT INTO daily_promos (id, date, title, created_by_admin_id) VALUES (%s, %s, %s, 1) ON CONFLICT (id) DO NOTHING;", (promo_id, dt, f"Whoosh promos for {dt}"))
        
        codes = df[col].dropna().astype(str).tolist()
        
        for code in codes:
            code = code.strip()
            if not code:
                continue
            
            # insert into promo_codes
            # valid_until = dt, valid_from = dt
            try:
                cur.execute("""
                    INSERT INTO promo_codes (brand, promo_code, valid_until, created_by_admin_id, promo_id)
                    VALUES (%s, %s, %s, %s, %s)
                    RETURNING id;
                """, ('WHOOSH', code, dt, 1, promo_id))
                
                promo_code_id = cur.fetchone()[0]
                
                # insert into promo_codes_metadata
                cur.execute("""
                    INSERT INTO promo_codes_metadata (promo_code_id, valid_from)
                    VALUES (%s, %s)
                """, (promo_code_id, dt))
                
                inserted_count += 1
            except psycopg2.IntegrityError:
                conn.rollback()
                # print(f"Duplicate code {code}, skipping...")
            except Exception as e:
                conn.rollback()
                print(f"Error inserting code {code}: {e}")
            else:
                conn.commit()

    print(f"Successfully inserted {inserted_count} new WHOOSH promo codes.")
    
    cur.close()
    conn.close()

if __name__ == '__main__':
    main()
