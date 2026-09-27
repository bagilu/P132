# P132 Evidence Model V0.1
Meaning → Form → Context → Evidence → State.

- Concept defines meaning.
- Form defines a language realization (zh-TW/en/ja).
- ArticleOccurrence anchors a concept to a position in normalized Chinese content.
- Exposure records what was actually shown to a learner.
- LearnerEvidence records explicit `translation_request` or `understand` events.
- No interaction is not equivalent to known.
- Evidence is source of truth and is not rewritten when the algorithm changes.
- LearnerVocabularyState is derived/current state and may be recalculated.
- State is keyed by User + Concept + TargetLanguage.
