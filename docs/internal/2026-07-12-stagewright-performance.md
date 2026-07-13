# Stagewright local performance baseline — 2026-07-12

Environment:

- CPU: AMD Ryzen 9 3950X 16-Core Processor
- RAM: 63.9 GB
- Lune: 0.10.4

`lune run scripts/benchmark-stagewright.luau` recorded:

- 256×256 dense grid validation: 55.343 ms; budget 1,000 ms.
- 1,000-node/1,500-edge graph validation: 102.260 ms; budget 1,000 ms.
- 500-enemy 20 Hz route sample batch: 1.405 ms average; budget 8 ms.
- Six-platform, 3,000-enemy route sample batch: 8.513 ms average; budget 30 ms.
- 900 visible-cell incremental mutation: 0.148 ms average; budget 16 ms.

These measurements cover pure schema/graph/path work and protect CI against algorithmic regressions. They are not substitutes for Studio MicroProfiler captures, client rendering FPS, network emulation, StreamingEnabled recovery, or the agreed mid-tier device test. Those remain manual acceptance items in `docs/STAGEWRIGHT_QA.md`.
