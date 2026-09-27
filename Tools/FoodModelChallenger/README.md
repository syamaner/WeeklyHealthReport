# Offline challenger preparation

This tool prepares #100's comparison packets from the unchanged #92 frozen baseline. It does not contact a provider, run a model, save food or permit automatic acceptance. See [the readiness contract](../../docs/model-challenger-readiness-v1.md) for reproduction and the decisions required before execution.

Packets preserve hard-rule-admitted candidate order and whole records, while omitting local labels and lexical scores. `validate_choice` admits only a listed record ID or decline. An empty packet must decline without a provider call. The generated manifest deliberately has `run_ready: false` and leaves model/run/spend/authority fields unset.
