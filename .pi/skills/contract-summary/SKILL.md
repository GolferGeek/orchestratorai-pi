---
name: contract-summary
description: Turn arbitrated contract findings into a concise executive summary and readable detailed Markdown report.
---

# Contract summary and reporting standard

Every workflow that produces a human-facing legal report should use this scan-friendly structure.
The exact wording may vary by workflow, but the reader should always be able to find the same core
information in the same order:

1. `#` Report title and document name
2. `## Executive summary` — what the document does and the overall conclusion
3. `## Attorney review focus` — the short action queue, using unchecked task items:
   `- [ ] SEVERITY — issue; attorney question or recommended action`
4. `## Findings` or clearly labeled perspective sections
5. `## Recommended actions`
6. `## Open questions for counsel` or `## Questions for the business owner`
7. `## Limitations`

When a workflow uses a team, preserve each perspective before synthesis. For example, use
`## Red-team findings`, `## Blue-team findings`, and `## Arbitrator's synthesis` in that order.
Do not collapse distinct reviewer positions into an unexplained conclusion.

Formatting rules:

- Prefer short paragraphs, bullets, and numbered lists.
- Do not use Markdown tables for substantive findings; tables are difficult to scan and render
  poorly in some clients.
- Give each material issue a severity, provision or source reference, practical impact, and
  recommended follow-up.
- Keep source excerpts short and preserve clause headings, line locations, or page references.
- Separate document facts, interpretation, risk assessment, recommendation, and attorney judgment.
- State assumptions and missing context instead of inventing facts or legal authority.
- The report must stand on its own for a reader who cannot review the full agreement immediately.
