# Nomad Pack registry

A Nomad Pack registry for running [Cursor CLI](https://cursor.com/docs/cli/overview) self-hosted (My Machines) workers on [HashiCorp Nomad](https://developer.hashicorp.com/nomad).

| Pack | What it runs |
| --- | --- |
| [`cursor_worker`](packs/cursor_worker) | A My Machines worker (`cursor-agent worker ... start`). No custom image: a prestart task installs the CLI. |

The pack name uses an underscore because that is the Nomad Pack convention (`nomad-pack generate pack`, and the community registry).

## Add the registry

From a machine with [`nomad-pack`](https://developer.hashicorp.com/nomad/tools/nomad-pack) installed:

```bash
nomad-pack registry add nomad-packs <git-url>
nomad-pack run cursor_worker --registry=nomad-packs
```

`<git-url>` is a git URL Nomad Pack can clone (go-getter). To try a local checkout instead:

```bash
nomad-pack run packs/cursor_worker
```

Pass variables with `--var` or `-f`. See the [pack README](packs/cursor_worker/README.md) for the variable list, the API key, `raw_exec`, and the exec chroot.

## Quickstart (`nomad agent -dev`)

Terminal 1:

```bash
nomad agent -dev
```

Terminal 2, from this repository:

```bash
export NOMAD_ADDR=http://127.0.0.1:4646

# Personal user API key from Cursor Dashboard → API Keys.
# Pool workers need a service account key instead. Do not commit the key.
nomad var put -force nomad/jobs/cursor_worker api_key=<user-api-key>

nomad-pack run packs/cursor_worker
```

The dev agent datacenter is `dc1`, which is the pack default. `exec` must run as root; a rootless dev agent only has `raw_exec`, which has to be selected explicitly:

```bash
nomad-pack run packs/cursor_worker --var driver=raw_exec
```

`raw_exec` is off unless the client enables it. `nomad agent -dev` enables it. A production client needs:

```hcl
plugin "raw_exec" {
  config {
    enabled = true
  }
}
```

`raw_exec` does not sandbox the task. It runs as the Nomad client's user and can see the host filesystem.

Rotate the key with the same put. `-force` replaces the variable:

```bash
nomad var put -force nomad/jobs/cursor_worker api_key=<user-api-key>
```

Watch placement and logs with the allocation id. `nomad alloc logs` does not take `-job`.

```bash
nomad job status cursor_worker
nomad alloc status <alloc-id>
nomad alloc logs <alloc-id> install-cli
nomad alloc logs <alloc-id> worker
```

`nomad alloc status` is where task events show up (download failed, template waiting on the variable, driver refused).

## Check the pack without a cluster

`make validate` renders the default job and `driver=raw_exec`, plus an any-repo example and a pinned CLI version, then runs `nomad job validate` on each. It also checks that invalid variables fail to render.

```bash
make install-tools   # Nomad 2.1.1 and nomad-pack 0.4.2, linux amd64
make validate
```

The versions match the Nomad release the reference job ran on (2.1.1) and the current stable nomad-pack (0.4.2).

## Support

<!-- TODO: Ko-fi link -->
