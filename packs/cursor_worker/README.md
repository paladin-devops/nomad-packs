# cursor_worker

Runs a [Cursor CLI](https://cursor.com/docs/cli/overview) self-hosted worker on Nomad. The worker process is:

```bash
cursor-agent worker \
  --name "nomad-${NOMAD_ALLOC_ID}" \
  --worker-dir <dir> \
  --management-addr "0.0.0.0:${NOMAD_PORT_mgmt}" \
  start
```

There is no custom image. A prestart task installs the CLI, then the worker task clones a git repository (by default the public [octocat/Hello-World](https://github.com/octocat/Hello-World) placeholder) and starts the worker. Nomad registers a service on the dynamic `mgmt` port and checks `GET /healthz`, which the CLI serves with `/readyz` and `/metrics`. The worker task waits 5 seconds on shutdown (`shutdown_delay`) so that check can drain.

The binary is `cursor-agent`, not `agent`. The install script creates both names; this pack calls `cursor-agent` so it does not collide with another `agent` on `PATH`.

## Dependencies

- A Linux Nomad client with the `exec` driver (the Nomad client must run as root) or `raw_exec` if that plugin is enabled.
- Outbound HTTPS to `cursor.com` and `downloads.cursor.com`.
- `bash`, `curl`, and `git` on the client.
- A Cursor API key in the Nomad Variable `nomad/jobs/<job_name>`, key `api_key`.

No other packs, Consul, Vault, or volumes are required.

## Requirements

- Nomad client with `bash`, `curl`, `tar`, and (when cloning) `git` visible to the task.
- Outbound HTTPS to `cursor.com`, `downloads.cursor.com`, and the worker hosts in the [My Machines networking](https://cursor.com/docs/cloud-agent/self-hosted/my-machines) list (`api2.cursor.sh`, `api2direct.cursor.sh`, `api3.cursor.sh`).
- CA certificates. Under `exec` those come from the host's `/etc/ssl` inside the chroot.
- A Cursor API key in a Nomad Variable. Not in this pack.

## API key

My Machines workers need a **personal user API key** from Cursor Dashboard → API Keys. Service account keys only start pool workers (`pool` set). Team admin keys and organization keys cannot start a worker.

The worker task renders the key into `secrets/cursor.env` as `CURSOR_API_KEY`. The default path is `nomad/jobs/<job name>` and the default key is `api_key`, in the job's namespace.

```bash
nomad var put -force nomad/jobs/cursor_worker api_key=<user-api-key>
```

Create the variable before the worker starts, or the task stays in a template wait. Rotate it by running the same command again (`-force` replaces the variable). The pack does not define a `nomad_variable` block, because that would put a secret in the pack.

## Repository

| Variables | What the worker does |
| --- | --- |
| `repo_url` set, `pool` empty | Personal My Machines worker, bound to that checkout. This is the default. |
| `repo_url` set, `pool` set | Pool worker bound to that checkout. |
| `repo_url` empty, `pool` set | Any-repo (or self-managed) directory. No git remote is registered. |
| `repo_url` empty, `pool` a name other than `default`, `clone_git_repos=true` | Any-repo pool that checks out the claimed repositories on claim. |

`repo_ref` is a branch, tag, or commit checked out after a full clone. Leave it empty to keep the remote's default branch.

`clone_git_repos` passes `--clone-git-repos`. The CLI implies `--mint-scm-token`. A team admin has to enable SCM token minting, and `git` must be on `PATH`. The flag is only valid for a named any-repo pool, so the pack rejects it when `pool` is empty or `default`, and when `repo_url` is set.

```bash
nomad-pack run packs/cursor_worker \
  --var repo_url= \
  --var pool=my-pool \
  --var clone_git_repos=true
```

Private-repo clone credentials are out of scope. The task runs `git clone` with whatever git already has on the client (nothing, in a stock setup). Use a public URL, or a client image that already has credentials. `--clone-git-repos` is the path that uses a short-lived SCM token from Cursor instead of a credential baked into the client.

## Drivers

`driver` is `exec` by default.

`exec` chroots to a subset of the host (`/bin`, `/usr`, `/lib`, `/lib64`, `/etc`) and runs the task as `nobody`. `nobody`'s HOME is `/nonexistent`, and that overrides the task `env` block. Both commands therefore `export HOME="$NOMAD_ALLOC_DIR/home"`. The CLI is installed under that shared alloc directory so the worker task can execute it. If install fails, the prestart logs say whether `curl`, `tar`, or CA certs were the problem.

`raw_exec` is the other accepted value. It does not chroot and it does not drop to `nobody`, so host binaries are easier to find. It also does not sandbox the task: the process runs as the Nomad client's user. Enable it on the client first:

```hcl
plugin "raw_exec" {
  config {
    enabled = true
  }
}
```

```bash
nomad-pack run packs/cursor_worker --var driver=raw_exec
```

## CLI version

`https://cursor.com/install` does not take a version. The script hardcodes one release (the copy fetched while writing this pack was `2026.11.22-e9042b2`) and a `?version=` query does not change it. Leave `cli_version` empty to run that script.

The install script refers to that version as `$CLI_VERSION`, and to the detected OS and architecture as `$os_name` and `$arch_name`, with no braces. The task driver treats `${...}` in `config` as Nomad interpolation and fails the task (`Unknown variable`) for shell names. `${NOMAD_*}` stays braced where Nomad itself should substitute it.

Set `cli_version` to download the versioned archive the install script uses:

```text
https://downloads.cursor.com/lab/<version>/<os>/<arch>/agent-cli-package.tar.gz
```

The prestart task then links `cursor-agent` the same way the script does. This pack does not verify a checksum. Cursor publishes a `.sha256` next to the archive; checking it is left to a later change.

```bash
nomad-pack run packs/cursor_worker --var cli_version=2026.11.22-e9042b2
```

## Resources

The worker task defaults to 1000 MHz and 1024 MB. That memory size is the one that ran successfully. A 2048 MB request froze a 4 GB test VM. The install task asks for another 200 MHz and 256 MB, and Nomad reserves both for the life of the allocation (1280 MB together at the defaults).

The CLI archive is about 180 MB compressed and is unpacked under the alloc directory. `ephemeral_disk` defaults to 0, which leaves the client default (often 300 MB), matching the job that already ran. Raise it if the install runs out of disk.

## Variables

`nomad-pack info packs/cursor_worker` prints the same list with types.

`nomad agent -dev` uses datacenter `dc1`, which is the default. To place the job in every datacenter, pass `--var datacenters='["*"]'`.

| Variable | Default | |
| --- | --- | --- |
| `job_name` | pack name `cursor_worker` | |
| `datacenters` | `["dc1"]` | |
| `region` | empty (omitted) | |
| `namespace` | empty (omitted) | |
| `count` | `1` | |
| `service_name` | job name, `_` replaced with `-` | default `cursor-worker` |
| `driver` | `exec` | `raw_exec` is the other value |
| `constraints` | linux kernel | `constraints=[]` clears it |
| `resources` | cpu 1000, memory 1024 | worker task |
| `install_resources` | cpu 200, memory 256 | prestart task |
| `ephemeral_disk` | `0` (omit) | MB |
| `restart` | 3 attempts, 10m, 15s, delay | |
| `cli_version` | empty | empty runs the install script |
| `repo_url` | octocat/Hello-World | empty skips the clone |
| `repo_ref` | empty | branch, tag, or commit |
| `pool` | empty | `--pool` name |
| `clone_git_repos` | `false` | any-repo pools only |
| `api_key_path` | `nomad/jobs/<job name>` | |
| `api_key_key` | `api_key` | |

Object variables are replaced as a whole:

```bash
nomad-pack run packs/cursor_worker \
  --var 'resources={cpu=500, memory=1024}'
```

## Logs

```bash
nomad job status cursor_worker
nomad alloc status <alloc-id>
nomad alloc logs <alloc-id> install-cli
nomad alloc logs <alloc-id> worker
```

Use the allocation id and the task name. Do not pass `-job` to `nomad alloc logs`. Events (chroot failures, template waits, restarts) are on `nomad alloc status`.

## Out of scope

Custom images, Kubernetes, Vault, publishing this pack to the community registry, and private-repo credentials on the clone.
