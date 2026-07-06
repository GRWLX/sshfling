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

release_version="1.2.3"
release_dist="$tmpdir/release-dist"
generated_dir="$tmpdir/generated"
mkdir -p "$release_dist"
release_files=(
  "sshfling_${release_version}_all.deb"
  "sshfling-${release_version}-1.noarch.rpm"
  "sshfling-${release_version}.tar.gz"
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
