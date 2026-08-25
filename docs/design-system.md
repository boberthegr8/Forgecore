# Forge Design System

Forge is dark-first across CRM, Scope, Reader, Quoter and future operations modules.

## Core palette

The canonical CSS variables live in `design/forge-theme.css`.

- Background: `#0b0c0e`
- Sidebar: `#0f1012`
- Surface: `#151619`
- Raised surface: `#191b1f`
- Border: `#292c31`
- Primary text: `#f4f4f5`
- Secondary text: `#a5a9b1`
- Muted text: `#6f747d`
- Forge accent: `#ff7617`

Semantic colors remain distinct for success, warning, danger and information states.

## Product rules

1. Forge orange is the suite accent. Modules should not become separate color brands.
2. Use dark charcoal surfaces rather than pure black.
3. Orange is for selected navigation, primary actions, focus and Forge identity—not every decorative element.
4. Dense estimating tables/forms should favor legibility and restrained borders over oversized cards.
5. Customer-facing print/PDF documents may remain light even when the application shell is dark.
6. Auth, organization identity, navigation and status language should feel consistent across modules.
7. Great White Streams assets/infrastructure are never part of this design or code system.
