PREFIX ?= $(HOME)/.local
VERSION ?= 0.1.4
TEMPLATE_DIR := $(PREFIX)/share/sshfling/templates

.PHONY: install-local uninstall-local test package package-deb package-rpm package-msi package-pkg clean

install-local:
	install -d "$(PREFIX)/bin" "$(TEMPLATE_DIR)/scripts" "$(TEMPLATE_DIR)/secrets" "$(TEMPLATE_DIR)/ssh-client" "$(TEMPLATE_DIR)/ssh-server" "$(TEMPLATE_DIR)/production" "$(TEMPLATE_DIR)/systemd"
	install -m 0755 bin/sshfling "$(PREFIX)/bin/sshfling"
	install -m 0644 .env.example LICENSE README.md compose.server.yml compose.client.yml "$(TEMPLATE_DIR)/"
	install -m 0755 scripts/install-local.sh scripts/create-network.sh scripts/generate-ssh-key.sh "$(TEMPLATE_DIR)/scripts/"
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
	python3 -m py_compile bin/sshfling
	bash -n scripts/install-local.sh scripts/create-network.sh scripts/generate-ssh-key.sh ssh-client/entrypoint.sh ssh-server/entrypoint.sh ssh-server/limited-session.sh production/sshfling-session packaging/*.sh
	docker compose -f compose.server.yml config >/dev/null
	docker compose -f compose.client.yml config >/dev/null

package: package-deb package-rpm package-msi package-pkg

package-deb:
	SSHFLING_VERSION="$(VERSION)" bash packaging/build-deb.sh

package-rpm:
	SSHFLING_VERSION="$(VERSION)" bash packaging/build-rpm.sh

package-msi:
	pwsh -NoProfile -ExecutionPolicy Bypass -File packaging/build-msi.ps1 -Version "$(VERSION)"

package-pkg:
	SSHFLING_VERSION="$(VERSION)" bash packaging/build-pkg.sh

clean:
	rm -rf build dist
