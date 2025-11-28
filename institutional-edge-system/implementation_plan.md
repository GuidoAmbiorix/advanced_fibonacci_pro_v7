# Implementation Plan - Liquid Glass Redesign

## Goal
Overhaul the frontend UI/UX to a "Liquid Glass" aesthetic. This involves high-quality glassmorphism, fluid background gradients, neon accents, and a premium modern feel.

## User Review Required
> [!NOTE]
> **Aesthetic Change**: The entire application will move from a flat "Cyber-Black" look to a translucent, depth-heavy "Liquid Glass" design.

## Proposed Changes

### 1. Design System (Tailwind & CSS)
#### [MODIFY] [tailwind.config.js](file:///C:/Users/gamparo/Desktop/Projects/advanced_fibonacci_pro_v7/institutional-edge-system/frontend/tailwind.config.js)
- Add custom colors: `glass-surface`, `glass-border`, `neon-blue`, `neon-purple`.
- Add `backdrop-blur` utilities if needed (Tailwind has them, but we might want custom levels).
- Add `animation` for "breathing" gradients.

#### [MODIFY] [main.css](file:///C:/Users/gamparo/Desktop/Projects/advanced_fibonacci_pro_v7/institutional-edge-system/frontend/src/assets/main.css)
- **Body**: Replace solid background with a deep, animated gradient (Mesh Gradient).
- **.card**:
    - `background: rgba(255, 255, 255, 0.05);` (or black based)
    - `backdrop-filter: blur(16px);`
    - `border: 1px solid rgba(255, 255, 255, 0.1);`
    - `box-shadow: 0 4px 30px rgba(0, 0, 0, 0.1);`
- **Buttons**: "Glass" buttons with hover glow effects.
- **Typography**: Improve readability on glass surfaces (text shadows, lighter weights).

### 2. Component Refactoring
#### [MODIFY] [Dashboard.vue](file:///C:/Users/gamparo/Desktop/Projects/advanced_fibonacci_pro_v7/institutional-edge-system/frontend/src/components/Dashboard.vue)
- Ensure the layout lets the background shine through.
- Add "Ambient Light" or "Orbs" in the background for the liquid effect.

#### [MODIFY] [SignalsPanel.vue](file:///C:/Users/gamparo/Desktop/Projects/advanced_fibonacci_pro_v7/institutional-edge-system/frontend/src/components/SignalsPanel.vue)
- Update "God Mode" badge to use a neon glow (`box-shadow`).
- Make signal cards semi-transparent.

#### [MODIFY] [StatCard.vue](file:///C:/Users/gamparo/Desktop/Projects/advanced_fibonacci_pro_v7/institutional-edge-system/frontend/src/components/StatCard.vue)
- Update to use the new glass card style.

## Verification Plan

### Manual Verification
1.  **Start Frontend**: `run_frontend.bat`
2.  **Visual Check**:
    -   Verify the background is animated/gradient.
    -   Verify cards are translucent (can see background blur behind them).
    -   Verify text is legible.
    -   Verify "God Mode" badge glows.
