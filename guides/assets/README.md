# Documentation analytics

`plausible.js` is the Plausible Analytics tracker, vendored so that the published docs
load no JavaScript from third-party domains.

- Source: https://plausible.io/js/script.js
- Downloaded: 2026-10-22
- Tracker version: 36 (the `v` field the script sends with every event)
- License: AGPL-3.0, see https://github.com/plausible/analytics

The script is injected into the HTML docs by `before_closing_body_tag/1` in `mix.exs`,
configured by the `@analytics_domain` and `@analytics_endpoint` attributes there.
It sets no cookies; it only honours a `plausible_ignore` flag in `localStorage` as an opt-out.
