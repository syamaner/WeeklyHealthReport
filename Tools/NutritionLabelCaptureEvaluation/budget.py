"""Route C spend stops (plan section 8.3, decision 9). Pure.

Inspect's native `cost_limit` is per sample and priced from a model-cost table;
the plan's stops use the cost OpenRouter reports per response and span the whole
evaluation, so this small guard enforces them around each call:

- stop a model's run if any single call reports more than $0.05;
- stop the whole evaluation at $25 of reported cost;
- stop at the first unknown-cost call beyond three;
- reserve the sealed run's 200 calls (at the $0.05 per-call ceiling, $10) out of the
  total before any development call, so the stop can never be reached with the
  untouched set unrun.

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
    sealed_reserved_calls: int = 200
    sealed_run: bool = False
    spent_usd: Decimal = Decimal("0")
    unknown_cost_calls: int = 0
    sealed_calls_made: int = 0
    stopped_models: set[str] = field(default_factory=set)

    @property
    def reserved_usd(self) -> Decimal:
        """Spend held back for the sealed calls not yet made."""
        remaining = max(self.sealed_reserved_calls - self.sealed_calls_made, 0)
        return Decimal(remaining) * self.per_call_usd

    def _limit(self) -> Decimal:
        # Development calls may not touch the sealed reservation; sealed calls may.
        return self.total_usd if self.sealed_run else self.total_usd - self.reserved_usd

    def before_call(self, model: str) -> None:
        if model in self.stopped_models:
            raise BudgetStop(f"{model} was stopped by the per-call limit")
        if self.sealed_run and self.sealed_calls_made >= self.sealed_reserved_calls:
            raise BudgetStop("the sealed run has used its reserved calls")
        if self.spent_usd + self.per_call_usd > self._limit():
            raise BudgetStop("total stop reached (the sealed-run reservation is held back)")

    def record(self, model: str, reported_cost_usd: Decimal | None) -> None:
        if self.sealed_run:
            self.sealed_calls_made += 1
        if reported_cost_usd is None:
            self.unknown_cost_calls += 1
            if self.unknown_cost_calls > self.unknown_cost_calls_allowed:
                raise BudgetStop("more than three unknown-cost calls")
            return
        self.spent_usd += reported_cost_usd
        if reported_cost_usd > self.per_call_usd:
            self.stopped_models.add(model)
            raise BudgetStop(f"{model} call cost {reported_cost_usd} exceeds the per-call stop")
        if self.spent_usd >= self.total_usd:
            raise BudgetStop("total stop reached")
