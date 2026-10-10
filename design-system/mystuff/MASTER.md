# MyStuff UI system

MyStuff is a personal inventory app: finding an item and knowing where it lives should feel effortless. This refinement applies UI/UX Pro Max's inventory/mobile Flat Design guidance to the existing native SwiftUI and iOS Liquid Glass shell. The skill's marketing page patterns and unrelated font pairings are not used; native system fonts preserve Dynamic Type and platform familiarity.

## Visual language

- Calm teal identity, a subtle neutral background, opaque content cards, and native glass navigation controls.
- Semantic light/dark colors in `MyStuff/Utilities/AppColor.swift`; no screen-specific hex colors.
- Rounded system headings; system body/subheadline text. Use scalable text styles and wrap names.
- 4/8-point spacing, 16-point phone gutters, 20–24-point section/card spacing, 24-point card corners.
- Home and gallery content constrained to 900 points; sign-in content to 560 points.
- SF Symbols for structural icons. User-selected location emoji remain user content; absent emoji fall back to a symbol.

## Interaction

- Home offers Add Item and Scan Items; secondary display/collapse commands live in View Options.
- Use native search throughout Home, Items, and Locations.
- Filters have 44-point targets, checkmarks and selected accessibility traits. Clear All stays available when filters are collapsed.
- Gallery tap opens the item; photo preview remains available by double tap and context menu. Missing photos don't block item details.
- No-match states give a direct reset action; empty states give a direct creation action.
- Sign-in keeps its action in the bottom safe area while introductory content scrolls. Async sign-in disables repeated submission and displays progress/errors. Data-operation failures surface an alert.
- Expand/collapse/view transitions honor Reduce Motion; sign-in uses no entrance choreography.
- Accessibility text sizes use one gallery column, a simplified overview, vertical actions, and a menu for grouping. Deep location trees limit visual indentation without changing hierarchy.
- Scan capture and review share the same destination card. Location selection uses grouped, spacious rows with full paths, teal checkmarks, and selected accessibility traits. Search matches parent paths as well as individual location names; accessibility text sizes omit decorative tree indentation.
- QR/NFC item updates lead with the item and its current home, followed by storage and optional photo cards. Save stays in the bottom safe area, shows progress, and disables changes/dismissal while saving.

## Shared components

`MyStuff/Views/AppUI.swift` defines content cards, section headings, location icons, and primary buttons. `MyStuff/Views/LocationPicker.swift` provides the shared destination label, tree rows, and searchable selection sections. Use these components before adding ad-hoc decoration.

## Visual QA

Debug builds accept the `-ui-preview` launch argument. It presents the normal app screens with injected MockDataService/MockStorageService and skips social sync, notification prompts, and background photo uploads. Add `-ui-preview-item item-1` to open the normal post-scan storage sheet for the demo TV Remote without scanner hardware. Both arguments are ignored in Release builds. Demo inventory edits stay in memory; preview photos stay on the device. No authentication or Firebase account changes are required. Run without the argument to inspect sign-in.

Check light/dark appearance, small and large phones, iPad and landscape, largest Dynamic Type, Reduce Motion, search/reset, filters, gallery, location expansion, and creation/cancel flows.
