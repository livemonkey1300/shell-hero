# Business pack (Canada)

Five skills and one adviser agent that run the admin side of a solo or small company in Canada:
books and sales tax, outbound sales under CASL, brand voice in English and French, support
triage, and first drafts of the legal documents every business needs. Phase 2 of this kit; the
engineering pack is in [`../README.md`](../README.md).

> **Not legal, tax or accounting advice.** These skills draft, calculate and check. A Canadian
> accountant and a lawyer licensed in your province review anything that matters before you rely
> on it. The legal facts below were checked against public sources in November 2026; **rates,
> thresholds and rules change**, and every skill re-checks its sources before using a number.

## What's in it

| Item | What it does | Never does |
|---|---|---|
| `finance-ops` (skill) | Chart of accounts, categorize transactions, monthly close, runway, invoices with the right GST/HST/QST lines and registration numbers, filing calendar, receipt rules; spreadsheets via the `xlsx` skill if you have it | move money, file with the CRA or Revenu Québec, invent a number |
| `sales-outreach` (skill) | ICP, prospect lists from consented or business-published sources, sequences, objection log, CRM hygiene, with a **CASL gate** that blocks drafting until a consent basis is recorded | send, harvest or guess addresses, scrape against a platform's terms, use bought lists |
| `brand-voice` (skill) | Voice and tone, messaging pillars, style sheet, line-by-line copy review for "AI slop", English/French for Quebec | publish, invent proof, treat machine French as final |
| `support-triage` (skill) | Redacts a ticket CSV, then mines themes ranked by cost, writes macros, sets escalation including a privacy-incident path | reply to customers, touch the help desk, decide a breach is not reportable |
| `legal-drafts` (skill) | Privacy policy (PIPEDA / Law 25), website terms, contractor checklist, CASL policy, NDA review — every output bannered as a draft for a lawyer | give advice, call anything compliant, sign or send |
| `launch-kit` (skill) | Positioning, taglines, launch-day timeline and copy for Product Hunt, itch.io, Show HN, newsletters; emails through the sales-outreach CASL gate | post, send, trade votes, use sockpuppets or undisclosed paid endorsements |
| `blog-post` (skill) | One reader, one question: researched outline and draft with every claim cited, brand-voice review, publishing checklist | publish, scrape behind logins, quote customers without written permission |
| `store-review` (skill) | Order/sales/returns CSVs → one-page review: revenue, AOV, repeat rate, cohorts, returns, margin, three ranked actions; computed by script on redacted data | keep personal info in the analysis, scrape competitors, file taxes |
| `business-advisor` (agent) | Pricing, unit economics, runway, federal vs provincial incorporation, what to do first; one recommendation, one-way doors flagged; routes to the skills and to the technical role agents | edit files, act, settle tax or legal questions |

## Scope: Canada, every province, Quebec in detail

Skills read a `<PROVINCE>` setting. Federal rules (GST/HST, CASL, PIPEDA) apply everywhere;
provincial differences are flagged where they were verified. **Quebec gets explicit treatment**
because it differs most: QST administered by Revenu Québec, Law 25 for privacy, and the Charter
of the French language (as amended by Bill 96, now Law 14) for commercial documents, websites,
contracts and signs. Alberta and British Columbia have their own private-sector privacy laws;
their specifics were **not** verified and are flagged for counsel.

Put this in your project's `CLAUDE.md` so every skill finds it without asking:

```markdown
## Business
- Province: <PROVINCE>                # e.g. QC, ON, BC
- Entity: <sole proprietor | corporation (federal | provincial)>
- Legal name / operating name: <…> / <…>
- Mailing address: <…>
- Contact for CASL identification: <phone | email | web>
- Unsubscribe: <link or reply address>, processed by <who>
- GST/HST account: <123456789 RT0001 | not registered (small supplier)>
- QST number: <from Revenu Québec, Quebec only>
- Fiscal year end: <MM-DD>  ·  GST/HST reporting period: <monthly | quarterly | annual>
- Privacy officer: <title, contact>
```

## Install

```sh
claude/install.sh --pack business                         # into ~/.claude
claude/install.sh --pack business --project ~/code/my-co  # or into a project
```
Or ask Claude in this repo: *"set me up with the business pack"*.

**In Quebec?** Start from [`presets/quebec.md`](presets/quebec.md): GST + QST, Revenu Québec,
Law 25 and French-first documents, already filled in.

## Your first week, using the pack

**Day 1 — decide the shape.** Ask `business-advisor`: *"Sole proprietor or corporation, and
federal or provincial? I sell to <where>."* It gives one recommendation with the verified facts
(name protection, extra-provincial registration, the $30,000 GST/HST threshold) and the exact
questions for your accountant and lawyer. Book those two calls; incorporation is a one-way door.

**Day 2 — set up the books.** `/finance-ops accounts`, then `/finance-ops tax-calendar` once you
know your registration status and reporting period. Fill the `## Business` block above. Decide
whether to register for GST/HST (and QST in Quebec) voluntarily before $30,000 — ask your
accountant.

**Day 3 — say who you are.** `/brand-voice define`, then `pillars`. If you will sell in Quebec,
`/brand-voice bilingual` — French for the website, invoices to consumers and contracts of
adhesion is not optional there.

**Day 4 — the documents a website needs.** `/legal-drafts privacy-policy` (it inventories what
your site actually collects first), `/legal-drafts terms`, `/legal-drafts casl-policy`. Appoint
your privacy officer (in Quebec, publish their title and contact on the site). Send all three
drafts to a lawyer.

**Day 5 — first customers.** `/sales-outreach icp`, then `prospects` from sources where people
asked to hear from you or published a business address for that purpose, then `sequence`. The
CASL gate tells you who you may email and drafts a consent request for the rest.

**Every month.** `/finance-ops close <YYYY-MM>`. When tickets arrive, `/support-triage themes
<export.csv>` and `escalation`.

## Facts register

Each skill carries the facts it uses, with the same source; this is the full list. "Indexed text"
means the official page was read through the search engine's copy because the site refused
automated fetching; re-check those first. **Checked 2026-11.**

### Sales tax and the CRA

| Fact | Source | Status |
|---|---|---|
| GST 5% (AB, BC, MB, NT, NU, QC, SK, YT); HST ON 13%, NB/NL/PE 15%, NS 14% from 2025-04-01 | https://www.canada.ca/en/revenue-agency/services/tax/businesses/topics/gst-hst-businesses/charge-collect-which-rate/calculator.html | verified |
| Provincial sales tax per the CRA table: BC 7%, MB 7%, SK 6%, QC QST 9.975% | same | verified |
| QST 9.975% on the price excluding GST | https://www.revenuquebec.ca/en/businesses/consumption-taxes/gsthst-and-qst/basic-rules-for-applying-the-gsthst-and-qst/ | verified (indexed text) |
| Small supplier $30,000 over four quarters; single-quarter rule; register within 29 days | https://www.canada.ca/en/revenue-agency/services/tax/businesses/topics/gst-hst-businesses/when-register-charge.html | verified |
| Same $30,000 test for QST; Quebec businesses register for GST/HST and QST with Revenu Québec | https://www.revenuquebec.ca/en/citizens/consumption-taxes/taxable-zero-rated-or-tax-exempt-goods-and-services/gst-and-qst/other-situations/small-suppliers/ · https://www.revenuquebec.ca/en/businesses/life-cycle/starting-a-business/registering-with-revenu-quebec/ | verified (indexed text) |
| GST/HST due: monthly/quarterly 1 month after period; annual 3 months after year-end; individual with Dec 31 year-end pays Apr 30, files Jun 15 | https://www.canada.ca/en/revenue-agency/services/tax/businesses/topics/gst-hst-businesses/file-gst-hst-return/reporting-requirements-deadlines.html | verified |
| Default reporting period: ≤ $1.5M annual, ≤ $6M quarterly, > $6M monthly | https://www.canada.ca/en/revenue-agency/services/forms-publications/publications/rc4022/general-information-gst-hst-registrants.html | verified (indexed text) |
| ITC invoice tiers: < $100, $100–$499.99 (adds tax and GST/HST number), $500+ (adds description, terms) | https://www.canada.ca/en/revenue-agency/services/tax/businesses/topics/gst-hst-businesses/calculate-prepare-report/input-tax-credit.html | verified (indexed text) |
| GST/HST account = 9-digit BN + RT + 4 digits | https://www.canada.ca/en/revenue-agency/services/forms-publications/publications/gi-067/basic-gst-hst-guidelines-charities.html | verified (indexed text) |
| Keep records six years from end of the tax year they relate to | https://www.canada.ca/en/revenue-agency/services/tax/businesses/topics/keeping-records/where-keep-your-records-long-request-permission-destroy-them-early.html | verified |
| Employee vs self-employed: whole relationship decides; contract label does not; CPP/EI ruling available | https://www.canada.ca/content/dam/cra-arc/formspubs/pub/rc4110/rc4110-23e.pdf | verified (indexed text) |

### CASL — https://laws-lois.justice.gc.ca/eng/acts/E-1.6/FullText.html and SOR/2012-36

| Fact | Section | Status |
|---|---|---|
| Consent + identification + contact info + unsubscribe for every CEM; contact info valid 60 days | s.6(1)–(3) | verified |
| Express consent request states purposes, who seeks it, contact info, right to withdraw | s.10(1); Regs s.4 | verified |
| Implied consent: existing business/non-business relationship; conspicuous publication with no "no spam" statement and relevance to role; address disclosed to sender with relevance | s.10(9) | verified |
| Existing business relationship: purchase/contract within 2 years; inquiry within 6 months | s.10(10) | verified |
| Unsubscribe at no cost, address/link valid 60 days, effect within 10 business days | s.11 | verified |
| Identification: business name, mailing address + phone/email/web; clear and prominent | Regs s.2–3 | verified |
| Sender bears the onus of proving consent | s.13 | verified |
| Max penalty $1M (individual), $10M (other) per violation | s.20(4) | verified |
| Private right of action suspended June 2017 | https://gazette.gc.ca/rp-pr/p2/2017/2017-06-14/html/si-tr31-eng.html | verified for 2017; current status **unverified** |

### Privacy

| Fact | Source | Status |
|---|---|---|
| PIPEDA scope; AB, BC, QC substantially similar laws; the 10 principles | https://www.priv.gc.ca/en/privacy-topics/privacy-laws-in-canada/the-personal-information-protection-and-electronic-documents-act-pipeda/pipeda_brief/ | verified |
| Accountability: appoint a responsible person, make name/title known | https://www.priv.gc.ca/en/privacy-topics/privacy-laws-in-canada/the-personal-information-protection-and-electronic-documents-act-pipeda/p_principle/principles/p_accountability/ | verified |
| Address harvesting outside PIPEDA's consent exceptions (s.7.1) | https://laws-lois.justice.gc.ca/eng/acts/P-8.6/page-2.html | verified |
| Breach with real risk of significant harm: report to OPC, notify individuals as soon as feasible, record every breach (s.10.1, s.10.3) | https://laws-lois.justice.gc.ca/eng/acts/P-8.6/page-3.html | verified |
| Law 25: person in charge (highest authority by default, delegable in writing, title and contact on website); incidents with risk of serious injury → CAI + individuals, register; PIA before transfers outside Quebec and for new systems; consent manifest/free/informed/specific; published privacy policy in clear terms; portability since 2024-09-22; AMPs up to 2% of worldwide turnover or $10M | https://www.cai.gouv.qc.ca/protection-renseignements-personnels/sujets-et-domaines-dinteret/principaux-changements-loi-25 | verified |

### French language (Quebec)

| Fact | Source | Status |
|---|---|---|
| Catalogues, ads, websites accessible in French; consumer contracts, invoices, receipts in French; labels in French; signage French or markedly predominant; 25+ employees for 6 months → register with the OQLF within the next 6 months | https://www.quebec.ca/culture/langue-francaise/exercer-droits-langue-francaise/obligations | verified |
| Contracts of adhesion: French version first, since 2023-06-01; trademarks on signs and products rules from 2025-06-01 | https://cfib-fcei.ca/en/site/qc-law-14-bill-96 · https://www.oqlf.gouv.qc.ca/francisation/droits_linguistiques/droits/langue-du-commerce-et-des-affaires.html · https://www.oqlf.gouv.qc.ca/francisation/entreprises/affichage-marques-noms.html | verified (CFIB + indexed OQLF text) |

### Incorporation

| Fact | Source | Status |
|---|---|---|
| Federal: name exclusive across Canada; still register extra-provincially where you carry on business | https://ised-isde.canada.ca/site/corporations-canada/en/naming-corporation/corporations-name-granting · https://ised-isde.canada.ca/site/corporations-canada/en/register-federal-corporation-province-or-territory | verified (indexed text) |
| Trade name registration is provincial | https://www.canada.ca/en/services/business/start/choosing-a-business-name-3.html | verified (indexed text) |

### Unverified — the skills say so wherever these come up

QST filing periods and due dates · whether BC PST / MB RST / SK PST applies to a given service ·
QST number format · place-of-supply rules between provinces · Alberta and BC privacy-law
specifics · Law 25 cookie/tracker defaults · non-compete enforceability by province · Quebec
civil-law contractor rules · CASL record retention period · whether B2B-only content is exempt
from French requirements · incorporation fees and the tax effect of incorporating · current
status of CASL's private right of action.

## Licences

Anthropic's `brand-guidelines` skill (github.com/anthropics/skills, Apache-2.0) was reviewed for
`brand-voice`. It applies Anthropic's own colours and fonts, so nothing in it is generic; no text
was copied and no attribution obligation arises. Everything in this pack is original to this kit.
