[[- /* Reject combinations the CLI would reject, before rendering a job. */ -]]
[[- $driver := var "driver" . -]]
[[- if not (or (eq $driver "exec") (eq $driver "raw_exec")) -]]
[[- fail "driver must be \"exec\" or \"raw_exec\"" -]]
[[- end -]]

[[- $job := coalesce (var "job_name" .) (meta "pack.name" .) -]]
[[- if not (regexMatch "^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$" $job) -]]
[[- fail (printf "job_name %q must contain only letters, digits, underscores, and hyphens" $job) -]]
[[- end -]]

[[- $service := "" -]]
[[- if ne (var "service_name" .) "" -]]
[[- $service = var "service_name" . -]]
[[- else -]]
[[- $service = replace "_" "-" $job -]]
[[- end -]]
[[- if not (regexMatch "^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$" $service) -]]
[[- fail (printf "service name %q must be an RFC 1123 label (letters, digits, dashes; no underscores)" $service) -]]
[[- end -]]

[[- if lt (var "count" .) 1 -]]
[[- fail "count must be at least 1" -]]
[[- end -]]

[[- $mode := var "restart.mode" . -]]
[[- if not (or (eq $mode "delay") (eq $mode "fail")) -]]
[[- fail "restart.mode must be \"delay\" or \"fail\"" -]]
[[- end -]]

[[- if and (ne (var "repo_ref" .) "") (eq (var "repo_url" .) "") -]]
[[- fail "repo_ref requires repo_url" -]]
[[- end -]]

[[- if var "clone_git_repos" . -]]
[[- if or (eq (var "pool" .) "") (eq (var "pool" .) "default") -]]
[[- fail "clone_git_repos requires pool set to a named pool other than \"default\"" -]]
[[- end -]]
[[- if ne (var "repo_url" .) "" -]]
[[- fail "clone_git_repos is any-repo mode: leave repo_url empty so the worker is not bound to a pre-cloned repository" -]]
[[- end -]]
[[- end -]]

[[- if and (ne (var "cli_version" .) "") (not (regexMatch "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$" (var "cli_version" .))) -]]
[[- fail "cli_version must be empty or a token such as 2026.11.22-e9042b2" -]]
[[- end -]]

[[- if and (ne (var "pool" .) "") (not (regexMatch "^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$" (var "pool" .))) -]]
[[- fail "pool must be empty or a name of letters, digits, underscores, and hyphens" -]]
[[- end -]]

[[- if not (regexMatch "^[A-Za-z_][A-Za-z0-9_]{0,63}$" (var "api_key_key" .)) -]]
[[- fail "api_key_key must be an identifier (letters, digits, underscores)" -]]
[[- end -]]

[[- if and (ne (var "api_key_path" .) "") (not (regexMatch "^[A-Za-z0-9][A-Za-z0-9/_-]{0,220}$" (var "api_key_path" .))) -]]
[[- fail "api_key_path may contain only letters, digits, slashes, underscores, and hyphens" -]]
[[- end -]]

[[- if contains "${" (var "repo_url" .) -]]
[[- fail "repo_url must not contain ${} ; Nomad interpolates that in env values" -]]
[[- end -]]

# Cursor CLI self-hosted worker.
# install-cli and worker share $NOMAD_ALLOC_DIR/home. Each command exports HOME
# because the exec driver runs as nobody, whose HOME is /nonexistent and
# overrides the env block.
job [[ template "job_name" . ]] {
[[- if var "region" . ]]
  [[ template "region" . ]]
[[ end ]]
[[- if var "namespace" . ]]
  [[ template "namespace" . ]]
[[ end ]]
  datacenters = [[ var "datacenters" . | toStringList ]]
  type        = "service"

  [[ template "constraints" (var "constraints" .) ]]

  group "worker" {
    count = [[ var "count" . ]]

    restart {
      attempts = [[ var "restart.attempts" . ]]
      interval = [[ var "restart.interval" . | quote ]]
      delay    = [[ var "restart.delay" . | quote ]]
      mode     = [[ var "restart.mode" . | quote ]]
    }

    network {
      port "mgmt" {}
    }

    [[- if gt (var "ephemeral_disk" .) 0 ]]
    ephemeral_disk {
      size = [[ var "ephemeral_disk" . ]]
    }
    [[- end ]]

    task "install-cli" {
      driver = [[ var "driver" . | quote ]]

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      env {
        HOME        = "${NOMAD_ALLOC_DIR}/home"
        CLI_VERSION = [[ var "cli_version" . | quote ]]
      }

      # Shell locals in config.args must be unbraced ($name). The task driver
      # interpolates dollar-brace expressions and rejects names it does not
      # know. Braced NOMAD_ variables in the env block are Nomad interpolation.
      config {
        command = "/bin/bash"
        args    = ["-c", <<EOT
set -euo pipefail
export HOME="$NOMAD_ALLOC_DIR/home"
mkdir -p "$HOME"

if ! command -v curl >/dev/null 2>&1; then
  echo "cursor_worker prestart: curl is not in PATH." >&2
  echo "The exec driver chroots to host /bin, /usr, /lib, /lib64, and /etc, and runs as nobody." >&2
  echo "Install curl on the Nomad client, or set driver=raw_exec (no sandbox; enable the raw_exec plugin first)." >&2
  exit 1
fi

if ! command -v tar >/dev/null 2>&1; then
  echo "cursor_worker prestart: tar is not in PATH. The CLI package is a tar.gz." >&2
  exit 1
fi

if [ -n "$CLI_VERSION" ]; then
  os_name="$(uname -s)"
  case "$os_name" in
    Linux) os_name="linux" ;;
    Darwin) os_name="darwin" ;;
    *)
      echo "cursor_worker prestart: unsupported OS $os_name" >&2
      exit 1
      ;;
  esac
  arch_name="$(uname -m)"
  case "$arch_name" in
    x86_64|amd64) arch_name="x64" ;;
    aarch64|arm64) arch_name="arm64" ;;
    *)
      echo "cursor_worker prestart: unsupported architecture $arch_name" >&2
      exit 1
      ;;
  esac
  url="https://downloads.cursor.com/lab/$CLI_VERSION/$os_name/$arch_name/agent-cli-package.tar.gz"
  dest="$HOME/.local/share/cursor-agent/versions/$CLI_VERSION"
  tmp="$HOME/.local/share/cursor-agent/versions/.tmp-$CLI_VERSION"
  rm -rf "$tmp"
  mkdir -p "$tmp"
  echo "cursor_worker prestart: installing pinned CLI $CLI_VERSION"
  echo "cursor_worker prestart: $url"
  echo "cursor_worker prestart: https://cursor.com/install cannot pin a version; this path uses the artifact URL that script embeds."
  if ! curl -fSL "$url" | tar --strip-components=1 -xzf - -C "$tmp"; then
    echo "cursor_worker prestart: pinned download failed." >&2
    echo "Check outbound HTTPS to downloads.cursor.com, CA certificates in the chroot (/etc/ssl), and that $CLI_VERSION is published for $os_name/$arch_name." >&2
    rm -rf "$tmp"
    exit 1
  fi
  if [ ! -x "$tmp/cursor-agent" ]; then
    echo "cursor_worker prestart: archive did not contain cursor-agent. The install script expects tar --strip-components=1 to yield ./cursor-agent." >&2
    exit 1
  fi
  rm -rf "$dest"
  mv "$tmp" "$dest"
  mkdir -p "$HOME/.local/bin"
  ln -sfn "$dest/cursor-agent" "$HOME/.local/bin/cursor-agent"
  ln -sfn "$dest/cursor-agent" "$HOME/.local/bin/agent"
else
  echo "cursor_worker prestart: installing CLI with https://cursor.com/install"
  echo "cursor_worker prestart: that script hardcodes one version. Set cli_version to pin."
  if ! curl -fsSL https://cursor.com/install | bash; then
    echo "cursor_worker prestart: install script failed." >&2
    echo "A certificate error usually means the exec chroot has no CA certs from host /etc/ssl." >&2
    echo "A connection error usually means outbound HTTPS to cursor.com or downloads.cursor.com is blocked." >&2
    exit 1
  fi
fi

if [ ! -x "$HOME/.local/bin/cursor-agent" ]; then
  echo "cursor_worker prestart: cursor-agent was not installed at $HOME/.local/bin/cursor-agent." >&2
  echo "The installer writes under HOME. This command exports HOME to the alloc dir so the worker task can see the same binary. nobody's HOME is /nonexistent and overrides the env block." >&2
  exit 1
fi

"$HOME/.local/bin/cursor-agent" --version
EOT
        ]
      }

      [[ template "resources" (var "install_resources" .) ]]
    }

    task "worker" {
      driver         = [[ var "driver" . | quote ]]
      shutdown_delay = "5s"

      env {
        HOME            = "${NOMAD_ALLOC_DIR}/home"
        REPO_URL        = [[ var "repo_url" . | quote ]]
        REPO_REF        = [[ var "repo_ref" . | quote ]]
        POOL            = [[ var "pool" . | quote ]]
        [[- if var "clone_git_repos" . ]]
        CLONE_GIT_REPOS = "true"
        [[- else ]]
        CLONE_GIT_REPOS = "false"
        [[- end ]]
      }

      # data is consul-template (double-brace). Do not put a dollar-brace in
      # this heredoc: HCL and the driver interpolate those before the template runs.
      template {
        destination = "secrets/cursor.env"
        env         = true
        data        = <<EOT
CURSOR_API_KEY={{ with nomadVar "[[ template "api_key_path" . ]]" }}{{ index . "[[ var "api_key_key" . ]]" }}{{ end }}
EOT
      }

      config {
        command = "/bin/bash"
        args    = ["-c", <<EOT
set -euo pipefail
export HOME="$NOMAD_ALLOC_DIR/home"
export GIT_TERMINAL_PROMPT=0
cd "$NOMAD_TASK_DIR"

agent="$HOME/.local/bin/cursor-agent"
if [ ! -x "$agent" ]; then
  echo "cursor_worker: $agent is missing or not executable." >&2
  echo "install-cli should have placed it in the shared alloc HOME. See: nomad alloc logs <alloc-id> install-cli" >&2
  exit 1
fi

if [ -n "$REPO_URL" ]; then
  if ! command -v git >/dev/null 2>&1; then
    echo "cursor_worker: git is not in PATH, so repo_url cannot be cloned." >&2
    echo "The exec chroot includes host /bin, /usr, /lib, /lib64, and /etc. Install git on the Nomad client, or set driver=raw_exec." >&2
    exit 1
  fi
  rm -rf repo
  echo "cursor_worker: cloning $REPO_URL"
  if ! git clone "$REPO_URL" repo; then
    echo "cursor_worker: git clone failed. This pack does not pass private-repo credentials. Use a public URL, or a client image that already has them." >&2
    exit 1
  fi
  if [ -n "$REPO_REF" ]; then
    echo "cursor_worker: checking out $REPO_REF"
    git -C repo checkout "$REPO_REF"
  fi
  worker_dir="$NOMAD_TASK_DIR/repo"
else
  worker_dir="$NOMAD_TASK_DIR/workspace"
  mkdir -p "$worker_dir"
  echo "cursor_worker: repo_url is empty; worker dir is $worker_dir"
fi

set -- \
  "$agent" worker \
  --name "nomad-${NOMAD_ALLOC_ID}" \
  --worker-dir "$worker_dir" \
  --management-addr "0.0.0.0:${NOMAD_PORT_mgmt}"

if [ -n "$POOL" ]; then
  set -- "$@" --pool "$POOL"
fi

if [ "$CLONE_GIT_REPOS" = "true" ]; then
  if ! command -v git >/dev/null 2>&1; then
    echo "cursor_worker: --clone-git-repos needs git on PATH." >&2
    exit 1
  fi
  set -- "$@" --clone-git-repos
fi

set -- "$@" start
echo "cursor_worker: starting $*"
exec "$@"
EOT
        ]
      }

      service {
        name     = "[[ template "service_name" . ]]"
        port     = "mgmt"
        provider = "nomad"

        check {
          type     = "http"
          path     = "/healthz"
          interval = "10s"
          timeout  = "2s"
        }
      }

      [[ template "resources" (var "resources" .) ]]
    }
  }
}
