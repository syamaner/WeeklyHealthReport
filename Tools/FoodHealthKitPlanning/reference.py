"""Executable planning examples only. No HealthKit, storage or transport adapter."""
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from fractions import Fraction
from collections import defaultdict
import re


UNITS = {
    **dict.fromkeys("carbohydrates protein fat_total fat_saturated fat_monounsaturated fat_polyunsaturated fiber sugar".split(), "g"),
    **dict.fromkeys("cholesterol thiamin_b1 riboflavin_b2 niacin_b3 pantothenic_acid_b5 vitamin_b6 vitamin_c vitamin_e calcium chloride iron magnesium phosphorus potassium sodium zinc copper manganese caffeine".split(), "mg"),
    **dict.fromkeys("vitamin_a biotin_b7 folate_b9 vitamin_b12 vitamin_d vitamin_k chromium iodine molybdenum selenium".split(), "mcg"),
    "energy_consumed": "kcal", "water": "mL",
}
SCALES = {"g": ("mass", Fraction(1)), "mg": ("mass", Fraction("0.001")),
          "mcg": ("mass", Fraction("0.000001")), "mL": ("volume", Fraction(1)),
          "L": ("volume", Fraction(1000)), "kcal": ("energy", Fraction(1))}


@dataclass(frozen=True)
class Contribution:
    contribution_id: str
    log_id: str
    log_version: str
    nutrient: str
    state: str
    amount: str | None = None
    unit: str | None = None
    confirmed_quantity_and_identity: bool = True
    compatible_form: bool = True
    conflict: bool = False
    occurred_at: int = 100


@dataclass(frozen=True)
class Intent:
    sync_key: str
    writer: str
    revision: int
    log_id: str
    log_version: str
    nutrient: str
    amount: Fraction
    unit: str
    occurred_at: int


def converted(value):
    """An omission reason is never replaced with an exact numeric value."""
    if value.nutrient not in UNITS:
        return None, "unsupported_nutrient"
    if value.state not in ("measured", "augmented"):
        return None, "non_scalar_state"
    if value.conflict or not value.confirmed_quantity_and_identity:
        return None, "unconfirmed_or_conflicted"
    if not value.compatible_form:
        return None, "unapproved_form"
    target = UNITS[value.nutrient]
    if value.unit not in SCALES or SCALES[value.unit][0] != SCALES[target][0]:
        return None, "incompatible_unit"
    if not isinstance(value.amount, str):
        return None, "invalid_amount"
    try:
        amount = Decimal(value.amount)
    except (InvalidOperation, TypeError, ValueError):
        return None, "invalid_amount"
    if not amount.is_finite() or amount < 0:
        return None, "invalid_amount"
    return Fraction(amount) * SCALES[value.unit][1] / SCALES[target][1], None


def prepare(values, writer, revision):
    """Return deterministic intents and per-item/nutrient omissions; never save."""
    if not re.fullmatch(r"[A-Za-z0-9_-]+", writer) or type(revision) is not int or revision < 1:
        raise ValueError("invalid writer or revision")
    groups, versions, identifiers = defaultdict(list), defaultdict(set), set()
    for value in values:
        if value.contribution_id in identifiers or any(not re.fullmatch(r"[A-Za-z0-9_-]+", text)
                for text in (value.log_id, value.log_version, value.contribution_id)):
            raise ValueError("duplicate contribution or invalid log identity")
        identifiers.add(value.contribution_id)
        if type(value.occurred_at) is not int:
            raise ValueError("invalid consumption timestamp")
        groups[value.log_id, value.nutrient].append(value)
        versions[value.log_id].add((value.log_version, value.occurred_at))
    if any(len(items) != 1 for items in versions.values()):
        raise ValueError("mixed log versions")
    intents, omissions = [], {}
    for (log, nutrient), contributions in sorted(groups.items()):
        results = [converted(value) for value in contributions]
        reasons = tuple(sorted({reason for _, reason in results if reason}))
        if reasons:
            omissions[log, nutrient] = reasons
            continue
        intents.append(Intent(f"food-projection-v1:{writer}:{log}:{nutrient}", writer, revision,
                              log, contributions[0].log_version, nutrient,
                              sum((amount for amount, _ in results), Fraction(0)), UNITS[nutrient], contributions[0].occurred_at))
    return tuple(intents), omissions


@dataclass(frozen=True)
class SyntheticSample:
    uuid: str
    source: str
    intent: Intent
    timestamp: int


def readback_matches(intent, samples, source):
    matches = [sample for sample in samples if sample.source == source
               and sample.intent.writer == intent.writer and sample.intent.sync_key == intent.sync_key]
    return len(matches) == 1 and matches[0].intent == intent and matches[0].timestamp == intent.occurred_at


def removable(samples, source, journal):
    """Journal maps exact owned UUIDs to full prior intents; never a date delete."""
    return tuple(sample for sample in samples if sample.source == source
                 and sample.uuid in journal and sample.intent == journal[sample.uuid]
                 and sample.timestamp == journal[sample.uuid].occurred_at)


def selected_source_total(samples, source, nutrient, start, end):
    """Predicate oracle only; a real adapter must use HealthKit statistics."""
    amounts = [sample.intent.amount for sample in samples if sample.source == source
               and sample.intent.nutrient == nutrient and start <= sample.timestamp < end]
    return sum(amounts, Fraction(0)) if amounts else None
