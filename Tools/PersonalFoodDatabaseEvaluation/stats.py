"""Wilson 95 per cent score interval. Pure."""
import math

Z95 = 1.959963984540054


def wilson(count: int, n: int, z: float = Z95):
    """(low, high) for count successes in n trials, rounded to six places; None when n is 0."""
    if isinstance(count, bool) or isinstance(n, bool) or not isinstance(count, int) or not isinstance(n, int):
        raise TypeError("count and n must be whole numbers")
    if n < 0 or count < 0 or count > n:
        raise ValueError("need 0 <= count <= n")
    if n == 0:
        return None
    p = count / n
    denom = 1 + z * z / n
    centre = (p + z * z / (2 * n)) / denom
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / denom
    return (round(max(0.0, centre - half), 6), round(min(1.0, centre + half), 6))
