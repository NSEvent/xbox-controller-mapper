# Lemon Squeezy distribution

Status: account verified, store created, test product drafted; **not selling yet** (2026-11-03).

## Account and storefront

Google sign-in reached new-account registration. The business-intent form was
submitted as Kevin Tang, United States, with the existing ControllerKeys website.
Lemon Squeezy recommended Stripe Managed Payments; we selected Lemon Squeezy for
its license API, download fulfillment and Chinese wallets. Kevin approved account
creation with his primary Google login and the displayed signup terms on 2026-11-02.
Google signup looped back to registration. Kevin completed email/password signup
on 2026-11-03; email verification succeeded. Store `controllerkeys.lemonsqueezy.com`
was created in test mode and the public support email below was saved.
Test product `1497491` is saved as a draft at
`https://app.lemonsqueezy.com/products/1497491`: USD 19.99 single payment,
Software tax category, English/Chinese description, license keys enabled with
unlimited length and activations, storefront visibility disabled. No files/media
uploaded yet. This is a test product ID, never a production configuration value.

Current handoff: `https://app.lemonsqueezy.com/settings/general/identity` opens
Stripe Connect onboarding in a separate window, initially requesting an email.
Kevin must complete financial-account onboarding, identity verification and payout
setup himself under browser-control rules. No Stripe details or payout information
were entered, and no payment was made. Do not repeat account creation.

Create a store/product in test mode first. Product settings:

- Name: ControllerKeys
- Price: USD 19.99, one-time payment, matching the existing app price.
- Generate license keys: enabled; lifetime; unlimited activations (all the buyer's Macs).
- Public support email: martini-doubler7g@icloud.com
- Website: https://www.kevintang.xyz/apps/controller-keys
- Policy: https://www.kevintang.xyz/apps/controller-keys/privacy-policy.html
- Fulfillment: signed, notarized DMG with Lemon Squeezy activation support.
  **Do not sell a key with the old Gumroad-only binary.**
- Cover/gallery: reuse the app's existing screenshots after visual inspection.
- Checkout copy: `docs/internal/lemon-squeezy-listing.md`.

Use the account's test checkout and test payment methods; never buy Kevin's own
product with real money to test it. Live paid verification needs separate exact
purchase approval. Store activation also requires a business questionnaire and
identity verification; collect only the fields the service actually requires.

## App integration

`LicenseDistribution.swift` deliberately contains no product IDs or checkout URL.
Until configured, the Lemon Squeezy picker and checkout button are hidden and
explicit Lemon Squeezy activation fails. This is a disabled integration candidate,
not a finished live channel.

After the live product exists, record its exact **store ID, product ID and variant
ID** in that file. These are public IDs, not secrets. Never use test-mode product
IDs in a customer build. Configure the live checkout URL after purchase delivery
and the compatible release are ready. Test-mode IDs are separate and may be passed
only to a local test verifier; never leave a debug/test bypass in release code.

Customers explicitly choose their purchase provider. Keys are never tried against
both services. Existing Gumroad keys, offline cache, trial and checkout remain.
Lemon Squeezy verification accepts only a matching key, matching store/product/
variant, valid active/inactive state and unexpired date. No API secret is embedded.
Requests use HTTPS, no redirects/cookies and bounded timeouts. Response errors are
not displayed verbatim; customer names/email are neither stored nor sent to analytics.

The unlimited-Mac license uses `/v1/licenses/validate` without creating activation
instances, matching existing local deactivation and indefinite offline ownership.
Do not configure a finite device limit with this implementation. Revocation is
checked on verification; previously confirmed offline licenses retain the existing
Gumroad-era behavior. Refund-triggered disablement and the business refund policy
must be checked before launch; don't assume local cached licenses are revocable.

## Acceptance before launch

1. Complete account creation and store approval; verify seller/public contact fields.
2. Create test product and test order; verify receipt key and download delivery.
3. Use that test key in a local test verifier bound to those exact test IDs.
4. Verify wrong store/product/variant, disabled/expired key and offline/network failures.
5. Create the live product, retaining all-Mac/lifetime/one-time terms; bind live IDs.
6. Run the full Mac Studio gate; produce the signed compatible release.
7. Verify existing Gumroad activation/cache and new Lemon Squeezy receipt instructions.
8. Verify actual Alipay/WeChat availability in the target checkout and, from mainland
   China without VPN, website, checkout, receipt, download, activation and updates.
9. Add the alternate checkout to the website and publish only after delivery works.

## Verification—2026-11-02

- Isolated Mac Studio copy: `/tmp/controllerkeys-lemon-20261102.rHjHoE`.
- Full `make test-full`: 2,496 XCTest cases, 35 skipped, zero failures; Python
  15 cases, three skipped, zero failures. Log: sibling `-gate.log`.
- Final source rebuild plus both licensing suites: 15 tests, zero failures,
  including the added preservation-on-Keychain-failure regression. Log: sibling
  `-final.log`. These final checks include the alternate checkout UI and all four
  translated string resources; full-suite run preceded those last small changes.
- `plutil -lint` passes for all four localization files; scoped Git whitespace passes.
- No real license API request, paid checkout, app installation, version bump,
  public push or release. Production identifiers and checkout remain unset.
- Studio's existing working tree was preserved; screen-test lock released.

## Sources (checked 2026-11-02)

- https://docs.lemonsqueezy.com/help/getting-started/activate-your-store
- https://docs.lemonsqueezy.com/help/getting-started/test-mode
- https://docs.lemonsqueezy.com/help/checkout/payment-methods
- https://docs.lemonsqueezy.com/help/licensing/generating-license-keys
- https://docs.lemonsqueezy.com/api/license-api
- https://docs.lemonsqueezy.com/api/license-api/validate-license-key

Wiki writeback deferred: start-of-session `make sync` failed with
`fatal: Cannot rebase onto multiple branches.` Per wiki instructions, no recovery
mutation or wiki edit was attempted. Research is already in the wiki's Gumroad page;
this setup status still needs to be reconciled there after sync is repaired.
