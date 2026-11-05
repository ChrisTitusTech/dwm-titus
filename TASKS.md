# Active Tasks

## 0.8 integration and release preparation

User authorization (2026-11-04): merge PR #425 after thumbnail acceptance,
finish review/merge of the other three PRs, address #368, and prepare 0.8.
Fedora 45 becomes the main ISO base; retain Fedora 44 compatibility.

| Issue | Pull request | Behavior |
| --- | --- | --- |
| #297 | [#424](https://github.com/ChrisTitusTech/dwm-titus/pull/424) | Visual layout selection, master sizing and per-tag gaps; scale preview retained. |
| #350 | [#425](https://github.com/ChrisTitusTech/dwm-titus/pull/425) | Window overview with opening-only static thumbnails; user verified. |
| #358 | [#422](https://github.com/ChrisTitusTech/dwm-titus/pull/422) | Optional calendar and explicitly fetched weather. |
| #370 | [#423](https://github.com/ChrisTitusTech/dwm-titus/pull/423) | Opt-in floating-window titlebars with move/close controls. |

- [x] Implement all four features and publish reviewed PRs with runtime evidence.
- [x] Complete thumbnail dev sync and receive user acceptance for #425.
- [x] Merge #425 at 7474120d915a9a80d77082d8f763e6b829f80fc0.
- [x] Integrate updated main, validate, review and merge #424 at f66298f9ef06f563df3e56ae6cceac3e17243afb.
- [x] Integrate updated main, validate, review and merge #423 at a058b8bd5136c6e87802b9ab0ad718880dd88b5c.
- [x] Integrate updated main, validate, review and merge #422 at e39dadadd6dc9fca55dbc5cc2809e390a5d0c7ba.
- [x] Qualify Fedora 45 build/lint/runtime and Fedora 44 compatibility, including the updated test SDKs.
- [x] Implement #368's Wi-Fi package/plugin checks and validate both new candidate image variants.
- [x] Prepare v0.8.0 source, release notes, candidate checksums and the [qualification record](docs/RELEASE-0.8.0.md).
- [ ] After separate publication authorization, replace both public images, verify complete downloads and close #368.

The release-preparation PR records the final independent review and artifact
manifest. Preparing candidates does not publish a tag, release or mirror objects.

Follow [ROADMAP.md](ROADMAP.md), [RELEASING.md](docs/RELEASING.md) and SPEC.md's
Fedora image contract. Keep initial failures, exact corrections, reused coverage
and untested hardware explicit. Keep #368 open until replacement published
media is verified; a source-only fix does not update existing downloads.
