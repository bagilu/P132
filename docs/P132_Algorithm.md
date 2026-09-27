# P132 PrepareArticle Algorithm Baseline — P132-ALG-0.1
V0.1 is deliberately conservative. Cold-start learners receive about half the normal budget; normal budget is approximately 2 foreign occurrences per 100 Chinese characters, capped at 10. Candidate priority currently maps Emerging/Stable > Familiar > New. Approved and replacement-eligible occurrences only are considered. Japanese may use `surface_reading` presentation.

The V0.1 implementation is deterministic and intentionally simple. Recency, diversity, NewWordCeiling, richer stage allocation, and research-calibrated scoring are reserved for the next algorithm migration. AlgorithmVersion is stored on every exposure so historical evidence remains interpretable.
