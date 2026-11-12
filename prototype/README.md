# Prototypes

Clickable HTML versions of the app. Open `index.html` in a browser; each page is a single file with no build step.

- **`app.html`** tracks the app as it's built. When the SwiftUI screens change, change this to match and update the "as of" commit on its card in `index.html`.
- **`ideas/`** holds one file per design idea. Start from a copy of `app.html`, change only the idea, say what changed in the comment at the top of its `<style>`, and add a card for it under Ideas in `index.html`. An idea that ships moves into the app and into `app.html`; the idea file can then go.
