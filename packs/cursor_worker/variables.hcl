# SPDX-License-Identifier: MPL-2.0

variable "job_name" {
  description = "The name to use as the job name. Empty uses the pack name."
  type        = string
  default     = ""
}

variable "region" {
  description = "The region where the job will be placed. Empty omits the field."
  type        = string
  default     = ""
}

variable "namespace" {
  description = "The namespace where the job will be placed. Empty omits the field, so the command's namespace is used. The API key Nomad Variable is read in that same namespace."
  type        = string
  default     = ""
}

variable "datacenters" {
  description = "A list of datacenters in the region which are eligible for task placement."
  type        = list(string)
  default     = ["dc1"]
}

variable "count" {
  description = "How many worker allocations to place. Each allocation gets its own name (nomad-<alloc id>) and its own clone."
  type        = number
  default     = 1
}

variable "service_name" {
  description = "Nomad service name (RFC 1123: letters, digits, and dashes). Empty uses the job name with underscores replaced by dashes, so the default job cursor_worker registers the service cursor-worker."
  type        = string
  default     = ""
}

variable "driver" {
  description = "Task driver for both tasks. exec (default) chroots the task and runs it as nobody. raw_exec has no sandbox, runs as the Nomad client's user, and must be enabled in the client config."
  type        = string
  default     = "exec"
}

variable "constraints" {
  description = "Constraints applied to the job. operator may be an empty string to omit it. Clear the default with constraints=[]."
  type = list(object({
    attribute = string
    operator  = string
    value     = string
  }))
  default = [
    {
      attribute = "$${attr.kernel.name}"
      operator  = "="
      value     = "linux"
    },
  ]
}

variable "resources" {
  description = "CPU (MHz) and memory (MB) for the long-running worker task. 1024 MB is the confirmed working default. A 2048 MB worker request froze a 4 GB test VM."
  type = object({
    cpu    = number
    memory = number
  })
  default = {
    cpu    = 1000
    memory = 1024
  }
}

variable "install_resources" {
  description = "CPU (MHz) and memory (MB) for the prestart install task. Nomad reserves these in addition to resources for the life of the allocation."
  type = object({
    cpu    = number
    memory = number
  })
  default = {
    cpu    = 200
    memory = 256
  }
}

variable "ephemeral_disk" {
  description = "Ephemeral disk in MB for the group. 0 omits the stanza and leaves the client default (often 300). The CLI unpacks under the shared alloc directory; raise this if the install runs out of space."
  type        = number
  default     = 0
}

variable "restart" {
  description = "Group restart policy. mode is delay or fail."
  type = object({
    attempts = number
    interval = string
    delay    = string
    mode     = string
  })
  default = {
    attempts = 3
    interval = "10m"
    delay    = "15s"
    mode     = "delay"
  }
}

variable "cli_version" {
  description = "Cursor CLI version to install, such as 2026.11.22-e9042b2. Empty runs https://cursor.com/install, which hardcodes one version and cannot pin. A non-empty value downloads https://downloads.cursor.com/lab/<version>/<os>/<arch>/agent-cli-package.tar.gz, the same URL shape that script uses."
  type        = string
  default     = ""
}

variable "repo_url" {
  description = "Git URL to clone as the worker directory. The default is a public placeholder. Empty skips the clone and uses an empty directory (any-repo or a directory you manage yourself). Do not put private-repo credentials here."
  type        = string
  default     = "https://github.com/octocat/Hello-World.git"
}

variable "repo_ref" {
  description = "Branch, tag, or commit to check out after cloning. Empty keeps the remote default branch. Requires repo_url. The clone is not shallow, so a commit SHA can be checked out."
  type        = string
  default     = ""
}

variable "pool" {
  description = "Team pool name passed to --pool. Empty starts a personal My Machines worker. Use a name other than default together with an empty repo_url for an any-repo pool."
  type        = string
  default     = ""
}

variable "clone_git_repos" {
  description = "Pass --clone-git-repos so an any-repo pool worker checks out the repositories in the claim. Requires pool set to a name other than default, and requires repo_url to be empty. The CLI implies --mint-scm-token; a team admin must also enable SCM token minting, and git must be on PATH."
  type        = bool
  default     = false
}

variable "api_key_path" {
  description = "Nomad Variable path that holds the Cursor API key. Empty means nomad/jobs/<job name>, in the job's namespace. Create it with nomad var put. Never put the key in this file."
  type        = string
  default     = ""
}

variable "api_key_key" {
  description = "Key inside that Nomad Variable whose value is the Cursor API key."
  type        = string
  default     = "api_key"
}
