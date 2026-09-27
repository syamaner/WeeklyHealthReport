# Pre-tuning judgement correction

v1 incorrectly looked up `fatTotal` rather than the catalogue's `fat_total`, classifying all numeric fat cases as tentative-only. It also labelled bison ribeye as relevant to the default beef ribeye intent. v2 fixes both errors before production tuning. The query list is unchanged, and the same first-run baseline is scored against v2. Both versions and v1 metrics are retained; this is a visible author correction, not independent review.
