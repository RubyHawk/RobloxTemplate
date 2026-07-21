# Stagewright map artwork

`open-grass-island.png` is a terrain-only, 16:9 editor backdrop generated for Stagewright. It intentionally contains no roads, route arrows, towers, or central obstacles. Stagewright's live graph remains the only source of path geometry.

To use it persistently in Roblox Studio:

1. Import the PNG as an image through Asset Manager for the open experience.
2. Copy its numeric asset ID after moderation/import completes.
3. In Stagewright, select the Map and paste that ID into **Map backdrop image ID** under **Map Properties**.

The backdrop is shared by every Stage and Level in the Map. It is visual authoring guidance only; painted cells, graph data, validation, and exported runtime paths remain authoritative.
