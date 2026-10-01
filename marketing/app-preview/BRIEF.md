# InsightRun — App Store preview, director's brief

## Film in one line
A 29 s portrait film where one real iPhone never cuts: the app's own screens carry the story while
editorial type, lifted UI cards and a 120 BPM score turn "your watch records" into "InsightRun explains".

## Deliverable
- App Store Connect app preview, iPhone 6.9": 886×1920, 30 fps, H.264 High ≤ 4.0, stereo AAC 48 kHz, 15-30 s.
- Language: en-US. Dark take from the Glint capture "EN app tour" (`cap_01m3rq3t6nbesyzfez7a9mv5z3`), light
  take from "EN light app tour" (`cap_01m3s3np091a0qttn10a98qq5k`): `--variant light` swaps footage, cuts and taps.

## Brand
- Dark: accent lime `#96FF70` (app `irPrimaryAccent` dark), AI violet `#B48DFF` (`irAIAccentSecondary`), ground
  `#050805` with deep green glows `#0E2A0B` / `#1F5A17` (the dark App Store screenshot look).
- Light: the light App Store screenshot style — mint mesh `#E9FFD9` / `#C8F7A8` / `#B8EE8E`, silver frame,
  headline `#0E1A0A`, accent `#2F8F1E`, AI violet deepened to `#7C4DDB` for contrast on a light ground.
- Type: SF Pro (heavy 800, tracking -0.035em) for headlines, SF Pro Rounded for numbers, SF Mono uppercase
  for labels — the same three voices the app uses.
- Copy reuses the App Store screenshot headlines so the preview and the screenshots read as one story.

## Motion rules
Render contract
- Everything is a pure function of `t`: no CSS transitions, no timers, no `Date.now`. `renderFrame(t)` sets
  the DOM, awaits the footage frame decode, then the frame is captured.
- Footage is the real simulator recording (demo mode, clean 09:41 status bar) decoded to a 30 fps sequence.

Look (bans)
- No centered text on a flat gradient as the idea of a shot; type is left-aligned and editorial.
- The device never hard-cuts and never tilts. Screen changes happen inside it (taps, pushes, scrolls).
- One accent at a time: lime for training, violet only for the coach chat.
- No invented UI: every card that leaves the screen is a crop of the real frame underneath.
- Easing is exponential out for entrances, exponential in for exits; only counters move linearly.
- Grain 3 %, soft vignette, nothing else on top.

Sound
- 120 BPM (beat 0.5 s, bar 2 s). Section changes land on beats, the big ones on downbeats.
- A whoosh leads into every section, a click on every tap, a soft pop on every lifted card, a thump on the logo.

Feedback loop
- Render stills at every section's key moment, score hierarchy / legibility / rhythm / brand / App Store
  compliance out of 10, fix anything under 8, re-render.

## Beat sheet (output seconds)
| Bar.beat | Time | Shot | Footage (source s) | Type |
|---|---|---|---|---|
| 1.1-1.4 | 0.0-2.0 | Cold open, words land on each beat | — | "Your watch / records." "InsightRun / explains." |
| 2.1 | 2.0-5.0 | Phone rises, readiness gauge lifts out | 0.0-3.0 @1× | 01 Readiness · "Know when to push" |
| 3.3 | 5.0-8.0 | Scroll to signals, camera pushes in | 3.0-7.8 @1.6× | 02 Signals · "Every signal, one glance" |
| 5.1 | 8.0-10.0 | Tap Workouts | 8.6-10.6 @1× | 03 Runs · "All your runs, organized" |
| 6.1 | 10.0-13.5 | Tap the interval session, verdict lifts out | 14.2-18.2 @1.14× | 04 Coach · "A coach after every run" |
| 7.4 | 13.5-16.5 | Scroll to map and heart rate | 18.7-23.4 @1.57× | 05 Analysis · "See how the run unfolded" |
| 9.2 | 16.5-21.5 | Goals → Paris 10K plan | 29.42-30.6, 33.2-36.0, 36.0-37.8 @2× | 06 Plan · "A plan that adapts to you" |
| 11.4 | 21.5-25.5 | Open the coach, question and answer lift out | 40.6-45.6 @1.25× | 07 Ask · "Ask your coach anything" |
| 13.4 | 25.5-29.0 | Phone sinks, icon and wordmark | — | "InsightRun" · "Every run, explained." |

## Mix variant (`--variant mix`, 29.5 s)
Dark until the run analysis, then a real Settings take ("EN appearance switch", `cap_01m3vdrqaz5aznmsk5gyshxdj2`,
app launched with `-DEMO_MODE -selectedTheme dark`) shows the switch, so the change of look is a feature, not an
inconsistency. The app flips instantly on the 18.0 downbeat; the film answers with a circular reveal from the finger
on "Light" (background first, then type and frame cross-fade as the circle passes), a riser and a pluck sparkle.

| Time | Shot | Footage |
|---|---|---|
| 2.0-16.5 | 01-05 as the dark cut | dark take |
| 16.5-19.0 | 06 Appearance · "Light or dark, your call": tap Appearance, tap Light, reveal | switch take 5.2-6.0, 6.67-8.37 |
| 19.0-23.0 | 07 Plan, plan header lifts out | light take 31.05-32.05, 34.4-37.4 |
| 23.0-26.5 | 08 Ask, question and answer lift out (last frame held) | light take 41.7-42.98 |
| 26.5-29.5 | End card in light | — |

## Light-first variants (`--variant mix-ld` EN, `--variant mix-fr` FR, 29.5 s)
Same cut as the mix, reversed: the light take carries 01-05, a Settings take switches Light → Dark on the 18.0
downbeat (EN `cap_01m3vpg0max67nhf3e0kxxz6qe`, FR `cap_01m3vnxfkqtbspd9c2dgjnh277`), and the dark take carries 07-08.
The circle reveals the dark ground. FR copy reuses the FR App Store screenshot headlines (tutoiement); the FR switch
take drops its status bar for one frame at 3.833 s, so the cut skips it.
