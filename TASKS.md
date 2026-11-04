# Active Tasks

## 0.8 feature PR handoff

The requested implementation boundary is complete. Each feature has its own
ready-for-review PR against main:

| Issue | Pull request | Behavior |
| --- | --- | --- |
| #297 | [#424](https://github.com/ChrisTitusTech/dwm-titus/pull/424) | Visual layout selection, master sizing and per-tag gaps; existing scale preview retained. |
| #350 | [#425](https://github.com/ChrisTitusTech/dwm-titus/pull/425) | Searchable window cards across tags, predictable selection and cancellation focus. |
| #358 | [#422](https://github.com/ChrisTitusTech/dwm-titus/pull/422) | Optional calendar and explicitly fetched weather with supported panel persistence. |
| #370 | [#423](https://github.com/ChrisTitusTech/dwm-titus/pull/423) | Opt-in floating-window titlebars with mouse move/close and workspace masks. |

- [x] Implement and document the four independent review boundaries.
- [x] Complete applicable local validation, nested X11 evidence and idle checks.
- [x] Resolve actionable independent Codex review findings and rerun affected checks.
- [x] Publish ready-for-review PRs and verify their remote contents.

Each PR records exact checks, explicitly reused unchanged coverage, initial
failed attempts and their follow-up results, plus hardware qualification gaps.
Screenshots and feature documentation accompany each implementation.

## Deferred release boundary

Stop at the four feature PRs. Review/merge decisions, release qualification and
publication require a subsequent user instruction. Issue #368 concerns the
published v0.7.2 ISO and remains deferred until the feature work is finished and
the 0.8 release is prepared. Follow [ROADMAP.md](ROADMAP.md) and the existing
Fedora image validation contract when that work is authorized.
