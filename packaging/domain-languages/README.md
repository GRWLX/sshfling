# Domain-language quarantine

This directory records the requested domain and platform language audit without
changing SSHFling's release support claims.

There are only two dispositions:

- `candidate`: the tracked source genuinely starts an installed `sshfling`
  process (or a caller-selected executable), passes arguments, waits, and
  reports the child status. It is still unpublished and unsupported.
- `blocked`: no source is provided because the language cannot host a local
  process, the only execution mechanism would weaken a platform security
  boundary, or the required proprietary platform cannot be validated here.

`manifest.tsv` is the machine-readable inventory. The authoritative blocker
details and external prerequisites are in
`docs/language-external-blockers.md`.

Run the non-promoting audit with:

```bash
./packaging/build-domain-languages.sh audit
./packaging/build-domain-languages.sh status
```

Run a candidate's conformance gate only on a host with its official runtime:

```bash
./packaging/build-domain-languages.sh gate matlab
```

The `package` action intentionally fails for every row. A candidate may not
become a release artifact until the existing support source, generated
matrices, release policy, and cross-platform release evidence are changed by a
separately authorized effort.
