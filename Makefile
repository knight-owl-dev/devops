.DEFAULT_GOAL := help

IMAGE ?= ci-tools
IMAGE_TAG ?= $(IMAGE):local
# Prefer the container-installed version for consistency with the rest of the
# validation toolchain; fall back to the repo copy on bare metal.
VALIDATE_ACTION_PINS := $(shell \
	command -v validate-action-pins 2>/dev/null \
	|| echo images/ci-tools/bin/validate-action-pins)

.PHONY: sync resolve build verify scan clean \
	lint lint-fix lint-lockfile lint-docker lint-sh lint-sh-fmt lint-sh-fmt-fix \
	lint-actions lint-md lint-md-fix lint-man man test-package help

# Resolve latest versions, build, and verify image
sync: resolve build verify

# Resolve latest versions and checksums
resolve:
	@scripts/$(IMAGE)/resolve.sh $(TOOLS)

# Build image locally
build:
	@docker compose \
		--env-file images/$(IMAGE)/versions.lock \
		-f images/$(IMAGE)/compose.yaml \
		build

# Verify all tools in the built image
verify:
	@docker run --rm \
		-v $(CURDIR)/scripts:/scripts \
		-v $(CURDIR)/images/$(IMAGE)/versions.lock:/versions.lock:ro \
		$(IMAGE_TAG) /scripts/$(IMAGE)/verify.sh

# Scan image for vulnerabilities
scan: build
	@echo "Scanning $(IMAGE_TAG) for vulnerabilities..."
	@docker run --rm \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-v $(CURDIR)/images/$(IMAGE)/.trivyignore:/.trivyignore:ro \
		aquasec/trivy:0.69.1 image \
		--severity CRITICAL,HIGH \
		--ignore-unfixed \
		--exit-code 1 \
		$(IMAGE_TAG)

# Run all linters
lint: lint-lockfile lint-docker lint-sh lint-sh-fmt lint-actions lint-md lint-man

# Fix all auto-fixable lint issues
lint-fix: lint-sh-fmt-fix lint-md-fix

# Validate lockfile keys match Dockerfile ARGs
lint-lockfile:
	@echo "Validating lockfile..." && scripts/lib/validate-lockfile.sh $(IMAGE) && echo "OK"

# Lint Dockerfiles
lint-docker:
	@echo "Linting Dockerfiles..." && hadolint images/*/Dockerfile && echo "OK"

# Lint shell scripts
lint-sh:
	@echo "Linting shell scripts..." \
		&& shellcheck scripts/*.sh scripts/*/*.sh tests/deb/*.sh images/*/bin/* \
		&& echo "OK"

# Check shell script formatting
lint-sh-fmt:
	@echo "Checking shell script formatting..." \
		&& shfmt -d -i 2 -ci -bn -sr scripts/ tests/ \
		&& echo "OK"

# Fix shell script formatting
lint-sh-fmt-fix:
	@echo "Fixing shell script formatting..." \
		&& shfmt -w -i 2 -ci -bn -sr scripts/ tests/ \
		&& echo "OK"

# Lint GitHub Actions workflows
lint-actions:
	@echo "Linting GitHub Actions..." \
		&& actionlint .github/workflows/*.yml \
		&& echo "OK"
	@echo "Validating GitHub Actions pins..." \
		&& $(VALIDATE_ACTION_PINS) .github/workflows/*.yml .github/actions/*/action.yml \
		&& echo "OK"

# Lint Markdown files
lint-md:
	@echo "Linting Markdown..." && markdownlint-cli2 '**/*.md' && echo "OK"

# Fix Markdown files
lint-md-fix:
	@echo "Fixing Markdown..." && markdownlint-cli2 --fix '**/*.md' && echo "OK"

# Lint man pages
lint-man:
	@echo "Linting man pages..." && mandoc -W warning docs/man/man1/*.1 > /dev/null && echo "OK"

# Preview man pages
man:
	@mandoc -a docs/man/man1/*.1

# Build and test deb package locally
test-package:
	@./tests/deb/test-all.sh

# Remove local image
clean:
	@echo "Removing $(IMAGE_TAG) ..."
	@docker rmi $(IMAGE_TAG) 2>/dev/null || true
	@echo "OK"

# Show all commands
help:
	@echo ""
	@echo "Devops Commands (IMAGE=ci-tools):"
	@echo "  make sync              Resolve*, build, and verify image"
	@echo "  make resolve           Resolve all tools to latest*"
	@echo "  make resolve TOOLS=... Pin specific tools (e.g. shfmt:v3.11.0)*"
	@echo "  make build             Build image locally"
	@echo "  make verify            Verify all tools in the built image"
	@echo "  make scan              Scan image for vulnerabilities"
	@echo "  make clean             Remove local image"
	@echo "  make lint              Run all linters"
	@echo "  make lint-actions      Lint GitHub Actions workflows"
	@echo "  make lint-lockfile     Validate lockfile against Dockerfile"
	@echo "  make lint-docker       Lint Dockerfiles"
	@echo "  make lint-fix          Fix all auto-fixable lint issues"
	@echo "  make lint-man          Lint man pages"
	@echo "  make lint-md           Lint Markdown files"
	@echo "  make lint-md-fix       Fix Markdown files"
	@echo "  make lint-sh           Lint shell scripts"
	@echo "  make lint-sh-fmt       Check shell script formatting"
	@echo "  make lint-sh-fmt-fix   Fix shell script formatting"
	@echo "  make man               Preview man pages"
	@echo "  make test-package      Build and test deb package locally"
	@echo "  make help              Show this message"
	@echo ""
	@echo "  * Writes images/\$$(IMAGE)/versions.lock"
	@echo ""
