# Matt queue archive

## 1. A Developer ID certificate, so Pi can be a downloadable app

- **Status:** Answered (2026-10-05) → Processed (2026-10-05)
- **Answer:** already enrolled
- **What:** Pi can only be given to someone today as a git repository they build
  themselves. To hand them an app they can download and open, the app has to be
  signed with an Apple **Developer ID** certificate and notarized by Apple. This
  Mac only has an *Apple Development* certificate, which cannot be used for
  that. It needs an Apple Developer Program membership ($99/year) and a
  Developer ID Application certificate created under it. Only you can do this —
  it is an account and identity action, not code.
- **Why it matters:** without it, macOS refuses to open the app on any machine
  it was not built on, so there is no download, no `.dmg` and no Homebrew
  install — and we cannot even test whether those work. Everything else in the
  packaging plan is ordinary work we can do; this is the one thing in the way.
  The technical question that could have killed the whole idea has already been
  answered: a signed, hardened Pi still launches `pi` and its child processes
  with no special permissions (`docs/verification/2026-09-30-hardened-runtime-spike.md`).
- **Options:** (a) enroll now and create the certificate, so packaging can be
  built and tested; (b) wait, and keep handing people the repository.
- **Recommendation:** (a), whenever you want anyone outside the building to open
  Pi without a checkout. There is no rush if the only audience is demos you
  drive yourself.
- **Reply:** "Yes, enrolling / already enrolled — I'll make the Developer ID
  cert", or "Not yet, keep shipping the repo."

- **Status:** Processed (2026-10-05)
- **Processed note:** Developer ID Application cert present on Studio: `Developer ID Application: Matthew Weber (227GEZ2676)` (8D05A72D…). Matt confirmed done 2026-10-05. Not App Store.


---

's queue: archive

Processed items moved out of `docs/matt-queue.md`, newest first. Each keeps its question, Matt's answer and the date.

_Nothing archived yet._
