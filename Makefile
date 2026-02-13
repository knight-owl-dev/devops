.DEFAULT_GOAL := help

IMAGE ?= ci-tools
IMAGE_TAG ?= $(IMAGE):local

.PHONY: sync resolve build verify lint lint-fix lint-docker lint-sh lint-sh-fmt lint-sh-fmt-fix lint-actions lint-md lint-md-fix clean help

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
		$(IMAGE_TAG) bash /scripts/$(IMAGE)/verify.sh

# Run all linters
lint: lint-docker lint-sh lint-sh-fmt lint-actions lint-md

# Fix all auto-fixable lint issues
lint-fix: lint-sh-fmt-fix lint-md-fix

# Lint Dockerfiles
lint-docker:
	@echo "Linting Dockerfiles..."
	@hadolint images/*/Dockerfile
	@echo "OK"

# Lint shell scripts
lint-sh:
	@echo "Linting shell scripts..."
	@shellcheck scripts/*/*.sh
	@echo "OK"

# Check shell script formatting
lint-sh-fmt:
	@echo "Checking shell script formatting..."
	@shfmt -d -i 2 -ci -bn -sr scripts/
	@echo "OK"

# Fix shell script formatting
lint-sh-fmt-fix:
	@echo "Fixing shell script formatting..."
	@shfmt -w -i 2 -ci -bn -sr scripts/
	@echo "OK"

# Lint GitHub Actions workflows
lint-actions:
	@echo "Linting GitHub Actions..."
	@actionlint
	@echo "OK"

# Lint Markdown files
lint-md:
	@echo "Linting Markdown..."
	@markdownlint-cli2 '**/*.md'
	@echo "OK"

# Fix Markdown files
lint-md-fix:
	@echo "Fixing Markdown..."
	@markdownlint-cli2 --fix '**/*.md'
	@echo "OK"

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
	@echo "  make clean             Remove local image"
	@echo "  make lint              Run all linters"
	@echo "  make lint-actions      Lint GitHub Actions workflows"
	@echo "  make lint-docker       Lint Dockerfiles"
	@echo "  make lint-fix          Fix all auto-fixable lint issues"
	@echo "  make lint-md           Lint Markdown files"
	@echo "  make lint-md-fix       Fix Markdown files"
	@echo "  make lint-sh           Lint shell scripts"
	@echo "  make lint-sh-fmt       Check shell script formatting"
	@echo "  make lint-sh-fmt-fix   Fix shell script formatting"
	@echo "  make help              Show this message"
	@echo ""
	@echo "  * Writes images/\$$(IMAGE)/versions.lock"
	@echo ""
