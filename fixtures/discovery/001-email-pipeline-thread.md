# Email thread - "Re: pipeline ideas from the HP sessions"

**Synthetic fixture for demonstration. All parties, facts and communications are fictional.**

**From:** Dana Ruiz <dana.ruiz@aspendevices.example>
**To:** Marco Chen <marco.chen@aspendevices.example>
**Date:** 2026-03-12T09:14:00Z

Marco - after the Harbor Peak sessions I keep coming back to how they shard the ingest queue. We don't have to copy anything, but the idea of partitioning by tenant before the dedupe step is just better than what we do. Can you sketch what that looks like in our scheduler?

---
**From:** Marco Chen  **To:** Dana Ruiz  **Date:** 2026-03-12T11:40:00Z

Sketched it. Honestly it's close to what they showed us in the second session. I'm not comfortable building it straight from memory of their deck - can we ask legal where the line is on the residuals clause?

---
**From:** Dana Ruiz  **To:** Marco Chen  **Date:** 2026-03-12T12:02:00Z

We're allowed to use what's in our heads. That's what the clause is for. Build it, don't document where it came from.
