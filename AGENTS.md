# Agents

This repository is a Nomad Pack registry for running Cursor CLI self-hosted (My Machines) workers on HashiCorp Nomad. Keep it small. Match Nomad Pack's layout (`nomad-pack generate`, the Create custom packs guide) and the job that already ran.

## What it does

`packs/cursor_worker` renders one service job. A prestart task installs the Cursor CLI. The main task clones a git repo (or prepares an empty directory) and runs `cursor-agent worker ... start`. The API key comes from a Nomad Variable, rendered into `secrets/cursor.env` as `CURSOR_API_KEY`.

## What done looks like

- `make install-tools && make validate` passes.
- That target renders default vars, `driver=raw_exec`, an any-repo pool, and a pinned `cli_version`, then `nomad job validate` on each rendered job. It also rejects `${...}` in the rendered job other than Nomad's own interpolations, and runs each rendered job on `nomad agent -dev` (as `raw_exec`, because `exec` needs root) until `install-cli` starts. `nomad job validate` alone does not interpolate driver config.
- Invalid `driver` and `clone_git_repos` without a pool fail at render.
- A real worker is not required for a pack change. Connecting needs a user API key, which must not be committed.

## Out of scope

Custom container images, Kubernetes, Vault, private-repo clone credentials, checksum verification of the CLI archive, and publishing to the Nomad Pack community registry. Nomad Variables only for the API key. Do not add a `nomad_variable` block that contains a secret.

## Decisions

- Pack name `cursor_worker` (underscore). Nomad Pack pack names and directories use underscores. The job name defaults to that; override with `job_name`.
- No image. Prestart runs `curl -fsSL https://cursor.com/install | bash` when `cli_version` is empty. That script hardcodes one version and ignores `?version=`. When `cli_version` is set, the task downloads `https://downloads.cursor.com/lab/<version>/<os>/<arch>/agent-cli-package.tar.gz` and links `cursor-agent`, which is the layout the script uses. Say so in the README if that URL shape changes.
- Call `cursor-agent`, not `agent`. The install script links both to the same binary. `agent` collides with other tools.
- Command shape, from the job that ran on Nomad 2.1.1 with CLI 2026.11.22: `cursor-agent worker --name nomad-<alloc id> --worker-dir <dir> --management-addr 0.0.0.0:${NOMAD_PORT_mgmt} start`. Options go before `start`.
- `driver` defaults to `exec`. `raw_exec` is the only other value. Document that `raw_exec` must be enabled on the client and is not sandboxed.
- The `exec` driver runs tasks as `nobody`. `nobody`'s HOME is `/nonexistent` and overrides the `env` block. Keep `export HOME="$NOMAD_ALLOC_DIR/home"` inside both task commands. Setting `env { HOME = ... }` alone does not work on `exec`. The alloc dir is shared; the task dir is not. The CLI has to be installed under the alloc dir.
- In `config.args` and template `data`, do not write shell locals as `${name}`. The task driver interpolates `${...}` and fails the task with `Unknown variable` for names it does not know (`os_name`, `arch_name`, `CLI_VERSION`). `$${name}` is not a fix; the driver still sees `${name}`. Use `$name`. Keep `${NOMAD_*}` and `${attr.*}` where Nomad interpolation is intended (env `HOME`, `--name`, `--management-addr`, constraints). The template `data` heredoc uses consul-template `{{ }}` and must not contain `${`.
- Worker memory default is 1024 MB, CPU 1000. Do not raise the default to 2048; that froze a 4 GB test VM. Install-task resources are extra and are reserved with the worker's.
- API key path defaults to `nomad/jobs/<job name>`, key `api_key`. Document a Cursor **user** API key for My Machines, and a service account key for pools. Document `nomad var put -force` for rotation. No secret in `variables.hcl`, docs, or examples.
- `repo_url` defaults to `https://github.com/octocat/Hello-World.git` because that is the clone in the job that ran. Empty `repo_url` skips the clone. `clone_git_repos` is the CLI's any-repo pool mode (`--clone-git-repos`) and requires a named `pool` other than `default` plus an empty `repo_url`.
- Service provider is `nomad`. HTTP check path is `/healthz` (the CLI also exposes `/readyz` and `/metrics` on `--management-addr`).
- `datacenters` defaults to `["dc1"]`, matching `nomad agent -dev` and the community registry. Override with `--var datacenters='["*"]'`. Region and namespace are omitted when empty.
- License is MPL-2.0, same as the community registry.
- The README Support section keeps the placeholder `<!-- TODO: Ko-fi link -->`. Do not invent a real tip link.

## How to test

```bash
make install-tools
make validate
```

`install-tools` downloads Nomad 2.1.1 and nomad-pack 0.4.2 for linux amd64 into `.tools/`, which is gitignored. A rootless `nomad agent -dev` cannot run the `exec` driver (`Driver must run as root`). `raw_exec` can. `make validate` starts its own dev agent on `127.0.0.1:4646` for the driver-interpolation check.

Logs, when a job is running: `nomad alloc status <alloc-id>` for events, then `nomad alloc logs <alloc-id> install-cli` and `nomad alloc logs <alloc-id> worker`. Do not use `nomad alloc logs -job`.
