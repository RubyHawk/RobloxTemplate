# Stagewright map backdrop asset boundary

Date: 2026-07-20

Official references reviewed:

- [Roblox assets and URI schemes](https://create.roblox.com/docs/projects/assets)
- [Asset Manager image import](https://create.roblox.com/docs/projects/assets/manager)
- [ViewportFrame rendering](https://create.roblox.com/docs/reference/engine/classes/ViewportFrame)
- [ImageLabel reference](https://create.roblox.com/docs/reference/engine/classes/ImageLabel)
- [Text and image labels](https://create.roblox.com/docs/ui/labels)
- [BasePart transparency](https://create.roblox.com/docs/reference/engine/classes/BasePart/Transparency)
- [Textures and decals](https://create.roblox.com/docs/parts/textures-decals)

Stagewright map artwork is editor guidance, not route or gameplay truth. The route graph, painted cell roles, and baked spline data remain authoritative. Each first-class Map stores its image asset ID; its Stages and Levels reference that Map without duplicating the artwork.

Persistent generated PNG backdrops must first be imported through Asset Manager and referenced with an `rbxassetid://` image ID. A local `rbxtemp://` file reference is session-only and is not suitable for saved or collaborative maps. Each Map owns one backdrop; its Stages and Levels share it while keeping independent path graphs and wave settings.

Flat map art is rendered directly through `ImageLabel.Image`, which officially accepts uploaded decal or image asset IDs. This avoids routing 2D art through an opaque Part, Decal, and `ViewportFrame`; that path could expose the white helper plane when the image was unavailable. The existing `ViewportFrame` remains only for optional real 3D Studio scenery. Generated artwork stays pathless, uses a clear central build surface, and keeps decorative obstacles near the island perimeter. Live Stagewright spline ribbons are rendered above it.
