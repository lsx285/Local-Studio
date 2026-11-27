# Local Studio

A native Swift 6 iPhone frontend for future LLM, image generation, and editing models running on your PC. No network requests, server, model integration, or third-party app dependencies yet.

The interface follows measured 430 × 932 pt references: black canvas, native Liquid Glass chrome, deep-blue user bubbles, an expanding composer, ordered photo attachments, and a blue dot-field generation animation. The temporary/new-chat controls sit at the **top right**, matching the screenshots. The Chat/Work selector, unrelated navigation control, microphone, and waveform button are omitted.

Normal conversations stay on the iPhone using an atomically written, file-protected archive. Temporary conversations stay in memory and disappear after process termination. New chat deletes the current conversation. Long-press a prompt to copy, edit, select, or share it. The plus opens Apple's inline Photos grid in a rounded gallery panel, with up to eight ordered photos and floating back/confirmation controls. All Photos opens the full system browser. The overflow menu reserves space for future settings.

**Frontend preview:** text replies and the 22-second generation sequence are simulated. Image requests show a bundled duck fixture cropped from the supplied reference. No image is actually generated or edited. This fixture and the app's original cursive-L vector icon are the only artwork bundled; personal screenshots and recordings are not published.

## Build and download

All compilation and simulator testing happen in [GitHub Actions](../../actions). Push to `main`, open a pull request, or run the workflow manually.

- Runner: `xcode-27` (Apple silicon); stable Xcode **27.2**, iOS **27.2 SDK**, Swift **6** language mode; minimum iOS 27.0.
- Checkout **7.0.1** and upload-artifact **7.0.2**, pinned to their release commits.
- Download **LocalStudio.ipa** directly from the run's artifact list. `archive: false` prevents a ZIP wrapper. The only uploaded artifact is the IPA.
- The IPA contains an unsigned `Payload/LocalStudio.app`; installation on an iPhone requires signing through your chosen installation tool.
- Simulator UI tests exercise sending, editing, new chat, multiline composition, cancellation, temporary mode, and the native photo picker. Review JPEGs are encoded in the final workflow step's log, without extra artifact archives.

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
