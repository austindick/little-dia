# Site icons in the Recent list

## Intent
The Recent list in the New Little Window box (⌃⇧⌘N, *Show recent*) shows a title, an address and an age per row. Site
icons make rows recognisable at a glance, the way a browser's history does.

## Goals, non-goals, anti-goals
- **Goals:** every row shows its site's icon. That includes pages already in the list before this change.
- **Non-goals:** icons anywhere else, such as little windows or the menu.
- **Anti-goals:** asking any third party for icons (for example, Google's favicon service), or making network requests for
  them at all. The list is private browsing history.

## Constraints
- **Where icons can come from:** only the Dia extension can read Dia's icons. The app can't.
- **Extension updates:** a new extension permission means an extension update. Dia reloads the extension itself, and
  grants permissions to unpacked extensions without asking.
- **Storage:** the list stays on this Mac, and *Clear Recent Pages* clears everything that belongs to it.

## Approaches
1. **Dia's own icon store, read by the extension through the `favicon` permission (chosen).** The extension asks for
   `chrome-extension://<id>/_favicon/?pageUrl=…&size=32`. This needs no network, and works for any page Dia has visited,
   so older rows get icons too. Unverified until tested: whether Dia allows it.
2. **The extension downloads `tab.favIconUrl`.** This is the fallback if Dia blocks approach 1. The download is usually
   served from Dia's cache but can hit the network, and it only works for pages that are open, so older rows get no
   icon.
3. **A web favicon service.** Rejected: it sends browsing history to a third party.

The owner approved approach 1, with approach 2 as the fallback.

## Design (approved)
- **Fetching:** when the list opens, the app asks the extension for icons of the rows that don't have one yet. The
  extension answers with PNG data. This also fills in pages already in the list.
- **Storage:** icons are cached on this Mac, one per site (host), and *Clear Recent Pages* deletes them.
- **Row:** a 16pt icon with slightly rounded corners sits left of the title. The title and address shift right.
- **Missing icon:** a grey globe in the same spot, so rows stay aligned.

## Left to the builder
- The message names and shapes.
- Which connection (profile) to ask, and what to do with several.
- The cache location and format.
- How quickly an icon appears in a list that's already open.
