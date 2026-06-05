---
applyTo: "**/*.json,**/*.json5,**/*.jsonc"
---
# JSON / JSON5 / JSONC Instructions

## Schema-First Editing
- Resolve the schema using these steps in order — stop at the first match:
  1. Check the file root for a `$schema` property. If present, use that schema exclusively.
  2. Search the project for a `*.schema.json` file whose name matches the file being edited. If found, use it.
  3. Look up the filename in the SchemaStore catalog (`https://www.schemastore.org/api/json/catalog.json`). If a matching entry exists, use it.
  4. Fall back to official documentation or existing codebase examples.
- Only use attributes documented in the schema. Never invent or guess attribute names — hallucinated attributes are silently ignored at best and break tooling at worst.
- When falling back to step 4: for JSONC/JSON5 files, add a `//` comment above the field with the source. For plain JSON files, note the source in the chat response.
