# Changelog

## 0.1.1 (2026-11-24)

- Install script uses `$os_name`, `$arch_name`, and `$CLI_VERSION` with no braces. The task driver treats `${...}` as Nomad interpolation and failed the prestart task with "Unknown variable".

## 0.1.0 (2026-11-23)

- Initial pack. Prestart install of the Cursor CLI, worker task, Nomad Variable API key, and an HTTP check on `/healthz`.
