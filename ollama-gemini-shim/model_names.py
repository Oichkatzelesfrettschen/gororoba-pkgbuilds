"""Translate Gemini model slugs without importing the HTTP service runtime."""

from __future__ import annotations

import re


def ollama_model(gemini_slug: str, override: str | None) -> str:
    """Keep an explicit tag or override; translate numeric family versions and the final tag separator."""
    if override:
        return override
    if ":" in gemini_slug:
        return gemini_slug
    separators = list(re.finditer(r"-(?=\d)", gemini_slug))
    if not separators:
        return gemini_slug
    separator = separators[-1].start()
    # Numeric version separators belong to the family; the final numeric segment is the Ollama tag.
    family = re.sub(r"-(?=\d)", "", gemini_slug[:separator])
    return f"{family}:{gemini_slug[separator + 1 :]}"
