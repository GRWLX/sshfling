#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$repo_root/build"
tmpdir="$(mktemp -d "$repo_root/build/release-matrix-test.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

evidence_dir="$tmpdir/evidence"
mkdir -p "$evidence_dir"
printf 'validated release evidence\n' >"$evidence_dir/pass.log"
evidence_sha="$(sha256sum "$evidence_dir/pass.log" | awk '{print $1}')"
evidence_ref="${evidence_dir#"$repo_root"/}/pass.log"
if [[ "$evidence_ref" == "$evidence_dir/pass.log" ]]; then
  evidence_ref="$(realpath --relative-to "$repo_root" "$evidence_dir/pass.log")"
fi

for ignored_evidence_path in \
  docs/release/enterprise-release-evidence/generated/release-assets-evidence.json \
  docs/release/enterprise-release-evidence/generated/release-assets-manifest.json \
  docs/release/enterprise-release-evidence/generated/release-assets-matrix.csv \
  docs/release/enterprise-release-evidence/security-scans/security-scan-report.json; do
  if ! git -C "$repo_root" check-ignore -q "$ignored_evidence_path"; then
    echo "expected generated release evidence path to be ignored: $ignored_evidence_path" >&2
    exit 1
  fi
done

write_matrix() {
  local path="$1"
  local row_id="$2"
  local sha="$3"
  {
    echo "row_id,readiness_status,result,evidence_ref,evidence_sha256,source_commit,blocker_reason,actual_result"
    printf '%s,PASS,pass,%s,%s,abc123,NOT_APPLICABLE,NOT_APPLICABLE\n' "$row_id" "$evidence_ref" "$sha"
  } >"$path"
}

write_manifest() {
  local path="$1"
  local rows_json="$2"
  cat >"$path" <<JSON
{
  "schema_version": 1,
  "evidence": [
    {
      "evidence_id": "$evidence_ref",
      "evidence_ref": "$evidence_ref",
      "artifact_path": "$evidence_ref",
      "sha256": "$evidence_sha",
      "source_commit": "abc123",
      "result": "pass",
      "rows": $rows_json
    }
  ]
}
JSON
}

write_matrix "$tmpdir/pass.csv" "row-one" "$evidence_sha"
write_manifest "$tmpdir/pass-manifest.json" '["row-one"]'
python3 "$repo_root/tools/release_matrix_validate.py" \
  --repo-root "$repo_root" \
  --matrix "$tmpdir/pass.csv" \
  --manifest "$tmpdir/pass-manifest.json" \
  --max-errors 5 >/tmp/sshfling-release-matrix-pass.log

legacy_repo="$tmpdir/legacy-repo"
legacy_scan_dir="$legacy_repo/docs/release/enterprise-release-evidence/security-scans"
legacy_evidence_dir="$legacy_repo/evidence"
mkdir -p "$legacy_scan_dir" "$legacy_evidence_dir"
printf 'validated legacy manifest alias evidence\n' >"$legacy_evidence_dir/pass.log"
legacy_sha="$(sha256sum "$legacy_evidence_dir/pass.log" | awk '{print $1}')"
legacy_ref="evidence/pass.log"
cat >"$legacy_scan_dir/security-scan-matrix.csv" <<CSV
row_id,readiness_status,result,evidence_ref,evidence_sha256,source_commit,blocker_reason,actual_result
SEC-LEGACY,PASS,pass,$legacy_ref,$legacy_sha,abc123,NOT_APPLICABLE,NOT_APPLICABLE
CSV
cat >"$legacy_scan_dir/security-scan-manifest.json" <<JSON
{
  "schema_version": 1,
  "evidence": [
    {
      "evidence_id": "$legacy_ref",
      "evidence_ref": "$legacy_ref",
      "artifact_path": "$legacy_ref",
      "sha256": "$legacy_sha",
      "source_commit": "abc123",
      "result": "pass",
      "rows": ["SEC-LEGACY"]
    }
  ]
}
JSON
python3 "$repo_root/tools/release_matrix_validate.py" \
  --repo-root "$legacy_repo" \
  --manifest docs/release/evidence-manifest.json \
  --max-errors 5 >/tmp/sshfling-release-matrix-legacy-manifest-alias.log 2>&1
test ! -e "$legacy_repo/docs/release/evidence-manifest.json"
grep -Fq "using paired generated manifest" /tmp/sshfling-release-matrix-legacy-manifest-alias.log

{
  echo "row_id,readiness_status,result,evidence_ref,evidence_sha256,source_commit,blocker_reason,actual_result"
  printf 'row-one,PASS,pass,%s,%s,abc123,NOT_APPLICABLE,NOT_APPLICABLE\n' "$evidence_ref" "$evidence_sha"
  printf 'row-one,PASS,pass,%s,%s,abc123,NOT_APPLICABLE,NOT_APPLICABLE\n' "$evidence_ref" "$evidence_sha"
} >"$tmpdir/duplicate-row.csv"
if python3 "$repo_root/tools/release_matrix_validate.py" \
  --repo-root "$repo_root" \
  --matrix "$tmpdir/duplicate-row.csv" \
  --manifest "$tmpdir/pass-manifest.json" \
  --max-errors 5 >/tmp/sshfling-release-matrix-duplicate-row.log 2>&1; then
  echo "expected release matrix validation to reject duplicate row IDs" >&2
  exit 1
fi
grep -Fq "duplicate row_id in matrix" /tmp/sshfling-release-matrix-duplicate-row.log

write_manifest "$tmpdir/missing-rows-manifest.json" '[]'
if python3 "$repo_root/tools/release_matrix_validate.py" \
  --repo-root "$repo_root" \
  --matrix "$tmpdir/pass.csv" \
  --manifest "$tmpdir/missing-rows-manifest.json" \
  --max-errors 5 >/tmp/sshfling-release-matrix-missing-rows.log 2>&1; then
  echo "expected release matrix validation to reject missing row coverage" >&2
  exit 1
fi
grep -Fq "does not cover this row" /tmp/sshfling-release-matrix-missing-rows.log

write_manifest "$tmpdir/unknown-row-manifest.json" '["row-one", "ghost-row"]'
if python3 "$repo_root/tools/release_matrix_validate.py" \
  --repo-root "$repo_root" \
  --matrix "$tmpdir/pass.csv" \
  --manifest "$tmpdir/unknown-row-manifest.json" \
  --max-errors 5 >/tmp/sshfling-release-matrix-unknown-row.log 2>&1; then
  echo "expected release matrix validation to reject manifest rows not present in the matrix" >&2
  exit 1
fi
grep -Fq "references unknown row_id: ghost-row" /tmp/sshfling-release-matrix-unknown-row.log

write_manifest "$tmpdir/duplicate-manifest-row.json" '["row-one", "row-one"]'
if python3 "$repo_root/tools/release_matrix_validate.py" \
  --repo-root "$repo_root" \
  --matrix "$tmpdir/pass.csv" \
  --manifest "$tmpdir/duplicate-manifest-row.json" \
  --max-errors 5 >/tmp/sshfling-release-matrix-duplicate-manifest-row.log 2>&1; then
  echo "expected release matrix validation to reject duplicate manifest row coverage" >&2
  exit 1
fi
grep -Fq "duplicates row_id: row-one" /tmp/sshfling-release-matrix-duplicate-manifest-row.log

write_manifest "$tmpdir/wildcard-manifest.json" '"*"'
if python3 "$repo_root/tools/release_matrix_validate.py" \
  --repo-root "$repo_root" \
  --matrix "$tmpdir/pass.csv" \
  --manifest "$tmpdir/wildcard-manifest.json" \
  --max-errors 5 >/tmp/sshfling-release-matrix-wildcard.log 2>&1; then
  echo "expected release matrix validation to reject wildcard row coverage" >&2
  exit 1
fi
grep -Fq "does not cover this row" /tmp/sshfling-release-matrix-wildcard.log

cat >"$tmpdir/evidence-ref-mismatch-manifest.json" <<JSON
{
  "schema_version": 1,
  "evidence": [
    {
      "evidence_id": "$evidence_ref",
      "evidence_ref": "${evidence_ref}.other",
      "artifact_path": "$evidence_ref",
      "sha256": "$evidence_sha",
      "source_commit": "abc123",
      "result": "pass",
      "rows": ["row-one"]
    }
  ]
}
JSON
if python3 "$repo_root/tools/release_matrix_validate.py" \
  --repo-root "$repo_root" \
  --matrix "$tmpdir/pass.csv" \
  --manifest "$tmpdir/evidence-ref-mismatch-manifest.json" \
  --max-errors 5 >/tmp/sshfling-release-matrix-evidence-ref-mismatch.log 2>&1; then
  echo "expected release matrix validation to reject manifest evidence_ref mismatch" >&2
  exit 1
fi
grep -Fq "manifest evidence_ref" /tmp/sshfling-release-matrix-evidence-ref-mismatch.log

cat >"$tmpdir/source-mismatch-manifest.json" <<JSON
{
  "schema_version": 1,
  "evidence": [
    {
      "evidence_id": "$evidence_ref",
      "evidence_ref": "$evidence_ref",
      "artifact_path": "$evidence_ref",
      "sha256": "$evidence_sha",
      "source_commit": "def456",
      "result": "pass",
      "rows": ["row-one"]
    }
  ]
}
JSON
if python3 "$repo_root/tools/release_matrix_validate.py" \
  --repo-root "$repo_root" \
  --matrix "$tmpdir/pass.csv" \
  --manifest "$tmpdir/source-mismatch-manifest.json" \
  --max-errors 5 >/tmp/sshfling-release-matrix-source-mismatch.log 2>&1; then
  echo "expected release matrix validation to reject manifest source commit mismatch" >&2
  exit 1
fi
grep -Fq "source_commit for $evidence_ref does not match row" /tmp/sshfling-release-matrix-source-mismatch.log

cat >"$tmpdir/missing-artifact-manifest.json" <<JSON
{
  "schema_version": 1,
  "evidence": [
    {
      "evidence_id": "$evidence_ref",
      "evidence_ref": "$evidence_ref",
      "artifact_path": "${evidence_ref}.missing",
      "sha256": "$evidence_sha",
      "source_commit": "abc123",
      "result": "pass",
      "rows": ["row-one"]
    }
  ]
}
JSON
if python3 "$repo_root/tools/release_matrix_validate.py" \
  --repo-root "$repo_root" \
  --matrix "$tmpdir/pass.csv" \
  --manifest "$tmpdir/missing-artifact-manifest.json" \
  --max-errors 5 >/tmp/sshfling-release-matrix-missing-artifact.log 2>&1; then
  echo "expected release matrix validation to reject missing manifest artifacts" >&2
  exit 1
fi
grep -Fq "manifest artifact path does not exist" /tmp/sshfling-release-matrix-missing-artifact.log

cat >"$tmpdir/escaping-artifact-manifest.json" <<JSON
{
  "schema_version": 1,
  "evidence": [
    {
      "evidence_id": "$evidence_ref",
      "evidence_ref": "$evidence_ref",
      "artifact_path": "../outside-release-evidence.log",
      "sha256": "$evidence_sha",
      "source_commit": "abc123",
      "result": "pass",
      "rows": ["row-one"]
    }
  ]
}
JSON
if python3 "$repo_root/tools/release_matrix_validate.py" \
  --repo-root "$repo_root" \
  --matrix "$tmpdir/pass.csv" \
  --manifest "$tmpdir/escaping-artifact-manifest.json" \
  --max-errors 5 >/tmp/sshfling-release-matrix-escaping-artifact.log 2>&1; then
  echo "expected release matrix validation to reject artifact paths that escape the repo" >&2
  exit 1
fi
grep -Fq "manifest artifact path escapes repo" /tmp/sshfling-release-matrix-escaping-artifact.log

ln -s pass.log "$evidence_dir/link.log"
link_ref="${evidence_dir#"$repo_root"/}/link.log"
if [[ "$link_ref" == "$evidence_dir/link.log" ]]; then
  link_ref="$(realpath --relative-to "$repo_root" "$evidence_dir/link.log")"
fi
{
  echo "row_id,readiness_status,result,evidence_ref,evidence_sha256,source_commit,blocker_reason,actual_result"
  printf 'row-link,PASS,pass,%s,%s,abc123,NOT_APPLICABLE,NOT_APPLICABLE\n' "$link_ref" "$evidence_sha"
} >"$tmpdir/symlink-artifact.csv"
cat >"$tmpdir/symlink-artifact-manifest.json" <<JSON
{
  "schema_version": 1,
  "evidence": [
    {
      "evidence_id": "$link_ref",
      "evidence_ref": "$link_ref",
      "artifact_path": "$link_ref",
      "sha256": "$evidence_sha",
      "source_commit": "abc123",
      "result": "pass",
      "rows": ["row-link"]
    }
  ]
}
JSON
if python3 "$repo_root/tools/release_matrix_validate.py" \
  --repo-root "$repo_root" \
  --matrix "$tmpdir/symlink-artifact.csv" \
  --manifest "$tmpdir/symlink-artifact-manifest.json" \
  --max-errors 5 >/tmp/sshfling-release-matrix-symlink-artifact.log 2>&1; then
  echo "expected release matrix validation to reject symlinked manifest artifacts" >&2
  exit 1
fi
grep -Fq "manifest artifact path uses symlink" /tmp/sshfling-release-matrix-symlink-artifact.log

write_matrix "$tmpdir/fake-sha.csv" "row-one" "NOT_APPLICABLE"
if python3 "$repo_root/tools/release_matrix_validate.py" \
  --repo-root "$repo_root" \
  --matrix "$tmpdir/fake-sha.csv" \
  --manifest "$tmpdir/pass-manifest.json" \
  --max-errors 5 >/tmp/sshfling-release-matrix-fake-sha.log 2>&1; then
  echo "expected release matrix validation to reject placeholder PASS sha" >&2
  exit 1
fi
grep -Fq "evidence_sha256 is not a real sha256" /tmp/sshfling-release-matrix-fake-sha.log

{
  echo "row_id,readiness_status,result,evidence_ref,evidence_sha256,source_commit,blocker_reason,actual_result"
  printf 'row-blocked,BLOCKED,blocked,NONE,NONE,abc123,external signing evidence missing,NOT_APPLICABLE\n'
} >"$tmpdir/blocked.csv"
write_manifest "$tmpdir/blocked-manifest.json" '[]'
python3 "$repo_root/tools/release_matrix_validate.py" \
  --repo-root "$repo_root" \
  --matrix "$tmpdir/blocked.csv" \
  --manifest "$tmpdir/blocked-manifest.json" \
  --max-errors 5 >/tmp/sshfling-release-matrix-blocked-shape.log

{
  echo "row_id,readiness_status,result,evidence_ref,evidence_sha256,source_commit,blocker_reason,actual_result"
  printf 'row-unsupported,UNSUPPORTED,unsupported,NONE,NONE,abc123,target outside supported package scope,NOT_APPLICABLE\n'
  printf 'row-experimental,EXPERIMENTAL,experimental,NONE,NONE,abc123,community target requires ecosystem maintainer review,NOT_APPLICABLE\n'
  printf 'row-na,NOT_APPLICABLE,not_applicable,NONE,NONE,abc123,NOT_APPLICABLE,NOT_APPLICABLE\n'
  printf 'row-future,FUTURE_WORK,future_work,NONE,NONE,abc123,future platform not claimed for this release,NOT_APPLICABLE\n'
} >"$tmpdir/non-pass-readiness-statuses.csv"
python3 "$repo_root/tools/release_matrix_validate.py" \
  --repo-root "$repo_root" \
  --matrix "$tmpdir/non-pass-readiness-statuses.csv" \
  --manifest "$tmpdir/blocked-manifest.json" \
  --max-errors 5 >/tmp/sshfling-release-matrix-non-pass-statuses.log

if python3 "$repo_root/tools/release_matrix_validate.py" \
  --repo-root "$repo_root" \
  --matrix "$tmpdir/blocked.csv" \
  --manifest "$tmpdir/blocked-manifest.json" \
  --require-pass \
  --max-errors 5 >/tmp/sshfling-release-matrix-blocked-strict.log 2>&1; then
  echo "expected --require-pass to reject BLOCKED rows" >&2
  exit 1
fi
grep -Fq "row is not allowed by --require-pass" /tmp/sshfling-release-matrix-blocked-strict.log

{
  echo "row_id,readiness_status,result,evidence_ref,evidence_sha256,source_commit,blocker_reason,actual_result,exception_id,exception_owner,exception_expires,notes"
  printf 'row-blocked,BLOCKED,blocked,NONE,NONE,abc123,external signing evidence missing,NOT_APPLICABLE,EXC-2999-001,security-review,2999-12-31,time-bound release exception\n'
} >"$tmpdir/blocked-approved-exception.csv"
python3 "$repo_root/tools/release_matrix_validate.py" \
  --repo-root "$repo_root" \
  --matrix "$tmpdir/blocked-approved-exception.csv" \
  --manifest "$tmpdir/blocked-manifest.json" \
  --require-pass \
  --allow-approved-exceptions \
  --max-errors 5 >/tmp/sshfling-release-matrix-blocked-approved-exception.log

{
  echo "row_id,readiness_status,result,evidence_ref,evidence_sha256,source_commit,blocker_reason,actual_result,exception_id,exception_owner,exception_expires,notes"
  printf 'row-blocked,BLOCKED,blocked,NONE,NONE,abc123,external signing evidence missing,NOT_APPLICABLE,EXC-2000-001,security-review,2000-01-01,expired release exception\n'
} >"$tmpdir/blocked-expired-exception.csv"
if python3 "$repo_root/tools/release_matrix_validate.py" \
  --repo-root "$repo_root" \
  --matrix "$tmpdir/blocked-expired-exception.csv" \
  --manifest "$tmpdir/blocked-manifest.json" \
  --require-pass \
  --allow-approved-exceptions \
  --max-errors 5 >/tmp/sshfling-release-matrix-blocked-expired-exception.log 2>&1; then
  echo "expected --allow-approved-exceptions to reject expired exception records" >&2
  exit 1
fi
grep -Fq "approved exception expired on 2000-01-01" /tmp/sshfling-release-matrix-blocked-expired-exception.log

release_version="1.2.3"
release_dist="$tmpdir/release-dist"
generated_dir="$tmpdir/generated"
mkdir -p "$release_dist"
mapfile -t catalog_release_files < <(
  bash "$repo_root/packaging/list-language-release-artifacts.sh" "$release_version" catalog
)
release_files=(
  "sshfling_${release_version}_all.deb"
  "sshfling-${release_version}-1.noarch.rpm"
  "sshfling-${release_version}.tar.gz"
  "SSHFling.Tool.${release_version}.nupkg"
  "SSHFling.${release_version}.nupkg"
  "sshfling-cli-${release_version}.jar"
  "sshfling-cli-${release_version}-javadoc.jar"
  "sshfling-cli-${release_version}-sources.jar"
  "sshfling-cli-${release_version}.pom"
  "sshfling-${release_version}.tgz"
  "sshfling-${release_version}-py3-none-any.whl"
  "sshfling-go-${release_version}.zip"
  "sshfling-cli-${release_version}.crate"
  "sshfling-php-${release_version}.zip"
  "sshfling-${release_version}.gem"
  "sshfling-native-${release_version}.tar.gz"
  "sshfling-perl-${release_version}.tar.gz"
  "sshfling-tcl-${release_version}.tar.gz"
  "sshfling-awk-${release_version}.tar.gz"
  "sshfling-sed-${release_version}.tar.gz"
  "sshfling-lua-${release_version}.tar.gz"
  "sshfling-zsh-${release_version}.tar.gz"
  "sshfling-fish-${release_version}.tar.gz"
  "sshfling-elvish-${release_version}.tar.gz"
  "sshfling-nushell-${release_version}.tar.gz"
  "sshfling-powershell-${release_version}.tar.gz"
  "sshfling-guix-scheme-${release_version}.tar.gz"
  "sshfling-${release_version}-1.all.rock"
  "sshfling-scripting-languages-${release_version}-validation.tsv"
  "${catalog_release_files[@]}"
  "sshfling-${release_version}.pkg"
  "sshfling-${release_version}.msi"
  "sshfling-${release_version}-windows.zip"
  "SHA256SUMS"
  "RELEASE-EVIDENCE.md"
)
for release_file in "${release_files[@]}"; do
  printf 'fake release artifact: %s\n' "$release_file" >"$release_dist/$release_file"
done

python3 "$repo_root/tools/generate_release_evidence.py" \
  --repo-root "$repo_root" \
  --mode release-assets \
  --artifacts-dir "$release_dist" \
  --version "$release_version" \
  --source-commit abc123 \
  --output-dir "$generated_dir" >/tmp/sshfling-release-evidence-generate.log

python3 "$repo_root/tools/release_matrix_validate.py" \
  --repo-root "$repo_root" \
  --matrix "$generated_dir/release-assets-matrix.csv" \
  --manifest "$generated_dir/release-assets-manifest.json" \
  --max-errors 5 >/tmp/sshfling-release-evidence-validate.log

printf 'unexpected release artifact\n' >"$release_dist/sshfling-unexpected-${release_version}.tar.gz"
if python3 "$repo_root/tools/generate_release_evidence.py" \
  --repo-root "$repo_root" \
  --mode release-assets \
  --artifacts-dir "$release_dist" \
  --version "$release_version" \
  --source-commit abc123 \
  --output-dir "$tmpdir/generated-unexpected" >/tmp/sshfling-release-evidence-unexpected.log 2>&1; then
  echo "expected release evidence generation to reject unexpected package artifacts" >&2
  exit 1
fi
grep -Fq "unexpected files" /tmp/sshfling-release-evidence-unexpected.log
rm -f "$release_dist/sshfling-unexpected-${release_version}.tar.gz"

rm -f "$release_dist/sshfling-${release_version}.msi"
if python3 "$repo_root/tools/generate_release_evidence.py" \
  --repo-root "$repo_root" \
  --mode release-assets \
  --artifacts-dir "$release_dist" \
  --version "$release_version" \
  --source-commit abc123 \
  --output-dir "$tmpdir/generated-missing" >/tmp/sshfling-release-evidence-missing.log 2>&1; then
  echo "expected release evidence generation to reject missing package artifacts" >&2
  exit 1
fi
grep -Fq "missing required release-assets files" /tmp/sshfling-release-evidence-missing.log

rm -rf "$release_dist"
mkdir -p "$release_dist"
for release_file in "${release_files[@]}"; do
  printf 'fake release artifact: %s\n' "$release_file" >"$release_dist/$release_file"
done
printf 'external msi bytes\n' >"$tmpdir/external.msi"
rm -f "$release_dist/sshfling-${release_version}.msi"
ln -s "$tmpdir/external.msi" "$release_dist/sshfling-${release_version}.msi"
if python3 "$repo_root/tools/generate_release_evidence.py" \
  --repo-root "$repo_root" \
  --mode release-assets \
  --artifacts-dir "$release_dist" \
  --version "$release_version" \
  --source-commit abc123 \
  --output-dir "$tmpdir/generated-symlink" >/tmp/sshfling-release-evidence-symlink.log 2>&1; then
  echo "expected release evidence generation to reject symlinked package artifacts" >&2
  exit 1
fi
grep -Fq "path must not use symlinks" /tmp/sshfling-release-evidence-symlink.log

if python3 "$repo_root/tools/generate_release_evidence.py" \
  --repo-root "$repo_root" \
  --mode release-assets \
  --artifacts-dir "$release_dist" \
  --version "../$release_version" \
  --source-commit abc123 \
  --output-dir "$tmpdir/generated-version-escape" >/tmp/sshfling-release-evidence-version-escape.log 2>&1; then
  echo "expected release evidence generation to reject version path separators" >&2
  exit 1
fi
grep -Fq "version must not contain path separators" /tmp/sshfling-release-evidence-version-escape.log

security_output="$tmpdir/security-scans"
python3 "$repo_root/tools/release_security_scan.py" \
  --repo-root "$repo_root" \
  --version "$release_version" \
  --source-commit abc123 \
  --allow-dirty \
  --output-dir "$security_output" >/tmp/sshfling-release-security-scan.log

for evidence_file in \
  secret-scan-report.json \
  license-report.json \
  shell-static-security-report.json \
  python-static-security-report.json \
  dependency-inventory.json \
  sbom.spdx.json \
  dockerfile-hygiene-report.json \
  systemd-hardening-report.json \
  key-custody-report.json \
  security-scan-report.json \
  security-scan-report.md \
  security-scan-matrix.csv \
  security-scan-manifest.json; do
  test -s "$security_output/$evidence_file"
done

python3 "$repo_root/tools/release_matrix_validate.py" \
  --repo-root "$repo_root" \
  --matrix "$security_output/security-scan-matrix.csv" \
  --manifest "$security_output/security-scan-manifest.json" \
  --max-errors 5 >/tmp/sshfling-release-security-matrix.log

python3 - "$security_output/security-scan-report.json" <<'PY'
import json
import sys

payload = json.loads(open(sys.argv[1], encoding="utf-8").read())
baseline = payload["baseline_checks"]
dependencies = baseline["dependency_inventory"]["dependencies"]
optional_tools = {item["name"]: item for item in payload["optional_tools"]}

assert payload["overall_status"] == "pass"
assert "source_tree_dirty" in payload
assert "dirty_fingerprint_sha256" in payload
assert baseline["secret_scan"]["status"] == "pass"
assert baseline["license_scan"]["status"] == "pass"
assert baseline["shell_static"]["status"] == "pass"
assert baseline["python_static"]["status"] == "pass"
assert baseline["dockerfile_hygiene"]["status"] == "pass"
assert baseline["systemd_hardening"]["status"] == "pass"
assert baseline["key_custody"]["status"] == "pass"
assert baseline["key_custody"]["external_evidence_required"]
assert any(item["name"] == "debian:bookworm-slim" for item in dependencies)
assert any(item["name"] == "python3" for item in dependencies)
assert all(item["status"] == "skipped" for item in payload["optional_tools"])
assert "osv-scanner" in optional_tools
PY
