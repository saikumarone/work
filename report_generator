import re
from collections import defaultdict
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side

# Re-run parsing and file creation (fresh session)

log_path = "/mnt/data/no_timescale_output.log"
with open(log_path, "r", encoding="utf-8", errors="ignore") as f:
    raw = f.read()

section_re = re.compile(r"^=+\s*([a-zA-Z0-9_]+)\.log\s*=+$", re.M)
sections = {}
positions = [(m.start(), m.end(), m.group(1).lower()) for m in section_re.finditer(raw)]
for i, (s, e, name) in enumerate(positions):
    endpos = positions[i+1][0] if i+1 < len(positions) else len(raw)
    sections[name] = raw[e:endpos]

def schema_from_line(line: str):
    line = line.strip()
    m = re.match(r"^([a-zA-Z_][a-zA-Z0-9_]*)\.", line)
    return m.group(1) if m else None

schemas = defaultdict(lambda: {
    "Tables": [],
    "Indexes": [],
    "Constraints": {"PK": [], "UK": [], "FK": []},
    "Sequences": [],
    "Functions": [],
    "Procedures": [],
    "Triggers": [],
    "Views": [],
    "Materialized Views": [],
    "Columns": [],
    "Partitions": [],
    "Extensions": [],
    "Invalid Constraints": [],
    "Invalid Index": [],
    "udf": [],
    "Users": [],
})

def get_qualified_lines(text):
    out = []
    for ln in text.splitlines():
        ln = ln.strip()
        if not ln or ln.startswith("(") or ln.startswith("-") or ln.lower().startswith("schema count"):
            continue
        if re.match(r"^[a-zA-Z_][a-zA-Z0-9_]*\.", ln):
            out.append(ln)
    return out

def add_lines_to_bucket(lines, bucket, subkey=None):
    for line in lines:
        sch = schema_from_line(line)
        if not sch:
            continue
        if subkey:
            schemas[sch][bucket][subkey].append(line.strip())
        else:
            schemas[sch][bucket].append(line.strip())

for name, content in sections.items():
    lines = get_qualified_lines(content)
    lname = name.lower()
    if lname in ("primarykey_constraint", "pkconstraint", "primarykey", "primary_keys"):
        add_lines_to_bucket(lines, "Constraints", "PK")
    elif lname in ("fkeyconstraint", "foreignkey_constraint", "foreign_keys", "fkeys"):
        add_lines_to_bucket(lines, "Constraints", "FK")
    elif "unique" in lname or lname in ("ukconstraint", "unique_constraints"):
        add_lines_to_bucket(lines, "Constraints", "UK")
    elif lname in ("columnorder", "columns"):
        add_lines_to_bucket(lines, "Columns")
    elif lname in ("indexlist", "indexes"):
        add_lines_to_bucket(lines, "Indexes")
    elif "materialized" in lname:
        add_lines_to_bucket(lines, "Materialized Views")
    elif lname == "views":
        add_lines_to_bucket(lines, "Views")
    elif "invalid_cons" in lname:
        add_lines_to_bucket(lines, "Invalid Constraints")
    elif "invalid_index" in lname:
        add_lines_to_bucket(lines, "Invalid Index")
    elif "partitions" in lname:
        add_lines_to_bucket(lines, "Partitions")
    elif "extension" in lname:
        add_lines_to_bucket(lines, "Extensions")
    elif lname in ("functions", "udf"):
        add_lines_to_bucket(lines, "Functions")
        add_lines_to_bucket(lines, "udf")
    elif lname in ("users", "roles"):
        add_lines_to_bucket(lines, "Users")

# Create workbook single sheet
wb = Workbook()
sh = wb.active
sh.title = "Combined Report"

header_fill = PatternFill(start_color="9CC3E5", end_color="9CC3E5", fill_type="solid")
bold_font = Font(bold=True)
wrap = Alignment(wrap_text=True, vertical="top")
thin = Side(style="thin")
border = Border(left=thin, right=thin, top=thin, bottom=thin)

row = 1
sh.merge_cells(start_row=row, start_column=1, end_row=row, end_column=8)
sh.cell(row=row, column=1, value="Database Name:  DEV").font = bold_font
row += 2

headers = ["Object Type", "Source Count", "Target Count", "Objects in Source and not in Target",
           "Objects in Target and not in Source", "Notes"]

def write_header():
    global row
    for ci, h in enumerate(headers, start=1):
        sh.cell(row=row, column=ci, value=h)
        sh.cell(row=row, column=ci).fill = header_fill
        sh.cell(row=row, column=ci).font = bold_font
        sh.cell(row=row, column=ci).alignment = wrap
        sh.cell(row=row, column=ci).border = border
    row += 1

def add_row(label, items):
    global row
    sh.cell(row=row, column=1, value=label).font = bold_font
    sh.cell(row=row, column=2, value=len(items))
    sh.cell(row=row, column=3, value=0)
    MAX_ITEMS = 400
    if len(items) > MAX_ITEMS:
        shown = "\n".join(items[:MAX_ITEMS] + [f"... (+{len(items)-MAX_ITEMS} more)"])
    else:
        shown = "\n".join(items)
    sh.cell(row=row, column=4, value=shown)
    sh.cell(row=row, column=5, value="")
    sh.cell(row=row, column=6, value="")  # Notes empty
    for c in range(1, 7):
        sh.cell(row=row, column=c).alignment = wrap
        sh.cell(row=row, column=c).border = border
    row += 1

for schema_name, data in sorted(schemas.items(), key=lambda x: x[0].lower()):
    sh.merge_cells(start_row=row, start_column=1, end_row=row, end_column=8)
    sh.cell(row=row, column=1, value=f"Schema Name: {schema_name}").font = bold_font
    row += 1

    write_header()

    add_row("Tables", data["Tables"])
    add_row("Indexes", data["Indexes"])

    start_constraints = row
    add_row("PK", data["Constraints"]["PK"])
    add_row("UK", data["Constraints"]["UK"])
    add_row("FK", data["Constraints"]["FK"])
    sh.merge_cells(start_row=start_constraints, start_column=1, end_row=start_constraints+2, end_column=1)
    sh.cell(row=start_constraints, column=1, value="Constraints").font = bold_font
    for r in range(start_constraints, start_constraints+3):
        for c in range(1, 7):
            sh.cell(row=r, column=c).border = border
            sh.cell(row=r, column=c).alignment = wrap

    add_row("Sequences", data["Sequences"])
    add_row("Functions", data["Functions"])
    add_row("Procedures", data["Procedures"])
    add_row("Triggers", data["Triggers"])
    add_row("Views", data["Views"])
    add_row("Materialized Views", data["Materialized Views"])
    add_row("Columns", data["Columns"])
    add_row("Partitions", data["Partitions"])
    add_row("Extensions", data["Extensions"])
    add_row("Invalid Constraints", data["Invalid Constraints"])
    add_row("Invalid Index", data["Invalid Index"])
    add_row("udf", data["udf"])
    add_row("Users", data["Users"])

    row += 2

sh.column_dimensions["A"].width = 24
sh.column_dimensions["B"].width = 15
sh.column_dimensions["C"].width = 15
sh.column_dimensions["D"].width = 80
sh.column_dimensions["E"].width = 40
sh.column_dimensions["F"].width = 10

out_path = "/mnt/data/fresh_schema_comparison_single_sheet.xlsx"
wb.save(out_path)

out_path
