# Reference measurements

Source PNGs: 1290 × 2796 pixels. Interpreted as 430 × 932 logical points at 3×. Coordinates below are measured from the full image, including system safe areas; system status bar and home indicator remain native.

| Element | Source pixels | Logical points |
|---|---|---|
| Short composer bounds | x102–1188, y2550–2694 | x34–396, y850–898; 362 × 48 |
| Multiline composer bounds | x36–1254, y2346–2694 | x12–418, y782–898; 406 × 116 |
| Expanded composer radius | approximately 84 | 28 |
| Send circle diameter | 96 | 32 |
| Top circular control | 132 | 44 |
| Top capsule bounds | x918–1230, y177–309 | 104 × 44 |
| Attachment thumbnails | approximately 360 × 360 | 120 × 120 |
| Conversation side margins | 48 | 16 |
| User text size | approximately 51 | 17 pt system |
| User bubble insets | approximately 48 horizontal, 33 vertical | 16 horizontal, 11 vertical |
| Artwork corner radius | approximately 48 | 16 |

Sampled dominant flat colors: background `#000000`; glass interior `#202020`/`#1F1F1F`; user bubble `#02055D`; prompt text approximately `#DEE1FF`; action blue `#3360F3`. Glass is Apple's live `.regular` material, with `.clear` on artwork sharing buttons. Its reflected colors vary with content and the OS, so its output is not a fixed fill.

Recording: 720 × 1562, 25 seconds. Prompt moves upward into the conversation in roughly 0.4 seconds. The generation field is **300 × 400 pt**, with **22 columns × 30 rows**, about 13.318 pt between centers. The 17 pt stage label sits 8 pt above the field. Its lower-right progress pill uses 15 pt text, 12/8 pt insets, and 20 pt margins. Labels: Sketching it out → Making the first draft → Setting the scene → Polishing details → Finishing up.

The first 2.8 seconds show a single blue dot. The simulated generation lasts 24 seconds. `GenerationMotion.dots` stores 306 samples at 15 Hz, each with the measured radius (1/64 pt) and sRGB color of 660 dots. Canvas interpolates at 60 fps, matching the recording's approximately 59 fps cadence. This draws at most 39,600 dots per second, below the original 40 × 40/30 fps implementation's 48,000. The trace is 807,856 bytes and contains no video frames, photos, text, or audio. Reduce Motion holds the field still while the stage and progress continue. `Scripts/measure_generation.py` reproduces the trace from the original local recording; it is offline design tooling and adds no app dependencies.

The send arrow is an original vector path measured from the white glyph at x1096–1134/y2601–2644 in the short composer reference. It uses a 2.2 pt rounded stroke in a 32 pt circle. Both the attachment scroll viewport and the full composer have explicit masks so thumbnails cannot escape the glass shape while scrolling.

Keyboard references `IMG_0460.png` and `IMG_0461.png` are both 1290 × 2796. ChatGPT's focused composer spans x36–1254/y1575–1719, or 406 × 48 pt with 12 pt side margins. The keyboard begins at y1755, leaving 36 px = **12 pt** between it and the composer. Local Studio's former focused composer spanned x102–1188/y1611–1755: 362 × 48 pt with 34 pt margins and no keyboard gap. A persistent UITextView now handles both layouts without replacing the responder. Its placeholder is a fixed label.

The longer composer reference spans x36–1254/y1011–1719: **406 × 236 pt**. Text uses 24 pt line fragments; seven visible lines (168 pt), a 16 pt top inset, and a 52 pt lower control region reproduce that height. The expand icon is centered around x394/y365 pt. It appears from four lines onward and reserves space in the first text line. In full-screen mode the panel spans x0–1290/y177–1755: **430 × 526 pt**, with 40 pt upper corners and an opaque #1E1E1E background. The text begins 78 pt below the panel top; the collapse control has a 16 pt top/right inset. The 32 pt send circle has 24 pt right/bottom margins. The same UITextView remains attached throughout expansion/collapse.

The prompt context menu is 250 × approximately 216 pt with a 28 pt corner radius. Its timestamp is 13 pt medium gray, leading aligned with 28 pt horizontal and 12 pt top insets. Four 42 pt action rows use 24 pt icon slots, 12 pt icon/text spacing, and 17 pt labels. A custom glass presentation avoids UIKit's centered menu title. The gallery confirmation button uses regular Liquid Glass tinted with the app accent, while All Photos uses clear Liquid Glass.

The generation stage label uses a moving gray brightness sweep with a 1.5-second cycle and fades when the stage changes. Reduce Motion uses a constant gray. The scroll-down arrow's reference white pixels span x625–663/y2434–2476, approximately 13 × 14.3 pt. Its rounded vector path sits in a 36 pt glass circle, 14 pt above the composer. Visibility uses scroll distance with hysteresis and the control is an overlay, so showing it never changes the viewport height.

Intentional adaptations from the request: trailing temporary/new-chat controls, matching the screenshots; omitted Chat/Work selector, unrelated circular control, composer microphone/waveform, and temporary-mode banner; Local Studio placeholder. The native inline Photos grid sits in a 406 × 542 pt rounded panel with floating back and All Photos/Add controls. Photo content belongs to the system picker and varies by the user's library and iOS version. Text selection uses native handles inside the original bubble, with no selection sheet. Sent-image long-press menus contain only Copy; assistant images offer Copy, Save to photos, and Share, using square.on.square, square.and.arrow.down, and square.and.arrow.up.

Pixel identity across different iPhones and system material versions is not guaranteed. CI performs only the device IPA build and package validation; visual review is manual.

## November 27 rail and motion refinements

The new close-up comparison measures the white rail X at 24 × 24 px (8 × 8 pt), versus 35 × 35 px (11.7 pt) in the previous build. A 10 pt bold SF Symbol replaces the former 15 pt symbol in a 22 pt dark circle. Removing a stable-ID attachment uses a 0.30-second spring (0.86 damping), with a small scale/fade removal and adjacent thumbnails moving into place. The send arrow is invisible, untappable, and excluded from accessibility when both draft and attachment selection are empty; the stop control remains available while generating.

Single sent photos fit their natural aspect ratio within 288 × 192 pt. Multiple sent photos use 128 pt square crops with 4 pt gaps, trailing aligned: three photos span 392 pt, starting at x22 on a 430 pt screen. Four photos form two rows of two. Narrower screens shrink the tiles to fit. Sent-image long presses retain the Copy-only menu.

The conversation disables scroll clipping so content continues beneath the safe-area composer, providing a live backdrop for its regular Liquid Glass. The gallery confirmation capsule uses clear interactive glass with a saturated blue tint, avoiding the pale regular-glass treatment. Gallery downward drags track the finger and dismiss after 44 pt, or a shorter drag with sufficient projected travel. Composer keyboard gestures use a 12 pt directional pan threshold instead of requiring a fast swipe; upward scrolling in an active long editor stays native.

The 9.39-second scroll-button recording shows a scale/fade with a slight upward settling motion. The 36 pt control transitions from 55% scale and 8 pt below its resting position using a 0.28-second spring with 0.88 damping; Reduce Motion uses a short fade. The initial generation dot has a 17 pt maximum diameter and smoothly pulses between 60% and 100% over 1.1 seconds, with a stable center. Reduce Motion holds it at full size. Timing and glass appearance remain subject to manual review of the IPA.


## Replacement reference: 10:28 PM recording

All 1,049 frames of the 720 × 1562, 59 fps, 17.78-second recording were decoded for analysis. This supersedes the previous 25-second reference timeline above. The new resource stores 883 frames at 59 Hz from 1.85 seconds onward: 660 radius/sRGB tuples plus 64 horizontal luminance samples per frame. No screenshots, text rasterization, or final artwork from the new recording are bundled. The measured label luminance drives the gradient directly, preserving the recorded sweep direction and pauses rather than reversing a repeating gradient. Stage boundaries are approximately 6.45, 10.95, and 14.95 seconds. This reference finishes during “Polishing details”; it does not show “Finishing up”.

| Time in recording | Observed behavior |
|---|---|
| 0–1.85 s | Prompt settles, initial blue dot |
| 1.85–6.45 s | Sketching it out, early percentage jump then slower increments |
| 6.45–10.95 s | Making the first draft |
| 10.95–14.95 s | Setting the scene |
| 14.95–16.6 s | Polishing details, percentage reaches 92 |
| 16.6–17.05 s | Label/badge disappear; dot field contracts vertically and widens |
| 17.05–17.55 s | Image-colored particles elongate into vertical strips and join into the final image |

The reveal uses the bundled demo artwork with a moving particle/strip mask, replacing the previous stretched-dot fade followed by a separate image crossfade. Its geometry and stagger timing are fitted to the recording; visual equivalence still requires simulator/device comparison. The final artwork content remains the existing demo fixture. The focused simulator check captures nine fixed timeline phases, including contraction and strip reveal; it does not assert pixel identity. No other UI checks are selected by the workflow.

User-text long presses now trigger medium impact feedback and spring-present the enlarged bubble/menu. The checked temporary-chat icon keeps the same white broken-ring bubble and adds a rounded 2.3 pt checkmark, through (8,12), (11,15), (16,8) inside the 23 pt glyph. Temporary-mode explanatory content remains hidden as previously requested.

## Comparison against Local Studio recording and native verification

Both supplied recordings (`localstudio.mov` and `chatgpt.mov`) were decoded frame by frame at 59 Hz. Registration of the dot-phase features maps reference frame i to previous-app frame i − 35. The recordings begin at different points in the interaction, so this is a registration offset, not evidence of an internal 0.593-second delay. The previous field began approximately 8 source pixels too high relative to its label. Its brightness estimator also removed energy from dim particles by subtracting a fixed threshold before integrating area. The first-row coordinate and energy integration have been corrected.

The fitted regular-bar reveal has been replaced by `GenerationReveal.mask`: 68 frames of vector contour geometry extracted from the reference, including changing particle positions and shapes. The resource includes blue-particle colors but no reference artwork pixels. The app's artwork supplies the revealed image. The extraction tool is `Scripts/measure_reveal.py` and requires ffmpeg, NumPy, and OpenCV; these are offline design dependencies only.

Rasterizing the extracted vector shapes gives mean visibility-mask intersection-over-union **0.99096**, ranging **0.94986–0.99937** across 68 frames. This uses a 12/255 visibility threshold and excludes isolated compression specks. It measures contour geometry only and must not be described as 99% overall rendered accuracy.

[Workflow run 46073241531](https://github.com/lsx285/Local-Studio/actions/runs/46073241531) passed the unsigned device build/package checks and the focused simulator check. It exported 31 fixed-time screenshots plus a completed-image capture; reveal captures are spaced 50 ms apart. The captures were downloaded and inspected. The image begins at y674 in both the 17.65-second reveal capture and the real completed-image capture, confirming that the final handoff preserves its vertical position. Registered dot-region comparisons still show pixel differences in antialiasing, brightness, and compression; no full-animation 99–100% pixel-identity claim is made.


## Icon and fullscreen refinement

All 21 app-owned glyphs now use reference-derived custom SVG artwork. No `systemName`/`systemImage` substitutions remain in the app source. Context-menu variants use 24 pt layout slots, response-row variants 18 pt slots with 12 pt gaps, header icons 44 pt slots, and composer controls their existing 32/36 pt slots. The former plus measured 63 × 63 high-coverage pixels; the reference measures 54 × 54 pixels (18 × 18 pt). Expand/collapse, send, stop, back, and scroll-arrow references were also inspected at full source resolution. Keyboard, Photos, share-sheet and status-bar graphics remain system-owned.

The actual SVG files were rasterized locally for side-by-side review at reference scale. Their half-pixel coordinate alignment was corrected and edge coverage fitted to the screenshots. OpenAI's published Apps SDK UI icons were compared as candidates; iOS variants differed for several glyphs, so those candidates were not substituted. The accepted review criterion is visual identity at the measured sizes, as clarified by the user; no pixel-for-pixel native iOS identity is claimed.

Fullscreen sizing no longer observes geometry affected by its own composer inset. The hidden header releases its height, conversation auto-scrolling is suppressed while fullscreen is open, and the editor sizing-mode change is not animated. Crucially, `sizeThatFits` no longer changes the live text view or its exclusion paths: it uses a separate cached TextKit layout limited to seven visible lines. Only actual bounds changes update the editor's exclusion path. This removes a source-level layout invalidation cycle; the freeze fix remains subject to manual device review because UI tests are disabled.

The workflow is IPA-only again. No simulator/UI tests or workflow monitoring were performed for this refinement.

The fullscreen composer backdrop now extends through the bottom keyboard and container safe areas. Its rounded shape is applied as a background after the content clip, so the editor and send control retain their keyboard-aware layout while #1E1E1E continues behind the keyboard's rounded corners and home indicator. This also covers the formerly black lower region when the keyboard is hidden. The top corners remain rounded and continue to expose the conversation behind them.

The 11:47:59 PM recording was inspected at its 59 fps cadence. The initial keyboard appearance belongs to the separate focus tap before expansion; it is not part of fullscreen presentation. Entry slides the panel upward over approximately 0.35 seconds while retaining the active keyboard. Exit is faster, approximately 0.22 seconds. The composer now stages those phases with an offset transform; the actual layout mode changes in an animation-disabled transaction so the editor's sizing proposals do not animate. The same UITextView, selection, first responder, and keyboard are retained across expansion and collapse. Repeated taps and keyboard-swipe gestures are suppressed during the transition; cancellation is tied to the view lifetime. Reduce Motion changes layout immediately. Timing is fitted to the recording and awaits the user's device review; UI tests and workflow monitoring remain disabled.

