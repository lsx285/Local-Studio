# Local Studio

A native Swift 6 iPhone frontend for future local chat, image generation, and editing models. Model integration is not connected yet.

The interface includes Liquid Glass controls, custom vector icons, photo attachments, an expanding composer, native text selection, and an animated artwork preview. The composer uses the same native text input across compact and fullscreen layouts. Regular conversations are saved on the iPhone; temporary conversations stay in memory.

Text responses and artwork generation are currently simulated. The bundled artwork and animation geometry are runtime resources used by the preview. No image is actually generated or edited.

## Build and download

Compilation happens in [GitHub Actions](../../actions). Push to main, open a pull request, or dispatch the workflow. It builds an unsigned iOS device app and uploads **LocalStudio.ipa** directly, without a ZIP wrapper. Installation requires signing through your chosen installation tool.

The build uses Xcode 27.2, the iOS 27.2 SDK, and Swift 6, targeting iOS 27.0 or newer. The workflow has no simulator, screenshot, or testing steps. Main-branch runs also delete all older repository workflow runs and their associated artifacts, retaining the current run.

Open LocalStudio.xcodeproj to browse the project. App contains the entry point and icons, Chat manages conversation state and storage, and Composer, Conversation, and Generation contain the interface. Resources holds the assets used by the app. No package manager or project generator is required.
