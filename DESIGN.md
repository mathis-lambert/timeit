# Timeit design system

## Direction

A native macOS time tracker for independent professionals, used many times a day. Adjectives: precise, calm, fast. The frame is macOS itself (window, sidebar, toolbar, Settings, menus) so the app feels at home next to Calendar; the content is a small custom component kit in the spirit of [shadcn/ui](https://ui.shadcn.com): crisp borders, a neutral ink primary, quiet states, one radius family.

Sources: Apple's [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos) (sidebars, toolbars, color), Gruber's ["Mac-assed Mac apps"](https://daringfireball.net/2020/11/sketch_mac_app_mac_apps) (conventions, familiarity, craft), and Evil Martians' [macOS look](https://evilmartians.com/chronicles/how-to-make-absolutely-any-app-look-like-a-macos-app) (hover and selection rules). Raycast inspires the command palette only.

## Rules

1. **Native frame, custom content.** `NavigationSplitView` with a `.sidebar` list, the window toolbar, menus and the Settings form stay native. Inside the content, every control comes from `Components.swift`, never a one-off style.
2. **The window is the frame.** The screen name is the window title (`navigationTitle`), the period is its subtitle. Period navigation lives in the toolbar like Calendar: a Semaine/Mois segmented control, then ‹ Aujourd'hui ›. No page titles or marketing headlines in the content.
3. **One accent, the native way.** `AccentColor` in the asset catalog, declared with `NSAccentColorName`, so sidebar icons, selection, focus rings and prominent buttons share it, and a user who picks another system accent sees theirs. In code, `Theme.accent` is `Color.accentColor`; never a hard-coded brand color.
4. **System text styles.** `.largeTitle` for metric values, `.title` for the running timer, `.headline` for card titles, `.body`, `.subheadline` for secondary lines, `.caption` for axes and the calendar. No fixed point sizes, no rounded design, no uppercase tracked labels. Durations and amounts use monospaced digits.
5. **Buttons are buttons.** One `primary` (ink) per context, `outline` or `secondary` beside it, `ghost` and `IconButton` for row actions, `destructiveGhost` for Delete in a dialog. No round floating action buttons, no colored text links.
6. **Tables are calm.** A header with a rule, rows with a rule between them, a faint fill under the pointer, the running row washed with its project color; double-click edits, the context menu holds the rest.

## Components (Components.swift)

| Piece | After shadcn | Here |
| --- | --- | --- |
| Button | variants default, secondary, outline, ghost, destructive | `TimeitButtonStyle(kind:large:)`, 30 / 34 pt high, radius 7, hover and press overlays, 45 % when disabled |
| Input | 1 px border, shadow-xs, 3 px focus ring | `timeitField()` and `inputFrame()`: surface, `Control.border`, accent border and ring while focused |
| Combobox | popover with a search field and a command list | `Combobox` (`Combobox.swift`): ↑↓, Return, Escape, sections, a check on the current value, optional "Créer « … »"; used by `ProjectMenu`, the client field and `CurrencyPicker` (currencies in circulation, searchable by code or name) |
| Date picker | button opening a calendar popover | `DateTimeField` (`DateFields.swift`): `MonthCalendar` (Monday first, ink selection, accent ring on today, no future days) beside `TimeField`, which reads "9", "930", "9h30", "9:30" and steps by a quarter hour with ↑↓ |
| Tabs | muted track, raised active tab | `SegmentedControl`, the raised tab slides with the shell spring |
| Switch | label and description beside a switch | `SwitchRow` |
| Badge | small rounded label | `Badge` for "En cours", "Non facturable", "En attente", counts |
| Card | border, rounded-xl, faint shadow | `card()`: `Control.surface`, radius 12, `Control.border`, shadow at 4 % |
| Table | header rule, row rules, muted hover | `ColumnHeader`, `ListRow`, `ShareBar` |
| Kbd | muted key | `KeyCap`, with an on-ink variant inside the primary button |
| Empty | icon tile, title, description, action | `EmptyState` |

Tokens live in `Control`: `border` (#E4E4E7 / #3A3A3F), `muted`, `surface`, `ink` and `onInk`, `hover`, `pressed`.

## Color

System backgrounds and labels for the frame; `Control` tokens for the content. The primary button is ink, not accent. The accent marks selection, focus, the running timer and today. Green (`Theme.positive`) marks estimated net income. Project colors (coral, blue, green, purple, gold, each with a dark sibling) appear as small dots, chart segments and calendar fills, always next to the project name.

## Layout

- **Sidebar**: screens, then projects with their color dot and weekly time (click filters, context menu edits or starts). Sync status sits in a footnote at the bottom, never an action.
- **Toolbar**: on every screen, the running timer (project, elapsed time, Stop), the project filter when set, "Quitter l'exemple" in the example workspace, the palette and Add. Each screen adds its own items: period controls (overview, calendar, reports), Actifs/Archives and New project (projects), Export (reports).
- **Overview**: the composer (description field, project popup, Démarrer), the metrics strip with goal progress, the weekly chart beside the breakdown, sessions grouped by day.
- **Calendar**: full bleed like Calendar, day totals in the header, tinted events, a thin "now" line. Dragging across empty time draws a session with a dashed outline snapped to quarter hours, then opens the session editor on those times; dragging an event shows its landing spot the same way.
- **Projects**: one card per client holding a table (project, rate, this week, total, row actions).
- **Reports**: the metrics strip, then a card with a table of projects, share bars and amounts.
- **Editors**: dialog layout with labels above fields, comboboxes for project, client and currency, date and time fields, switch rows and the dialog buttons at the bottom right.

## Glass (Glass.swift)

Liquid Glass comes from the system chrome (sidebar, toolbar). The app adds it in two places only, through `glass(_:tint:radius:)`, with an opaque fallback under Reduce Transparency:

- `selection`: the running timer card (`liveLens`) and the palette's highlighted command, tinted with the project color.
- `panel`: the command palette, which clips its results rather than its glass, carries `panelShadow()` and a `lightRing` whose band of light crosses it once when it opens.

Content, cards, tables, rows and buttons are never glass.

## Motion and performance

Motion only explains a state change: the composer switching between idle and running (`shellAnimation`, spring 0.28 s, none with Reduce Motion) and the palette fade. Nothing loops: a repeating effect forces the whole glass window to recomposite every frame (about 100 % CPU while a timer ran, 0.6 % without). `runningTimerStaysCheapToRender` guards this with a 10 % ceiling. The timer ticks through `TimelineView` once per second; finished rows render static text.

## Accessibility

Light and dark through semantic colors. Color always sits next to text. Icon-only buttons have labels and help tags. Calendar drags have form alternatives. System controls bring keyboard focus and VoiceOver behavior.

## Settings availability and update channels

Keep Settings native, precise and calm: system text styles, grouped forms, semantic labels and no extra decorative surfaces. Cloud shows “Pas encore disponible” with local-backup guidance; it offers no connection action. Updates has one native channel picker, a short explanation and the same check action as the app menu. Stable, Beta and Nightly share one app and one workspace. Explain that returning to Stable waits for a newer stable version. Disable channel changes during an update session. Unavailable local builds explain why checking is disabled.

2026-11-01 review: existing native hierarchy and typography retained; selected, disabled and unavailable states have explicit text, no color-only meanings or added animation. Live-window captures cover Stable and Nightly settings.

## Missing exchange rates

Gross and net metrics explicitly say “Total incomplet” when sessions lack rates;
a completely missing amount is a dash, not zero. A shared notice below the metrics
explains the excluded session count and offers an outline “Réessayer” button.
During retrieval the button says “Récupération des taux…” and is disabled.
No spinner or looping animation; existing system text styles and card tokens apply.
