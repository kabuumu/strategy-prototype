# ⚔️ Godot Strategy Prototype

[![Build and Deploy to GitHub Pages](https://github.com/kabuumu/strategy-prototype/actions/workflows/deploy.yml/badge.svg)](https://github.com/kabuumu/strategy-prototype/actions/workflows/deploy.yml)

An agent-crafted, turn-based & real-time tactical strategy game built in Godot 4.4.

## 🚀 Play the Game
The game is automatically compiled and hosted via GitHub Pages. You can play it directly in your browser:
👉 **[Play Strategy Prototype on GitHub Pages](https://kabuumu.github.io/strategy-prototype/)**

---

## 🎮 Key Features
- **Tactical Hex Battles**: A turn-based grid battle scene featuring biome-tinted textured tiles, player unit movement, target priorities, and strategic planning.
- **RTS Skirmish Mode**: A standalone real-time skirmish mode featuring circular footprint unit physics, group unit orders, dynamic HP representation by soldier count, and a Pause-and-Plan mechanism.
- **Campaign Mode**: Navigate a multi-tier overworld campaign map (Tiers 0–4) where each node presents choices (battles, elite boss fights, recruits, heals) leading to the final elite warlord showdown.
- **Relics & Upgrades**: Accumulate powerful relics and unit upgrades (e.g. Veteran health boost) across your campaign runs.

---

## 🛠️ Tech Stack & Conventions
- **Engine**: [Godot Engine 4.4](https://godotengine.org/) (Forward Plus renderer, Canvas Items stretch, 1280x720 viewport)
- **Language**: GDScript
- **Architecture**:
  - `GameManager` (Autoload Singleton) handles persistent cross-scene run-states (player roster, map layout, current tier).
  - All UI is built dynamically entirely in code (no editor UI node clutter).
- **Automation**: Fully automated GitHub Actions pipeline (`deploy.yml`) that exports to Web WASM, inserts custom Cross-Origin isolation headers via a custom service worker, and cache-busts asset URLs.
