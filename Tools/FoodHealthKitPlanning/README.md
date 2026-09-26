# Executable planning specification

This standard-library-only reference supports the **unratified**
[HealthKit projection plan](../../docs/food-healthkit-write-plan.md). It has no
HealthKit imports, Apple SDK, file writer, credentials, network or app integration.
It cannot request permission, create a HealthKit sample, save or delete anything.

Run invented-data contract examples from the repository root:

```sh
python3 -m unittest discover -s Tools/FoodHealthKitPlanning/tests -v
```

The tests compare all 39 proposed identifiers/units with the existing read
catalogue, exercise strict scalar eligibility and omissions, deterministic intent
identity, exact unit arithmetic, duplicate/mixed-version input rejection, synthetic
readback comparison and exact journal-owned deletion filtering. A source/date
predicate oracle checks half-open membership and missing-versus-zero behaviour.
It is not a replacement for HealthKit statistics or proof of Apple API behaviour.

Input contributions are **already consumed and basis-normalised**, with explicit
confirmation/compatibility flags supplied by each synthetic case. The reference
does not infer those facts, resolve product identity, convert serving sizes, handle
unapproved vitamin forms or independently prove an input's provenance. Rational
arithmetic avoids hiding rounding in the examples; a real adapter's representation
and comparison tolerance still require ratification and tests.

The reference does not implement the proposed durable journal, permission state,
crash recovery, real predicates, schema-v5 serializer or device adapter. Those
remain future implementation evidence, clearly separate from these planning
examples. No existing app code calls this module.
