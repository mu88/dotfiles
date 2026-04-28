---
applyTo: "**/*.json,**/*.json5,**/*.jsonc"
---
# JSON / JSON5 / JSONC Instructions

## Schema-First Editing
- Before editing a JSON file, always check for a `$schema` property at the root. If present, treat it as the authoritative source of truth for allowed attributes and their types.
- If no `$schema` property is present, look for a matching schema in the project (e.g. a `*.schema.json` file, a `$schema` entry in a related config, or a known SchemaStore entry for the file name).
- Only use attributes that are documented in the schema. Never invent or guess attribute names — hallucinated attributes are silently ignored at best and break tooling at worst.
- If no schema can be found, fall back to official documentation or existing examples in the codebase. Document the source of your knowledge in a comment (JSONC/JSON5) or in the PR description.
