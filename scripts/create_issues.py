mkdir -p scripts
cat > scripts/create_issues.py << 'PY'
import csv, os, subprocess, sys

repo = subprocess.check_output(["gh","repo","view","--json","nameWithOwner","-q",".nameWithOwner"], text=True).strip()
csv_path = sys.argv[1] if len(sys.argv) > 1 else "issues.csv"

with open(csv_path, newline='', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    for row in reader:
        title = row.get("Title","").strip()
        body = row.get("Body","").strip()
        labels = [s.strip() for s in row.get("Labels","").split(",") if s.strip()]
        milestone = row.get("Milestone","").strip()

        cmd = ["gh","issue","create","--title",title,"--body",body]
        if labels:
            for lab in labels:
                cmd += ["--label", lab]
        if milestone:
            cmd += ["--milestone", milestone]

        print(">>", " ".join(cmd))
        subprocess.run(cmd, check=True)
PY
