# Convert every sheet of an .ods file to a TSV-ish JSON (list of rows), keeping all text exactly.
import zipfile, json, sys, xml.etree.ElementTree as ET
NS = {
 'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
 'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
 'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
}
T = '{%s}' % NS['table']; X = '{%s}' % NS['text']; O = '{%s}' % NS['office']
def cell_text(c):
    paras = []
    for p in c.iter(X + 'p'):
        buf = []
        def walk(e):
            if e.text: buf.append(e.text)
            for ch in e:
                tag = ch.tag
                if tag == X + 's': buf.append(' ' * int(ch.get(X + 'c', '1')))
                elif tag == X + 'tab': buf.append('\t')
                elif tag == X + 'line-break': buf.append('\n')
                else: walk(ch)
                if ch.tail: buf.append(ch.tail)
        walk(p)
        paras.append(''.join(buf))
    if paras: return '\n'.join(paras)
    v = c.get(O + 'value') or c.get(O + 'date-value') or c.get(O + 'string-value')
    return v or ''
sheets = {}
z = zipfile.ZipFile(sys.argv[1])
with z.open('content.xml') as f:
    cur = None; rows = None
    for ev, el in ET.iterparse(f, events=('start', 'end')):
        if ev == 'start' and el.tag == T + 'table':
            cur = el.get(T + 'name'); rows = []
        elif ev == 'end' and el.tag == T + 'table-row':
            row = []
            for c in el:
                if c.tag not in (T + 'table-cell', T + 'covered-table-cell'): continue
                rep = int(c.get(T + 'number-columns-repeated', '1'))
                txt = cell_text(c)
                row.extend([txt] * min(rep, 200))
            while row and row[-1] == '': row.pop()
            rrep = int(el.get(T + 'number-rows-repeated', '1'))
            if row:
                for _ in range(min(rrep, 1000)): rows.append(row)
            el.clear()
        elif ev == 'end' and el.tag == T + 'table':
            sheets[cur] = rows; el.clear()
json.dump(sheets, open(sys.argv[2], 'w'), ensure_ascii=False)
for k, v in sheets.items():
    print(f'{k}\t{len(v)} rows\tmax cols {max((len(r) for r in v), default=0)}')
