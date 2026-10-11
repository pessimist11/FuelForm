#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
python3 scripts/check_project.py
backend/.venv/bin/python -m pytest backend/tests -q
CLANG_MODULE_CACHE_PATH=/private/tmp/fuelform-clang-cache swift run --disable-sandbox --cache-path /private/tmp/fuelform-spm-cache --package-path ios --scratch-path /private/tmp/fuelform-swift-build FuelFormCoreChecks
