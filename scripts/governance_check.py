import json
import sys
from pathlib import Path

manifest_path = Path("target/manifest.json")
if not manifest_path.exists():
    raise SystemExit("target/manifest.json is missing; run dbt docs generate first")

manifest = json.loads(manifest_path.read_text())
errors = []
public_models = []
for node in manifest["nodes"].values():
    if node.get("resource_type") != "model":
        continue
    if not node.get("description", "").strip():
        errors.append(f"model {node['name']} has no description")
    for name, column in node.get("columns", {}).items():
        if not column.get("description", "").strip():
            errors.append(f"column {node['name']}.{name} has no description")
    direct_sources = [
        dependency
        for dependency in node.get("depends_on", {}).get("nodes", [])
        if dependency.startswith("source.")
    ]
    if direct_sources and not node.get("original_file_path", "").startswith("models/staging/"):
        errors.append(
            f"non-staging model {node['name']} directly references a source: "
            f"{', '.join(direct_sources)}"
        )
    if node.get("original_file_path", "").startswith("models/marts/"):
        public_models.append(node)
        if not node.get("config", {}).get("contract", {}).get("enforced"):
            errors.append(f"mart {node['name']} does not enforce a contract")
        for name, column in node.get("columns", {}).items():
            if not column.get("data_type"):
                errors.append(f"mart column {node['name']}.{name} has no data_type")

exposures = manifest.get("exposures", {})
if not any(item.get("name") == "hourly_strategy_analysis" for item in exposures.values()):
    errors.append("hourly_strategy_analysis exposure is missing")
if not public_models:
    errors.append("no public mart models found")

if errors:
    print("Governance checks failed:", file=sys.stderr)
    print("\n".join(f"- {error}" for error in errors), file=sys.stderr)
    raise SystemExit(1)
print(f"Governance checks passed for {len(public_models)} mart models and the analysis exposure.")

