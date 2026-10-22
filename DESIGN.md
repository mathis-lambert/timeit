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

- Surfaces: content cards use `Theme.surface` (primary at 3.5 %) with a 0.5 pt hairline, no shadow. Glass is reserved for floating controls: timer bar, toolbar, palette, demo badge. Native segmented pickers and control groups provide their own glass.
- Radius: cards 14, rows 8, timer bar 16.
- Spacing: gutter 28, 20 between sections, 8–12 inside groups. Content capped at 1160 pt.
- Motion: `Motion.standard` (smooth, 0.28 s) for the composer morph; `Motion.quick` (ease-out, 0.14 s) for the palette fade.

## Layout

Native split view. Sidebar: brand, navigation, projects with weekly hours, running-timer pill, sync status, profile. Toolbar: a ⌘K search pill and Add. Dashboard: title and period controls, the timer bar, one metrics strip (time with goal ring, gross, net), the weekly chart next to the breakdown, sessions grouped by day. Calendar: one surface with day totals, flat tinted events and a thin "now" line. Projects: a dense list per client, with actions revealed on hover. Reports: the metrics strip, a table with share bars, then exports.

## Components and states

Rows highlight on hover; secondary actions (resume, edit, archive) appear on hover and are also in context menus. Buttons are ranked: one `.glassProminent` per context, `.glass` or link style for the rest. Tables left-align text and right-align tabular figures. Empty states use a symbol, a sentence and at most one action. Forms keep their input on validation errors.

## Motion and performance

Motion only where it explains a state change: the composer morph and the palette fade. No hover scaling, staggered entrances, bars that grow, bouncy springs or rolling digits. Nothing loops: a repeating effect, even on an 8 pt dot, forces the whole glass window to recomposite every frame (measured at about 100 % CPU while a timer ran, 0.6 % without). `runningTimerStaysCheapToRender` guards this with a 10 % ceiling. The timer ticks through `TimelineView` once per second; finished rows render static text.

## Accessibility

Light and dark through semantic colors. Color always sits next to text. Icon-only buttons have labels and help. Calendar drags have form alternatives. Native focus and VoiceOver labels; hover-revealed actions are also reachable through context menus and accessibility actions.

## Audit

Checked against the frontend-design-deslop checklist (2026-10-22): no gradients, glows, side accent rails, icon tiles, decorative blur, bouncy or looping motion, or glass on content. SF as the primary face and Liquid Glass on controls are deliberate native choices.
