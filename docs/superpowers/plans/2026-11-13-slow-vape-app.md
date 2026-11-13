# Slow Vape implementation plan

**Goal** Build the agreed offline Mac app.
**Architecture** SwiftUI screens share a single model with an AppKit window controller. Local data is persisted atomically, and period and limit calculations live in SlowVapeCore.
**Spec** [Slow Vape for Mac](../specs/2026-11-13-slow-vape-design.md)

- [ ] Test rolling windows, calendar boundaries, coverage and alert repeat logic.
- [ ] Add local history and settings, wire up the existing camera and track real coverage.
- [ ] Add first launch, dashboard, settings, menu item and persistent foreground alert.
- [ ] Build and sign the app, run unit tests, and check the window and alert in macOS.
