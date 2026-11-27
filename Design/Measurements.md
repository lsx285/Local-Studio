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

Intentional adaptations from the request: trailing temporary/new-chat controls, matching the screenshots; omitted Chat/Work selector, unrelated circular control, and composer microphone/waveform; Local Studio placeholder. The memory-off product status is replaced by a temporary-chat status only when temporary mode is enabled. The native inline Photos grid sits in a 406 × 542 pt rounded panel with floating back and All Photos/Add controls. Photo content belongs to the system picker and varies by the user's library and iOS version.

Pixel identity across different iPhones and system material versions is not guaranteed. The checked-in simulator tests produce review captures for comparing measured spacing and behavior.
