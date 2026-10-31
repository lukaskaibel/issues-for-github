# Timeline comparison captures

Both sets were captured on 28 October 2026 (Asia/Makassar), on the same Mac with Xcode 27.1, using Debug builds of:

- Before: `b0f8792d29f036ca95b01abd65a7d00e45ac3d7e`, the pull request's base.
- After: `7c5f355e9ff7f8de4931186a02024bc7571edd29`, the implementation before this screenshot-only update.

Each build ran as an isolated app on its own in-memory sample data, seeded on the same day. No account or live
project was used. Both used English, the en_US locale, a 1280 × 820 point window at 2× resolution, a 240 point
sidebar, and the Months preset. The after build's sample data includes the start-date field added by this feature.

For every capture the app window was raised, the corresponding sidebar row was selected through the native UI,
and the selected row was verified before capturing the window. Light and dark appearances were captured for both
the project's Release Plan timeline and its Roadmap. Sidebar selection colors match between the two revisions;
the old repository screenshots were not used as the baseline.

The before images are in `before/`. The matching after images are the `timeline-{light,dark}.webp` and
`roadmap-{light,dark}.webp` files in `Design/screenshots/`.

Both sets use the repository's `Tools/readme-images/compose.py` window layout: 130 × 110 pixel padding, 1800 pixel
output width, and WebP quality 92. Native window contents, including the sidebar colors, were not retouched.
