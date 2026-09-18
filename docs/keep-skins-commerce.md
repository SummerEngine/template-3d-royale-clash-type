# Royal Clash keep skins

The Skins menu uses the authenticated Summer SDK for published offers, checkout,
and canonical owned inventory. Default is free. Rose Gold Keep and Emerald Keep
change only the player's keep surface materials; existing team/hit overlays,
mesh geometry and combat values remain unchanged. This is the existing local
battle's appearance, not an authoritative multiplayer equipment protocol.

## Verified staging catalog binding

`scripts/keep_skin_catalog.json` binds staging Royal Clash
`game_01M26GJ4XDM98JTTTKCK2G9G4D` to its activated cosmetic definitions and public
store items: Rose Gold `item_01M2S0E0WR1S2RE88Z1H8RKE91` and Emerald
`item_01M2S0E4C4ZBW5H6WAZDZC7R9S`. Normal catalog review and activation succeeded
on 2026-09-18 UTC. The public storefront returned Rose Gold at 300 Sparks and
Emerald at 100 Sparks, with previews matching the rendered game materials.
These are catalog publications, not ownership grants.

Definition and storefront IDs are separate fields; never infer identity from a
display name. The SDK supplies current offer IDs and Sparks amounts from the
live store. No price or offer ID is authored in game code. Use the destination
game's verified binding for any environment other than this staging game.

Checkout opens Summer's trusted confirmation; the game cannot approve, top up,
settle, or mint anything. This slice spends an existing Sparks balance only; top-ups are out of scope. Pending or
unknown requests disable another Buy submission. Retained checkout status is
presentation only, and a purchase receipt does not unlock a skin. The SDK's
independent owned inventory must contain its mapped definition. This game never
uses its demo coins or chest rewards as Sparks or inventory.

Only a selected appearance preference is written, under separate hashed account
and game sections in `user://keep_skins.cfg` (separate from audio settings). Ownership and receipts are never
persisted by this game. Initial load, failed refresh, account changes, and loss of
ownership fail to Default. Inventory events revalidate the current selection.
Opening Skins refreshes inventory; there is no network polling timer. Runtime
context checks read local SDK objects to fence account changes and stale async
completions. These checks introduce no authentication or Host transport logic.

## Focused qualification

Local candidate qualification completed the full game import, both policy and
on-disk loadout tests, project-context loading of six scripts, and five rendered
frames with the current task Engine. The executable SHA-256 is
`0e6fa63d5fba04252c70e49086f6790310600b5fc132fd1eb4b42788e0776f32`.
Strict logs contained no script/ConfigFile errors. The final display-name and
verified catalog bindings are data-only changes after that render pass.
Actual checkout, ownership delivery, and iOS acceptance remain required below.

Use an isolated writable directory for test files:

```
ROYAL_SKIN_TEST_DIRECTORY=<isolated-test-directory> <summer-engine> --headless \
  --summer-no-api --summer-no-publish --path <game> \
  --script res://tests/keep_skin_state_test.gd
```

The independent preference-policy test covers unloaded inventory, absent
ownership, one skin versus another, account/game separation, revocation and empty
publication mappings. It also exercises real mesh/material objects to verify
variant changes preserve original resources, geometry and the team overlay. Its test definition IDs are confined to the test script;
release code contains no synthetic purchase or entitlement provider.

Then qualify the real package with the canonical definitions: unpaid Buy opens
Summer, decline grants nothing, insufficient Sparks grants nothing, an existing funded balance and explicit checkout produce one platform purchase, inventory arrival
enables Equip, scene entry shows the chosen player keep while the enemy/team
markers remain recognizable, and a cold launch restores the preference only
after refreshing ownership. Verify revocation/sign-out defaults and account
switch isolation. Existing lifecycle/replay restrictions remain separate.

## Staging iOS source publication

`summer.build.json` declares this staging Game as standalone iOS with entry
`res://scenes/menu.tscn` and the `Summer iOS embedded` export preset. The existing
Android preset remains available. Both presets exclude tests. The iOS preset
explicitly includes the trusted catalog mapping and `override.cfg`; the latter
retains the earlier qualified compatibility renderer and two-worker profile.
Engine/SDK versions are omitted intentionally: Platform resolves them from its
active operator BuildPolicy at source seal. This is not proof that the admitted
exporter supports the required SDK classes; verify the immutable preview's
producer identity and export diagnostics before approval.

After source review and catalog binding, use the normal Platform helper with
`--preview-only` to prepare the immutable Build for review. Its default without
that option approves the Build automatically. Publish the approved Build through
the existing build-publication command, then select it in a coordinated Release
draft; the legacy direct authority Release command rejects standalone Builds.
Preserve the release's intended other-platform members. Reacquire the activated
iOS release through the normal authenticated player endpoint and verify its new
Build/package identity before native acceptance. Earlier local PCK hashes are
not evidence for this source.

`tests/card_loadout_test.gd` exercises fresh, audio-only, malformed and valid
on-disk profiles through the production loader. Run it with the same isolated
test directory as the skin test; require exit zero, its PASS receipt and no
ConfigFile or script errors. A missing key with a null default can return the
fallback while still emitting an Engine error, so the PASS line alone is not
sufficient.
