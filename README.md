# MarketWatch

A personal iOS watchlist app for Indian equities (NSE/BSE). Create any number of
named watchlists, add scrips to each by company name or symbol, and rename or
delete lists as needed. Prices are read live from a Google Sheet you control,
using the Sheet's own `GOOGLEFINANCE()` formula.

## Features

- Multiple watchlists — create, rename, delete (swipe actions on the list screen)
- Add/remove scrips within a watchlist
- Search-to-add for NSE scrips (autocomplete against nseindia.com), or add any
  NSE/BSE scrip manually
- Adding a scrip appends a `GOOGLEFINANCE()` row to your Google Sheet automatically
- Pull-to-refresh reads current prices back from that Sheet, for both NSE and BSE

## How pricing works

Rather than scraping NSE/BSE for live prices, the app signs in to your Google
account and reads/writes a Google Sheet through Google's official, documented
Sheets API v4. The Sheet does the actual pricing via `GOOGLEFINANCE()`, a
built-in Sheets formula that covers both NSE and BSE tickers
(`GOOGLEFINANCE("NSE:TCS","price")`, `GOOGLEFINANCE("BSE:500325","price")`).

This is more reliable than hitting NSE's website directly, but it isn't
risk-free either — flag these before relying on it:

- The Sheets API itself is a stable, official Google API. `GOOGLEFINANCE` is
  not covered by the same guarantee — it's a spreadsheet formula function, its
  coverage of individual symbols can be incomplete, and Google has changed its
  behavior for certain tickers/exchanges before without notice.
- You need your own Google Cloud OAuth client and your own Sheet (steps
  below) — nothing is shared or bundled.
- NSE's search-to-add (`NSEService.swift`, `/api/search/autocomplete`) is
  still an unofficial, undocumented endpoint, used only to help you find a
  symbol while adding a scrip — not for pricing. It can break or get blocked
  independently of everything above; manual add always works as a fallback.

### 1. Create the Google Sheet

1. Create a new Google Sheet in your own Google account.
2. Rename its first tab to exactly `Prices`.
3. Add a header row: `Symbol | Exchange | Price | Change | %Change`.
4. Copy the **Spreadsheet ID** out of its URL:
   `docs.google.com/spreadsheets/d/`**`THIS_PART`**`/edit`

You don't need to add any rows yourself — the app appends a row (with
`GOOGLEFINANCE` formulas already filled in) each time you add a scrip.

### 2. Create a Google Cloud OAuth client

1. In [Google Cloud Console](https://console.cloud.google.com/), create a
   project (or use an existing one).
2. Enable the **Google Sheets API** for it (APIs & Services → Library).
3. Configure the **OAuth consent screen** (APIs & Services → OAuth consent
   screen): External, and add your own Google account under Test users —
   personal/testing mode is enough, no Google review needed.
4. Create credentials → **OAuth client ID** → Application type **iOS**.
   Bundle ID: `com.marketwatch.app` (matches `project.yml`'s
   `PRODUCT_BUNDLE_IDENTIFIER` — change both together if you rename it).
5. Copy the generated **Client ID** — it looks like
   `1234567890-abc123.apps.googleusercontent.com`.

### 3. Wire the IDs into the project

Edit `MarketWatch/project.yml`:

```yaml
GOOGLE_OAUTH_CLIENT_ID: "1234567890-abc123.apps.googleusercontent.com"
GOOGLE_REVERSED_CLIENT_ID: "com.googleusercontent.apps.1234567890-abc123"
```

(the second value is just the first with `.apps.googleusercontent.com`
replaced by moving `com.googleusercontent.apps.` to the front — this is
the custom URL scheme Google's OAuth redirect uses on iOS). Then re-run
`xcodegen generate` (see below) so it lands in the generated Info.plist.

### 4. Connect it in the app

Launch the app, tap the gear icon on the Watchlists screen, tap **Sign in
with Google**, and paste your Sheet's Spreadsheet ID into the Settings
screen. From then on, adding a scrip appends a price row to the Sheet, and
pull-to-refresh reads current values back.

Sign-in uses a hand-rolled OAuth 2.0 + PKCE flow (`GoogleAuthService.swift`)
built on Apple's own `ASWebAuthenticationSession`, rather than Google's
GoogleSignIn-iOS SDK — this avoids taking on a third-party SDK dependency
whose exact API I can't verify from here. The flow follows Google's
documented "OAuth 2.0 for Mobile & Desktop Apps" pattern; if sign-in starts
failing, that doc is the first place to check for changes.

## Project structure

```
MarketWatch/
  project.yml              # XcodeGen spec — generates the .xcodeproj
  MarketWatch/
    MarketWatchApp.swift
    Models/
      WatchList.swift
      Scrip.swift
    Views/
      WatchListsView.swift       # list of watchlists: create/rename/delete
      WatchListDetailView.swift  # scrips in one list, refresh prices
      AddScripView.swift         # search NSE + manual add
      SettingsView.swift         # Google sign-in, Spreadsheet ID
    Services/
      NSEService.swift           # NSE symbol search only (not pricing)
      GoogleAuthService.swift    # OAuth 2.0 + PKCE sign-in
      GoogleSheetsService.swift  # reads/appends rows in your Sheet
      KeychainHelper.swift       # stores the OAuth refresh token
```

Persistence is via SwiftData (`WatchList` <-> `Scrip`, one-to-many), stored
locally on device. The OAuth refresh token lives in the iOS Keychain; the
Spreadsheet ID lives in `UserDefaults`. Nothing else syncs off the device.

## Opening the project

This repo doesn't check in a generated `.xcodeproj` (Xcode project files are
better generated than hand-maintained). On a Mac with Xcode installed:

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) if you don't have
   it: `brew install xcodegen`
2. Fill in `GOOGLE_OAUTH_CLIENT_ID` / `GOOGLE_REVERSED_CLIENT_ID` in
   `MarketWatch/project.yml` (see setup steps above) — the app still builds
   and runs without this, you just won't be able to sign in to Google yet.
3. From the `MarketWatch/` directory, run:
   ```
   cd MarketWatch
   xcodegen generate
   ```
4. Open the generated `MarketWatch.xcodeproj` in Xcode, select a simulator or
   your device (target: iOS 17+), and run.

## Known limitations / things to verify

- **Not built or run in Xcode as part of producing this code** — this was
  written in a Linux environment without Xcode/a simulator/network access to
  Google's OAuth endpoints, so none of it has been compiled or tested end to
  end. Expect to fix small build errors on first open, and treat the OAuth
  flow especially as unverified until you've walked through it once yourself.
- `CFBundleURLTypes` / custom Info.plist keys are generated by XcodeGen's
  `info.properties` mechanism with `$(...)` variable substitution from build
  settings — a standard, documented XcodeGen/Xcode feature, but double-check
  the generated Info.plist if the redirect doesn't fire.
- NSE session cookies (for search only) are fetched by loading nseindia.com's
  homepage once per app launch before calling the JSON endpoint — a common
  workaround for their bot protection, not a documented contract.
- No app icon / launch screen asset catalog is included; Xcode will use
  defaults.
