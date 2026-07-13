# Stagewright lanes and merged spawns — 2026-07-13

## Authoring contract

Each edge references a lane profile. A profile contains one, two, or three
lateral offsets from the baked cubic Bézier centerline. Stagewright exposes
explicit **1 Lane**, **2 Lanes**, and **3 Lanes** actions for the selected
edge's profile. The standard four-stud spacing produces `{0}`, `{-2, 2}`, or
`{-4, 0, 4}` and expands the derived route-clearance mask with the corridor.

The graph may contain multiple stable Spawn nodes and multiple incoming edges
to one Junction. No special merge edge type is needed: two independently baked
branches reference the same destination node, then share that node's outgoing
edge. Validation requires every edge to reference a valid profile with one to
three finite offsets and enough clearance to cover the furthest lane.

## Runtime contract

The server sorts Spawn nodes by stable ID and distributes enemies across them
deterministically. Lane sequences advance independently of spawn selection, so
two spawns and two lanes exercise all four spawn/lane combinations instead of
pinning each spawn to one side. When an edge uses a different lane count, the
server maps the enemy's stable lane sequence into that profile and replicates
only the resulting lane index.

Server targeting samples the authoritative offset CFrame. Clients receive the
chosen spawn edge and lane index, then render pooled enemies from the same baked
samples. Clients cannot submit spawn choices, lane choices, or positions.

## Production fixture

`Centerbound Dual Approach` contains upper and lower outer spawns. Each has its
own two-lane approach, both branches enter `Spawn Merge`, and all enemies then
follow the shared centerbound route. The default profile is two lanes and can
be changed to one or three in Stagewright without moving nodes or handles.
