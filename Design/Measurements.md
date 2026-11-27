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
