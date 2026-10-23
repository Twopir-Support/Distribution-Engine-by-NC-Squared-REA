# Evidence and Gaps

## 1. How we investigated

| Step | Tool | Result |
|---|---|---|
| Read the REA skill | `rea-agents@6.7.0` (registered in `.mcp.json`), skill `reverse-engineer-anything` v42 | The skill routes "browser action the agent must perform" to `capture_browser_scenario`. |
| Capture the AppExchange listing | REA `capture_browser_scenario`, launch mode, headless Chromium (`/opt/pw-browsers/chromium-1243`) | Evidence `ev_9e5476b4c256a669f9e7039e5adfb6c8207755ecd04d6eb60795f9724acf2cea`: overview screenshot and accessibility tree. |
| Capture listing tabs (DOM) | REA `capture_browser_scenario` with clicks on Specs, Resources and Support | Evidence `ev_10eb86227b42752ee8c8d6c4031c05108115ca8379c88572ef1bd97a71efbcc0`. The serialised DOM held only the cookie banner, because the listing renders inside shadow roots. Recorded as REA unknown `unk_fdbe68cd…`. |
| Capture listing tabs (screenshots) | REA `capture_browser_scenario`, screenshot after each step | Evidence `ev_4f65011bb6e66d8af250173a8e53e564d938ca17662e8a616e5eaa4509c59803`. Screenshots are in `docs/evidence/`. |
| Read public documentation | WebSearch and WebFetch, run by a research sub-agent | `help.distributionengine.com`: the sitemap lists 354 URLs. All 311 Distribution Engine articles were fetched as text and the core ones were read in full. |
| Record runtime unknown | REA `record_unknown` | `unk_96b473a6…`: the package's runtime behaviour was not observable. |
| Export the evidence bundle | REA `export_evidence_bundle` | 3 records, 7.2 MB. It is kept outside the repository because of its size. The Evidence IDs above make it reproducible. |

**Authorised running instance.** None was available.

- The environment has no Salesforce org, sandbox or trial credentials.
- We did not attempt to sign up for a trial, log in, or bypass any authentication, licensing or managed-package protection.
- The managed package (`n2de` namespace) cannot be inspected. REA can analyse shipped artifacts, but there is no downloadable artifact for a managed Salesforce package, and its Apex is obfuscated and hidden from subscribers.

**What REA could and could not do here.**

- REA can drive and observe a browser. That is how the listing was captured.
- REA cannot inspect a SaaS backend.
- Without an authorised org running the package, it could not observe routing behaviour.
- Everything about behaviour therefore comes from the vendor's public documentation.

## 2. Confidence by feature group

| Group | Features | Confidence | Why |
|---|---|---|---|
| Listing facts (package contents, compatibility, positioning claims) | F60 and the listing facts | **Verified** | Observed by REA on the live listing on 2026-10-23. |
| Teams, distributors, methods, caps, weighting, sticky | F01–F21 | **Partially verified** | Explicit vendor documentation. Runtime not observed. |
| Availability | F27–F34 | **Partially verified** | Explicit vendor documentation. |
| Classifier | F35–F40 | **Partially verified** | Explicit vendor documentation. The interactive map UI is described but was not seen. |
| SLA, reassign, rejection, tracking | F41–F45 | **Partially verified** | Explicit vendor documentation. |
| Console, logs, analytics, simulator | F48–F54 | **Partially verified** | Screen structure is documented; screenshots are not available as text. |
| Pre-breach warnings and manager escalation chains | Part of F42/F43 | **Inferred** | These appear only on marketing pages (M). Our checkpoints make them configurable. |
| Integration with Salesforce Enterprise Territory Management | Part of F35 | **Unverified / contradicted** | The listing claims it works with Enterprise Territory Management. The help centre says territories work "without relying on Salesforce Enterprise Territory Management". |

## 3. Where our implementation intentionally differs

| Topic | Reference (documented) | Ours | Reason |
|---|---|---|---|
| Territory definition | Interactive clickable map of countries, states and postcodes, with country, state and postcode zoom for 6 countries | Lists of countries, states and postcodes (prefixes and ranges), plus conditions and paste import | No map dataset can be shipped clean-room. The classification result is equivalent. |
| Lead matching engine | Uses Salesforce Duplicate and Matching Rules | Built-in domain, normalised-name (Jaro-Winkler) and email matching, configurable per rule | Duplicate and Matching rules cannot be deployed generically or evaluated in batch from Apex for this purpose. **Inferred equivalent.** |
| Shifts | Up to 3 blocks per day, with a shift planner 12 weeks ahead | Up to 3 blocks per day. No dated shift planner. | Gap F33. |
| On-hold thresholds | Not documented | Configurable: `Hold_After_Failures__c` (default 10) and `Hold_Minutes__c` (default 60) | Unknown values. |
| Distribution after insert | Scheduler only (about 1 minute); triggers fire on update | Also distributes immediately after classification (optional setting) | Better speed-to-lead. The setting can be turned off to match the reference. |
| Pull availability | Not documented | Pull does not require the user to be online | The user is actively asking for work. |
| Licensing | Per-member licences | None | Independent build, not an ISV package. |
| Distribution Engine Details | Lookup field on each record to the details object | Details keyed by `Record_Id__c`. Filters use `DE.*` pseudo-paths. | Avoids extra DML in insert triggers and works for any object. |

## 4. Open questions and unresolved items

1. **Exact round robin tie-break** when several members have never been assigned. The documentation does not say. We use member record Name.
2. **Weighting cycle maths.** The documentation gives examples (2 = twice per cycle; 0.5 = every other cycle) but no algorithm. We implemented credit-based cycles that reproduce those examples. The behaviour when eligibility changes in the middle of a cycle is unknown.
3. **Load balancing tie-break** is unknown. We fall back to round robin order.
4. **On-hold thresholds**: see section 3.
5. **Whether Pull respects caps** is not explicit. We respect caps.
6. **SLA "Continuous Field Monitoring" frequency** is unknown. We check every scheduler run.
7. **Email template content** is only partly documented (the fields are listed). Ours is a plain-text summary built from the same fields.
8. **Analytics chart definitions and team performance formulas** (for example "Distribution Fidelity") are not defined. We implement the metrics whose meaning is clear, and leave out Distribution Fidelity.
9. **The internal data model** (92 custom objects) is not public. Ours is independent and smaller (22 objects plus 1 platform event).

## 5. Features we could not inspect or did not implement

See `parity-matrix.md` for the current status of each item.

- **F26 Role Assignment** (team roles on Account, Case and Opportunity): not implemented.
- **F33 Shift Planner**: not implemented.
- **F39 Delay Filters**: not implemented as a separate feature. The same effect comes from a distributor filter on `CreatedDate` with a relative value (for example `less than` "5 minutes ago"), which is the vendor's own recommendation in H/setup-examples/delaying-distribution.
- **F45 Slack notifications**: not implemented. In-app notifications, email and platform events are implemented.
- **F62 Licensing**: not applicable.
- **F63 Personas / Custom Team Manager**: not implemented. Four fixed permission sets cover the documented standard roles.
- **F64 InsideSales and Pardot integrations**: not implemented.
- **Install Guide, Setup Guide, whitepaper, datasheets and case studies** linked from the listing: only their titles were captured.
- **Demo video** ("Watch Demo"): not viewed. No transcript was available.

## 6. Validation environment limits

- **No Salesforce org** was available, so Apex tests could not be executed and no deployment could be attempted. We did not claim either.
- **Offline validation we did run:**
  - Salesforce CLI source conversion to Metadata API format.
  - apex-ls 6.4.0 `CheckForIssues`, which does semantic type-checking of Apex against the project's own metadata and the platform's standard types.
  - PMD 7.7.0 Apex rules.
  - Prettier Apex parse.
  - ESLint and Jest for the LWC components.

  Results are recorded in `parity-matrix.md` and `docs/progress-log.md`.
