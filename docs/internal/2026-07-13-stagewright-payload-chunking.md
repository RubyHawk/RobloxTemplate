# Stagewright payload chunking — 2026-07-13

Studio startup logs showed that `StringValue.Value` rejects strings at or above 200,000 bytes. Seeding
Stage 1 with ten copied levels produced an authoring payload of roughly 481 KB, so the plugin failed in
`ProjectStore.save()` before it could create the toolbar.

Stagewright now stores payloads up to 180,000 bytes directly for backward compatibility. Larger working
copies and exported authoring/runtime payloads use a small `StagewrightChunked:v1` manifest plus numbered
`StringValue` chunks. The manifest records the chunk count, exact byte length, and canonical checksum.
Readers reject missing, malformed, truncated, or checksum-mismatched data. Existing one-value working
copies and RBXM bundles remain readable.

The chunk values are written before the manifest so observers never accept a partially written revision.
Undo/redo processing defers reads until the complete ChangeHistory operation has settled.
