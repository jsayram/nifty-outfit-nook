# 0010: The stylist on the phone (Phase 28)

Status: built 22 October 2026. Questions for Jose at the end.

## The device question

Lily's phone is an iPhone 12 (A14). Apple's on-device model, the Foundation Models framework, only runs where Apple Intelligence does. Apple's article "Generating content and performing tasks with Foundation Models" says model availability "depends on whether the device and region supports Apple Intelligence" and tells apps to check `SystemLanguageModel.default.availability` and plan a fallback. On an ineligible phone that check returns `.unavailable(.deviceNotEligible)` ("The device does not support Apple Intelligence"). Apple Intelligence starts at the iPhone 15 Pro. Apple's newer `PrivateCloudComputeLanguageModel` has the same `deviceNotEligible` reason, so it doesn't help an iPhone 12 either.

So on Lily's phone the on-device model never runs. Style Me answers with the cloud stylist (27a) or with Quick ideas, the rule-based stylist built here.

## What Style Me does now

`StylistRouter` (Models) picks who answers each request:

| Cloud set up | Her OK | Connection | Answers | Label |
|---|---|---|---|---|
| no | any | any | Quick ideas | "Made on this iPhone from your own pieces." |
| yes | no | any | Quick ideas | ...plus "For the stylist's ideas, Style Me needs your OK." and Review |
| yes | yes | offline | Quick ideas | "You're offline, so these were made on this iPhone from your own pieces." |
| yes | yes | online or unknown | the cloud stylist, as a 27c job | none |

Limits are only known from the server's answer, so a cloud job that's refused (paused by 24b's switch, her allowance used up, too many at once, signed out) or fails gives way to Quick ideas with the reason: the limit's own words (`CloudLimitText`), or "The stylist didn't finish, so these were made on this iPhone. Nothing was charged." with Ask the stylist. Her Cancel and a changed request don't fall back. Nothing on the phone path is sent or counted. A newer iPhone with the model ready and an on-device stylist installed would get the on-device lane instead of Quick ideas; none is installed yet (below), so that lane is tested but unused.

Looks made on the phone carry `StyleResult.madeBy` (`.rules` or `.onDevice`), and Your looks shows **Quick ideas (on your phone)** above them, with the reason. "Uses 1 styling" under Try a different outfit becomes "Made on this iPhone, free" when the next request would stay on the phone. Try it on and Ask stylist are dimmed while offline, as for the offline banner.

Without a backend (today's TestFlight builds), her own closet uses Quick ideas in place of Stage A's stand-in stylist. The debug sample closet keeps the stand-in, so Stage A's snapshots and UI tests don't move.

## Quick ideas

`QuickIdeasStylist` (Models) returns the same typed result as the cloud stylist, checked by `ResultCheck`, with a why line per version from templates in Features (`QuickIdeasText`). Deterministic, and only plain matching on stored facts, as the public repo requires (SECURITY_STANDARD.md §3; amendment "Public repo note"): no fit or proportion rules, nothing about her body, no prompts.

- **Only her pieces:** it chooses from `StylingContext.eligibleGarments`, which the app builds on the phone (the source, in her closet, not away or in the wash).
- **Weather:** a firm rule. A top, bottom, dress or layer that doesn't suit today's band (`TemperatureBand.suitableWarmth`) is used only when she owns nothing of that kind that does. Cold, cool or wet days add her best suitable layer; hot days never do. Sandals lose out on wet or cold days, boots on hot ones.
- **Formality:** each occasion has a usual dressiness (office smart; casual, brunch and concert casual; date night and event dressy; Other none). A piece that matches scores up, two steps off scores down. Occasion tags count too.
- **Colour:** neutrals (black, white, cream, beige, tan, brown, gray, navy, denim) go with anything; neutrals plus one colour family scores best; two colours or two prints score down. Her colour wish counts, and a required one limits the outfits to those that bring it in when any can.
- **No repeats, and variety:** Simple skips outfits already shown for this request (Try a different outfit) and outfits worn inside her repeat window while another is possible, and says "You wore this..." when it can't. A piece worn in the last three days gives way to an equal one.
- **Versions:** Dressed up swaps in one dressier piece of hers; Something new adds one idea (a cardigan, a bag or a belt in a neutral) or, with Only mine or from a suitcase, another of her pieces.
- **Speed:** it tries every top and bottom with her six best shoes; a 150-piece closet stays inside the test's half-second limit on the simulator.

## Foundation Models: later work

Built: the availability check (`SystemModelCheck` in Services, set by the app) and the router's on-device lane. Not built: a stylist on the model. Three reasons to wait:

1. **The prompt would be public.** An on-device stylist needs its instructions in the app, and this repo is public; SECURITY_STANDARD.md keeps prompts and styling rules in the private backend. That needs Jose's written decision.
2. **It wouldn't reach Lily.** Her iPhone 12 can't run it.
3. **Context and testing.** The model's context is 4,096 tokens for instructions, prompt and answer together; 27a measured a 40-piece closet at about 2,560 tokens of input. A large closet would need trimming. Its answers also vary, so CI could only test it with a fake.

If Jose wants it: a `FoundationModelsStylist` behind the same `Stylist` protocol, using guided generation (`@Generable`) into the 27a answer schema with piece aliases, validated by `ResultCheck` like the cloud's answer, installed as `NookServices.onDeviceStylist` only when the check says `.available`. The router and label already handle it.

## Tests

- `QuickIdeasTests` (Models): 400 generated closets and requests per property: every result passes `ResultCheck`, uses only pieces from the context, has no piece twice and no two versions alike, has why lines and comes out the same twice; every warmth-sensitive piece suits the band when she owns one that does, with a layer on cold, cool or wet days and none on hot ones; no repeat of a shown or recent outfit while another exists, and the note when it must. Worked examples for formality, colour, cold rain, heat, variety, the why facts, insufficient, and the 150-piece timing.
- `StylistRouterTests` (Models): the routing table, the fallback after every cloud error, and after every job failure.
- `SystemModelCheckTests` (Services): each availability maps to its status, and the real check answers on the simulator.
- `YourLooksCloudTests` (Features): without consent, Quick ideas then Allow asks the cloud; offline and without consent, Quick ideas from her pieces that suit the rainy day, nothing sent; limits and failures give way to Quick ideas, and Ask the stylist goes back.
- `QuickIdeasLabelSnapshotTests` (Features): each reason, the on-device title, dark, AX5, and Your looks with Quick ideas.
- `CloudStylistTests` (UI): updated for Quick ideas before consent and after a failure, plus `testOfflineWithoutConsentStillGivesQuickIdeas`, the checkpoint.

## Questions for Jose

1. Before consent, Style Me now shows Quick ideas with Review, where 27a showed only "Style Me needs your OK". OK?
2. The colour and formality matching above is generic. Is that fine in the public repo, or should anything move to the backend?
3. Build the Foundation Models stylist for newer iPhones (which means an on-device prompt in this public repo), or leave it?
