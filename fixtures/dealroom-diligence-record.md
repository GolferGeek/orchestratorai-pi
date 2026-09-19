# Due diligence record - Cedar Analytics acquisition (synthetic)

**Synthetic fixture for demonstration. All parties, facts, figures and citations are fictional.**

**Transaction:** Harbor Peak Systems, LLC to acquire 100% of the equity of Cedar Analytics, Inc.
**Room:** fixtures/dealroom (5 documents)  **Prepared:** buyer-side counsel

## Risk matrix

| id | Severity | Category | Documents | Consequence |
|---|---|---|---|---|
| R-1 | CRITICAL | Commercial | 01-msa-northwind.md | Northwind MSA s.11 forbids assignment or change of control without consent that may be withheld in Northwind's sole discretion. Northwind is ~41% of recurring revenue. Closing without consent voids the contract and is a material breach. |
| R-2 | CRITICAL | Financial | 02-loan-security-agreement.md | Change of control is an immediate event of default under s.9 absent 30 days' prior written lender consent. Lender holds a first lien on all assets including IP and may accelerate $9.5M and foreclose on the IP. |
| R-3 | HIGH | Financial | 02-loan-security-agreement.md | Q2 compliance certificate shows net leverage 3.4x against a 3.0x covenant. No waiver in the room; an existing default may already be running. |
| R-4 | HIGH | IP | 04-employment-ip-memo.md | 11 employees (including 2 core pipeline engineers) have no invention assignment on file; 11 contractors have none at all, and contractor work covered the connector framework and scheduler. Chain of title to core IP is not established. |
| R-5 | HIGH | Commercial | 01-msa-northwind.md | Availability was 99.41/99.38/99.62 against a 99.9% SLA. Three consecutive months below 99.5% gives Northwind termination for cause plus pro-rata refund; two of the three months qualify. |
| R-6 | HIGH | Privacy | 05-data-processing-addendum.md | DPA relies on the Privacy Shield framework for EEA transfers with no standard contractual clauses; two 2025 sub-processors are absent from the list attached to the Northwind MSA. |
| R-7 | MEDIUM | Governance | 03-cap-table-summary.md | Series B protective provision requires majority Series B approval for a change of control; Greyfield expects its 2x preference in cash at closing. |
| R-8 | MEDIUM | Employment | 04-employment-ip-memo.md | Open state wage-and-hour audit with no records produced, plus an unanswered misclassification demand letter. |
| R-9 | MEDIUM | Governance | 03-cap-table-summary.md | 310,000 options granted March 2026 on a November 2024 409A; stale valuation creates 409A exposure for grantees and the company. |
| R-10 | LOW | Commercial | 01-msa-northwind.md | Most-favoured-customer warranty in s.12 is uncapped under s.16; no pricing audit in the room to confirm compliance. |

## Deal-breaker flags
- **R-1 and R-2 together.** Both the largest customer and the secured lender hold consent rights that a change of control triggers. Neither consent is in the room. Closing without both is not viable.
- **R-4.** Core IP chain of title is incomplete. A buyer acquiring for the technology may not own it.

## Cross-document findings
- The lender's lien (02) attaches to IP whose ownership is unestablished (04) - a foreclosure would transfer an encumbered and defective asset.
- The SLA failures (01, R-5) give Northwind an independent termination right, so the consent risk in R-1 compounds: Northwind has leverage to refuse consent or to reprice.
- The DPA sub-processor list (05) does not match the list attached to the Northwind MSA (01), so Cedar may already be in breach of its largest customer contract on privacy terms.

## Missing materials
- Northwind consent to assignment; lender consent and any covenant waiver.
- Schedule A (employees without PIIAA) and the contractor master agreements, both referenced in 04.
- Refreshed 409A valuation; SOC 2 report described as "in progress"; standard contractual clauses for EEA transfers.
- Documentation of the two former employees' asserted 120,000-share claims.

## Open items for counsel
1. Confirm whether the lender default under R-3 is live and whether it has been waived orally.
2. Obtain the PIIAA gap list and assess remediation cost and feasibility pre-closing.
3. Determine whether Northwind's termination right under R-5 has already accrued.
