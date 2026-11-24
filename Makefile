# Render the cursor_worker pack and validate the job with Nomad.
# CI runs: make install-tools && make validate
# Offline job validate checks HCL shape. It does not interpolate driver config.
# scripts/check-rendered-jobs.sh scans for shell ${...} and runs each rendered
# job on nomad agent -dev, which is where "Unknown variable" is raised.

NOMAD_VERSION ?= 2.1.1
NOMAD_PACK_VERSION ?= 0.4.2
OS ?= linux
ARCH ?= amd64

TOOLS_DIR := $(abspath .tools)
NOMAD ?= $(TOOLS_DIR)/nomad
NOMAD_PACK ?= $(TOOLS_DIR)/nomad-pack
PACK := packs/cursor_worker
RENDER_DIR := .render

.PHONY: install-tools render validate clean

install-tools:
	mkdir -p $(TOOLS_DIR)/tmp
	curl -fsSL -o $(TOOLS_DIR)/tmp/nomad.zip \
		https://releases.hashicorp.com/nomad/$(NOMAD_VERSION)/nomad_$(NOMAD_VERSION)_$(OS)_$(ARCH).zip
	unzip -qo $(TOOLS_DIR)/tmp/nomad.zip -d $(TOOLS_DIR)/tmp/nomad
	install -m 0755 $(TOOLS_DIR)/tmp/nomad/nomad $(TOOLS_DIR)/nomad
	curl -fsSL -o $(TOOLS_DIR)/tmp/nomad-pack.zip \
		https://releases.hashicorp.com/nomad-pack/$(NOMAD_PACK_VERSION)/nomad-pack_$(NOMAD_PACK_VERSION)_$(OS)_$(ARCH).zip
	unzip -qo $(TOOLS_DIR)/tmp/nomad-pack.zip -d $(TOOLS_DIR)/tmp/nomad-pack
	install -m 0755 $(TOOLS_DIR)/tmp/nomad-pack/nomad-pack $(TOOLS_DIR)/nomad-pack
	rm -rf $(TOOLS_DIR)/tmp
	$(NOMAD) version
	$(NOMAD_PACK) version

render:
	rm -rf $(RENDER_DIR)
	mkdir -p $(RENDER_DIR)/exec $(RENDER_DIR)/raw_exec $(RENDER_DIR)/any_repo $(RENDER_DIR)/pinned
	$(NOMAD_PACK) render $(PACK) --to-dir $(RENDER_DIR)/exec --render-output-template >$(RENDER_DIR)/exec.log \
		|| { cat $(RENDER_DIR)/exec.log; exit 1; }
	$(NOMAD_PACK) render $(PACK) --to-dir $(RENDER_DIR)/raw_exec --var driver=raw_exec >$(RENDER_DIR)/raw_exec.log \
		|| { cat $(RENDER_DIR)/raw_exec.log; exit 1; }
	$(NOMAD_PACK) render $(PACK) --to-dir $(RENDER_DIR)/any_repo \
		--var repo_url= \
		--var pool=my-pool \
		--var clone_git_repos=true >$(RENDER_DIR)/any_repo.log \
		|| { cat $(RENDER_DIR)/any_repo.log; exit 1; }
	$(NOMAD_PACK) render $(PACK) --to-dir $(RENDER_DIR)/pinned \
		--var cli_version=2026.11.22-e9042b2 >$(RENDER_DIR)/pinned.log \
		|| { cat $(RENDER_DIR)/pinned.log; exit 1; }

JOB = cursor_worker/cursor_worker.nomad

validate: render
	NOMAD_ADDR=http://127.0.0.1:9 $(NOMAD) job validate $(RENDER_DIR)/exec/$(JOB)
	NOMAD_ADDR=http://127.0.0.1:9 $(NOMAD) job validate $(RENDER_DIR)/raw_exec/$(JOB)
	NOMAD_ADDR=http://127.0.0.1:9 $(NOMAD) job validate $(RENDER_DIR)/any_repo/$(JOB)
	NOMAD_ADDR=http://127.0.0.1:9 $(NOMAD) job validate $(RENDER_DIR)/pinned/$(JOB)
	grep -q 'driver = "exec"' $(RENDER_DIR)/exec/$(JOB)
	grep -q 'driver = "raw_exec"' $(RENDER_DIR)/raw_exec/$(JOB)
	grep -q 'export HOME="$$NOMAD_ALLOC_DIR/home"' $(RENDER_DIR)/exec/$(JOB)
	grep -q 'octocat/Hello-World' $(RENDER_DIR)/exec/$(JOB)
	grep -q 'nomad/jobs/cursor_worker' $(RENDER_DIR)/exec/$(JOB)
	grep -q 'name     = "cursor-worker"' $(RENDER_DIR)/exec/$(JOB)
	grep -q 'CLONE_GIT_REPOS = "true"' $(RENDER_DIR)/any_repo/$(JOB)
	grep -q '\-\-clone-git-repos' $(RENDER_DIR)/any_repo/$(JOB)
	grep -q 'REPO_URL        = ""' $(RENDER_DIR)/any_repo/$(JOB)
	grep -q '2026.11.22-e9042b2' $(RENDER_DIR)/pinned/$(JOB)
	mkdir -p $(RENDER_DIR)/reject
	if $(NOMAD_PACK) render $(PACK) --to-dir $(RENDER_DIR)/reject/docker --var driver=docker \
		>$(RENDER_DIR)/reject/docker.out 2>&1; then \
		echo "driver=docker should have failed to render"; exit 1; \
	fi
	grep -q "raw_exec" $(RENDER_DIR)/reject/docker.out
	if $(NOMAD_PACK) render $(PACK) --to-dir $(RENDER_DIR)/reject/clone --var clone_git_repos=true \
		>$(RENDER_DIR)/reject/clone.out 2>&1; then \
		echo "clone_git_repos without a pool should have failed to render"; exit 1; \
	fi
	grep -q "clone_git_repos" $(RENDER_DIR)/reject/clone.out
	NOMAD=$(NOMAD) ./scripts/check-rendered-jobs.sh $(RENDER_DIR)

clean:
	rm -rf $(TOOLS_DIR) $(RENDER_DIR)
