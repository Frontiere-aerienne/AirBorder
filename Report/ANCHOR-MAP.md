# Anchor map for `Report/main.tex`

The authors approved these seven anchor papers on 2026-11-11 (`.github/report-review/ANCHORS.json`).
They also decided:

- the limit is 7 anchors, up from 3;
- no external data sources are cited;
- most anchors are from the AI era; three earlier papers are kept (Fernandes 2018, Lim 2009,
  Amershi 2019).

After the change, the bibliography holds only these keys:

- **Anchors:** `ref8`, `ref7`, `ref218` (new), `ref219` (new), `ref220` (new), `ref221` (new), `ref144`
- **Project materials:** `ref2`, `ref13`, `ref14`

Kocielnik and Möller, briefly assigned keys `ref216` and `ref217` in an earlier pick that day, were
**replaced**. Do not add `ref216` or `ref217`. Amershi (`ref144`) was dropped and then reinstated,
so keep it.

Line numbers refer to `main.tex` at commit `b73996b`. They will drift as the report is edited, so
search for the quoted text instead. The wording below is a suggestion. Each claim must stay within
what the paper's abstract shows (the **Shows** line for each anchor).

## Bibliography entries

Keep `ref7`, `ref8` and `ref144`, and add their page ranges and full author lists. Add `ref218`, `ref219`, `ref220` and `ref221`. Delete
every other `\bibitem` except `ref2`, `ref13` and `ref14`.

```latex
\bibitem{ref7}
Brian Y. Lim, Anind K. Dey and Daniel Avrahami. 2009. Why and Why Not Explanations Improve the Intelligibility of Context-Aware Intelligent Systems. In Proceedings of the SIGCHI Conference on Human Factors in Computing Systems (CHI '09). ACM, 2119--2128. \url{https://doi.org/10.1145/1518701.1519023}

\bibitem{ref8}
Michael Fernandes, Logan Walls, Sean Munson, Jessica Hullman and Matthew Kay. 2018. Uncertainty Displays Using Quantile Dotplots or CDFs Improve Transit Decision-Making. In Proceedings of the 2018 CHI Conference on Human Factors in Computing Systems (CHI '18). ACM, 1--12. \url{https://doi.org/10.1145/3173574.3173718}

\bibitem{ref144}
Saleema Amershi, Dan Weld, Mihaela Vorvoreanu, Adam Fourney, Besmira Nushi, Penny Collisson, Jina Suh, Shamsi Iqbal, Paul N. Bennett, Kori Inkpen, Jaime Teevan, Ruth Kikin-Gil and Eric Horvitz. 2019. Guidelines for Human-AI Interaction. In Proceedings of the 2019 CHI Conference on Human Factors in Computing Systems (CHI '19). ACM, 1--13. \url{https://doi.org/10.1145/3290605.3300233}

\bibitem{ref218}
Sunnie S. Y. Kim, Q. Vera Liao, Mihaela Vorvoreanu, Stephanie A. Ballard and Jennifer Wortman Vaughan. 2024. ``I'm Not Sure, But...'': Examining the Impact of Large Language Models' Uncertainty Expression on User Reliance and Trust. In Proceedings of the 2024 ACM Conference on Fairness, Accountability, and Transparency (FAccT '24). ACM, 822--835. \url{https://doi.org/10.1145/3630106.3658941}

\bibitem{ref219}
Sunnie S. Y. Kim, Jennifer Wortman Vaughan, Q. Vera Liao, Tania Lombrozo and Olga Russakovsky. 2025. Fostering Appropriate Reliance on Large Language Models: The Role of Explanations, Sources, and Inconsistencies. In Proceedings of the 2025 CHI Conference on Human Factors in Computing Systems (CHI '25). ACM, 1--19. \url{https://doi.org/10.1145/3706598.3714020}

\bibitem{ref220}
Helena Vasconcelos, Matthew J\"{o}rke, Madeleine Grunde-McLaughlin, Tobias Gerstenberg, Michael S. Bernstein and Ranjay Krishna. 2023. Explanations Can Reduce Overreliance on AI Systems During Decision-Making. Proceedings of the ACM on Human-Computer Interaction 7, CSCW1 (CSCW '23), 1--38. \url{https://doi.org/10.1145/3579605}

\bibitem{ref221}
Zelun Tony Zhang, Sebastian S. Feger, Lucas Dullenkopf, Rulu Liao, Lou S\"{u}sslin, Yuanting Liu and Andreas Butz. 2024. Beyond Recommendations: From Backward to Forward AI Support of Pilots' Decision-Making Process. Proceedings of the ACM on Human-Computer Interaction 8, CSCW2 (CSCW '24), 1--32. \url{https://doi.org/10.1145/3687024}
```

Every anchor must be cited at least once in the body, before `\appendix`.

## The seven anchors

### `ref8`: Fernandes et al., CHI 2018

**Shows:** A controlled, incentivized experiment asked people when to leave for a bus. Quantile
dotplots (50 outcomes) and CDF plots led to better and more consistent decisions than text
uncertainty or a display without uncertainty. With dotplots, the expected payoff reached 97% of
optimal, 5 percentage points above the no-uncertainty display. Text uncertainty was sensitive to
which probability interval it stated.

| Where | Claim (current text) | Action |
|---|---|---|
| Related research (l. 144) | "Transit-uncertainty research motivates displaying possible outcomes alongside a single estimate \cite{ref8,ref9}" | Change to `\cite{ref8}`. Suggested: "In a controlled transit experiment, quantile dotplots and CDFs led to better leave-time decisions than a single predicted time or text uncertainty \cite{ref8}." |
| System, Probability (l. 271) | "A dotplot can make possible outcomes inspectable, following transit-uncertainty research \cite{ref8,ref9}" | Change to `\cite{ref8}`. |
| Evaluation Plan, Metrics (l. 373) | H2 deadline interpretation accuracy | Optional: the H2 tasks score the decision, not only whether participants can read the value, "following \cite{ref8}". Do not change H2. |

**Must not claim:** airport-connection results or calibration.

### `ref7`: Lim, Dey, Avrahami, CHI 2009

**Shows:** A controlled study with more than 200 participants tested understanding after
different explanation types. Explanations of *why* the system behaved as it did led to better
understanding and stronger trust. Explanations of *why not* led to lower understanding, although
performance was still adequate.

| Where | Claim (current text) | Action |
|---|---|---|
| Related research (l. 140) | "Explanation research motivates showing why a plan changed and which constraint prevents an alternative \cite{ref7}" | **Revise.** "Which constraint prevents an alternative" is a *why-not* explanation, which *lowered* understanding. Suggested: "Explaining why a system behaved as it did improved understanding and trust, whereas why-not explanations lowered understanding \cite{ref7}. AirBorder therefore leads with why the plan changed and keeps blocked alternatives secondary." |
| Evaluation Plan, Metrics (l. 373) | "value extraction scored separately from cause explanation" | Optional: ground the separate cause-explanation score in Lim et al.'s test of understanding \cite{ref7}. |

**Must not claim:** speed effects, or travel results.

### `ref218`: Kim et al., FAccT 2024 (new)

**Shows:** A pre-registered experiment with 404 participants answering medical questions with or
without a fictional AI-assisted search engine. When the system's answers began with first-person
uncertainty ("I'm not sure, but…"), participants were less confident in the system, agreed with
it less, and answered more accurately. An exploratory analysis attributes this mostly to reduced,
but not eliminated, overreliance on incorrect answers. Uncertainty stated impersonally ("It's not
clear, but…") had weaker effects that were not statistically significant. The authors conclude
that the exact wording matters and should be tested with users.

| Where | Claim (current text) | Action |
|---|---|---|
| System, Probability (l. 275): "a separate safety policy decides whether the evidence supports a recommendation" | How AirBorder says it is unsure | Add: "How a system expresses uncertainty changes reliance: first-person uncertainty reduced reliance on incorrect answers, and the exact wording mattered \cite{ref218}. AirBorder marks provisional estimates and withholds a leave-by time the evidence does not support; their wording is tested with travelers." |
| Operational limits (l. 299–303) | Provisional estimates and stale data labelled | Can cite `ref218` for labelling provisional guidance in plain language. |
| Evaluation Plan, Metrics (l. 373), S3 | Confidence measured separately from correctness | Optional: confidence can fall while accuracy rises \cite{ref218}, so S3 ratings are interpreted alongside H1/H2 accuracy. Do not change S3. |

**Must not claim:** travel or probability-display results, or that AirBorder uses first-person
wording, unless it does.

### `ref219`: Kim et al., CHI 2025 (new)

**Shows:** A think-aloud study identified features of language-model answers that shape reliance:
explanations, inconsistencies in explanations, and sources. A pre-registered controlled experiment
with 308 participants then found:

- explanations increased reliance on both correct and incorrect answers;
- providing sources reduced reliance on incorrect answers;
- explanations containing inconsistencies also reduced reliance on incorrect answers.

| Where | Claim (current text) | Action |
|---|---|---|
| Operational limits (l. 303) | "Amershi et al.\ motivate correction and scoped fallback \cite{ref144}" | **Keep** the Amershi sentence (see `ref144`), then add the provenance grounding: "Showing sources reduced reliance on incorrect answers from a language model, while explanations alone increased reliance on correct and incorrect answers alike \cite{ref219}; each input therefore carries its observation time and source, and model advice is screened by deterministic checks." |
| Initial Design (l. 171 onward) | Provenance labels ("From your ticket", "Added by you") | Can cite `ref219` for showing where information comes from. |
| Evaluation Plan, Method/Metrics | H1 feasible next action | Optional: because explanations can raise reliance on wrong answers as well as right ones \cite{ref219}, include a task where the shown plan is infeasible and score whether participants reject it. Adding this task changes the method, so the authors must approve it first. |

**Must not claim:** travel results, or that the explanation view will improve accuracy.

### `ref220`: Vasconcelos et al., CSCW 2023 (new)

**Shows:** People choose strategically whether to engage with an AI's explanation. In five maze
studies (N = 731) with a simulated AI:

- task difficulty, explanation difficulty and monetary reward all changed how much people over-relied on the AI;
- explanations reduced overreliance when they lowered the cost of verifying the AI's answer.

| Where | Claim (current text) | Action |
|---|---|---|
| System, Probability (l. 275) | "records a complete calculation trace" | Add: "Explanations reduced overreliance when they made the AI's answer cheaper to verify \cite{ref220}; the trace therefore shows the route, queue and deadline values a traveler can check, rather than a general rationale." |
| Related research (l. 140), after the Lim sentence | Change view | Optional: pair with `ref7` and `ref219`. Explanations help when they reduce verification effort \cite{ref220}, not merely by being present \cite{ref219}. |

**Must not claim:** travel or navigation results.

### `ref221`: Zhang et al., CSCW 2024 (new)

**Shows:** A mixed-methods study with 32 professional pilots in a realistic diversion scenario,
preceded by a focus group with four pilots. It compared AI that gives an end-to-end recommendation
with *continuous support* for the pilot's decision process. Continuous support helped pilots
reason forward, beyond the system's limits, and made decisions faster when combined with a
recommendation, though this forward support could be disrupted. Pilots' statements suggest the
design goal shifts from giving recommendations to supporting quick information gathering.

| Where | Claim (current text) | Action |
|---|---|---|
| Introduction (l. 32–50), problem and contribution | AirBorder turns scattered constraints into a feasible next action | Add after the contribution statement: "In aviation, AI support that helped pilots gather information throughout a diversion decision, rather than only recommending an outcome, supported forward reasoning and faster decisions when combined with a recommendation \cite{ref221}. AirBorder applies this to passengers: it shows the time budget, required steps and their consequences alongside the next action." |
| Initial Design (l. 171 onward), "One journey, an inspectable next action" | The next action is shown with its time budget and steps | Can cite `ref221` for presenting decision information alongside, not instead of, the recommended action. |
| Evaluation Plan, Hypotheses (H1) | Feasible next action after a gate change | Optional grounding for why H1 scores the traveler's chosen action rather than agreement with the app \cite{ref221}. Do not change H1. |

**Must not claim:** passenger results; the participants were professional pilots in a
diversion scenario.

### `ref144`: Amershi et al., CHI 2019

**Shows:** 18 design guidelines for human-AI interaction, validated over several rounds,
including a study in which 49 design practitioners tested them against 20 AI products. These are
design guidelines checked by practitioners, not an end-user performance result.

| Where | Claim (current text) | Action |
|---|---|---|
| Operational limits (l. 303) | "Amershi et al.\ motivate correction and scoped fallback \cite{ref144}" | **Keep.** Optionally name the guidelines: support efficient correction, scope services when in doubt, make clear why the system did what it did. |
| System, Probability (l. 275) | "a separate safety policy decides whether the evidence supports a recommendation" | Can cite `ref144` for scoping services when in doubt. |
| Initial Design (l. 171 onward) | Traveler edits and "Added by you" labels | Can cite `ref144` for supporting efficient correction. |

**Must not claim:** that following the guidelines improves traveler performance.

## Other body citations (before `\appendix`)

Remove each citation below. The default is to keep the sentence as the authors' own reasoning or
description; cut it only where the sentence depends on the source.

| Line | Key(s) | Content | Action |
|---|---|---|---|
| 36 | `ref84`, `ref85` | EUROCONTROL / U.S. DOT delay statistics | **Cut the statistics** (no external data sources). Keep the motivation through the interviews (`ref13`). |
| 48 | `ref211` | Missed connections make itinerary delay exceed flight delay | Cut, or restate as reasoning without a statistic. |
| 57, 115, 133, 212 | `ref13` | Interview record | **Keep.** |
| 71 | `ref2` | Deployed survey | **Keep.** |
| 115, 312 | `ref14` | Verification record | **Keep.** |
| 126, 130 | `ref4`, `ref147` | Flighty Connection Assistant features | Remove the cites. Describe the baseline as the authors observed it, with version and date in the Method's Equipment paragraph. |
| 133 | `ref3`, `ref5`, `ref205` | TripIt, Fly Delta, other tools | Remove the cites; keep a short uncited list or cut. |
| 133 | `ref213`, `ref214` | Cultural context from two dramas | Cut. |
| 140 | `ref6` | External cognition | Remove the cite; keep as design rationale. |
| 142 | `ref113`, `ref114`, `ref115` | Airport wayfinding, AR vs 2D maps, signage | Remove the cites. Keep "we retain a route overview and measure recall separately" as the authors' own design decision. |
| 142, 370 | `ref215` | AR situational-awareness review | Remove the cite. The later AR comparison's measures stay as the authors' rationale; no anchor covers AR. |
| 144, 271 | `ref9` | Kay et al. 2016 | Drop; `ref8` covers the claim. |
| 146 | `ref37` | A-CDM milestones | Remove the cite; describe the adaptation as AirBorder's own, or cut. |
| 161, 172 | `ref94`, `ref95` | Heathrow Terminal 2 official map | Remove the cites. **Keep image credit in the caption text** ("Map: Heathrow/Atrius, captured 4 October 2026"), because the figure reproduces their map. |
| 212 | `ref88`, `ref89` | Australian biosecurity guidance | Remove the cites. |
| 232 | `ref212` | Platform tooling | Remove the cite. |
| 246 | `ref149`, `ref150`, `ref154`, `ref155` | Time zones and US/UK transition dates | Remove the cites. |
| 250, 258 | `ref10`, `ref11`, `ref12` | Dijkstra, A*, orienteering | Remove the cites; standard algorithms can be named without a citation. |
| 277 | `ref17` | ARKit | Remove the cite. |
| 279 | `ref77`, `ref79` | Timatic, One ID | Remove the cites, or cut the partner sentence. |
| 289 | `ref105`, `ref106`, `ref108`, `ref116` | Procedure sources in the caption | Remove the cites. |
| 296 | `ref143` | Ancker et al. medication instructions | Cut the sentence. |
| 319 | `ref28`, `ref29`, `ref30` | EEA/UK assessments | Remove the cites. |
| 323 | `ref146`, `ref148` | Trial/freemium research | Cut the claim. |
| 329 | `ref26`, `ref27` | ChatGPT Apps SDK, Claude MCP connectors | Remove the cites; name the products in text if needed. |
| 333 | `ref156` | "Inspired by dots" | Remove the cite. |
| 335 | `ref142` | Iqbal and Bailey, task-boundary prompts | Remove the cite; keep it as a design choice to test. |

## Appendix

The appendix currently has about 288 `\cite` commands. The rule "appendix-only material is not
cited" means every appendix citation must be removed. Any appendix claim that needs a source must
cite an anchor whose finding matches it, or be reworded or cut.

## Checks after editing

```
cd Report && latexmk -pdf main.tex
python3 Scripts/reporting/check_citations.py --strict
python3 Scripts/reporting/check_rubric.py
```
