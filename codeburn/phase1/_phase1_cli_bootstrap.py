from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType


_PHASE1_DIR = Path(__file__).resolve().parent


def _load_local_module(module_name: str, file_name: str) -> ModuleType:
    module_path = _PHASE1_DIR / file_name
    spec = importlib.util.spec_from_file_location(module_name, module_path)
    if spec is None or spec.loader is None:
        raise ImportError(f"unable to load phase1 local module: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_print_phase1_header():
    module = _load_local_module("_codeburn_phase1_header_local", "codeburn_phase1_header.py")
    return module.print_phase1_header


def load_token_observability_level():
    module = _load_local_module("_codeburn_token_observability_local", "token_observability.py")
    return module.token_observability_level