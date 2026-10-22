# Timeit design system

## Direction

A native macOS time tracker for independent professionals, used many times a day. Adjectives: precise, calm, fast. The identity comes from macOS itself, used well, rather than from custom decoration: the app should feel like it shipped next to Calendar and Reminders.

Sources: Apple's [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos) (sidebars, toolbars, color), Gruber's ["Mac-assed Mac apps"](https://daringfireball.net/2020/11/sketch_mac_app_mac_apps) (conventions, familiarity, craft), and Evil Martians' [macOS look](https://evilmartians.com/chronicles/how-to-make-absolutely-any-app-look-like-a-macos-app) (hover and selection rules). Raycast inspires the command palette only.

## Rules

1. **System components before custom ones.** `NavigationSplitView` with a `.sidebar` list, the window toolbar, `Table`, `Form`, `ContentUnavailableView`, `Picker`, `ControlGroup`, push buttons. A custom view needs a reason a system one cannot meet (the calendar grid, the charts, the palette).
2. **The window is the frame.** The screen name is the window title (`navigationTitle`), the period is its subtitle. Period navigation lives in the toolbar like Calendar: a Semaine/Mois segmented control, then ‹ Aujourd'hui ›. No page titles or marketing headlines in the content.
3. **One accent, the native way.** `AccentColor` in the asset catalog, declared with `NSAccentColorName`, so sidebar icons, selection, focus rings and prominent buttons share it, and a user who picks another system accent sees theirs. In code, `Theme.accent` is `Color.accentColor`; never a hard-coded brand color.
4. **System text styles.** `.largeTitle` for metric values, `.title` for the running timer, `.headline` for card titles, `.body`, `.subheadline` for secondary lines, `.caption` for axes and the calendar. No fixed point sizes, no rounded design, no uppercase tracked labels. Durations and amounts use monospaced digits.
5. **Buttons are buttons.** Push buttons for actions (`.borderedProminent` for the one primary action of a context), toolbar buttons with symbols and help tags, menus for secondary actions. No round floating action buttons, no colored text links as buttons.
6. **Lists do not hover.** Rows highlight only when selected or running; actions are in the context menu, double-click opens the editor. Menu-like rows (the menu-bar panel) highlight under the pointer.

## Color

System backgrounds and labels everywhere. The accent marks selection and the primary action. Green (`Theme.positive`) marks estimated net income. Project colors (coral, blue, green, purple, gold, each with a dark sibling) appear as small dots, chart segments and calendar fills, always next to the project name.

## Layout

- **Sidebar**: screens, then projects with their color dot and weekly time (click filters, context menu edits or starts). Sync status sits in a footnote at the bottom, never an action.
- **Toolbar**: on every screen, the running timer (project, elapsed time, Stop), the project filter when set, "Quitter l'exemple" in the example workspace, the palette and Add. Each screen adds its own items: period controls (overview, calendar, reports), Actifs/Archives and New project (projects), Export (reports).
- **Overview**: the composer (description field, project popup, Démarrer), the metrics strip with goal progress, the weekly chart beside the breakdown, sessions grouped by day.
- **Calendar**: full bleed like Calendar, day totals in the header, tinted events, a thin "now" line. Dragging across empty time draws a session with a dashed outline snapped to quarter hours, then opens the session editor on those times; dragging an event shows its landing spot the same way.
- **Projects and reports**: native tables with numeric columns aligned to the trailing edge.

## Glass (Glass.swift)

Liquid Glass comes from the system chrome (sidebar, toolbar). The app adds it in two places only, through `glass(_:tint:radius:)`, with an opaque fallback under Reduce Transparency:

- `selection`: the running timer card (`liveLens`) and the palette's highlighted command, tinted with the project color.
- `panel`: the command palette, which clips its results rather than its glass, carries `panelShadow()` and a `lightRing` whose band of light crosses it once when it opens.

Content, cards, tables, rows and buttons are never glass.

## Motion and performance

Motion only explains a state change: the composer switching between idle and running (`shellAnimation`, spring 0.28 s, none with Reduce Motion) and the palette fade. Nothing loops: a repeating effect forces the whole glass window to recomposite every frame (about 100 % CPU while a timer ran, 0.6 % without). `runningTimerStaysCheapToRender` guards this with a 10 % ceiling. The timer ticks through `TimelineView` once per second; finished rows render static text.

## Accessibility

Light and dark through semantic colors. Color always sits next to text. Icon-only buttons have labels and help tags. Calendar drags have form alternatives. System controls bring keyboard focus and VoiceOver behavior.
