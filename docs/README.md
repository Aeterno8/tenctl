# Tenctl Documentation

Sphinx documentation for Tenctl.

## Build

```bash
cd docs
pip install -r requirements.txt
make html
```

Open `build/html/index.html` in browser.

## Build Serbian Translation

```bash
make build-sr
```

## Structure

- `source/getting-started/` - Installation and quickstart
- `source/user-guide/` - Tenant management
- `source/admin-guide/` - Configuration and operations
- `source/reference/` - CLI commands and error codes

## Format

Written in reStructuredText (RST).

Documentation: https://www.sphinx-doc.org/
