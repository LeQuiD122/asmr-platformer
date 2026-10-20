"""The lobby from above (the hundredth pass): python blender/plan_lobby.py writes blender/plan_lobby.png.

Every deck and walk, and every thing on them at its footprint (lobby_layout.footprints, the same shapes check_hub.py
measures), drawn from src/Shared/LobbyLayout.lua, so crowding shows before Studio does. North (the level gates) is up,
so the world's -Z is drawn upward."""
import math
import pathlib
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Circle, Polygon, Rectangle

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import lobby_layout  # noqa: E402

OUT = pathlib.Path(__file__).resolve().parent / "plan_lobby.png"
COLOURS = {
    "level pad": "#9fd8c0", "start pad": "#78dc8c", "mode key": "#8fa8e0", "length key": "#8fa8e0",
    "pose key": "#c0b0e0", "statue plinth": "#a8a2b8", "leaderboard": "#2c2a36", "board lever": "#46424e",
    "shop kiosk": "#f4c0d0", "daily chest": "#e0b060", "challenges board": "#c8a070", "materials board": "#c8a070",
    "post box": "#d04040", "back house": "#b0a8c4", "bench": "#9a7048", "planter": "#5c8c4c", "pool": "#6fb6d6",
    "viewer": "#b09050", "squish lift": "#f4c0d0", "lamp post": "#f0d890", "column": "#d6d0e4",
}


def colour(name):
    for key, value in COLOURS.items():
        if name.startswith(key):
            return value
    return "#cccccc"


def main():
    L = lobby_layout.read()
    fig, ax = plt.subplots(figsize=(13, 13))
    ax.set_facecolor("#3b5c7a")
    m = L["margin"]
    for name, d in L["decks"].items():
        ground = "#5e7a52" if name == "garden" else "#5a5468"
        ax.add_patch(Rectangle((d["x"] - d["w"] / 2, -(d["z"] + d["d"] / 2)), d["w"], d["d"], color="#46404f", zorder=1))
        ax.add_patch(Rectangle((d["x"] - d["w"] / 2 + m, -(d["z"] + d["d"] / 2 - m)), d["w"] - 2 * m, d["d"] - 2 * m,
                               color=ground, zorder=1.5))
        ax.text(d["x"], -(d["z"] - d["d"] / 2 + 2.5), name.upper(), ha="center", va="top", color="white", fontsize=9,
                zorder=9)
    for w in L["walks"]:
        x0, x1, z0, z1 = lobby_layout.walk_rect(L, w["to"])
        ax.add_patch(Rectangle((x0, -z1), x1 - x0, z1 - z0, color="#8a7458", zorder=1))
    for name, (x0, x1, z0, z1) in lobby_layout.lanes(L):
        ax.add_patch(Rectangle((x0, -z1), x1 - x0, z1 - z0, fill=False, ec="#f0e0a0", ls=":", lw=1.0, zorder=4))
    for shape in lobby_layout.footprints(L):
        if shape["role"] == "clear":
            pts = lobby_layout._corners(shape)
            ax.add_patch(Polygon([(p[0], -p[1]) for p in pts], closed=True, fill=False, ec="white", lw=1.2, zorder=6))
            ax.text(shape["x"], -shape["z"], "spawn", ha="center", va="center", color="white", fontsize=7, zorder=10)
            continue
        if shape["kind"] == "circle":
            ax.add_patch(Circle((shape["x"], -shape["z"]), shape["r"], color=colour(shape["name"]), zorder=5))
        else:
            pts = lobby_layout._corners(shape)
            ax.add_patch(Polygon([(p[0], -p[1]) for p in pts], closed=True, color=colour(shape["name"]), zorder=5))
        label = shape["name"]
        if label.startswith(("planter", "lamp", "column", "bench", "pose key")):
            continue
        ax.text(shape["x"], -shape["z"], label.replace(" board", "").replace("level pad ", "L"), ha="center",
                va="center", fontsize=6, zorder=10,
                color="white" if label.startswith(("leaderboard", "board lever")) else "black")
    ax.set_aspect("equal")
    ax.set_xlim(-150, 150)
    ax.set_ylim(-150, 175)
    ax.set_title("The lobby from above (north up), from LobbyLayout.lua; dotted: ways kept clear")
    fig.tight_layout()
    fig.savefig(OUT, dpi=80)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
