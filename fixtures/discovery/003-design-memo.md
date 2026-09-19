# Design Memo - Scheduler v4 tenant partitioning

**Synthetic fixture for demonstration. All parties, facts and communications are fictional.**

**Author:** Marco Chen  **Date:** 2026-04-02  **Status:** Approved for implementation

## Background
Scheduler v3 dedupes before partitioning, which creates a hot-shard problem above ~8k events/sec.

## Proposed change
Partition by tenant id before the dedupe step; dedupe within each partition.

## Derivation
This design follows from the load profile in our own incident reports (INC-2291, INC-2304). **An earlier draft of this memo cited "the Harbor Peak approach" as prior art; that line was removed on 2026-04-01 at the request of D. Ruiz.**

## Risks
Rebalancing during partition changes may duplicate events at the boundary. Mitigated by idempotency keys.
