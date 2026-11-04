# Fedora 0.8 Roadmap

## Current scope

Implement the remaining desktop feature requests in separate ready-for-review
pull requests: #297, #350, #358 and #370. The user authorized this sequence on
2026-11-04. Do not merge or publish the release in this workflow.

Issue #368 concerns the published v0.7.2 ISO and stays deferred until these
features are finished and the 0.8 release is prepared. Source fixes do not
qualify or update already published images.

## Review boundaries

1. #297: visual layout selection, master sizing and per-tag tile gaps in
   Appearance, retaining the existing desktop-scale preview workflow.
2. #350: an event-driven overview of individual windows across tags, with
   keyboard navigation and focus/tag selection without moving windows.
3. #358: optional calendar and weather panel widgets, supported by the panel
   settings protocol and bounded, explicitly requested weather networking.
4. #370: optional floating-window titlebars with move and close controls,
   configurable without changing existing defaults.

Complete each boundary's focused checks, aggregate repository gate, nested X11
runtime evidence and independent Codex review before opening its PR. Record
untested multi-monitor or hardware behavior precisely. The four feature PRs
are the stop point; release qualification, #368, merging and publication follow
separately after the feature work is complete.
