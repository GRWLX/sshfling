PREFIX ?= $(HOME)/.local
VERSION ?= $(shell bash packaging/resolve-version.sh)
TEMPLATE_DIR := $(PREFIX)/share/sshfling/templates
RELEASE_EVIDENCE_OUTPUT_DIR ?= docs/release/enterprise-release-evidence/generated
RELEASE_SECURITY_EVIDENCE_OUTPUT_DIR ?= docs/release/enterprise-release-evidence/security-scans
RELEASE_MATRIX ?= $(RELEASE_SECURITY_EVIDENCE_OUTPUT_DIR)/security-scan-matrix.csv
RELEASE_MANIFEST ?= $(RELEASE_SECURITY_EVIDENCE_OUTPUT_DIR)/security-scan-manifest.json
RELEASE_SECURITY_SCAN_FLAGS ?=
RELEASE_SECURITY_LOCAL_OUTPUT_DIR ?= build/release-security-local
RELEASE_MATRIX_VALIDATE_FLAGS ?=
RELEASE_SCANNER_BIN_DIR ?= $(if $(RUNNER_TEMP),$(RUNNER_TEMP),$(CURDIR)/build)/release-scanners/bin
ENTERPRISE_RELEASE_OUTPUT_DIR ?= docs/release
ENTERPRISE_RELEASE_EVIDENCE_DIR ?= docs/release/enterprise-release-evidence
WEB_LANGUAGE_CONSUMERS ?= react vue svelte angular elm purescript rescript html-css cfml hack

.PHONY: install-local uninstall-local test test-native test-containers test-release-security-scan official-distro-readiness official-distro-readiness-strict official-distro-draft-validate official-distro-submission-prepare language-deployment-matrix release-package-rehearsal release-assets-evidence release-security-scan release-security-scan-local release-security-scan-optional release-security-scan-strict release-security-evidence-validate release-readiness-artifacts release-readiness-validate release-matrix-validate check-package-version package package-deb package-rpm package-msi package-pkg package-dotnet package-java package-node package-python package-go package-rust package-php package-ruby package-native-libraries package-perl package-functional-languages package-systems-languages package-scripting-languages clean
.PHONY: package-web-language-consumers package-dart-consumer package-language-catalog package-language-catalog-strict package-scripting-languages audit-domain-languages

install-local:
	install -d "$(PREFIX)/bin" "$(PREFIX)/libexec/sshfling" "$(TEMPLATE_DIR)/native" "$(TEMPLATE_DIR)/scripts" "$(TEMPLATE_DIR)/secrets" "$(TEMPLATE_DIR)/ssh-client" "$(TEMPLATE_DIR)/ssh-server" "$(TEMPLATE_DIR)/production" "$(TEMPLATE_DIR)/systemd"
	install -m 0755 bin/sshfling "$(PREFIX)/bin/sshfling"
	install -m 0755 native/sshfling-linux-account native/sshfling-unix-identity "$(PREFIX)/libexec/sshfling/"
	install -m 0755 native/sshfling-linux-account native/sshfling-unix-identity "$(TEMPLATE_DIR)/native/"
	install -m 0644 .env.example LICENSE README.md compose.server.yml compose.client.yml "$(TEMPLATE_DIR)/"
	install -m 0755 scripts/install-local.sh scripts/uninstall-local.sh scripts/create-network.sh scripts/generate-ssh-key.sh "$(TEMPLATE_DIR)/scripts/"
	install -m 0644 secrets/.gitkeep "$(TEMPLATE_DIR)/secrets/.gitkeep"
	install -m 0644 ssh-client/Dockerfile "$(TEMPLATE_DIR)/ssh-client/Dockerfile"
	install -m 0755 ssh-client/entrypoint.sh "$(TEMPLATE_DIR)/ssh-client/entrypoint.sh"
	install -m 0644 ssh-server/Dockerfile ssh-server/sshd_config "$(TEMPLATE_DIR)/ssh-server/"
	install -m 0755 ssh-server/entrypoint.sh ssh-server/limited-session.sh "$(TEMPLATE_DIR)/ssh-server/"
	install -m 0755 production/sshfling-login-shell production/sshfling-session "$(TEMPLATE_DIR)/production/"
	install -m 0644 systemd/sshflingd.service systemd/sshfling-prune.service systemd/sshfling-prune.timer systemd/sshflingd.env.example "$(TEMPLATE_DIR)/systemd/"

uninstall-local:
	PREFIX="$(PREFIX)" bash scripts/uninstall-local.sh

test:
	python3 -m py_compile bin/sshfling packaging/python/src/sshfling/__init__.py tools/release_matrix_validate.py tools/generate_release_evidence.py tools/generate_enterprise_release_readiness.py tools/generate_language_deployment_matrix.py tools/generate_language_support_matrix.py tools/official_distro_readiness.py tools/release_security_scan.py tools/validate_promoted_language_evidence.py tools/workflow_static_check.py
	python3 tools/generate_language_support_matrix.py --check
	python3 tools/generate_language_deployment_matrix.py --check
	python3 tools/official_distro_readiness.py --check
	python3 -m unittest discover -s tests/release -p 'test_*.py'
	python3 -m unittest discover -s tests/sshfling -p 'test_*.py'
	@if command -v node >/dev/null 2>&1; then node --check packaging/node/index.js && node --check packaging/node/bin/sshfling.js; fi
	@if command -v gofmt >/dev/null 2>&1; then test -z "$$(find packaging/go -type f -name '*.go' -print0 | xargs -0 gofmt -l)"; fi
	@if command -v cargo >/dev/null 2>&1 && cargo fmt --version >/dev/null 2>&1; then cargo fmt --check --manifest-path packaging/rust/Cargo.toml; fi
	@if command -v php >/dev/null 2>&1; then php -l packaging/php/src/SSHFling.php >/dev/null && php -l packaging/php/bin/sshfling >/dev/null; fi
	@if command -v ruby >/dev/null 2>&1; then ruby -c packaging/ruby/lib/sshfling.rb >/dev/null && ruby -c packaging/ruby/bin/sshfling >/dev/null; fi
	@if command -v perl >/dev/null 2>&1; then perl -c packaging/perl/Makefile.PL >/dev/null && perl -c packaging/perl/lib/SSHFling.pm >/dev/null && perl -Ipackaging/perl/lib -c packaging/perl/bin/sshfling >/dev/null; fi
	find . -type d -name __pycache__ -prune -exec rm -rf {} +
	bash -n scripts/install-local.sh scripts/uninstall-local.sh scripts/create-network.sh scripts/generate-ssh-key.sh ssh-client/entrypoint.sh ssh-server/entrypoint.sh ssh-server/limited-session.sh packaging/*.sh tools/provision-release-scanners.sh tests/cross-os/validate-local-install.sh tests/release/*.sh
	python3 tools/workflow_static_check.py --strict-timeouts
	bash packaging/build-domain-languages.sh audit
	$(MAKE) test-native
	bash tests/cross-os/validate-local-install.sh
	sh tests/cross-os/validate-cli.sh ./bin/sshfling "$(VERSION)"
	bash tests/release/validate-release-matrix.sh
	docker compose -f compose.server.yml config >/dev/null
	docker compose -f compose.client.yml config >/dev/null

test-native:
	bash -n native/sshfling-linux-account native/sshfling-native-prune production/sshfling-session tests/cross-os/validate-native-linux-account.sh tests/cross-os/validate-native-unix-identity.sh tests/cross-os/validate-native-login-shell.sh tests/cross-os/validate-native-prune.sh tests/cross-os/validate-native-session-policy.sh
	sh -n native/sshfling-unix-identity production/sshfling-login-shell
	bash tests/cross-os/validate-native-linux-account.sh
	bash tests/cross-os/validate-native-unix-identity.sh
	bash tests/cross-os/validate-native-login-shell.sh
	bash tests/cross-os/validate-native-prune.sh
	bash tests/cross-os/validate-native-session-policy.sh

test-containers:
	SSHFLING_VERSION="$(VERSION)" bash tests/docker/run-container-image-tests.sh

test-release-security-scan:
	python3 -m unittest discover -s tests/release -p 'test_*.py'

official-distro-readiness:
	python3 tools/official_distro_readiness.py --write

official-distro-readiness-strict:
	python3 tools/official_distro_readiness.py --check --fail-on-blocked

official-distro-draft-validate: check-package-version
	SSHFLING_VERSION="$(VERSION)" bash packaging/validate-official-distro-drafts.sh

official-distro-submission-prepare: check-package-version
	SSHFLING_VERSION="$(VERSION)" bash packaging/prepare-official-distro-submission.sh

language-deployment-matrix:
	python3 tools/generate_language_deployment_matrix.py --write --update-todo

release-package-rehearsal:
	VERSION="$(VERSION)" bash tests/release/validate-package-publishing-rehearsal.sh

release-assets-evidence:
	python3 tools/generate_release_evidence.py --mode release-assets --artifacts-dir release-dist --version "$(VERSION)" --output-dir "$(RELEASE_EVIDENCE_OUTPUT_DIR)"

release-security-scan:
	PATH="$(RELEASE_SCANNER_BIN_DIR):$$PATH" python3 tools/release_security_scan.py --version "$(VERSION)" --output-dir "$(RELEASE_SECURITY_EVIDENCE_OUTPUT_DIR)" $(RELEASE_SECURITY_SCAN_FLAGS)

release-security-scan-local:
	$(MAKE) release-security-scan RELEASE_SECURITY_EVIDENCE_OUTPUT_DIR="$(RELEASE_SECURITY_LOCAL_OUTPUT_DIR)" RELEASE_SECURITY_SCAN_FLAGS="$(RELEASE_SECURITY_SCAN_FLAGS) --allow-dirty"

release-security-scan-optional:
	PATH="$(RELEASE_SCANNER_BIN_DIR):$$PATH" python3 tools/release_security_scan.py --version "$(VERSION)" --output-dir "$(RELEASE_SECURITY_EVIDENCE_OUTPUT_DIR)" --run-optional-tools $(RELEASE_SECURITY_SCAN_FLAGS)

release-security-scan-strict:
	PATH="$(RELEASE_SCANNER_BIN_DIR):$$PATH" python3 tools/release_security_scan.py --version "$(VERSION)" --output-dir "$(RELEASE_SECURITY_EVIDENCE_OUTPUT_DIR)" --run-optional-tools --strict-optional-tools $(RELEASE_SECURITY_SCAN_FLAGS)

release-security-evidence-validate:
	python3 tools/release_matrix_validate.py --matrix "$(RELEASE_SECURITY_EVIDENCE_OUTPUT_DIR)/security-scan-matrix.csv" --manifest "$(RELEASE_SECURITY_EVIDENCE_OUTPUT_DIR)/security-scan-manifest.json" $(RELEASE_MATRIX_VALIDATE_FLAGS)

release-readiness-artifacts:
	python3 tools/generate_enterprise_release_readiness.py --version "$(VERSION)" --output-dir "$(ENTERPRISE_RELEASE_OUTPUT_DIR)" --evidence-dir "$(ENTERPRISE_RELEASE_EVIDENCE_DIR)"

release-readiness-validate:
	python3 tools/release_matrix_validate.py --matrix "$(ENTERPRISE_RELEASE_OUTPUT_DIR)/enterprise-release-matrix.csv" --manifest "$(ENTERPRISE_RELEASE_EVIDENCE_DIR)/enterprise-readiness-manifest.json" $(RELEASE_MATRIX_VALIDATE_FLAGS)

release-matrix-validate:
	@if [ "$(RELEASE_MATRIX)" = "$(RELEASE_SECURITY_EVIDENCE_OUTPUT_DIR)/security-scan-matrix.csv" ] && [ "$(RELEASE_MANIFEST)" = "$(RELEASE_SECURITY_EVIDENCE_OUTPUT_DIR)/security-scan-manifest.json" ]; then \
		$(MAKE) release-security-scan; \
	fi
	python3 tools/release_matrix_validate.py --matrix "$(RELEASE_MATRIX)" --manifest "$(RELEASE_MANIFEST)" $(RELEASE_MATRIX_VALIDATE_FLAGS)

check-package-version:
	@bash -c 'source packaging/version.sh; assert_sshfling_version_matches_source "$$1" "$$2" >/dev/null' _ "$(VERSION)" "$(CURDIR)"

package: package-deb package-rpm package-msi package-pkg package-dotnet package-java package-node package-python package-go package-rust package-php package-ruby package-native-libraries package-perl package-language-catalog

package-deb: check-package-version
	SSHFLING_VERSION="$(VERSION)" bash packaging/build-deb.sh

package-rpm: check-package-version
	SSHFLING_VERSION="$(VERSION)" bash packaging/build-rpm.sh

package-msi: check-package-version
	pwsh -NoProfile -File packaging/build-msi.ps1 -Version "$(VERSION)"

package-pkg: check-package-version
	SSHFLING_VERSION="$(VERSION)" bash packaging/build-pkg.sh

package-dotnet: check-package-version
	SSHFLING_VERSION="$(VERSION)" bash packaging/build-dotnet.sh

package-java: check-package-version
	SSHFLING_VERSION="$(VERSION)" bash packaging/build-java.sh

package-node: check-package-version
	SSHFLING_VERSION="$(VERSION)" bash packaging/build-node.sh

package-web-language-consumers: package-node
	SSHFLING_NPM_PACKAGE="$(CURDIR)/dist/sshfling-$(VERSION).tgz" bash packaging/build-web-language-consumers.sh $(WEB_LANGUAGE_CONSUMERS)

package-dart-consumer: package-node
	SSHFLING_NPM_PACKAGE="$(CURDIR)/dist/sshfling-$(VERSION).tgz" bash packaging/build-web-language-consumers.sh dart

package-language-catalog: check-package-version
	$(MAKE) package-scripting-languages VERSION="$(VERSION)"
	SSHFLING_VERSION="$(VERSION)" bash packaging/build-functional-languages.sh --allow-blocked
	SSHFLING_VERSION="$(VERSION)" bash packaging/build-systems-languages.sh --allow-blocked

package-language-catalog-strict: package-language-catalog package-dart-consumer
	python3 tools/validate_promoted_language_evidence.py \
		--version "$(VERSION)" \
		--functional "dist/sshfling-functional-languages-$(VERSION)-validation.tsv" \
		--systems "dist/sshfling-systems-languages-$(VERSION)-validation.tsv" \
		--scripting "dist/sshfling-scripting-languages-$(VERSION)-validation.tsv"

package-functional-languages: check-package-version
	SSHFLING_VERSION="$(VERSION)" bash packaging/build-functional-languages.sh

package-systems-languages: check-package-version
	SSHFLING_VERSION="$(VERSION)" bash packaging/build-systems-languages.sh

package-scripting-languages: check-package-version
	SSHFLING_VERSION="$(VERSION)" bash packaging/build-scripting-languages.sh

audit-domain-languages:
	bash packaging/build-domain-languages.sh audit

package-python: check-package-version
	SSHFLING_VERSION="$(VERSION)" bash packaging/build-python.sh

package-go: check-package-version
	SSHFLING_VERSION="$(VERSION)" bash packaging/build-go.sh

package-rust: check-package-version
	SSHFLING_VERSION="$(VERSION)" bash packaging/build-rust.sh

package-php: check-package-version
	SSHFLING_VERSION="$(VERSION)" bash packaging/build-php.sh

package-ruby: check-package-version
	SSHFLING_VERSION="$(VERSION)" bash packaging/build-ruby.sh

package-native-libraries: check-package-version
	SSHFLING_VERSION="$(VERSION)" bash packaging/build-native-libraries.sh

package-perl: check-package-version
	SSHFLING_VERSION="$(VERSION)" bash packaging/build-perl.sh

clean:
	rm -rf build dist
