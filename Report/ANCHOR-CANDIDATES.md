# Anchor source candidates

**Chosen and approved on 2026-11-11 (6 anchors):** Fernandes et al. 2018 (`ref8`), Lim et al. 2009
(`ref7`), Kim et al. 2024 (`ref218`, new), Kim et al. 2025 (`ref219`, new), Vasconcelos et al. 2023
(`ref220`, new) and Zhang et al. 2024 (`ref221`, new). The authors raised the cap from 3 to 6, chose
not to cite external data sources, and asked for at most two anchors from before the
large-language-model era. An earlier pick that day (Kocielnik 2019, Amershi 2019, Möller 2014) was
replaced. Each paper was checked against its DOI record (Crossref) and abstract (OpenAlex). Picks
are marked ✅ and recorded in `.github/report-review/ANCHORS.json`; `Report/ANCHOR-MAP.md` maps
each one to the claims in `main.tex` it supports.

- **In bib** gives the key when the paper is already in `Report/main.tex`. Those entries and
  their DOIs are already there.
- **Not yet** means the paper needs a new `\bibitem`. Confirm the full citation and DOI in the
  ACM Digital Library or IEEE Xplore before adding it.
- **Grounds** says which part of AirBorder the paper would support.

## Uncertainty and probabilistic decisions (leave-by time, probability of reaching the gate)

| Paper | Venue | In bib | Grounds |
|---|---|---|---|
| ✅ Fernandes, Walls, Munson, Hullman, Kay. *Uncertainty Displays Using Quantile Dotplots or CDFs Improve Transit Decision-Making* | CHI 2018 | ref8 | Probability-based leave-by guidance and the dotplot; H2 (deadline interpretation) |
| Kay, Kola, Hullman, Munson. *When(ish) is My Bus? User-centered Visualizations of Uncertainty in Everyday, Mobile Predictive Systems* | CHI 2016 | ref9 | Mobile display of uncertain arrival and wait times; the leave-by card |
| Kale, Nguyen, Kay, Hullman. *Hypothetical Outcome Plots Help Untrained Observers Judge Trends in Ambiguous Data* | IEEE VIS 2018 (TVCG 2019) | not yet | Alternatives to the dotplot for showing simulated journey outcomes |
| Hullman, Qiao, Correll, Kale, Kay. *In Pursuit of Error: A Survey of Uncertainty Visualization Evaluation* | IEEE VIS 2018 (TVCG 2019) | not yet | How to evaluate uncertainty displays; the metrics for H2 |

## Explanations and intelligibility (explaining what changed after a gate change)

| Paper | Venue | In bib | Grounds |
|---|---|---|---|
| ✅ Lim, Dey, Avrahami. *Why and Why Not Explanations Improve the Intelligibility of Context-Aware Intelligent Systems* | CHI 2009 | ref7 | The change view and calculation trace; H1 and the cause-explanation metric |
| Liao, Gruen, Miller. *Questioning the AI: Informing Design Practices for Explainable AI User Experiences* | CHI 2020 | not yet | Which questions travelers ask of a recommendation ("why this leave-by time?") |
| Kulesza, Burnett, Wong, Stumpf. *Principles of Explanatory Debugging to Personalize Interactive Machine Learning* | IUI 2015 | not yet | Letting travelers correct extracted itinerary fields and preferences |

## Human-AI interaction, trust and fallback (safety policy, provenance labels, model fallback)

| Paper | Venue | In bib | Grounds |
|---|---|---|---|
| Amershi et al. *Guidelines for Human-AI Interaction* | CHI 2019 | ref144 | Correction, scoped fallback, provenance labels, and withholding unsupported recommendations |
| Horvitz. *Principles of Mixed-Initiative User Interfaces* | CHI 1999 | ref157 | When the app should act, suggest or defer to the traveler |
| Kocielnik, Amershi, Bennett. *Will You Accept an Imperfect AI? Exploring Designs for Adjusting End-user Expectations of AI Systems* | CHI 2019 | not yet | Communicating that probability estimates are imperfect; confidence ratings (S3) |
| Bansal et al. *Does the Whole Exceed its Parts? The Effect of AI Explanations on Complementary Team Performance* | CHI 2021 | not yet | Whether explanations actually improve decisions, not only trust |

## Reliance on AI and language models (2023 onward)

| Paper | Venue | In bib | Grounds |
|---|---|---|---|
| ✅ Kim, Liao, Vorvoreanu, Ballard, Wortman Vaughan. *"I'm Not Sure, But...": Examining the Impact of Large Language Models' Uncertainty Expression on User Reliance and Trust* | FAccT 2024 | ref218 (add bibitem) | Wording of provisional estimates and abstention; S3 confidence |
| ✅ Kim, Wortman Vaughan, Liao, Lombrozo, Russakovsky. *Fostering Appropriate Reliance on Large Language Models: The Role of Explanations, Sources, and Inconsistencies* | CHI 2025 | ref219 (add bibitem) | Provenance labels and explanations; scoring reliance on correct and incorrect plans |
| ✅ Vasconcelos, Jörke, Grunde-McLaughlin, Gerstenberg, Bernstein, Krishna. *Explanations Can Reduce Overreliance on AI Systems During Decision-Making* | CSCW 2023 (PACM HCI 7, CSCW1) | ref220 (add bibitem) | The calculation trace as a low-cost way to verify a recommendation |
| Bo, Wan, Anderson. *To Rely or Not to Rely? Evaluating Interventions for Appropriate Reliance on Large Language Models* | CHI 2025 | not yet | Reliance interventions reduce over-reliance but rarely improve appropriate reliance |

## Aviation and AI (2020 onward)

| Paper | Venue | In bib | Grounds |
|---|---|---|---|
| ✅ Zhang, Feger, Dullenkopf, Liao, Süsslin, Liu, Butz. *Beyond Recommendations: From Backward to Forward AI Support of Pilots' Decision-Making Process* | CSCW 2024 (PACM HCI 8, CSCW2) | ref221 (add bibitem) | Supporting the traveler's own decision with the time budget and steps, not only a recommendation; H1 |
| Guimarães, Soares, Ventura. *Decision Support Models for Predicting and Explaining Airport Passenger Connectivity From Data* | IEEE T-ITS 2022 (journal) | not eligible | Missed-connection prediction at a hub; journal, not a conference paper |
| Schon, Bruder, Liebherr, Theis. *Cleared for Takeoff: Artificial Intelligence Acceptance in Air Traffic Control* | CHIWORK 2025 | not yet | Controller survey (N=83) on trust and transparency; attitudes only |
| Brown, Pelikan, Broth. *Walking with Robots: Video Analysis of Human-Robot Interactions in Transit Spaces* | CHI 2026 | not yet | Airport cleaning robots and passenger movement; not information support |
| Wen et al. *AdaptiveCoPilot: Design and Testing of a NeuroAdaptive LLM Cockpit Guidance System* | IEEE VR 2025 | not yet | LLM cockpit guidance, N=8 pilots |

## Airport and indoor navigation, accessibility (terminal routing, AR guide, accessibility settings)

| Paper | Venue | In bib | Grounds |
|---|---|---|---|
| Guerreiro, Ahmetovic, Sato, Kitani, Asakawa. *Airport Accessibility and Navigation Assistance for People with Visual Impairments* | CHI 2019 | not yet | Airport-specific navigation; step-free and accessibility routing |
| Ahmetovic, Gleason, Ruan, Kitani, Takagi, Asakawa. *NavCog: A Navigational Cognitive Assistant for the Blind* | MobileHCI 2016 | not yet | Turn-by-turn indoor guidance and the map/text fallback |
| Sato, Oh, Naito, Takagi, Kitani, Asakawa. *NavCog3: An Evaluation of a Smartphone-Based Blind Indoor Navigation Assistant with Semantic Features in a Large-Scale Environment* | ASSETS 2017 | not yet | Large-venue indoor navigation evaluation; navigation-error metrics |
| Möller, Kranz, Diewald, Roalter, Huitl, Stockinger, Koelle, Lindemann. *Experimental Evaluation of User Interfaces for Visual Indoor Navigation* | CHI 2014 | not yet | Compares VR and AR views for camera-based indoor navigation under unreliable localization; the Map and Camera views and the later AR comparison |

## Notifications and interruptions (reminders, proactive prompts)

| Paper | Venue | In bib | Grounds |
|---|---|---|---|
| Iqbal, Bailey. *Effects of Intelligent Notification Management on Users and Their Tasks* | CHI 2008 | ref142 | Timing reminders and prompts at task boundaries |
| Mehrotra, Pejovic, Vermeulen, Hendley, Musolesi. *My Phone and Me: Understanding People's Receptivity to Mobile Notifications* | CHI 2016 | not yet | When travelers act on leave-by reminders |
| Pielot, Church, de Oliveira. *An In-Situ Study of Mobile Phone Notifications* | MobileHCI 2014 | not yet | Notification load and attention on the move |

## Travel, time zones and mobile planning (itineraries, time-zone-aware deadlines)

| Paper | Venue | In bib | Grounds |
|---|---|---|---|
| Brown, Chalmers. *Tourism and Mobile Technology* | ECSCW 2003 | not yet | How travelers plan and replan with mobile tools; the interview findings |
| Tang, Zhao, Cao, Inkpen. *Your Time Zone or Mine? A Study of Globally Time Zone-Shifted Collaboration* | CSCW 2011 | ref152 | Reasoning across time zones; time-zone-aware deadlines |
| Mok, Sun, Sen, Sarrafzadeh. *Challenging but Connective: Large-Scale Characteristics of Synchronous Collaboration Across Time Zones* | CHI 2023 | ref153 | Time-zone burden in scheduling work during layovers |

## Evaluation method and measures (Evaluation Plan)

| Paper | Venue | In bib | Grounds |
|---|---|---|---|
| Greenberg, Buxton. *Usability Evaluation Considered Harmful (Some of the Time)* | CHI 2008 | not yet | Justifying a comparative study against an established baseline |
| Ledo, Houben, Vermeulen, Marquardt, Oehlberg, Greenberg. *Evaluation Strategies for HCI Toolkit Research* | CHI 2018 | not yet | Choosing evaluation strategies for a prototype |
| Kaptein, Nass, Markopoulos. *Powerful and Consistent Analysis of Likert-Type Rating Scales* | CHI 2010 | not yet | Analyzing ease and confidence ratings (S3) |
| Hart. *NASA-Task Load Index (NASA-TLX); 20 Years Later* | HFES Annual Meeting 2006 | not yet | A workload measure, if you add cognitive workload as a metric |

## Already in the bibliography but weaker fits

| Paper | Venue | In bib | Note |
|---|---|---|---|
| Guo, Kandel, Hellerstein, Heer. *Proactive Wrangling: Mixed-Initiative End-User Programming of Data Transformation Scripts* | UIST 2011 | ref158 | Mixed-initiative design, but about data wrangling rather than travel |

## Picking the anchors

Final choice (2026-11-11): two earlier papers kept for the primary hypotheses, Fernandes 2018 (H2,
uncertainty display) and Lim 2009 (H1, change explanation), and four papers from 2023 onward: three on
reliance on AI and language models and one aviation study of AI decision support for pilots
(Zhang et al. 2024). Möller 2014 was dropped because no recent AR indoor-navigation
paper at a peer-reviewed HCI conference was found and the AR comparison is secondary; Amershi 2019 and Kocielnik
2019 were replaced by the Kim papers. Kay 2016 overlaps with Fernandes 2018; Guerreiro 2019 studies
blind travelers rather than AirBorder's population.
