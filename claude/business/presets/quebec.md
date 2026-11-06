# Preset: Quebec (QC)

Paste the block below into your project's `CLAUDE.md` (replacing the generic `## Business` block),
then fill the `<…>` fields. Every number and rule here comes from the pack's
[facts register](../README.md#facts-register); the skills re-check those sources before relying on
them.

```markdown
## Business
- Province: QC
- Language: French first for anything consumer-facing (website, invoices and receipts to
  consumers, contracts of adhesion, catalogues, ads, signage); English version alongside is fine
- Entity: <sole proprietor | corporation (federal | Quebec)>
- Legal name / operating name: <…> / <…>    # Quebec: the name generally needs a French version (unverified here; check with the OQLF)
- Mailing address: <…>
- Contact for CASL identification: <phone | email | web>
- Unsubscribe: <link or reply address>, processed by <who> within 10 business days
- Sales taxes: GST 5% + QST 9.975% (QST on the price excluding GST)
- GST account: <123456789 RT0001 | not registered (small supplier, under $30,000)>
- QST number: <from Revenu Québec | not registered>
- Tax administrator: Revenu Québec (GST and QST in Quebec)
- Fiscal year end: <MM-DD>  ·  Reporting period: <monthly | quarterly | annual>
- Privacy officer (Law 25): <title, contact>, published on the website
```

## What Quebec changes in each skill

| Skill | Quebec behaviour |
|---|---|
| `finance-ops` | invoices carry both GST and QST lines and both numbers once registered; the filing calendar includes QST |
| `brand-voice` | `bilingual` mode is on: French drafted first, then English |
| `legal-drafts` | the privacy policy follows Law 25 (privacy officer, incident register, privacy impact assessments, portability); consumer documents are French first |
| `sales-outreach` | the CASL gate is federal and identical; outreach to Quebec consumers is in French |
| `support-triage` | privacy incidents go to the privacy officer, and the Law 25 incident register is updated |

## Before you rely on it

- Re-check the "indexed text" facts in the register in a browser. Revenu Québec, LégisQuébec and
  the OQLF block automated reading, so those were read through search results.
- Confirm with your accountant: when to register for QST and GST if you're under $30,000, your
  reporting period, and which expenses are deductible.
- Confirm with a Quebec lawyer: your privacy policy, terms and contracts (civil law, not common law).
