"""Deterministic RNG wrapper.

The simulator must be reproducible: same seed -> same fight, same fish, same
outcome.  ``random.Random`` is a fixed Mersenne Twister and is stable across
CPython versions, so it is a safe choice.  The wrapper keeps the call sites
small and makes the seed explicit.
"""

from __future__ import annotations

import random
from typing import Iterable, Sequence, TypeVar

T = TypeVar("T")


class Rng:
    """Small deterministic wrapper around :class:`random.Random`."""

    __slots__ = ("_rng",)

    def __init__(self, seed: int | str | None = None) -> None:
        self._rng = random.Random(seed)

    # -- primitives --------------------------------------------------------
    def random(self) -> float:
        return self._rng.random()

    def uniform(self, a: float, b: float) -> float:
        return self._rng.uniform(a, b)

    def randint(self, a: int, b: int) -> int:
        return self._rng.randint(a, b)

    def choice(self, seq: Sequence[T]) -> T:
        return self._rng.choice(seq)

    def choices(self, seq: Sequence[T], weights: Iterable[float], k: int = 1) -> list[T]:
        return self._rng.choices(seq, weights=list(weights), k=k)

    def gauss(self, mu: float = 0.0, sigma: float = 1.0) -> float:
        return self._rng.gauss(mu, sigma)

    def seed(self, seed: int | str | None) -> None:
        self._rng = random.Random(seed)

    # -- helpers -----------------------------------------------------------
    def chance(self, percent: float) -> bool:
        """True with probability ``percent`` / 100."""
        return self._rng.random() * 100.0 < percent

    def between(self, a: float, b: float) -> float:
        return self.uniform(a, b)
