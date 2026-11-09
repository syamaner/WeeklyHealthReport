# Intake file format

One JSON file per input, written to `<workspace>/inbox/<source_id>.json` and registered with
`intake.py add`. The same item is never registered twice: re-adding refreshes its source list.

```json
{
  "source": {
    "id": "label-photos-2026-11-08",
    "kind": "image",
    "captured": "2026-11-08",
    "description": "three label photos from the owner, foods only"
  },
  "items": [
    {
      "title": "Synthetic Example Rice Cakes",
      "brand": "Example Brand",
      "aliases": ["rice cakes"],
      "kind": "food",
      "state": null,
      "region": null,
      "note": null,
      "label": {
        "origin": "photo_unconfirmed",
        "basis": "per_100_g",
        "values": {"energy_consumed": 380, "fat_total": 3.0, "fat_saturated": 0.5,
                   "carbohydrates": 80.0, "sugar": 0.5, "fiber": 4.0, "protein": 8.0, "sodium": 200}
      }
    }
  ]
}
```

The values above are synthetic, for illustration only.

Field rules:

- `source.id`: lower-case letters, digits and hyphens; name the input type and date, never a
  person, place or order.
- `source.kind`: `free_text`, `pdf`, `csv`, `image`, `export`, `url` or `typed`.
- `title`: the product as sold, without the brand when `brand` is set; keep pack size if it is
  part of the identity. `aliases`: what the owner might type, no brand-only aliases.
- `kind`: `food` or `supplement` (supplements are kept but not exported in catalogue v1).
- `state`: `raw`, `cooked`, `canned`, `frozen`, `dried`, `smoked` or null when the input does not
  say. `region`: `UK`, `Taiwan`, `restaurant` or null. Restaurant items are name-only.
- `label`: only when the input shows real label values.
  - `origin`: `owner_typed` (the owner wrote the numbers), `photo_unconfirmed` / `page_unconfirmed`
    (read by the agent), `photo_confirmed` / `page_confirmed` (after the owner checked them).
  - `basis`: `per_100_g` or `per_100_ml` for catalogue values. `per_serving` is accepted for
    supplements but not used for food values.
  - `transforms` (optional): for any value converted from what is printed,
    `{"sodium": {"transform_id": "salt_to_sodium_v1", "version": "pasted-label-conversions-v1",
    "source_value": {"value": 0.5, "unit": "g"}}}`. These are the app's own calculated pairs (so the
    value keeps `calculated: true`): `salt_to_sodium_v1` and `kj_to_kcal_v1`, both version
    `pasted-label-conversions-v1`. (`mass-g-to-mg` / `v1` is only for Open Food Facts values and is
    a unit conversion, not a calculation.) The export recomputes the value from
    `source_value` and refuses a mismatch.
  - `values`: canonical keys and units only: `energy_consumed` kcal; `protein`, `fat_total`,
    `fat_saturated`, `fat_monounsaturated`, `fat_polyunsaturated`, `carbohydrates`, `sugar`,
    `fiber` g; `sodium` mg (label salt g × 400, recorded as a transform); vitamins and minerals in mg or mcg as in
    `intake.py` `CANON`. Copy only what is printed; never derive a missing value.
- A label is one printed panel. When the same food arrives again with a confirmed label, the newest
  confirmed label replaces the earlier one as a whole; nutrients are never mixed across two panels,
  because the product may have been reformulated.
- Never include amounts eaten, prices, dates of purchase, names, addresses or reference numbers.
