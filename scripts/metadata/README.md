# Metadata generators

Python 3 scripts that generate repetitive metadata and the replication documents. Run them from the repository root.

| Script | Purpose | Command |
|---|---|---|
| `genmeta2.py` (uses `genmeta_lib.py`) | Custom objects, fields, validation rules and the platform event | `rm -rf force-app/main/default/objects/* && cd scripts/metadata && python3 genmeta2.py ../..` |
| `genapp.py` | App, tabs, utility bar, custom permissions, notification type, permission sets, report types, reports, dashboard | `python3 scripts/metadata/genapp.py .` |
| `gendatadoc.py` | `docs/data-model.md` from the object metadata | `python3 scripts/metadata/gendatadoc.py . scripts/metadata/datamodel-head.md` |
| `gen_matrix.py` (uses `csvmap_*.py`) | Metadata inventory, dependency map, replication matrix and summary from `docs/evidence/reference-package-components.csv` | `python3 -I scripts/metadata/gen_matrix.py docs/evidence/reference-package-components.csv .` |

Run the generators in this order: `genmeta2.py`, then `genapp.py` (permission sets read the object metadata), then `gendatadoc.py`, then `gen_matrix.py` (status is computed from what exists in the repository).
