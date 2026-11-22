# Reusable resident reviewers

These three fictional reviewers turn the audience in [AUDIENCE.md](../AUDIENCE.md)
into repeatable usability checks. They simulate reading and comprehension; they
do not substitute for interviews with residents or establish factual accuracy.
Their age, family situation, faith, and work are individual background details,
not claims about groups. Use ordinary adult language, limited technical confidence,
and limited time rather than an IQ label or a caricature of low intelligence.

## Agents and invocation

Project agent definitions:

- [resident_marlene](../../.codex/agents/resident_marlene.toml): a widowed older
  resident who strongly values kindness and community harmony.
- [resident_frank](../../.codex/agents/resident_frank.toml): an older churchgoing
  election-time voter who recognizes names but rarely follows council business.
- [resident_dana](../../.codex/agents/resident_dana.toml): a working resident who
  follows local issues but has little time and no technical expertise.

Example request in a Codex chat opened on this repository:

> Use resident_marlene, resident_frank, and resident_dana to review [URLs] as
> separate agents. Keep the review read-only. Return each persona's first
> impression, likely misunderstandings, task results, and three most useful
> improvements, then consolidate the findings with page examples.

Codex discovers project agents in `.codex/agents/`; their models and permissions
inherit from the parent. A running chat may need a fresh session to discover
new files. If named-agent selection is unavailable, explicitly give each separate
subagent its TOML `developer_instructions` and this protocol. Disclose that fallback;
do not claim the named configuration was loaded by the runtime. These are agent
instructions to review without edits, not a separately enforced read-only sandbox.

## Shared review method

Read the current audience document and the persona definition. The coordinating
reviewer derives acceptance from the user task and binding product requirements;
for member profiles, also read the purpose and product questions in
[the accountability design](../superpowers/specs/2026-11-07-council-accountability-design.md)
and [RES-10](../application-map/resident-workflows.md#res-10--inspect-an-officials-attendance-and-voting-record-p1).
Keep requirements outside the persona's assumed knowledge. The simulated reader
knows only the visible page and their stated background.

Review public content as supplied, ordinarily anonymously at a phone viewport
around 390 by 844. Inspect a screenshot for layout as well as rendered text.
Use read-only navigation and disclosures; do not sign in with invented credentials,
submit forms, change application data, call paid providers, or edit files.
If browser access is unavailable, use supplied captures and label the result
capture-based. Hidden DOM text and source code may explain a concern to the
coordinator, but cannot count as something the persona saw without opening it.

Start with a simulated 30-second scan: what would the person notice, understand,
and believe? This is a reading budget, not an instrumented human timing result.
Then attempt the relevant tasks below with ordinary links and controls. Record
actual interactions separately from predicted behavior; stop the persona's
journey where their motivation would plausibly end rather than giving them
researcher-level persistence. The coordinator can inspect further to diagnose.

1. Identify who the official is, their role, and the time period covered.
2. Explain one campaign position in the reader's own words.
3. Find a related action and explain exactly what the member voted to do.
4. Distinguish that action from an eventual project or policy result.
5. Explain attendance without treating missing records as absences or ignoring
   the difference between the service period and available records.
6. Follow one useful issue/source link and decide whether it answers the question.

Do not force every page into every task. For other resident pages, apply the
same comprehension test to the task the reader actually came to perform.

## Evidence and output

Return a concise report with these fields:

- **Basis:** date, URLs, public/signed-in state, viewport, live versus captured
  evidence, and material limits. A checkout revision is not proof of the server's
  revision. A connection or tooling failure is not automatically a product defect.
- **First impression:** two or three clearly labeled simulated first-person
  sentences, including anything useful. Do not invent a real interview or quote.
- **Task results:** understood / misunderstood / could not find / not exercised,
  with the visible wording or location that supports each judgment.
- **Top concerns:** up to three, each connecting observed wording/layout to a
  likely interpretation, its consequence, and the smallest helpful improvement.
- **Keep:** one or two things that help this reader and should be preserved.

Prioritize a wrong takeaway over awkward styling. A strong finding looks like:
"The heading names a fee ordinance, but the displayed Yes/Passed describes a
vote to postpone it; a reader could believe the fees were approved." Verify the
particular example before reporting it. Use neutral explanatory copy rather
than endorsements, vote advice, grades, or more favorable/negative political
framing. Distinguish related votes from evidence that a campaign goal was fulfilled.

The coordinator consolidates duplicates while preserving different reactions.
Agreement among simulations is not proof of correctness or actual user satisfaction.
Keep observed UI facts, predicted misunderstandings, proposed changes, and
unverified factual/source questions separate. Do not mark workflows verified or
update the application map solely because these reviewers agree.
