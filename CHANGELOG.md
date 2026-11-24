# Changelog

## 0.1.1 (2026-11-24)

- `cursor_worker` 0.1.1: shell variables in the task script are unbraced so the Nomad driver does not parse them as interpolations. `make validate` runs each rendered job on a dev agent.

## 0.1.0 (2026-11-23)

- Initial registry. One pack, `cursor_worker`, runs a Cursor CLI self-hosted worker on Nomad.
