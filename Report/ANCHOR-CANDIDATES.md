# Anchor source candidates

Choose **up to 3** authoritative peer-reviewed conference papers as the report's anchor sources.
Then list their bibliography keys under `anchors` in `.github/report-review/ANCHORS.json` and set
`"approved": true`. The **Citation anchors** check fails until you do.

- **In bib** gives the key when the paper is already in `Report/main.tex`. Those entries and
  their DOIs are already there.
- **Not yet** means the paper needs a new `\bibitem`. Confirm the full citation and DOI in the
  ACM Digital Library or IEEE Xplore before adding it.
- **Grounds** says which part of AirBorder the paper would support.

## Uncertainty and probabilistic decisions (leave-by time, probability of reaching the gate)

| Paper | Venue | In bib | Grounds |
|---|---|---|---|
| Fernandes, Walls, Munson, Hullman, Kay. *Uncertainty Displays Using Quantile Dotplots or CDFs Improve Transit Decision-Making* | CHI 2018 | ref8 | Probability-based leave-by guidance and the dotplot; H2 (deadline interpretation) |
| Kay, Kola, Hullman, Munson. *When(ish) is My Bus? User-centered Visualizations of Uncertainty in Everyday, Mobile Predictive Systems* | CHI 2016 | ref9 | Mobile display of uncertain arrival and wait times; the leave-by card |
| Kale, Nguyen, Kay, Hullman. *Hypothetical Outcome Plots Help Untrained Observers Judge Trends in Ambiguous Data* | IEEE VIS 2018 (TVCG 2019) | not yet | Alternatives to the dotplot for showing simulated journey outcomes |
| Hullman, Qiao, Correll, Kale, Kay. *In Pursuit of Error: A Survey of Uncertainty Visualization Evaluation* | IEEE VIS 2018 (TVCG 2019) | not yet | How to evaluate uncertainty displays; the metrics for H2 |

## Explanations and intelligibility (explaining what changed after a gate change)

| Paper | Venue | In bib | Grounds |
|---|---|---|---|
| Lim, Dey, Avrahami. *Why and Why Not Explanations Improve the Intelligibility of Context-Aware Intelligent Systems* | CHI 2009 | ref7 | The change view and calculation trace; H1 and the cause-explanation metric |
| Liao, Gruen, Miller. *Questioning the AI: Informing Design Practices for Explainable AI User Experiences* | CHI 2020 | not yet | Which questions travelers ask of a recommendation ("why this leave-by time?") |
| Kulesza, Burnett, Wong, Stumpf. *Principles of Explanatory Debugging to Personalize Interactive Machine Learning* | IUI 2015 | not yet | Letting travelers correct extracted itinerary fields and preferences |

## Human-AI interaction, trust and fallback (safety policy, provenance labels, model fallback)

| Paper | Venue | In bib | Grounds |
|---|---|---|---|
| Amershi et al. *Guidelines for Human-AI Interaction* | CHI 2019 | ref144 | Correction, scoped fallback, provenance labels, and withholding unsupported recommendations |
| Horvitz. *Principles of Mixed-Initiative User Interfaces* | CHI 1999 | ref157 | When the app should act, suggest or defer to the traveler |
| Kocielnik, Amershi, Bennett. *Will You Accept an Imperfect AI? Exploring Designs for Adjusting End-user Expectations of AI Systems* | CHI 2019 | not yet | Communicating that probability estimates are imperfect; confidence ratings (S3) |
| Bansal et al. *Does the Whole Exceed its Parts? The Effect of AI Explanations on Complementary Team Performance* | CHI 2021 | not yet | Whether explanations actually improve decisions, not only trust |

## Airport and indoor navigation, accessibility (terminal routing, AR guide, accessibility settings)

| Paper | Venue | In bib | Grounds |
|---|---|---|---|
| Guerreiro, Ahmetovic, Sato, Kitani, Asakawa. *Airport Accessibility and Navigation Assistance for People with Visual Impairments* | CHI 2019 | not yet | Airport-specific navigation; step-free and accessibility routing |
| Ahmetovic, Gleason, Ruan, Kitani, Takagi, Asakawa. *NavCog: A Navigational Cognitive Assistant for the Blind* | MobileHCI 2016 | not yet | Turn-by-turn indoor guidance and the map/text fallback |
| Sato, Oh, Naito, Takagi, Kitani, Asakawa. *NavCog3: An Evaluation of a Smartphone-Based Blind Indoor Navigation Assistant with Semantic Features in a Large-Scale Environment* | ASSETS 2017 | not yet | Large-venue indoor navigation evaluation; navigation-error metrics |
| Möller, Kranz, Diewald, Roalter, Huitl, Stockinger, Koelle, Lindemann. *Experimental Evaluation of User Interfaces for Visual Indoor Navigation* | CHI 2014 | not yet | Comparing camera-based and map-based indoor guidance; the later AR comparison |

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

## Picking three

Three anchors should together cover the app's core claim and your primary hypotheses. A
common shape is one uncertainty paper (the leave-by probability), one explanation or
human-AI paper (what changed and why), and one navigation or airport paper (routing in the
terminal). Several combinations work. The choice is yours.
