PREFIX ?= $(HOME)/.local
VERSION ?= $(shell bash packaging/resolve-version.sh)
TEMPLATE_DIR := $(PREFIX)/share/sshfling/templates
RELEASE_MATRIX ?= docs/release/enterprise-release-matrix.csv
RELEASE_MANIFEST ?= docs/release/evidence-manifest.json
RELEASE_EVIDENCE_OUTPUT_DIR ?= docs/release/enterprise-release-evidence/generated

.PHONY: install-local uninstall-local test test-containers release-assets-evidence release-matrix-validate check-package-version package package-deb package-rpm package-msi package-pkg clean

install-local:
	install -d "$(PREFIX)/bin" "$(TEMPLATE_DIR)/scripts" "$(TEMPLATE_DIR)/secrets" "$(TEMPLATE_DIR)/ssh-client" "$(TEMPLATE_DIR)/ssh-server" "$(TEMPLATE_DIR)/production" "$(TEMPLATE_DIR)/systemd"
	install -m 0755 bin/sshfling "$(PREFIX)/bin/sshfling"
	install -m 0644 .env.example LICENSE README.md compose.server.yml compose.client.yml "$(TEMPLATE_DIR)/"
	install -m 0755 scripts/install-local.sh scripts/uninstall-local.sh scripts/create-network.sh scripts/generate-ssh-key.sh "$(TEMPLATE_DIR)/scripts/"
	install -m 0644 secrets/.gitkeep "$(TEMPLATE_DIR)/secrets/.gitkeep"
	install -m 0644 ssh-client/Dockerfile "$(TEMPLATE_DIR)/ssh-client/Dockerfile"
	install -m 0755 ssh-client/entrypoint.sh "$(TEMPLATE_DIR)/ssh-client/entrypoint.sh"
	install -m 0644 ssh-server/Dockerfile ssh-server/sshd_config "$(TEMPLATE_DIR)/ssh-server/"
	install -m 0755 ssh-server/entrypoint.sh ssh-server/limited-session.sh "$(TEMPLATE_DIR)/ssh-server/"
	install -m 0755 production/sshfling-session "$(TEMPLATE_DIR)/production/sshfling-session"
	install -m 0644 systemd/sshflingd.service systemd/sshflingd.env.example "$(TEMPLATE_DIR)/systemd/"

uninstall-local:
	rm -f "$(PREFIX)/bin/sshfling"
	rm -rf "$(PREFIX)/share/sshfling"

test:
	python3 -m py_compile bin/sshfling tools/release_matrix_validate.py tools/generate_release_evidence.py
	find . -type d -name __pycache__ -prune -exec rm -rf {} +
	bash -n scripts/install-local.sh scripts/uninstall-local.sh scripts/create-network.sh scripts/generate-ssh-key.sh ssh-client/entrypoint.sh ssh-server/entrypoint.sh ssh-server/limited-session.sh production/sshfling-session packaging/*.sh tests/release/*.sh
	sh tests/cross-os/validate-cli.sh ./bin/sshfling "$(VERSION)"
	bash tests/release/validate-release-matrix.sh
	docker compose -f compose.server.yml config >/dev/null
	docker compose -f compose.client.yml config >/dev/null

test-containers:
	SSHFLING_VERSION="$(VERSION)" bash tests/docker/run-container-image-tests.sh

release-assets-evidence:
	python3 tools/generate_release_evidence.py --mode release-assets --artifacts-dir release-dist --version "$(VERSION)" --output-dir "$(RELEASE_EVIDENCE_OUTPUT_DIR)"

release-matrix-validate:
	python3 tools/release_matrix_validate.py --matrix "$(RELEASE_MATRIX)" --manifest "$(RELEASE_MANIFEST)"

check-package-version:
	@bash -c 'source packaging/version.sh; assert_sshfling_version_matches_source "$$1" "$$2" >/dev/null' _ "$(VERSION)" "$(CURDIR)"

package: package-deb package-rpm package-msi package-pkg

package-deb: check-package-version
	SSHFLING_VERSION="$(VERSION)" bash packaging/build-deb.sh

package-rpm: check-package-version
	SSHFLING_VERSION="$(VERSION)" bash packaging/build-rpm.sh

package-msi: check-package-version
	pwsh -NoProfile -File packaging/build-msi.ps1 -Version "$(VERSION)"

package-pkg: check-package-version
	SSHFLING_VERSION="$(VERSION)" bash packaging/build-pkg.sh

clean:
	rm -rf build dist
