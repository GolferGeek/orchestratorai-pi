# Matter Record: Harbor Peak v. Aspen Devices — Dual Track: Cedar Analytics Acquisition Due Diligence / IP Litigation Defense (Scheduler v4 Trade Secrets & Residuals Clause Issues)

**Matter ID:** HP-v-AD-2026-001  
**Client:** Harbor Peak Systems, LLC (Buy-Side Client / Plaintiff)  
**Subject:** Track 1: Buyer-Side Due Diligence — Cedar Analytics Acquisition | Track 2: IP Litigation — Aspen Devices Scheduler v4 Trade-Secret & Residuals Clause Defense  
**Target Entity (Track 1):** Cedar Analytics, Inc.  
**Respondent Entity (Track 2):** Aspen Devices, Inc.  
**Current Date:** July 9, 2026  

---

## 1. Merged Entities Index
| # | Entity Name | Legal/Formal Name | Category / Type | Key Facts from Records |
|---|------------|-------------------|-----------------|------------------------|
| 1 | Cedar Analytics, Inc. | Cedar Analytics, Inc. | Target Company (Track 1) | Acquired target; 54 employees; ~$10.2M annualized ARR; $9.5M outstanding loan with Meridian Credit Partners; IP assignment gaps for 11 employees and all 11 contractors; data privacy compliance deficiencies (EU-US Privacy Shield deprecated, backup deletion carve-out); Series B protective provisions granting veto power over any change of control |
| 2 | Contractors (11 persons) | Contractors (unnamed) | External Resources – IP Risk Subject (Track 1) | Zero have written IP assignment agreements; work included connector framework and scheduler components; contractor master agreements referenced but not available in data room |
| 3 | Employees | Employees (54 total) | Human Capital / IP Owners (Track 1) | 43 signed PIIAA; 11 lack PIIAA (hired January 2023–June 2024, including 2 engineers on core ingestion pipeline); 19 California-based employees with unenforceable 12-month non-competes |
| 4 | Founders | Foundors (3) | Insiders / Common Equity Holders (Track 1) | Hold 6,400,000 common shares (42.1% fully diluted); subject to Series B and A senior preferences; PIIAA status uncertain given hiring date overlap with gap period |
| 5 | Greyfield Capital | Greyfield Capital (fund entity) | Investor – Series B Preferred Holder (Track 1) | Holds 2,050,000 Series B shares (13.5% fully diluted); controls majority of outstanding Series B; protective provision requires majority Series B holder approval for any merger/sale/change of control; informally expects cash satisfaction of $ preference at closing |
| 6 | Harbor Peak Systems, LLC | Harbor Peak Systems, LLC | Acquirer / Plaintiff (Track 1 & 2) | Proposed acquirer conducting diligence on Cedar Analytics (Track 1). **Plaintiff in Track 2** — source of confidential information; technical sessions and NDA Section 4 residuals clause at center of IP trade-secret claim. Under Northwind MSA Section 11, has right to request change-of-control consent from customer (actually subject to customer's veto). |
| 7 | Meridian Credit Partners, LP | Meridian Credit Partners, LP | Lender / First Lien Creditor (Track 1) | Provided $9.5M term loan (SOFR + 7.25%); holds first-priority lien on all assets including IP, source code, customer contracts; net leverage covenant breached (3.4x vs. 3.0x limit with no waiver); change of control = immediate default; may accelerate debt and foreclose on collateral without written consent |
| 8 | Northwind Retail Group | Northwind Retail Group | Anchor Customer – Contract Counterparty (Track 1) | Holds largest customer MSA ($4.2M annual subscription, ~41% of Cedar's recurring revenue); three consecutive months of SLA violations (99.4-99.6% actual vs. 99.9% target, below 99.5% termination-for-cause trigger); MSA Section 11 grants change-of-control consent right (withheld at sole discretion). Also referenced in Track 2 as competitive win for Aspen Devices v4 against HP. |
| 9 | State Agency | State agency (unnamed) | Government Regulator – Active Enforcement (Track 1) | Opened wage/hour audit in May 2026; Cedar has not yet produced records to regulator; regulatory exposure increasing over time |
| 10 | Sub-processor (Analytics Vendor) | Analytics vendor (India, unnamed) | Third-Party Service Provider (Track 1) | Added to Cedar's sub-processor list in 2025; does not appear on sub-processor list attachment to Northwind MSA – potential breach of Northwind Section 4 notice/objection rights |
| 11 | Sub-processor (Support Vendor) | Support vendor (Philippines, unnamed) | Third-Party Service Provider (Track 1) | Added to Cedar's sub-processor list in 2025; does not appear on sub-processor list attachment to Northwind MSA – potential breach of Northwind Section 4 notice/objection rights |
| 12 | Talbot Venture Partners | Talbot Venture Partners (fund entity) | Dual-Class Preferred Investor (Track 1) | Holds Series A preference (3,100,000 shares, 1x non-participating); holds Series B preference (1,250,000 shares, 2x non-participating + 8% cumulative dividend accruing since February 2025). Alignment with transaction terms uncertain given multiple series of preferences |
| 13 | Two Former Employees | Two (unnamed) former employees | Title Claimants / Equity Dispute Parties (Track 1) | Assert claims to 120,000 ungranted shares based on alleged verbal equity promises; no documentation in data room supporting or refuting claims |
| 14 | **Aspen Devices, Inc.** | Aspen Devices, Inc. | **Respondent Company (Track 2)** | **Defendant company in trade-secret action with HP. Developed Scheduler v4 with features allegedly derived from Harbor Peak technical sessions during Cedar evaluation course. Internal marketing states "closes the gap with Harbor Peak on ingest." Q2 Board deck confirms corporate awareness of "IP/contract risk from the HP evaluation period – legal is tracking."** |
| 15 | **Dana Ruiz** | Dana Ruiz (VP / Executive, Aspen Devices, Inc.) | **Key Corporate Actor (Track 2)** | Directed Marco Chen to sketch scheduler queue-partitioning design after Harbor Peak sessions. Instructed: "We're allowed to use what's in our heads. Build it, don't document where it came from." Requested removal of "Harbor Peak approach" citation from Marco's design memo (April 1, 2026). Asked Priya Anand on April 5 note how much documentation suffices for derivation write-up while prioritizing v4 ship date. |
| 16 | **Marco Chen** | Marco Chen (Engineer, Aspen Devices, Inc.) | **Core Individual Actor (Track 2)** | Attended Harbor Peak technical sessions during Cedar evaluation; received confidential info from second session on ingest queue partitioning methodology. Admitted sketch was "close to what they showed us in the second session." Authored Scheduler v4 Design Memo (April 2, 2026) after removing explicit HP reference at Dana's request; cites only incident reports INC-2291, INC-2304 for derivation. Privilege-requested legal advice from Priya Anand re: NDA residuals clause scope. |
| 17 | **Priya Anand** | Priya Anand, Esq. — VP Legal, Aspen Devices, Inc. | **Internal Counsel (Track 2)** | Received privileged attorney-client request from Marco Chen (March 13, 2026) re: NDA Section 4 residuals clause scope. Responded that clause is narrow — protects "unaided memory" only, with significant evidence burden on proving "unaided." Recommended documenting independent derivation path; cautioned against tracing to specific HP artifacts. Noting litigation exposure memo under preparation. CC'd by Dana Ruiz on April 5 internal note re the same matter. |
| 18 | **Kessler Data Consulting** | Kessler Data Consulting (third-party vendor) | **External Consultant – Counterparty Witness / Potential Discovery Target (Track 2)** | Billed $11,100 (May 30, 2026) for Scheduler v4 load testing (42 hrs x $185/hr = $7,770) and partition rebalancing analysis (18 hrs x $185/hr = $3,330). May serve as witness or discovery target on methodology independent of HP knowledge. |
| 19 | **Scheduler v4** | Scheduler v4 (Aspen Devices internal product/architecture artifact) | **Subject Technology Artifact (Track 2)** | Tenant-partition-before-dedupe scheduler architecture for event ingestion pipeline. Throughput +3.1x over v3; shipped June 2026. Competitive positioning explicitly references HP ("closes the gap," "similar shape, better price"). Design Memo author Marco Chen removed explicit HP citation on Dana Ruiz's directive (April 1). Official derivation basis: incident reports INC-2291, INC-2304 only. |
| 20 | **Harbor Peak Mutual NDA** | Confidentiality Agreement — Harbor Peak Systems, LLC and Aspen Devices, Inc. (via Cedar evaluation channel) | **Governing Instrument – Track 2** | NDA Section 4 contains residuals clause permitting use of knowledge in "unaided memory" after confidential relationship ends; does not protect derived knowledge from HP written materials or session content. Source: Marco Chen privileged legal request; Priya Anand's privileged response characterizing scope as narrower than Aspen assumed. Prior-art artifact at issue: second HP session on ingest queue partitioning methodology. |

---

## 2. Key Contractual Instruments & Capital Structure
### A. Master Services Agreement — Cedar Analytics x Northwind Retail Group (Effective March 3, 2024)
- **Term & Scope:** Three years + auto-renewing yearly terms; $4.2M annual subscription, invoiced quarterly in advance.
- **SLA / Availability:** 99.9% target; credit remedy capped at 30%; termination-for-cause if three consecutive months below 99.5%. 
- **Assignment & Change of Control — Section 11:** Neither party may assign without prior written consent, explicitly includes M&A/sales of assets/equity. Violation = void assignment + material breach.
- **Provisions (Misc):** Most-Favored-Customer pricing (Section 12) is uncapped; Limitation of Liability cap excludes confidentiality, indemnities, and Section 12 breaches. Law: NY.

### B. Loan and Security Agreement — Cedar Analytics x Meridian Credit Partners, LP (August 14, 2025)
- **Principal + Interest:** $9.5M term loan at SOFR + 7.25%, interest-only through August 2026.
- **Security – Section 5:** First-priority lien on ALL assets incl. IP, source code, customer contracts; UCC-1 filed.
- **Covenants – Max Leverage:** Net leverage capped at 3.0x; Q2 reports 3.4x (breach/technical default); no waiver on file.
- **Change of Control — Section 9:** COI = immediate event of default unless lender consents in writing at least 30 days prior.

### C. Capitalization Summary as of June 30, 2026
| Class | Holder | Shares | % Fully Diluted | Preference / Rights |
|-------|--------|--------|-----------------|---------------------|
| Common | Founders (3) | 6.4M | 42.1% | Standard common |
| Series A Preferred | Talbot Venture Partners | 3.1M | 20.4% | 1x non-participating |
| Series B Preferred | Talbot VC Partners | 1.25M | 8.2% | 2x non-participating + 8% accruing dividend (since Feb 2025) |
| Series B Preferred | Greyfield Capital | 2.05M | 13.5% | 2x non-participating + 8%; Protective provision = majority Series B approval for COI |
| Options (Granted) | Employees | 1.85M | 12.2% | No restrictions related to Track 2 |
| Options (Pool, ungranted)| Reserved | 0.55M | 3.6% | Standard post-grant / hiring pool |

### D. Harbor Peak Mutual NDA — Governing Instrument for Track 2 Claims
- **Parties:** Harbor Peak Systems x Aspen Devices (via Cedar evaluation channel)
- **Section 4 Residuals Clause:** Permits use of knowledge retained in "unaided memory" after end of confidential relationship; does NOT protect derived knowledge from HP written materials or session content.
- **Litigation Significance:** Priya Anand's privileged legal advice characterizes clause as narrower than Aspen assumed. Core disputes: Marco Chen design as unaided vs derivative; Dana Ruiz suppression directive undermining independent-derivation defense.

---

## 3. Revised Chronology of Risk Events
### Track 1 — Cedar Analytics Due Diligence (Pre-existing)
- **January 2023:** DPA v1.0 executed with deprecated EU-US Privacy Shield (Schrems II risk).
- **October/November 2024:** 409A Valuation performed; options later granted March 2026 using stale valuation.
- **Jan – Jun 2024 / Feb 2025:** Cedar hires 11 employees without IP Assignment Agreements and engages 11 contractors without IP assignment agreements (Core tech gaps). Series B preferred dividends begin accruing at 8%.
- **August 2025:** Loan closing ($9.5M) + UCC-1 filed on all assets incl unassigned IP work product.
- **April – May 2026:** Former employee demands unpaid overtime + State wage-and-hour audit opened; records withheld.
- **Q2 2026:** Net leverage breached (3.4x vs 3.0x cap). Three months of availability at ~99.4% triggers Northwind termination threshold.
- **June 2026:** Cap Table Snapshot: Greyfield majority control of Series B with COI block + Scheduler v4 ships to market. 
- **July 2026 (Current):** Track 1 diligence active. Critical path items identified.

### Track 2 — HP v AD IP Litigation (New from Discovery Batch)
- **February – March 2026:** Aspen Devices attends Harbor Peak technical sessions during Cedar evaluation; Marco Chen specifically attends second HP session on queue-partitioning methodology, receives confidential info under mutual NDA.
- **March 12, 2026 — Email Thread (Doc 001):** Dana Ruiz emails Marco Chen encouraging "partitioning by tenant before the dedupe" from HP sessions. Instructs: "**Build it, don't document where it came from.**" Marco expresses discomfort building "straight from memory," asks legal on residuals clause line.
- **March 13, 2026 — Privileged Legal Email (Doc 002):** Marco Chen to VP Legal Priya Anand: Priya responds that "**unaided** is doing a lot of work" per her advice advising documenting independent derivation path and avoiding anything tracing to specific HP artifacts. Notes preparing litigation exposure memo.
- **April 1, 2026 — Design Memo Redaction:** "Harbor Peak approach" citation removed from Dana's request; Marco Chen draft on Marco Chen design memo approved for implementation.
- **April 2, 2026 — Approved Design Memo (Doc 003):** Marco Chen design memo approved: scheduler tenant-partition-before-dedupe; risks mitigated by idempotency keys.
- **April 5, 2026 — Note to Counsel (Doc 006):** Dana Ruiz notes how much "incident-report framing" is sufficient -- shows corporate consciousness at senior level.
- **May 30, 2026 — Third-Party Invoice (Doc 005):** Kessler Data Consulting invoices $11,100 for scheduler v4 load testing + partition rebalancing analysis; timing coincides with pre-launch validation.
- **Q2 2026 — Board Deck (Doc 004):** Corporate acknowledgment of "**IP/contract risk from the HP evaluation period – legal is tracking**." Competitively frames Scheduler v4 at HP product level. Two competitive wins directly vs HP in Q2.
- **June 2026: Scheduler v4 Ships to Market** — +3.1x throughput; competitive positioning against HP publicly confirmed.

---

## 4. Overall Assessment & Action Plan
### Track 1 — Cedar Analytics Due Diligence (Pre-existing)
#### Critical Blockers (Deal Breakers)
1. **Change-of-Control/Assignment Consent:** Northwind MSA (Section 11) requires written consent; Meridian Loan (Section 9) triggers immediate default on COI.
2. **IP Ownership Defects:** 11 new employees and *all* contractors lack PIIAs covering core tech (ingestion pipeline/scheduler).
3. **Capitalization Obstacles:** Greyfield holds a formal veto over any merger via Series B Protective Provision; informal demand for cashed-out liquidation preference at closing.

#### High-Risk Issues
1. Northwind SLA Breach & Termination Right: Under active termination trigger per Section 7.
2. Unpaid Debt Liabilities: $9.5M debt secured by IP and all assets; acceleration risk without cure/consent.
3. Privacy/Transfer Frameworks: DPA relies on invalidated US-EU Privacy Shield.

#### Immediate Next Steps (Track 1)
1. Obtain signed waivers/consents from Greyfield Capital (Series B) and formal assignment consent/novation negotiation with Northwind Retail Group (MSA).
2. Negotiate Meridian Credit Partners' 30-day advance waiver for leverage breach and COI default, potentially via bridge financing.
3. Execute retroactive PIIA agreements for the 11 affected employees; engage contractors in IP assignment or establish escrow holdback based on technology audit.
4. Require Cedar to update DPA from Privacy Shield to EU SCCs before closing.

---

### Track 2 — HP v AD IP Litigation / Trade-Secret Defense (NEW)
#### Critical Issues
1. **Dana Ruiz Directive vs Residuals Clause:** Dana's instruction to "don't document where it came from" suggests conscious suppression of confirmatory/denying documentation -- highly damaging if drafts surface in discovery or litigation.
2. **Design Not Truly "Unaided":** Marco Chen admitted his design was "**close to what they showed us in the second session**"; combined with removed HP citation and Priya Anand's confirmation of narrow residuals-clause scope -- potentially dispositive for trade-secret misappropriation liability.
3. **Corporate Awareness & Evidence-Suppression Risk:** Board deck "legal is tracking" risk disclosure + Dana's suppression directive = corporate consciousness of IP exposure while proceeding anyway -- potentially aggravates punitive-damages analysis.
4. **Competitive-Framing Contradicts Independent Derivation:** Marketing materials stating v4 "closes the gap Harbor Peak on ingest" and demos noted as "**similar shape, better price** directly undermine any truly independent-derivation defense from incident reports alone.

#### High-Risk Issues
1. **Priya Anand's Preparatory Exposure Memo:** Priya preparing litigation exposure memo; that work product may itself be discoverable per "legal is tracking" disclosure.
2. **Kessler Data Consulting Engagement:** Third-party in partition-rebalancing analysis; could serve as independent-derivation witness but also opens scope for methodology discovery.
3. **Ship-vs-Cleanup Tension:** Dana's preference to ship rather than revise derivation write-up shows prioritization of timeline over IP-risk remediation -- aggravating factor.

#### Immediate Next Steps (Track 2)
1. **Preserve All Drafts Under Litigation Hold:** Secure Marco Chen's pre-April-1 design memo version(s) citing "Harbor Peak approach" as prior art; immediately preserve to avoid spoliation consequences.
2. **Privilege Audit on Counsel Communications:** Confirm scope of communications with Priya Anand -- both March 13 privileged email and April 5 note (CC'd counsel). Evaluate whether April 5 note is protected work product or potentially discoverable.
3. **Independent-Derivation Defense Documentation (If Proceeding):** If advancing as formal defense, require Marco Chen and Dana Ruiz to provide detailed timelines documenting all independent research/design inputs between Feb-June 2026 per Priya Anand's "document independent derivation path" recommendation.
4. **Assess Competitive-Framing Discovery Exposure:** Evaluate sales/marketing materials ("similar shape," direct wins vs HP) for litigation discovery exposure; may support willfulness in damages analysis under applicable statute (e.g., DTSA).
5. **Evaluate Insurance/Indemnity Position:** Verify whether Aspen Devices D&O insurance or IP indemnity provisions cover trade-secret claims related to Scheduler v4 competitive features derived from HP sessions.

---

## 5. Document Source Map
### Track 1 / Deal Room Documents (Cedar Analytics Due Diligence)
| Doc | Fixture Path | Summary Focus | Status |
|-----|-------------|------------|--------|
| README | fixtures/dealroom/README.md | Synthetic deal room context / Buyer-side set reference | Cataloged |
| D-001 | fixtures/dealroom/01-msa-northwind.md | Northwind MSA; SLA breaches, Section 11 COI consent/unrestricted termination rights | Reviewed |
| D-002 | fixtures/dealroom/02-loan-security-agreement.md | Meridian Loan Agreement; leverage breach, IP collateral pledge, COI default risk | Reviewed |
| D-003 | fixtures/dealroom/03-cap-table-summary.md | Cedar Cap Table incl Series B protective provisions; Greyfield dominance; former equity claims | Reviewed |
| D-004 | fixtures/dealroom/04-employment-ip-memo.md | PIIAA gaps for 11 employees + all contractors; wage/hour audit exposure | Reviewed |
| D-005 | fixtures/dealroom/05-data-processing-addendum.md | Deprecated Privacy Shield, deletion/carve-outs; missing Northwind sub-processors on list | Reviewed |

---

### Track 2 / Discovery Documents (HP v AD IP Litigation)
| Doc | Fixture Path | Summary Focus | Status |
|-----|-------------|------------|--------|
| **001** | fixtures/discovery/001-email-pipeline-thread.md | Dana Ruiz -> Marco Chen email thread (March 12, 2026): Encourages implementing queue-partitioning design inspired by HP sessions; instructs "Build it, don't document where it came from." Shows Dana's intent to suppress provenance documentation. | **Reviewed** |
| **002** | fixtures/discovery/002-email-counsel-advice.md | Marco Chen -> Priya Anand privileged legal email (March 13, 2026): Attorney-client communication re: Section 4 residuals clause scope. Priya advises clause is narrow -- protects unaided memory only; "unaided" bears heavy evidentiary burden; recommends documenting independent derivation. Notes preparing litigation exposure memo. | **Privileged / Att.-Client** |
| **003** | fixtures/discovery/003-design-memo.md | Marco Chen Design Memo (April 2, 2026): Scheduler v4 tenant-partition-before-dedupe architecture. Originally cited "Harbor Peak approach"; explicit HP reference removed April 1 per Dana Ruiz request; final version cites only incident reports INC-2291, INC-2304 as derivation basis. Approved for implementation. | **Reviewed** |
| **004** | fixtures/discovery/004-board-deck-excerpt.md | Aspen Devices Q2 2026 Board Deck excerpts: Scheduler v4 +3.1x throughput; competitive wins directly from HP; risk disclosure acknowledging "IP/contract risk from the HP evaluation period – legal is tracking." | **Reviewed** |
| **005** | fixtures/discovery/005-invoice.md | Kessler Data Consulting invoice (May 30, 2026): $11,100 for scheduler v4 load testing (42 hrs x $185/hr = $7,770) and partition rebalancing analysis (18 hrs x $185/hr = $3,330). Available as third-party witness/target. | **Reviewed** |
| **006** | fixtures/discovery/006-note-copied-to-counsel.md | Dana Ruiz note to Marco Chen, CC Priya Anand (April 5, 2026): Discusses v4 ship date slippage risk if derivation write-up redone; asks Priya how much documentation suffices for derivation write-up. Shows corporate consciousness of IP risk, prioritizing timeline over remediation. | **Reviewed** |
| **007** | fixtures/discovery/README.md | Synthetic discovery corpus description: Six Aspen Devices documents (emails, design memo, board deck excerpt, note to counsel, invoice) deliberately including privileged, non-privileged, and borderline items. | **Cataloged** |

---

# Timeline — Harbor Peak v. Aspen Devices
**Matter ID:** HP-v-AD-2026-001  
**Subject:** Misappropriation of Confidential Information / Breach of Mutual NDA – Technical Evaluation Period  
**Prepared from:** Discovery corpus (fixtures/discovery/), 5 documents produced from Aspen Devices' files  

---

## Chronology

### January–March 2026 — Pre-Sessions
- **~Early March 2026:** Marco Chen attends a series of "Harbor Peak technical sessions" as part of Aspen Devices' product evaluation. No written materials are received; knowledge is retained in memory. Dana Ruiz (VP Product) also participates in or reviews session content (implied by subsequent communications).

### March 2026 — Critical Period
| Date | Event | Source |
|------|-------|--------|
| **March 12, 2026** | Dana Ruiz emails Marco Chen: "after the Harbor Peak sessions I keep coming back to how they shard the ingest queue … Can you sketch what that looks like in our scheduler?" Ruiz encourages implementation using retained knowledge but advises *not* documenting the source. | Email Thread (Doc 1) |
| **March 12, 2026** | Marco Chen responds: design is "close to what they showed us." expresses concern about building from memory alone and raises residuals clause question. | Email Thread (Doc 1) |
| **March 13, 2026** | Marco Chen sends *privileged* email to VP Legal Priya Anand (CC Dana Ruiz): asks whether the mutual NDA's residual clause permits engineers to implement a queue-partitioning design retained from memory of Harbor Peak sessions. | Privileged Email (Doc 2) |
| **March 13, 2026** | Priya Anand advises Marco and Dana: residuals clause is narrower than assumed — protects "unaided memory" only; recommends (1) documenting an independent derivation path and (2) avoiding implementation that traces to specific Harbor Peak artifacts. States she is preparing a memo on litigation exposure. | Privileged Email (Doc 2) |

### April 2026 — Design & Internal Risk Management
| Date | Event | Source |
|------|-------|--------|
| **April 1, 2026** | Dana Ruiz requests removal of the "Harbor Peak approach" citation from an earlier draft of Marco Chen's design memo. The removed reference had cited Harbor Peak as prior art for tenant partitioning. | Design Memo (Doc 3) |
| **April 2, 2026** | Marco Chen's Scheduler v4 design memo is approved for implementation. Derivation section cites Aspen's own incident reports (INC-2291, INC-2304). The memo explicitly notes: "An earlier draft of this memo cited 'the Harbor Peak approach' as prior art; that line was removed on 2026-04-01 at the request of D. Ruiz." | Design Memo (Doc 3) |
| **April 5, 2026** | Dana Ruiz sends note to Marco Chen with Priya Anand CC'd: v4 ship date would slip to June if the team stops to redo an independent-derivation write-up and she "would rather ship." Asks Priya whether incident-report framing is sufficient documentation. Note states it is being copied per Priya's request. | Internal Memo (Doc 6) |

### May 2026 — Validation Work
| Date | Event | Source |
|------|-------|--------|
| **May 30, 2026** | Kessler Data Consulting submits invoice for Scheduler v4 load testing (42 hrs) and partition rebalancing analysis (18 hrs), totaling $11,100. Work validates the new tenant-partitioning architecture. | Invoice (Doc 5) |

### June / Q2 2026 — Launch & Competitive Impact
| Date | Event | Source |
|------|-------|--------|
| **June 2026** | Scheduler v4 ships. Achieves +3.1x throughput over v3. Board deck excerpt states: "Closes the gap with Harbor Peak on ingest, which was our biggest competitive loss reason in 2025." | Board Deck (Doc 4) |
| **Q2 2026** | Aspen Devices wins two deals from Harbor Peak — Northwind pilot and Cedar evaluation. Sales note: "v4 architecture demos well against HP — similar shape, better price." | Board Deck (Doc 4) |
| **Q2 2026** | Board deck Slide 21 (Risks): "IP/contract risk from the HP evaluation period — legal is tracking." Legal's post-departure memo referenced in March email (Priya Anand, Doc 2) presumably underlies this disclosure. | Board Deck (Doc 4) |

---

## Issue Timeline Summary

```
Jan/Feb     ●         Harbor Peak evaluation program begins
              \
Mar 12        ● Ruiz → Chen: build on memory of HP sessions; don't document source
Mar 13        ● Chen → Anand [PRIV]: residuals clause question
              ● Anand [PRIV]: narrow reading; document independent derivation
Apr 1         ● Ruiz removes "Harbor Peak approach" citation from design memo draft
Apr 2         ● Chen's approved memo cites internal incident reports as derivation path
Apr 5         ● Ruiz → Chen (CC Anand): push back on delaying ship for write-up
May 30        ● Third-party validation of scheduler v4 partitioning architecture
Jun / Q2      ● Scheduler v4 ships; closes competitive gap with HP
              ● Two HP deals won in Q2 ("similar shape" sales note)
              ● Legal risk disclosure to board
```

## Key Issues for Harbor Peak's Claim

1. **Residuals Clause Scope:** Under the mutual NDA, Aspen claims protection for "unaided memory." Priya Anand's privileged advice suggests this narrow reading but does not foreclose liability if independent derivation cannot be credibly shown.

2. **Obfuscation of Derivation Source:** The removal of "Harbor Peak approach" from the design memo draft at Ruiz's direction suggests an affirmative effort to sever the documented provenance chain from Harbor Peak sessions, which is a significant risk factor for any misappropriation claim.

3. **"Similar Shape" Architecture:** The external communications (board deck sales note) admit Scheduler v4 architecture closely mirrors Harbor Peak's ingest pipeline design ("similar shape"), raising independent-examination questions about whether the claimed independent derivation through incident reports INC-2291/INC-2304 is substantively credible.

4. **Competitive Timing:** Ship + HP deal wins in Q2 2026 immediately following technical sessions places timeline of causation within Harbor Peak's window of protection (typically 12–24 months post-NDA).

---

## Document Index (Discovery Batch)

| # | Doc Name | Date Issued/Contained Within | Privilege Status | Relevance to Claim |
|---|----------|------------------------------|------------------|--------------------|
| 1 | 001-email-pipeline-thread.md | March 12, 2026 | Non-privileged | Ruiz's direction to bypass documentation; core evidence of intent |
| 2 | 002-email-counsel-advice.md | March 13, 2026 | Attorney-client privileged (claimed) | Counsel's narrow reading of residuals clause; litigation-exposure memo trigger |
| 3 | 003-design-memo.md | April 2, 2026 (draft revision Apr 1) | Non-privileged | Redacted provenance; "independent derivation" justification via INC #s |
| 4 | 004-board-deck-excerpt.md | June / Q2 2026 | Non-privileged (board-facing) | Admissions of competitive overlap, legal risk tracking, and IP/contract exposure |
| 5 | 005-invoice.md | May 30, 2026 | Non-privileged | Confirms third-party validation of claimed architectural changes |
| 6 | 006-note-copied-to-counsel.md | April 5, 2026 | Borderline (legal CC'd) | Demonstrates management prioritization of ship date over documentation adequacy |

*Timeline constructed from Aspen Devices discovery corpus. Attorney-client privileged communications are flagged but do not affect the underlying factual chronology.*