# Local Studio

A native Swift 6 iPhone frontend for future LLM, image generation, and editing models running on your PC. No network requests, server, model integration, or third-party app dependencies yet.

The interface follows measured 430 × 932 pt references: black canvas, native Liquid Glass chrome, deep-blue user bubbles, an expanding composer, ordered photo attachments, and a blue dot-field generation animation. The temporary/new-chat controls sit at the **top right**, matching the screenshots. The Chat/Work selector, unrelated navigation control, microphone, and waveform button are omitted.

Normal conversations stay on the iPhone using an atomically written, file-protected archive. Temporary conversations stay in memory and disappear after process termination; the temporary-mode button has no extra banner. New chat deletes the current conversation. Long-press a prompt to copy, edit, select, or share it. Select text highlights the entire text in place with native selection handles. Long-press a sent attachment for Copy only; assistant artwork offers Copy, Save to photos, and Share. Saving requests add-only Photos access when chosen. The plus opens Apple's inline Photos grid in a rounded gallery panel, with up to eight ordered photos and floating back/confirmation controls. All Photos opens the full system browser. The overflow menu reserves space for future settings.

The composer keeps one native text editor while changing layouts, preserving focus, cursor position, and text. It expands to 406 pt on the 430 pt reference screen with the keyboard open and sits 12 pt above it. Swipe up on the composer to show the keyboard and down to dismiss it. Short text and its placeholder do not scroll; long drafts scroll after seven 24 pt lines. Longer drafts expose the corner expand control; expanding fills the area above the keyboard, and collapsing restores the compact layout with the same draft and cursor. The scroll-to-bottom control floats above the composer without resizing the conversation. Scroll distance and visibility of the actual final row hide it when you manually reach the bottom. Incoming results do not pull you away from older messages.

**Frontend preview:** text replies and the 17.55-second generation sequence are simulated. Image requests show a bundled duck fixture cropped from the supplied reference. No image is actually generated or edited. The generation field renders 660 vector dots using 883 measured frames of radii and colors sampled at 59 fps, plus per-frame label luminance profiles. Personal screenshots, video frames, and audio are not published.

## Build and download

All compilation happens in [GitHub Actions](../../actions). Push to `main`, open a pull request, or run the workflow manually. Visual review is manual; The workflow builds the IPA without simulator or UI tests.

- Runner: `xcode-27` (Apple silicon); stable Xcode **27.2**, iOS **27.2 SDK**, Swift **6** language mode; minimum iOS 27.0.
- Checkout **7.0.1** and upload-artifact **7.0.2**, pinned to their release commits.
- Download **LocalStudio.ipa** directly from the run's artifact list. `archive: false` prevents a ZIP wrapper. The only uploaded artifact is the IPA.
- The IPA contains an unsigned `Payload/LocalStudio.app`; installation on an iPhone requires signing through your chosen installation tool.
- The workflow builds and validates the unsigned device app and uploads `LocalStudio.ipa` directly. Simulator/UI tests and screenshot exports are disabled.

Open `LocalStudio.xcodeproj` to browse the project. Build settings and shared scheme are checked in; no project generator, package manager, or signing secret is required.

## Source layout

`App` holds the entry point and measured colors. `Chat` owns session state and persistence. `Composer`, `Conversation`, and `Generation` contain the small native views. `Resources/AppIcon.icon` is a layered Icon Composer document with an original cursive L SVG over a blue gradient. `LocalStudioUITests` owns interaction and screenshot coverage. No frontend code was delegated to helper agents.

## Design and platform references

- [Measured reference specification](Design/Measurements.md)
- [Apple SDK requirements](https://developer.apple.com/xcode/system-requirements)
- [Applying Liquid Glass](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- [Icon Composer](https://developer.apple.com/icon-composer/)
- [Runner software](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)
- [Direct artifact uploads](https://github.com/actions/upload-artifact#upload-an-individual-file-unzipped)


App-owned controls use custom SVG assets sized against the supplied iPhone references, including separate context-menu and response-row variants. The composer plus has an 18 pt glyph inside its 32 pt control. Fullscreen sizing comes from the outer viewport; text measurement uses a separate cached TextKit layout, without changing the active UITextView during SwiftUI measurement.
