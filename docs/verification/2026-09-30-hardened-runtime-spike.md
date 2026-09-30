# Hardened runtime spike — 2026-09-30

Answers the one open question in
[productize-plan.md](../productize-plan.md) option 2: **does a Pi.app signed
with the hardened runtime still launch an externally installed `pi`, and the
delegated `pi` children that `pi` spawns?**

**Answer: yes, and with no entitlements at all.** The hardened runtime does not
restrict `fork`/`exec` of another program, and it is not inherited across
`exec` — the spawned `node`/`pi` processes run under their own signature and
their own flags, so V8's JIT and pi-agents' delegation are unaffected. Signing,
notarization and a Homebrew cask are not blocked by the child processes.

What *is* blocked is the **App Sandbox**, which is a different entitlement and a
different distribution channel. See phase C.

Nothing was notarized or published. `dist/Pi.app` was not touched; every
signature in this record was applied to a scratch copy.

## Method

| | |
|---|---|
| Build under test | A byte copy of `dist/Pi.app` (built from `de9bdb4`) placed at `spike/Pi.app`, so the app still finds the project two levels up from its bundle, exactly as `dist/` does |
| Signing identity | `Apple Development: MATT Weber (Q95DF7CUGG)`, team `227GEZ2676` — the only codesigning identity on this Mac. **No Developer ID certificate exists here**, which limits what phase A can say about Gatekeeper (below) but not what it says about the hardened runtime |
| Workflow driven | `kb-query`, end to end, through the real UI with the [click-through harness](../../scripts/clickthrough/) — select, New run, Start, then the final review approved by a real click carrying a per-run token |
| Model | `qwen3.6:latest` via Ollama |
| Delegation evidence | `ps` was sampled every 5s for the whole run, and the in-kernel signature of each child was read with `codesign -d +<pid>` |

## Baseline — what `dist/Pi.app` is signed as today

```
Identifier=Pi
CodeDirectory v=20400 flags=0x20002(adhoc,linker-signed)
Signature=adhoc      TeamIdentifier=not set      Info.plist=not bound
```

No entitlements, no hardened runtime, no team — the signature the Swift linker
puts on any locally built binary. "The app's current entitlements", which the
task asked to test first, is therefore the empty set, and that is phase A.

`otool -L` on the executable lists only system libraries
(`Foundation`, `AppKit`, `SwiftUI`, `/usr/lib/libsqlite3.dylib`,
`/usr/lib/swift/*`). Nothing third-party is loaded into the app's address
space, which is why library validation has nothing to reject — see phase B.

## Phase A — hardened runtime, no entitlements

```sh
codesign --force --options runtime --timestamp \
  --sign "Apple Development: MATT Weber (Q95DF7CUGG)" spike/Pi.app
```

Result: `CodeDirectory v=20500 flags=0x10000(runtime)`,
`Identifier=com.orchestratorai.pi`, `TeamIdentifier=227GEZ2676`, timestamped,
and `codesign --verify --deep --strict` reports *valid on disk* and *satisfies
its Designated Requirement*. The running process carries the same flags
(`codesign -d +<pid>` → `flags=0x10000(runtime)`), so the test is really testing
a hardened process and not a stale on-disk signature.

**kb-query: pass.** Run `aa14b2af`, status `completed`, final review `approved`
by a harness click (token `ct-1790807447-38560`). The report cites
`matters/contract-review/nda/example-mutual-nda.md`,
`fixtures/example-nda.md` and
`fixtures/onboarding/conflicting-version-nda.md` — so the delegated agent really
read files off disk, rather than producing something from nothing.

### The process tree, which is the whole point

```
36987  Pi          spike/Pi.app/Contents/MacOS/Pi     flags=0x10000(runtime)
 39087  pi         /opt/homebrew/Cellar/node/26.4.0/bin/node   flags=0x2(adhoc)
  39156  pi        /opt/homebrew/Cellar/node/26.4.0/bin/node   flags=0x2(adhoc)
```

Three facts worth stating separately, because the plan's worry conflated them:

1. **The hardened app spawned the external interpreter.** `PiRunner.launchPi`
   does a plain `Process.run()` on the `pi` found by
   `PiEnvironment.findPiExecutable()`. The hardened runtime places no
   restriction on executing another program; its restrictions
   (unsigned executable memory, DYLD insertion, library validation, debugging)
   all apply *within* a process.
2. **`pi` spawned its delegated child.** pid 39156 under 39087 is the
   pi-agents delegate; the store shows its `node_session` and `node_completed`
   for the run. That is one hardened grandparent, two non-hardened descendants.
3. **The hardened runtime is not inherited.** Both children are the Homebrew
   `node` binary and carry `flags=0x2(adhoc)` — no `runtime` bit. Each `exec`
   installs the flags from the *new* binary's signature. So Node's JIT never
   needed `allow-jit`, and nothing the children load is subject to the app's
   library validation.

### What did *not* break

- **PATH.** `PiEnvironment.processEnvironment` hands the child an augmented
  PATH, and the Finder-launched hardened app found `~/.npm-global/bin/pi` and
  Homebrew's `node` from it. Nothing is stripped that the app relies on — the
  app sets no `DYLD_*` variable, which is the family the hardened runtime does
  strip.
- **The `.env` read.** `TYPESAFE_API_KEY` still reaches the child; a hardened
  app reads files normally.
- **The SQLite store.** The extension wrote `data/orchestrator.sqlite` and the
  app's WAL watchers saw it; the run appeared, streamed, and completed live.
- **`pkill`.** `terminateDirectChildren` shells out to `/usr/bin/pkill`; the
  Stop button was present throughout and the tree was reaped at quit.

### The one thing phase A cannot say

`spctl -a -t exec spike/Pi.app` → **rejected**, `origin=Apple Development`. That
is the expected and uninteresting answer: an Apple Development certificate is
not a Developer ID and the app is not notarized, so Gatekeeper refuses it on
assessment. It launched anyway because a locally built bundle carries no
`com.apple.quarantine` attribute. **Gatekeeper acceptance was therefore not
tested, and cannot be on this Mac** — that needs a Developer ID Application
certificate and a notarization round trip. Nothing in this spike suggests it
would fail; notarization inspects the bundle, and this bundle contains exactly
one executable and an `Info.plist`.

## Phase B — hardened runtime plus the entitlements the plan feared

The plan named
`com.apple.security.cs.allow-unsigned-executable-memory` and
`com.apple.security.cs.disable-library-validation` as things this might need.
Phase B added both, plus `com.apple.security.cs.allow-jit`, and re-ran the same
workflow:

```sh
codesign --force --options runtime --timestamp \
  --entitlements minimal.entitlements \
  --sign "Apple Development: MATT Weber (Q95DF7CUGG)" spike/Pi.app
```

```xml
<dict>
  <key>com.apple.security.cs.allow-jit</key><true/>
  <key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
  <key>com.apple.security.cs.disable-library-validation</key><true/>
</dict>
```

**kb-query: pass.** Run `ed9f93b5`, status `completed`, final review `approved`
(token `ct-1790807611-47276`). Tree: `46716 Pi` → `47790 pi` → `47875 pi`, the
same shape as phase A.

So phase B works, and so does phase A. **The minimal set of entitlements needed
is none.** These three change nothing here, and each one is a real weakening of
the runtime that a reviewer would ask about, so the build script should not add
them. The reason they are not needed is the one in phase A, point 3: they govern
what happens inside the app's own address space, and the interpreter runs in a
different address space under its own signature.

## Phase C — App Sandbox: this is what actually breaks

The App Sandbox is a separate entitlement from the hardened runtime, and it is
required only for Mac App Store distribution — not for Developer ID, a `.dmg`,
or a Homebrew cask. Phase C signed the same scratch app with it, to know which
distribution channels the current design closes off:

```xml
<dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.files.user-selected.read-write</key><true/>
  <key>com.apple.security.network.client</key><true/>
</dict>
```

The app launched (`Pi[55204] (libsystem_secinit.dylib) AppSandbox`) and was
given a container at `~/Library/Containers/com.orchestratorai.pi`. Then:

**kb-query: fail — and it never got as far as spawning anything.**

```
ERR no element #sidebar.workflow.kb-query
ERR no element #runs.new_run
FAIL start button never became enabled (last=ERR no element #launch.start); live runs:
```

There is no workflow row, no New run button and no Start button, because there
is no project to show. What the live window actually said:

```
Could not open data/orchestrator.sqlite in /Users/golfergeek/projects/orchestratorai/orchestratorai-pi
0 of 0 runs
Pi has not trusted this project yet
Not installed yet — No .pi/workflows/contract-review.yaml in this project
```

All fourteen catalog rows render as *Not installed yet*: the sandbox denies
reading `.pi/workflows/*.yaml`, `data/orchestrator.sqlite` and
`~/.pi/agent/trust.json`, so from the app's point of view the project is empty.

### The spawn itself, tested separately

Because the sandboxed app stops one step earlier, a small probe answers the
spawn question directly — a 20-line Swift binary that calls
`FileManager.isExecutableFile` on `pi` and then `Process.run()`s `pi --version`,
in an `.app` bundle signed the same three ways:

| Signature | `pi` is executable | `Process.run()` on `pi` |
|---|---|---|
| ad-hoc, no hardened runtime | yes | **ok** — `0.85.1` |
| hardened runtime, no entitlements | yes | **ok** — `0.85.1` |
| hardened runtime + App Sandbox | **no** | **fails** — `NSCocoaErrorDomain Code=4 "The file "cli.js" doesn't exist." NSFilePath=/Users/golfergeek/.npm-global/bin/pi` |

The sandboxed probe's `HOME` is rewritten to
`~/Library/Containers/com.orchestratorai.spawnprobe/Data`, and the npm prefix is
unreadable, so the `pi` shim cannot resolve its own `cli.js`. There is no
entitlement that fixes this: a sandboxed process's children inherit its sandbox,
and an arbitrary interpreter outside the container is exactly what the sandbox
exists to prevent.

### One behaviour worth knowing about

Under the sandbox, `FileManager.fileExists(atPath:)` on the project's
`.pi/settings.json` still returns **true** — `stat` succeeds where `open` is
denied. `PiEnvironment.findProjectDirectory` uses `fileExists` to pick the
project, so it reports the right directory and then everything that reads inside
it fails. If the app is ever sandboxed, that check needs to be an actual read,
or the failure will keep presenting as "the project is empty" rather than "I
cannot read the project".

## What this means for the packaging plan

| Option | Verdict |
|---|---|
| 2 — signed, notarized `.dmg` with Developer ID | **Not blocked by the child processes.** Hardened runtime, no entitlements, works today |
| 3 — Homebrew cask | Not blocked either; it inherits (2)'s signature |
| 4 — first-run setup | Unaffected |
| Mac App Store | **Closed** while the app spawns an externally installed `pi`. Not on the plan's list, and this is the reason to keep it off |

The plan's sentence *"the single biggest unknown in the whole plan"* can be
retired. The remaining packaging work in option 2 is the ordinary list — a
Developer ID certificate, a signing and notarization step in
`scripts/build-app.sh`, the resource-embedding and first-run seed, an icon, a
version scheme — with no architectural change to how `pi` is launched.

## What this spike did not test

- **Gatekeeper and notarization.** No Developer ID certificate exists on this
  Mac, so `spctl` assessment necessarily fails and the notarization round trip
  was not attempted. The hardened-runtime question is answered; the
  *distribution* question is not.
- **A quarantined copy.** The scratch app carries no `com.apple.quarantine`
  attribute, so the first-launch path a downloader sees was not exercised.
- **TCC.** The repository lives under `~/projects`, which is not a
  TCC-protected location. A hardened, Developer-ID-signed app whose `pi` child
  reads `~/Documents` or `~/Desktop` should prompt for access **attributed to
  Pi.app**, and changing the signature resets existing grants. Neither was
  exercised. This is worth a second, smaller spike before a `.dmg` ships,
  because the prompt would appear at the moment a user points a workflow at a
  real matter folder.
- **The other thirteen workflows.** One workflow, `kb-query`, twice. The signing
  behaviour is not per-workflow, but this record covers one.
- **Resource embedding.** The scratch app still finds the project two levels up
  from its bundle. Moving `.pi/` into `Contents/Resources` and seeding
  `~/Library/Application Support` is untested work, and it is the part of option
  2 that remains.

## Reproducing

```sh
REPO=~/projects/orchestratorai/orchestratorai-pi
mkdir -p $REPO/spike && cp -R $REPO/dist/Pi.app $REPO/spike/Pi.app
codesign --force --options runtime --timestamp --sign "<identity>" $REPO/spike/Pi.app
codesign -d --verbose=2 $REPO/spike/Pi.app        # expect flags=0x10000(runtime)
osascript -e 'tell application id "com.orchestratorai.pi" to quit'
open $REPO/spike/Pi.app
bash /tmp/pidrv/runwf.sh kb-query "hardened-runtime spike" 45
```

The scratch copy must sit one directory below the repository root, the way
`dist/` does, or the app will not find the project. `spike/` was deleted
afterwards; `dist/Pi.app` was never re-signed.
