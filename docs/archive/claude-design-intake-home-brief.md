# Claude Design brief: intake-first home

## Product direction

Make the app home screen a summary of today's logged food intake, followed by clear routes to manage food intake and export Apple Health data. Use the current local calendar day for food intake. Existing completed-day HealthKit export periods remain unchanged.

## Home

Show date, logged energy, protein, carbohydrates and fat, plus a concise list or count of today's entries. Label these as logged intake, not a claim about everything eaten. Represent missing nutrients and an empty log explicitly; unknown values must not silently become zero. Distinguish today's provisional totals from completed-day HealthKit summaries.

Provide two clear actions: Manage food intake and Export health data. Food management leads to search, barcode capture, saved foods/favourites, adding/editing/removing entries and reviewed list import. Health export leads to period selection, review and the existing manual export flow. Health export diagnostics and account settings should not dominate the landing screen.

## Search states to design

Use everyday food language, clear candidate names/preparation, and visible source context. Keep technical score/version details in expandable detail. Distinguish no match, missing catalogue coverage, a component search suggestion, unavailable search and an unresolved entry. Fish and chips should offer separate fish and potato-chip searches; ribeye should explain the missing cut and clearly label broader alternatives. Never turn these into automatic nutrition acceptance.

## Boundaries and deliverables

Design home, food management, search/results/no-match, candidate review, and health export navigation in Claude Design. Include empty, partial-data and loading states, accessible text sizes and one-handed interaction. Reuse the existing explicit confirmation and evidence flows. No medical targets or advice; no new provider/network/account assumption. Produce reviewable screen designs and navigation before implementing the visual redesign.

The home intake aggregation must remain pure and local, with tests for calendar/day boundaries, unknown nutrients, edits, deletions and empty logs. Wire storage and clocks at composition. Do not duplicate export orchestration inside the new home view.
