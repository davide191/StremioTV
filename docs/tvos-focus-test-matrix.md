# tvOS focus — manual test matrix (Siri Remote)

Invariant under test: **every pushed screen always has a focusable control in
its own content**, so focus can never fall back to (and stay in) the tab bar.

Run each row twice: once with **clicks** (D-pad ring) and once with **swipes**
(touch surface). "Tab bar focused" = a tab title (Accueil / Bibliothèque /
Recherche / Réglages) is highlighted. That must only happen when you
deliberately press ▲ from the top row of a screen.

Setups:
- **Guest**: "Continuer sans compte". Cinemeta only, so **every stream list is
  empty** (case G).
- **Debrid account**: account with a debrid stream add-on (case H, playable).
- **Torrent-only account**: Torrentio without debrid (all streams non-playable).

| # | Flow | Steps | Expected |
|---|------|-------|----------|
| A | Home → detail | Home, ▼ to hero or a poster, select | Focus on **Voir les sources / Reprendre** (movie) or **Ajouter** (series). ◀▶▲▼ move inside the page. ▲ from the top row reaches the tab bar, ▼ comes back. |
| B | Search → detail | Search tab, type a title, ▼ to a result, select | Same as A. Menu returns to the same result card. |
| C | Catalog → detail | Home, ▶ to a row's **Tout voir**, select, wait, select a poster | Grid shows **Annuler** while loading, then posters (first poster focused). Detail as A. Menu returns to the same poster. |
| C2 | Empty/failed catalog | Airplane-mode the router (or use an add-on with an empty catalog), open Tout voir | **Réessayer** is focused. Never the tab bar. Menu pops. |
| D | Series → episode → streams | Open a series, ▼ to an episode, select | Streams screen: **Annuler** focused while loading, then the **first playable** stream. Menu returns to **the same episode row**, not the top of the page. |
| E | Tab bar in and out | On any detail, ▲ until the tab bar is focused, then ▼ | Focus returns into the page (top row). Repeat on Home and the grid. |
| F | Streams loading | Debrid account, select Voir les sources | **Annuler** is focused immediately. Selecting it pops back to the detail. Menu also pops. |
| G | Zero streams | Guest, any movie, Voir les sources | After loading, **Réessayer** is focused. Select it: Annuler, then Réessayer again. Menu pops to the detail with **Voir les sources** focused. |
| G2 | Torrent-only | Torrent-only account, any title | Rows are dimmed but **focusable and scrollable** to the bottom. Clicking one does nothing. Menu pops. |
| H | Populated streams | Debrid account | First **playable** stream focused, even if torrents are listed above it. In a mixed list, ▲▼ skip the (disabled) torrent rows. |
| I | Repeated push/pop | Home → detail → Menu → another poster → detail → Menu, ×5 | Each Menu lands on the poster you opened. The Home rows never blank out or reload. |
| J | Player → back | From H, play, Menu to stop | Back on the stream list, with **the stream you played** focused. The list is not reloaded. Menu → detail (same episode row for a series). |
| J2 | Next episode | Series, play, ▼ (next episode) inside the player, then Menu | Back on the stream list, focus inside the page. Menu → detail with focus inside the page. |
| K | Tab switch mid-load | Open streams and immediately ▲ to the tab bar, switch tab, come back | The stream list loads normally (an interrupted search is not reported as "no streams"). |

Automated coverage (`.github/workflows/tvos-ci.yml`, Apple TV simulator, whole
suite run 3× per CI run): `UITests/FocusNavigationUITests.swift` covers A, C, D,
E, G, G2, H, I and J, using a local mock stream add-on for the populated and
torrent-only cases. `Tests/FocusLogicTests.swift` covers the phase and
focusability rules.
