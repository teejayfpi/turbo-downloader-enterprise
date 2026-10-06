# Monetization guide

Turbo Downloader is an on-device download manager for Android, Windows, Linux,
and macOS. This guide is practical advice for turning it into income without
breaking the things users like about it: it is offline-first, it is private,
and it does not route files through a server.

Nothing here is legal or financial advice. Check the rules of each store and
payment provider before you rely on them.

## 1. Decide what is free and what is paid

The safest split keeps the core useful and sells convenience or scale, never
the user's own data.

Keep free (this is what earns trust and reviews):

- Downloading, resuming, and pausing, on every platform.
- The built-in engine, at whatever quality it can produce on-device.
- One download at a time, with a sensible speed cap.

Sell as Pro (one-time unlock):

- Unlimited simultaneous downloads.
- Batch and playlist downloads.
- Scheduled downloads and "download later".
- The high-resolution merge path and per-format picking, where it is legal to
  offer.
- Custom download folders and filename templates.
- No promotional card on the home screen.

A one-time unlock is a good fit for a utility like this. Subscriptions fit
poorly because a download manager does not create a recurring cost for you:
there is no server doing the work. Charging a subscription for on-device work
tends to produce refunds and bad reviews.

## 2. Revenue streams, best first

1. **Pro unlock (one-time).** Simplest to run, easiest to explain. Suggested
   price: US$4-8, or the local equivalent. In Nigeria, N3,000-N6,000 reads as
   a fair one-time price for a desktop utility.
2. **Free with a limit, paid to lift it.** Ship the free tier above and gate
   the concurrency and batch features. This converts far better than a fully
   locked app because people can feel the value first.
3. **Tips / "buy the developer a coffee".** A small, always-visible way to
   support the designer works well alongside a free tier and costs nothing to
   add. The existing WhatsApp credit and a GitHub Sponsors link are enough.
4. **Store listing sales.** Microsoft Store and the Mac App Store can host the
   paid app directly and handle tax and receipts for you.
5. **Sponsorship or a "powered by" placement.** Only worth doing once you have
   real download numbers, and never in a way that ships user data anywhere.

Avoid, unless you change the product fundamentally: ads (they break the
offline-first promise and hurt reviews), selling download history, and any
"premium server acceleration" that quietly proxies the user's traffic.

## 3. Where to sell, per platform

| Platform | Best route | Notes |
| --- | --- | --- |
| Android | Google Play, with an in-app purchase for Pro | Play Billing takes a cut; a one-time in-app product maps cleanly to the unlock. |
| Windows | Direct installer (the Inno Setup build) + Microsoft Store | The direct `.exe` avoids store fees and is what power users expect. |
| macOS | Direct `.dmg`/`.zip` or the Mac App Store | Notarize the direct build so Gatekeeper does not block it. |
| Linux | Direct archive, or Flathub / Snap | Flathub is free and reaches a lot of users; a "donate" link converts here. |

For direct sales, use a merchant of record so you do not have to handle VAT
and sales tax yourself. Gumroad, Lemon Squeezy, and Paddle all work and take a
per-sale fee. For Nigerian customers, Paystack and Flutterwave have low fees
and local payment methods, and Selar is built for one-time digital sales.

## 4. Licensing and activation without a server

Because the app is device-only, do not build license checks that require a
server. This is now implemented:

- **Trial.** A fresh install gets a fixed free window (7 days by default). The
  clock starts on first run and is stored locally.
- **Signed keys.** A Pro key is `base64url(payload).base64url(signature)` where
  the payload is the licence claims and the signature is Ed25519. The app
  bundles only the **public** key, so it can verify but never mint keys.
- **Time-limited access.** A key may carry an expiry. The app shows a live
  countdown and locks back to the free tier when it ends.
- **Tamper resistance.** The app remembers the latest wall-clock time it has
  seen, so winding the clock back cannot extend a trial or a licence.
- **Storage.** The key lives in the existing secure store, not in plain
  preferences.
- **Binding.** Keys are not bound to a device. For a utility at this price that
  is an acceptable trade: it keeps honest users honest without hurting them.
  Device binding is possible later via a locally stored fingerprint.

See `docs/LICENSING.md` for the exact commands to generate a keypair, issue a
key, and ship a build that accepts it.

What is gated on access (matches the free/Pro split above): simultaneous
downloads, batch/playlist downloads, and scheduled downloads. Everything else
— single downloads, resume, pause, the built-in engine — works with or without
a licence.

## 5. Compliance and trust

- **Respect the source sites.** A general-purpose downloader is fine; a tool
  that specifically defeats DRM or circumvents paywalls is not. Keep the
  wording, and the defaults, on the right side of that line.
- **Say what leaves the device.** The answer should stay "nothing". Put that on
  the store listing and in the app; it is a selling point, not just a promise.
- **Have a privacy policy and terms** before you charge money. Both stores
  require them, and a payment provider will ask.
- **Keep the licence and attributions** (yt-dlp, FFmpeg, Flutter) intact. If you
  bundle a GPL component, honour its terms.

## 6. A concrete first 90 days

- **Days 1-14:** Ship the free app to Play and to a GitHub release. Add a
  "Support the developer" link and a clear Pro feature list in Settings.
- **Days 15-45:** Add the one-time Pro unlock behind a feature flag, sell it
  through Play Billing on Android and a signed key on desktop. Price it and
  leave it alone for a month.
- **Days 46-90:** Watch the conversion and refund rate. If people refund
  because a feature was missing, fix that feature before raising the price. Add
  the Microsoft Store listing. Start a simple changelog so reviewers see the
  app is alive.

Track only three numbers: installs, Pro conversion rate, and refund rate. If
conversion is under about 1%, the free tier is too generous or the Pro list is
not compelling; if refunds are above a few percent, the Pro features are not
delivering what the listing promised.

## 7. What not to do

- Do not gate the user's own downloads behind a subscription.
- Do not add analytics or crash reporting that phones home; it contradicts the
  product and the privacy policy.
- Do not promise "unlimited speed" or "bypass restrictions"; both invite
  takedowns and store rejections.
- Do not undercut yourself with a launch discount you then have to honour
  forever.
