# Application behavior map

Baseline: **2026-10-10**, checkout `0849dfc34fdb9db0a3fdd22640ee87a2d4f298cb`.

This map describes Two Rivers Reporter's resident website, account system,
administrative interfaces, resident API, and the background work that changes
what readers see. It is the discovery/documentation foundation for independent
behavioral QA alongside development TDD.

**Evidence level: repository discovery, not demonstrated runtime behavior.**
Requirements, controllers, views, JavaScript, models, services, jobs, middleware,
routes, and runner configuration were inspected. Rails was booted locally to
enumerate routes and compare dispatch targets with controller action methods.
No browser journeys, production inspections, external email deliveries, paid AI
calls, application tests, or fault-injection experiments were performed for this
documentation baseline. A mapped workflow is not a covered or passing workflow.

Current verification: [October 10–11 audit](overnight-progress.md) records four merged changes, two decision-dependent draft PRs, exact runtime/fault evidence and remaining unknown variants at combined master 61d6779. The discovery baseline below is historical, not a claim that subsequent tests did not run.

## Read the map

| Document | Use |
| --- | --- |
| [Inventory and access model](inventory.md) | Audiences, pages, controls, navigation, permissions, representation boundaries |
| [Workflow index](workflow-index.md) | Direct links to 57 stable workflow IDs and their QA priorities |
| [Account workflows](account-workflows.md) | Applications, sign-in/out, session transitions, passkeys, API keys |
| [Resident workflows](resident-workflows.md) | Topic/meeting discovery, reporting, sources, civic officials, API research |
| [Administrative workflows](admin-workflows.md) | Membership decisions, editorial repair, records, jobs, prompts, imagery |
| [Data and background workflows](data-and-background.md) | Data dependencies, enrichment, asynchronous state changes, external failures |
| [Route inventory](routes.md) | Every declared application-controller route and its action-presence check |
| [Discrepancies and verification needs](verification-register.md) | Conflicting descriptions, unfinished surfaces, and unverified behavior |
| [Reviewed contracts and decisions](behavior-contracts.md) | Authoritative resolutions and remaining owner choices from #171/#172/#175 |
| [Observed policy matrices](policy-matrices.md) | Separate source observations and pending access/context/expired-link retention decisions |
| [Overnight audit and progress](overnight-progress.md) | Current per-issue acceptance, commands, environments, fault checks and remaining work |
| [Maintenance and subsequent QA](maintenance-and-qa.md) | Updating this map and using it for the separate coverage/effectiveness review |

## Authority and evidence

The map is a derived reference. It does not replace the binding product spec,
Topic Governance, specialized designs, or repository playbooks.

| Reference | Domain |
| --- | --- |
| [Development plan](../DEVELOPMENT_PLAN.md) | Product purpose, source authority, resident API, access, membership, cancellation |
| [Audience](../AUDIENCE.md) | Resident needs and interaction expectations; account/search assumptions reconciled to current approved designs |
| [Topic Governance](../topics/TOPIC_GOVERNANCE.md) | Persistent concerns, uncertainty, review, lifecycle, factual restraint |
| [Passwordless design](../superpowers/specs/2026-07-23-passwordless-auth-and-applications-design.md) | Account applications, approval, authentication, ownership, email |
| [Session design](../superpowers/specs/2026-07-25-session-and-reauthentication-hardening-design.md) | Expiry, context, step-up, freshness, lockout prevention |
| [Public access design](../superpowers/specs/2026-07-24-tiered-public-access-design.md) | Teasers, withheld content, open/gated modes |
| [Verified crawler policy](../verified-crawler-access.md) | Reporting exceptions, discovery, cache/proxy boundaries |
| [Resident API contract](../read-only-api.md) | Keys, read-only scope, pagination, transcript revision, research/update discovery |
| [Admin design, including shipped corrections](../superpowers/specs/2026-07-26-admin-ui-revamp-design.md) | Navigation, triage UI, preserved orphan actions, presentation constraints |
| [Roster design](../superpowers/specs/2026-09-03-canonical-committee-rosters-design.md) | Current office/roster authority versus attendance |
| [Page architecture playbook](../../.claude/skills/page-architecture/SKILL.md) | Page data flow and evidence pipelines; current navigation reconciled; empty-state discrepancies remain explicit |
| [Design system](../plans/2026-03-28-atomic-design-system-spec.md) | Public Living Room and admin Silo themes, responsive presentation |
| [Project handbook](../../CLAUDE.md) and [agent instructions](../../AGENTS.md) | Repository procedures and verification rules |

Each workflow has a stable identifier, risk priority, starting conditions, a
trigger, intended resulting state, observable outcome, subsequent behavior,
failure variants, and implementation evidence. The intended outcome comes from
the linked requirements. Where requirements do not settle an interaction, a
**candidate acceptance criterion** is explicitly identified. Code is evidence
that an implementation path exists; it cannot settle the intended behavior by
itself. Conflicts remain in the verification register until reviewed.

Use these evidence terms separately:

- **Required:** an expectation stated by a binding document or the user's
  behavioral-validation brief.
- **Observed in source:** a route, control, query, state change, or error path
  found in this checkout. This is static evidence, even when Rails lists it.
- **Runtime verified:** the exact journey was exercised with specified audience,
  data, browser/environment, and meaningful outcome assertions. None is claimed
  by this initial map.
- **Unsettled:** conflicting requirements, incomplete functionality, or an
  interaction whose correct outcome still needs a product decision.

## Workflow priorities

These priorities sequence future QA work; they are not defect severity ratings.

| Priority | Reason | Initial examples |
| --- | --- | --- |
| P0 | Loss of access control, credentials, irreplaceable records, or source truth | AUTH-04 sign-out, AUTH-05 expiry/revocation, AUTH-10 credentials, RES-07 source provenance, RES-11 gating, ADM-03 account deletion |
| P1 | Primary resident tasks and important administrative/background outcomes | Applications/approval, topic and meeting research, merges, transcript import, job completion, API continuation |
| P2 | Lower-impact presentation and navigation or explicitly unfinished functionality | Passkey reminder dismissal, About, mobile menu behavior, Explore placeholder |

Start future behavioral validation with AUTH-01 through AUTH-05, RES-11,
AUTH-13 through AUTH-15, ADM-01 through ADM-04, and source-preservation scenarios.
Keep the normal TDD cycle. This additional reference is intended to reveal
missing expectations and interactions, rather than reward test volume.

## Discovery completeness and limits

- Every source-backed controller dispatch in the local route set is listed in
  [routes.md](routes.md): 174 rows, including a duplicate declaration and 10
  rows whose actions are absent. The `/members` redirect, `/up`, static discovery
  files, and framework routes are accounted for separately.
- The public and admin navigation structures, contextual controls, settings,
  request formats, middleware, core domain associations, and background entry
  points are inventoried. Routes without a UI and templates without a route are
  identified rather than counted as ordinary user workflows.
- No claim is made that local data is complete, that production matches this
  revision/configuration, that remote sources/providers are currently reachable,
  or that every interaction works. Each workflow needs runtime evidence in a
  later QA pass. Production and provider facts in older documents are historical
  context, not newly verified facts.
- A route inventory helps discover omissions. It does not establish workflow
  coverage, visual/usability correctness, assertion quality, or defect detection.

## Baseline checks actually run

`bin/rails routes --expanded` completed locally. A temporary `bin/rails runner`
script enumerated controller routes and checked each source-backed target with
`action_methods`; it neither dispatched user requests nor queried application
records. Documentation links, workflow references, and route-table parity were
checked, along with `git diff --check`. No application source or tests changed.

The separate test review, new behavioral suite, recurring QA schedule, and
independent reviewer assignment remain future work, as described in
[maintenance-and-qa.md](maintenance-and-qa.md).
