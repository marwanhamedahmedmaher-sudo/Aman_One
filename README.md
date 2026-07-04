# aman_sales_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Supervisor web tools (`docs/` + edge functions)

Alongside the Flutter app, this repo is the **source of truth** for the browser-based
supervisor tools:

- **HTML pages** in `docs/` — `visit-export.html` (Excel export of field visits),
  `admin-portal.html` and `supervisor-portal.html` (rep-account management). These are
  thin clients; all authentication/authorization is enforced server-side.
- **Edge functions** in `supabase/functions/` — `export-visits-xlsx` and `admin-users`
  are the privileged backends they call (supervisors are scoped to their own
  `business_unit` here, not in the HTML). Deploy these to the prod Supabase project when
  they change.

> **Publishing the pages:** browsers can't load these from `*.supabase.co` (the platform
> serves edge-function HTML as `text/plain`), so the served copies live on GitHub Pages in
> the separate **[`aman-pages`](https://github.com/marwanhamedahmedmaher-sudo/aman-pages)**
> repo. **Edit the page here in `docs/`, then copy it into `aman-pages`** (renaming
> `visit-export.html` → `index.html`) and push — Pages redeploys automatically. The
> `docs/` copy stays canonical; `aman-pages` is only a publish target. The old
> `visit-export-page` / `admin-portal-page` edge functions are **dead paths** (parked).
