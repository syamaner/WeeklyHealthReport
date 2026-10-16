"""Route C spend stops (plan section 8.3, decision 9). Pure.

Inspect's native `cost_limit` is per sample and priced from a model-cost table;
the plan's stops use the cost OpenRouter reports per response and span the whole
evaluation, so this small guard enforces them around each call:

- stop a model's run if any single call reports more than $0.05;
- stop the whole evaluation at $25 of reported cost;
- stop at the first unknown-cost call beyond three.

Unknown costs are counted and reported as unknown, never as zero.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from decimal import Decimal


class BudgetStop(RuntimeError):
    """Raised when a pre-registered spend stop is reached."""


@dataclass
class RunBudget:
    per_call_usd: Decimal = Decimal("0.05")
    total_usd: Decimal = Decimal("25")
    unknown_cost_calls_allowed: int = 3
    reserved_usd: Decimal = Decimal("0")
    spent_usd: Decimal = Decimal("0")
    unknown_cost_calls: int = 0
    stopped_models: set[str] = field(default_factory=set)

    def before_call(self, model: str) -> None:
        if model in self.stopped_models:
            raise BudgetStop(f"{model} was stopped by the per-call limit")
        if self.spent_usd + self.reserved_usd >= self.total_usd:
            raise BudgetStop("total stop reached (including the reserved sealed-run budget)")

    def record(self, model: str, reported_cost_usd: Decimal | None) -> None:
        if reported_cost_usd is None:
            self.unknown_cost_calls += 1
            if self.unknown_cost_calls > self.unknown_cost_calls_allowed:
                raise BudgetStop("more than three unknown-cost calls")
            return
        self.spent_usd += reported_cost_usd
        if reported_cost_usd > self.per_call_usd:
            self.stopped_models.add(model)
            raise BudgetStop(f"{model} call cost {reported_cost_usd} exceeds the per-call stop")
        if self.spent_usd + self.reserved_usd >= self.total_usd:
            raise BudgetStop("total stop reached")
