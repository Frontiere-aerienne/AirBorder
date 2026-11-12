# Anchor map for `Report/main.tex`

The authors approved five anchor papers on 2026-11-11 (`.github/report-review/ANCHORS.json`).
They raised the cap from 3 to 5 and chose **not** to cite external data sources. After the
change, the bibliography holds only these keys:

- **Anchors:** `ref8`, `ref7`, `ref216` (new), `ref144`, `ref217` (new)
- **Project materials:** `ref2`, `ref13`, `ref14`

This map lists the claims each anchor supports and what happens to every other body citation.
Line numbers refer to `main.tex` at commit `b73996b`. They will drift as the report is edited,
so search for the quoted text instead. The wording below is a suggestion. Each claim must stay
within what the paper's abstract shows (the **Shows** line for each anchor).

## Bibliography entries

Keep `ref7`, `ref8` and `ref144`, and add their page ranges. Add `ref216` and `ref217`.
Delete every other `\bibitem` except `ref2`, `ref13` and `ref14`.

```latex
\bibitem{ref7}
Brian Y. Lim, Anind K. Dey and Daniel Avrahami. 2009. Why and Why Not Explanations Improve the Intelligibility of Context-Aware Intelligent Systems. In Proceedings of the SIGCHI Conference on Human Factors in Computing Systems (CHI '09). ACM, 2119--2128. \url{https://doi.org/10.1145/1518701.1519023}

\bibitem{ref8}
Michael Fernandes, Logan Walls, Sean Munson, Jessica Hullman and Matthew Kay. 2018. Uncertainty Displays Using Quantile Dotplots or CDFs Improve Transit Decision-Making. In Proceedings of the 2018 CHI Conference on Human Factors in Computing Systems (CHI '18). ACM, 1--12. \url{https://doi.org/10.1145/3173574.3173718}

\bibitem{ref144}
Saleema Amershi, Dan Weld, Mihaela Vorvoreanu, Adam Fourney, Besmira Nushi, Penny Collisson, Jina Suh, Shamsi Iqbal, Paul N. Bennett, Kori Inkpen, Jaime Teevan, Ruth Kikin-Gil and Eric Horvitz. 2019. Guidelines for Human-AI Interaction. In Proceedings of the 2019 CHI Conference on Human Factors in Computing Systems (CHI '19). ACM, 1--13. \url{https://doi.org/10.1145/3290605.3300233}

\bibitem{ref216}
Rafal Kocielnik, Saleema Amershi and Paul N. Bennett. 2019. Will You Accept an Imperfect AI? Exploring Designs for Adjusting End-user Expectations of AI Systems. In Proceedings of the 2019 CHI Conference on Human Factors in Computing Systems (CHI '19). ACM, 1--14. \url{https://doi.org/10.1145/3290605.3300641}

\bibitem{ref217}
Andreas M\"{o}ller, Matthias Kranz, Stefan Diewald, Luis Roalter, Robert Huitl, Tobias Stockinger, Marion Koelle and Patrick A. Lindemann. 2014. Experimental Evaluation of User Interfaces for Visual Indoor Navigation. In Proceedings of the SIGCHI Conference on Human Factors in Computing Systems (CHI '14). ACM, 3607--3616. \url{https://doi.org/10.1145/2556288.2557003}
```

Every anchor must be cited at least once in the body, before `\appendix`.

## The five anchors

### `ref8`: Fernandes et al., CHI 2018

**Shows:** A controlled, incentivized experiment asked people when to leave for a bus. Quantile
dotplots (50 outcomes) and CDF plots led to better and more consistent decisions than text
uncertainty or a display without uncertainty. With dotplots, the expected payoff reached 97% of
optimal, 5 percentage points above the no-uncertainty display. Text uncertainty was sensitive to
which probability interval it stated. The study measured decision quality, not only whether
people could read probabilities.

**Supports:**

| Where | Claim (current text) | Action |
|---|---|---|
| Related research (l. 144) | "Transit-uncertainty research motivates displaying possible outcomes alongside a single estimate \cite{ref8,ref9}" | Change to `\cite{ref8}` (drop `ref9`). Suggested wording: "In a controlled transit experiment, quantile dotplots and CDFs led to better leave-time decisions than a single predicted time or text uncertainty \cite{ref8}." |
| System, Probability (l. 271) | "A dotplot can make possible outcomes inspectable, following transit-uncertainty research \cite{ref8,ref9}" | Change to `\cite{ref8}`. |
| Evaluation Plan, Metrics (l. 373) | H2 deadline interpretation accuracy | Optional grounding: the H2 tasks score the decision, not only whether participants can read the value, "following \cite{ref8}". Do not change H2 itself. |

**Must not claim:** that dotplots improve airport connections, or anything about calibration.
Fernandes et al. did not study real calibrated probabilities.

### `ref7`: Lim, Dey, Avrahami, CHI 2009

**Shows:** A controlled study with more than 200 participants tested understanding after
different explanation types. Explanations of *why* the system behaved as it did led to better
understanding and stronger trust. Explanations of *why not* led to lower understanding, although
performance was still adequate.

**Supports:**

| Where | Claim (current text) | Action |
|---|---|---|
| Related research (l. 140) | "Explanation research motivates showing why a plan changed and which constraint prevents an alternative \cite{ref7}" | **Revise.** "Which constraint prevents an alternative" is a *why-not* explanation, and Lim et al. found that type *lowered* understanding. Suggested: "Explaining why a system behaved as it did improved understanding and trust, whereas why-not explanations lowered understanding \cite{ref7}. AirBorder therefore leads with why the plan changed and keeps blocked alternatives secondary." |
| Evaluation Plan, Metrics (l. 373) | "value extraction scored separately from cause explanation and transfer to a second case" | Optional: ground the separate cause-explanation score in Lim et al.'s test of understanding after explanations \cite{ref7}. |

**Must not claim:** that explanations improve task speed, or that Lim et al. studied travel.

### `ref216`: Kocielnik, Amershi, Bennett, CHI 2019 (new)

**Shows:** In a scheduling assistant that detects meeting requests in email, two versions had the
same 50% accuracy but avoided different error types (false positives or false negatives). That
choice changed how accurate people perceived the system to be and whether they accepted it.
Techniques that prepared users for imperfection before use significantly increased acceptance.

**Supports:**

| Where | Claim (current text) | Action |
|---|---|---|
| System, Probability (l. 275): "a separate safety policy decides whether the evidence supports a recommendation" | Withholding or abstaining is an explicit choice about which error to avoid | Add: "Which errors a system avoids changes perceived accuracy and acceptance even at equal accuracy \cite{ref216}; AirBorder avoids a confident leave-by time that the evidence does not support." |
| Operational limits (l. 299–303) | Provisional estimates and labelled stale data | May cite `ref216` for telling travelers up front that estimates can be wrong. |
| Evaluation Plan, Metrics (l. 373): S3 ease and confidence ratings | Confidence is shaped by expectations, not only performance | Optional grounding for measuring confidence separately from correctness \cite{ref216}. Do not change S3. |

**Must not claim:** anything about travel, probability displays, or the 50% figure as a property
of AirBorder.

### `ref144`: Amershi et al., CHI 2019

**Shows:** 18 design guidelines for human-AI interaction, validated over several rounds,
including a study in which 49 design practitioners tested them against 20 AI products. These are
design guidelines checked by practitioners, not an end-user performance result.

**Supports:**

| Where | Claim (current text) | Action |
|---|---|---|
| Operational limits (l. 303) | "Amershi et al.\ motivate correction and scoped fallback \cite{ref144}" | Keep. Optionally name the guidelines: support efficient correction, scope services when in doubt, make clear why the system did what it did. |
| Initial Design (l. 171 onward) | Provenance labels ("From your ticket", "Added by you") and traveler edits | Optional: cite `ref144` as design guidance for showing the source of information and allowing correction. |

**Must not claim:** that following the guidelines improves traveler performance.

### `ref217`: Möller et al., CHI 2014 (new)

**Shows:** For camera-based (visual) indoor localization, the authors built AR and VR views that
communicate localization accuracy. When needed, the interface asked users to point the phone at
distinctive regions. In a navigation experiment, the VR view supported efficient and effective
indoor navigation even when location and orientation accuracy were unreliable.

**Supports:**

| Where | Claim (current text) | Action |
|---|---|---|
| Related research (l. 142) | Dong et al. AR versus 2D maps sentence \cite{ref114} | Replace with a Möller-grounded sentence: "In camera-based indoor navigation, an interface that communicated localization quality, and a VR view that stayed usable when accuracy was unreliable, supported efficient navigation \cite{ref217}. AirBorder keeps the Map view and written steps available when camera alignment is poor." The route-memory claim ("measure recall separately") loses its source, so state it as the authors' own design decision. |
| Operational limits (l. 301) | "When alignment fails, camera arrows stop… stale position is labeled explicitly" | Cite `ref217` for communicating localization quality and keeping a non-AR fallback. |
| Evaluation Plan, Later AR comparison (l. 370) | Replaces Woodward and Ruiz `ref215` | Ground the map-only versus camera-plus-map comparison under tracking loss in \cite{ref217}. Keep the situational-awareness questions as the authors' own rationale; Möller et al. did not measure situational awareness. |

**Must not claim:** AR route-memory effects, airport-specific results, or that Möller et al.
compared AR with a 2D map (they compared AR and VR views).

## Other body citations (before `\appendix`)

Remove each citation below. The default is to keep the sentence as the authors' own reasoning
or description; cut it only where the sentence depends on the source.

| Line | Key(s) | Content | Action |
|---|---|---|---|
| 36 | `ref84`, `ref85` | EUROCONTROL 27.6% / 46% and U.S. DOT 21.9% delay statistics | **Cut the statistics** (authors' decision: no external data sources). Keep the motivation through the interviews (`ref13`). |
| 48 | `ref211` | Missed connections make itinerary delay exceed flight delay | Cut the claim, or restate it as reasoning without a statistic. |
| 57, 115, 133, 212 | `ref13` | Interview record | **Keep** (project material). |
| 71 | `ref2` | Deployed survey | **Keep** (project material). |
| 115, 312 | `ref14` | Verification record | **Keep** (project material). |
| 126, 130 | `ref4`, `ref147` | Flighty Connection Assistant features | Remove the cites. Describe the baseline as the authors observed it, with version and date in the Method's Equipment paragraph. |
| 133 | `ref3`, `ref5`, `ref205` | TripIt, Fly Delta, other tools | Remove the cites; keep a short uncited list or cut. |
| 133 | `ref213`, `ref214` | Cultural context from two dramas | Cut. |
| 140 | `ref6` | External cognition | Remove the cite; keep as design rationale. |
| 142 | `ref113`, `ref115` | Airport wayfinding and signage studies | Cut, or restate as the authors' design decision without attribution. |
| 142, 370 | `ref114`, `ref215` | AR vs 2D maps; AR situational awareness | Replace with `ref217` as above. |
| 144, 271 | `ref9` | Kay et al. 2016 | Drop; `ref8` covers the claim. |
| 146 | `ref37` | A-CDM milestones | Remove the cite; describe the adaptation as AirBorder's own, or cut. |
| 161, 172 | `ref94`, `ref95` | Heathrow Terminal 2 official map | Remove the cites. **Keep image credit in the caption text** ("Map: Heathrow/Atrius, captured 4 October 2026"), because the figure reproduces their map. |
| 212 | `ref88`, `ref89` | Australian biosecurity guidance | Remove the cites; keep the caption without the attribution, or cut. |
| 232 | `ref212` | Platform tooling | Remove the cite. |
| 246 | `ref149`, `ref150`, `ref154`, `ref155` | Time zones and US/UK transition dates | Remove the cites; the method stays as the implementation description. |
| 250, 258 | `ref10`, `ref11`, `ref12` | Dijkstra, A*, orienteering | Remove the cites; the standard algorithms can be named without a citation. |
| 277 | `ref17` | ARKit | Remove the cite. |
| 279 | `ref77`, `ref79` | Timatic, One ID | Remove the cites, or cut the partner sentence. |
| 289 | `ref105`, `ref106`, `ref108`, `ref116` | Procedure sources in the caption | Remove the cites. |
| 296 | `ref143` | Ancker et al. medication instructions | Cut the sentence (clinical domain, no anchor). |
| 319 | `ref28`, `ref29`, `ref30` | EEA/UK assessments | Remove the cites. |
| 323 | `ref146`, `ref148` | Trial/freemium research | Cut the claim. |
| 329 | `ref26`, `ref27` | ChatGPT Apps SDK, Claude MCP connectors | Remove the cites; name the products in text if needed. |
| 333 | `ref156` | "Inspired by dots" | Remove the cite. |
| 335 | `ref142` | Iqbal and Bailey, task-boundary prompts | Remove the cite; keep it as a design choice to test. |

## Appendix

The appendix currently has about 288 `\cite` commands. The rule "appendix-only material is not
cited" means every appendix citation must be removed. Any appendix claim that needs a source
must cite an anchor whose finding matches it, or be reworded or cut.

## Checks after editing

```
cd Report && latexmk -pdf main.tex
python3 Scripts/reporting/check_citations.py --strict
python3 Scripts/reporting/check_rubric.py
```
