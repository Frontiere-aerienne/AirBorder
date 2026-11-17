# No-LLM runtime

AirBorder's native app, browser app, and Worker do not call language models. Planning and calculation explanations stay deterministic. Apple Vision ticket OCR and the optional Google Cloud Vision `TEXT_DETECTION` endpoint are separate from generative inference and are not changed.

The former Workers AI explanation endpoint and Gemini official-link discovery adapter have been removed. The entry chain still tries configured Sherpa and Timatic structured providers. If neither can answer, it provides bundled official verification links for supported destinations, or directs the traveler to verify manually. It returns no inferred requirements and cannot authorize entry or a landside/city recommendation.

For maintainers: both Worker configuration files omit the Workers AI binding. No Gemini key, model name, or discovery domain configuration is needed. Repository changes do not remove legacy settings from an already deployed Worker or update a live deployment; deploy the revised code through the project's normal release process and review unused credentials separately. The [July design report](Reports/2026-07-14-airportxr-long-haul-layover.md) is historical and describes the retired prototype.
