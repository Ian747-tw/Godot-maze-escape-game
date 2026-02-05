# Maze Runner

A simple 2D maze runner game built with Godot 4. Avoid the killer, navigate through doors, and find your way to the exit!

## Controls

| Action | Key(s) |
| --- | --- |
| **Move** | WASD / Arrow Keys |
| **Run** | Shift |
| **Interact (Doors)** | E |
| **Restart Level** | R |
| **Quit Game** | Esc |

## Getting Started

1.  Clone the repository.
2.  Open the project in **Godot 4.3+**.
3.  Press **F5** to play the game.

## Features

-   **Dynamic AI**: A killer that hears and sees you. Use stealth to your advantage!
-   **Interactive Environment**: Doors that swing open based on your position.
-   **Atmospheric Lighting**: Use your flashlight to navigate the dark maze.
-   **Audio System**: Sound-based detection system.

## Project Structure

-   `main.gd/tscn`: The level controller and UI handler.
-   `player.gd/tscn`: Player movement and input.
-   `killer.gd/tscn`: AI logic (Patrol, Investigate, Search, Chase).
-   `door.gd/tscn`: Interactive door mechanics.
-   `systems/`: Global management scripts (e.g., SoundSystem).
