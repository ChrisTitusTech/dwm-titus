# Active Tasks

## 0.8 integration and release preparation

User authorization (2026-11-04): merge PR #425 after thumbnail acceptance,
finish review/merge of the other three PRs, address #368, and prepare 0.8.

| Issue | Pull request | Behavior |
| --- | --- | --- |
| #297 | [#424](https://github.com/ChrisTitusTech/dwm-titus/pull/424) | Visual layout selection, master sizing and per-tag gaps; scale preview retained. |
| #350 | [#425](https://github.com/ChrisTitusTech/dwm-titus/pull/425) | Window overview with opening-only static thumbnails; user verified. |
| #358 | [#422](https://github.com/ChrisTitusTech/dwm-titus/pull/422) | Optional calendar and explicitly fetched weather. |
| #370 | [#423](https://github.com/ChrisTitusTech/dwm-titus/pull/423) | Opt-in floating-window titlebars with move/close controls. |

- [x] Implement all four features and publish reviewed PRs with runtime evidence.
- [x] Complete thumbnail dev sync and receive user acceptance for #425.
- [x] Merge #425 at 7474120d915a9a80d77082d8f763e6b829f80fc0.
- [ ] Integrate updated main, validate, review and merge #424.
- [ ] Integrate updated main, validate, review and merge #423.
- [ ] Integrate updated main, validate, review and merge #422.
- [ ] Address #368's published-image Wi-Fi omission and validate new artifacts.
- [ ] Prepare v0.8.0 source, release notes, checksums and qualification record.

Follow [ROADMAP.md](ROADMAP.md), [RELEASING.md](docs/RELEASING.md) and SPEC.md's
Fedora image contract. Keep initial failures, exact corrections, reused coverage
and untested hardware explicit. Keep #368 open until replacement published
media is verified; a source-only fix does not update existing downloads.
