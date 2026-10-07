# orchestratorai-pi — Claude notes

## Matt's queue (asking Matt for anything)

Everything waiting on Matt lives in `docs/matt-queue.md`, most important first, each item with a Status: Waiting, then Asked (date), then Answered (date, with Matt's words), then Processed. Processed items move to `docs/matt-queue-archive.md`. When you need Matt to decide or do something, add it with Status: Waiting, in priority order, in the file's self-contained format (title with deadline, Status, What, Why it matters, Options, Recommendation, the exact Reply). Never leave an ask only in chat; Matt reads in bursts and doesn't carry context between messages.

When Matt says "give me your top issue", "the next one" or "what's waiting on me?", give the first item that isn't Answered yet, exactly as written, and mark it Asked. When he answers, mark it Answered with his words, act on it, record the decision, then mark it Processed and move it to the archive. grokbot reads the same file across Matt's projects.