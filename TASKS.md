# Active Tasks

## 0.8 integration and release publication

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
- [x] Publish the Fedora 45 replacement images after separate release authorization, verify both complete public downloads and byte ranges, and confirm #368 is closed.

PR #427 merged at `529e772c808927450080a7fd9fdbc22c113d253f`. Its tree matches
the independently reviewed candidate source `37115915c527b33f4a7786cf197f1c2d739cc214`.
The user authorized the 0.8 Fedora 45 release on 2026-11-04. Both canonical mirror
images, matching checksums/build records and byte-range requests passed full public
download verification. See the [public verification record](https://downloads.christitus.com/iso/PUBLICATION-VERIFICATION.json).
Merging #427 automatically closed #368; its publication gate is now verified.

Follow [ROADMAP.md](ROADMAP.md), [RELEASING.md](docs/RELEASING.md) and SPEC.md's
Fedora image contract. Keep initial failures, exact corrections, reused coverage
and untested hardware explicit. This completes the 0.8 publication boundary;
no subsequent roadmap phase is started here.
