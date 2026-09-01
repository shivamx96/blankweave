# Blankweave releases

Blankweave uses stable [Semantic Versioning](https://semver.org/) releases with
two mutually checked pieces of metadata:

- `VERSION` declares exactly one `MAJOR.MINOR.PATCH` version in the release
  commit;
- an annotated `vMAJOR.MINOR.PATCH` Git tag marks that exact commit as released.

Neither is sufficient alone. Blankweave treats an untagged commit as a
development build, and the updater refuses a tag that does not match the
commit's `VERSION`. Annotated tags are required; lightweight tags are not
release boundaries.

For each release:

1. update `VERSION` in the PR;
2. merge the validated PR to `main`;
3. create and push the matching annotated tag on that exact commit;
4. do not advertise or update to the release until the tag is present.

`MIN_ROLLBACK_VERSION` is a separate compatibility floor, not the current
release. The initial floor is `0.1.0`, anchored by the annotated `v0.1.0` tag on
the known-working encrypted-boot and UWSM baseline. Releases older than that are
unsupported.

The initial release sequence is:

- `0.1.0` — known-working baseline;
- `0.1.1` — annotated-tag release infrastructure;
- `0.2.0` — read-only `blankweave doctor`;
- `0.3.0` — safe update and bounded recovery;
- `0.4.0` — guided and repeatable `blankweave setup`.

Config-file schema numbers belong to their individual formats and are not
Blankweave release versions.
