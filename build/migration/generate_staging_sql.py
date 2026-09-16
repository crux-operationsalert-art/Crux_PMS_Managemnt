#!/usr/bin/env python3
"""Emit INSERT statements for the remaining stg.* rows, straight from the workbook.

The database is only reachable through a tool that puts every row into a model's
context, which is slow and expensive for ~14,000 rows. This writes the SQL to
disk instead, so it can be run in the Supabase SQL editor or by psql.

Mapping and the decisions behind it: build/migration/STAGING_MAP.md.

    python3 generate_staging_sql.py <workbook.xlsx> <out_dir>

Resume points are passed per table so a partly-loaded table is topped up rather
than duplicated. Defaults match the live database as at 2026-09-15.
"""
import sys, os, datetime
import openpyxl

RESUME = {'branches': 352, 'branch_assignments': 1202}   # first row_no still needed
BATCH = 500

def lit(v):
    if v is None:
        return 'null'
    if isinstance(v, (datetime.datetime, datetime.date)):
        v = v.isoformat(sep=' ')
    # Excel stores whole numbers as floats, so a matrix Level of 1 arrives as
    # 1.0. 40_matrix strips non-digits from it, which turns '1.0' into '10' and
    # silently drops every row for failing `between 1 and 5`.
    if isinstance(v, float) and v.is_integer():
        v = int(v)
    s = str(v).strip()
    if s == '':
        return 'null'
    return "'" + s.replace("'", "''") + "'"

def sheet(wb, name):
    ws = wb[name]
    it = ws.iter_rows(values_only=True)
    hdr = [str(h).strip() if h is not None else '' for h in next(it)]
    idx = {h: i for i, h in enumerate(hdr) if h}
    for n, row in enumerate(it, start=2):          # row 1 is the header
        if not any(c is not None and str(c).strip() for c in row):
            continue
        yield n, (lambda c, r=row: r[idx[c]] if c in idx and idx[c] < len(r) else None)

def emit(out, table, cols, rows):
    """rows: iterable of tuples already in `cols` order. Writes batched INSERTs."""
    n = 0
    buf = []
    def flush():
        if not buf:
            return
        out.write('insert into stg.%s (%s) values\n' % (table, ', '.join(cols)))
        out.write(',\n'.join(buf))
        out.write(';\n\n')
        buf.clear()
    for r in rows:
        buf.append('(' + ','.join(lit(v) for v in r) + ')')
        n += 1
        if len(buf) >= BATCH:
            flush()
    flush()
    return n

def main(xlsx, outdir):
    os.makedirs(outdir, exist_ok=True)
    wb = openpyxl.load_workbook(xlsx, read_only=True, data_only=True)

    # BranchID -> BranchCode. Every other sheet references branches by id, while
    # the migration joins on code. Without this the coverage rules resolve to
    # nothing, silently.
    bmap = {}
    for _, g in sheet(wb, 'BRANCHES'):
        bid, bcode = g('BranchID'), g('BranchCode')
        if bid and bcode:
            bmap[str(bid).strip()] = str(bcode).strip()
    resolved = unresolved = 0
    def bcode(v):
        nonlocal resolved, unresolved
        if v is None or not str(v).strip():
            return None
        k = str(v).strip()
        if k in bmap:
            resolved += 1
            return bmap[k]
        unresolved += 1
        return None

    counts = {}

    def run(table, cols, sheet_name, build, resume=None):
        path = os.path.join(outdir, '%s.sql' % table)
        with open(path, 'w', encoding='utf-8') as out:
            out.write('-- stg.%s from %s\n' % (table, sheet_name))
            if resume:
                out.write('-- resuming at spreadsheet row %d\n' % resume)
            out.write('begin;\n\n')
            rows = (build(g) for n, g in sheet(wb, sheet_name)
                    if resume is None or n >= resume)
            # row_no must come from the sheet, so rebuild the generator with n
            rows = []
            for n, g in sheet(wb, sheet_name):
                if resume is not None and n < resume:
                    continue
                rows.append(build(n, g))
            c = emit(out, table, cols, rows)
            out.write('commit;\n')
        counts[table] = c
        print('%-22s %6d rows -> %s' % (table, c, path))

    run('branches',
        ['row_no','client_code','code','name','address','zone','state','city','status',
         'bm_name','bm_mobile','bm_email','poc_email','dublicate','updated_at'],
        'BRANCHES',
        lambda n, g: (n, g('ClientID'), g('BranchCode'), g('BranchName'), g('Address'),
                      g('Zone'), None, g('Location'), g('Status'), g('BranchManagerName'),
                      g('BranchManagerMobile'), g('BranchManagerEmail'), g('CruxPOCEmail'),
                      None, g('UpdatedAt')),
        resume=RESUME['branches'])

    run('matrix',
        ['row_no','client_code','branch_code','level','level_name','name','mobile','email',
         'updated_by','updated_at'],
        'ESCALATION_MATRIX',
        lambda n, g: (n, g('ClientID'), bcode(g('BranchID')), g('Level'), g('LevelName'),
                      g('ContactName'), g('Mobile'), g('Email'), g('UpdatedBy'), g('UpdatedAt')))

    run('branch_assignments',
        ['row_no','user_email','branch_code','client_code','role','created_at'],
        'BRANCH_ASSIGNMENTS',
        lambda n, g: (n, g('PersonEmail'), bcode(g('BranchID')), g('ClientID'),
                      g('AssignmentRole'), g('CreatedAt')),
        resume=RESUME['branch_assignments'])

    run('people_events_copy',
        ['row_no','person_email','at','kind','note','actor_email'],
        'Copy of PEOPLE_EVENTS',
        lambda n, g: (n, g('PersonEmail'), g('Timestamp'), g('Type'), g('Notes'), g('IssuedBy')))

    run('email_log',
        ['row_no','at','idempotency_key','template_key','recipient','state','error','entity_ref'],
        'EMAIL_LOG',
        lambda n, g: (n, g('Timestamp'), g('IdempotencyKey'), g('Type'), g('ToAddr'),
                      g('Status'), g('Error'), g('MessageRef')))

    run('audit_log',
        ['row_no','at','actor_email','action','entity_type','entity_ref','old_value','new_value'],
        'AUDIT_LOG',
        lambda n, g: (n, g('Timestamp'), g('User'), g('Action'), g('Entity'), g('EntityID'),
                      g('OldValue'), g('NewValue')))

    wb.close()
    print('\nbranch references resolved: %d, unresolved: %d' % (resolved, unresolved))
    print('total rows: %d' % sum(counts.values()))

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
