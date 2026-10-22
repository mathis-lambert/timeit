# Timeit design system

## Context and direction

Native macOS time tracker for independent professionals. Artifact type: pro desktop utility, used many times a day. Primary action: start or switch the timer without losing focus. Adjectives: precise, calm, fast, warm. Essence: **quiet working companion**.

References, transposed: Raycast for the keyboard-first palette and its restraint on frequent actions; Things and Linear for calm hierarchy; Apple's macOS 26 guidance for Liquid Glass, which belongs to the floating control layer and not to content.

## Signature move

The **timer bar**: an idle composer ("Sur quoi travaillez-vous ?" + project chip + round start button) that morphs into the running timer through `GlassEffectContainer` and `glassEffectID`. Supporting identity: the brand mark, a ring that fills with the week's progress toward the weekly goal.

## Typography

System San Francisco, a deliberate native choice, not a default: the app must feel like part of macOS. SF Rounded with monospaced digits for durations and amounts only. Scale: 10.5 (labels), 12–13.5 (body and rows), 14–15 (card and section titles), 20 (sheet titles), 26 (page titles), 28 (metric values). Body text stays 13 pt, the macOS desktop standard.

## Color

Neutral system backgrounds dominate. One accent, ember #D9482A / #F57352 (light/dark), used for the brand mark, the start button, today markers and the "now" line. Green #16855C / #4CC994 only for estimated net income. Project colors (coral, blue, green, purple, gold, each with a dark-mode sibling) appear as small dots, chart segments and calendar fills, always next to the project name.

## Tokens (Theme.swift)

- Content surfaces use `card()`: `Theme.surface` (primary at 3.5 %) with a 0.5 pt hairline, no shadow.
- Radius: cards 14, rows 8, timer bar 16, palette 16.
- Spacing: gutter 28, 20 between sections, 8–12 inside groups. Content capped at 1160 pt.
- Motion: `Motion.shell` (spring, 0.28 s, bounce 0.08) for glass changing shape, through `shellAnimation(value:)`, which honors Reduce Motion; `Motion.quick` (ease-out, 0.14 s) for the palette fade.

## Glass (Glass.swift)

Liquid Glass goes through one modifier, `glass(_:tint:radius:)`, whose role sets the intensity: the more a surface matters, the more glass it is. No view calls `glassEffect` directly. With Reduce Transparency every surface becomes opaque with a hairline.

| Role | Glass | Used for |
| --- | --- | --- |
| `selection` | regular, tint at 14 % (26 % dark), interactive | what is live: the running timer bar, the running session and project rows, the sidebar's running pill, the menu-bar timer; the palette's highlighted command |
| `control` | regular, tint at 8 % (16 % dark), interactive | the idle composer, the project filter chip |
| `accent` | regular, fully tinted, interactive | the start and stop buttons |
| `panel` | regular, untinted | the command palette, the example-workspace badge |

- `liveLens(_:radius:)` puts a `selection` lens behind a row while its project runs, tinted with the project color.
- The palette clips its results, not its glass, carries `panelShadow()` and a `lightRing`: a fine accent ring and faint halo, with one band of light crossing it from bottom to top in 0.9 s when it opens. The band is driven by one animatable value, so nothing renders once it has passed.
- The composer and its button share a `GlassEffectContainer` and `glassEffectID`s, so the idle bar morphs into the running timer whatever starts it.
- Not glass: content cards, charts, tables, the calendar, rows at rest, hover (a flat fill), buttons inside glass surfaces, sheets and Settings (system forms).
- No light or glow under glass surfaces: it spreads into a smudge on anything larger than a small tile.

## Layout

Native split view. Sidebar: brand, navigation, projects with weekly hours, running-timer pill, sync status, profile. Toolbar: a ⌘K search pill and Add. Dashboard: title and period controls, the timer bar, one metrics strip (time with goal ring, gross, net), the weekly chart next to the breakdown, sessions grouped by day. Calendar: one surface with day totals, flat tinted events and a thin "now" line. Projects: a dense list per client, with actions revealed on hover. Reports: the metrics strip, a table with share bars, then exports.

## Components and states

Rows highlight on hover; secondary actions (resume, edit, archive) appear on hover and are also in context menus. Buttons are ranked: one `.glassProminent` per context, `.glass` or link style for the rest. Tables left-align text and right-align tabular figures. Empty states use a symbol, a sentence and at most one action. Forms keep their input on validation errors.

## Motion and performance

Motion only where it explains a state change: the composer morph, the palette fade and its one-shot light band. No hover scaling, staggered entrances, bars that grow, bouncy springs or rolling digits. Nothing loops: a repeating effect, even on an 8 pt dot, forces the whole glass window to recomposite every frame (measured at about 100 % CPU while a timer ran, 0.6 % without). `runningTimerStaysCheapToRender` guards this with a 10 % ceiling. The timer ticks through `TimelineView` once per second; finished rows render static text.

## Accessibility

Light and dark through semantic colors. Color always sits next to text. Icon-only buttons have labels and help. Calendar drags have form alternatives. Native focus and VoiceOver labels; hover-revealed actions are also reachable through context menus and accessibility actions.

## Audit

Checked against the frontend-design-deslop checklist (2026-10-22): no gradients, glows, side accent rails, icon tiles, decorative blur, bouncy or looping motion, or glass on content. SF as the primary face and Liquid Glass on controls are deliberate native choices.
