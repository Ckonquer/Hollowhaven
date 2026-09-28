"""Segment S4 navigation data: walkable polylines of the areas S4 crosses, joined into one graph per area.

Every point comes from the game's own layout data (the authored walk-test paths), so the bot walks the same
lines the unit tests sweep a player capsule along:
  * hushed_works: data/works_layout.gd PATHS (critical, loop_a, to_sluice, sluice_valve_b, to_bells,
    to_lightwell, lightwell_mirror_b, lightwell_reset, to_shortcut, to_east_door, landing_exit) and
    data/works_layout_deep.gd CRITICAL_PATH + SIDE_PATHS (+ a few stand points in front of interactables);
  * hallowmere_reach: data/hallowmere_layout.gd PATHS (main_road - bent round the Commons festival pole at
    (0, 60) -, north_road, bellhouse_road, refuge_spur, arrival_road ...) + the Conservatory doors (conservatory.gd door_points) and the Bellhouse stair
    (BELLHOUSE: stair_x 72, ramp -77 .. -83.5, gate -84.6, way down -87.2);
  * surface: the Haven, the Ward Stone and the Moonlit Ruin -> waygate trail (data/world_layout.gd CH2_POINTS).
Points are (x, y, z) floor positions; y only separates levels (the Works have stacked rooms).
"""
from __future__ import annotations

import heapq
import math

WORKS_LINES = {
    "critical": [(-72.5, -6.0, 0.8), (-67.0, -6.0, 0.0), (-64.0, -6.0, 0.0), (-56.0, -7.0, 0.0), (-47.0, -7.0, 0.0),
                 (-38.0, -7.0, 0.0), (-30.0, -11.0, 0.0), (-17.0, -11.0, 0.0), (-2.0, -11.0, 0.0), (5.0, -11.0, 0.0),
                 (18.0, -18.0, 0.0), (22.0, -18.0, 0.0), (24.0, -18.0, 5.5)],
    "landing_exit": [(-72.5, -6.0, 0.8), (-75.0, -6.0, 0.0), (-76.4, -6.0, 0.0)],
    "landing_cp": [(-72.5, -6.0, 0.8), (-70.6, -6.0, -2.8)],
    "lockers_cp": [(-56.0, -7.0, 0.0), (-54.2, -7.0, -2.0)],
    "loop_a": [(-17.0, -11.0, 0.0), (-14.5, -11.0, 3.0), (-14.5, -11.0, 6.0), (-14.5, -13.0, 12.0), (-14.5, -13.0, 20.0),
               (-14.5, -13.0, 32.75), (-9.0, -13.0, 32.75), (2.0, -16.0, 32.75), (12.0, -16.0, 33.5), (12.0, -16.0, 26.5),
               (20.75, -16.0, 26.0), (20.75, -16.0, 24.0), (20.75, -18.0, 13.0), (21.0, -18.0, 8.5), (24.0, -18.0, 5.5)],
    "to_sluice": [(24.0, -18.0, 5.5), (24.0, -18.0, -3.5), (28.75, -18.0, -6.0), (28.75, -18.0, -13.0), (28.75, -20.0, -21.0),
                  (28.75, -20.0, -27.0), (24.5, -20.0, -33.0), (21.6, -20.0, -36.9)],
    "sluice_valve_b": [(28.75, -20.0, -27.0), (33.0, -20.0, -32.4), (34.9, -20.0, -33.4)],
    "sluice_plaque": [(28.75, -20.0, -21.0), (26.3, -20.0, -23.6)],
    "to_bells": [(24.0, -18.0, 5.5), (21.0, -18.0, 8.5), (20.75, -18.0, 13.0), (20.75, -16.0, 24.0), (20.75, -16.0, 26.0),
                 (12.0, -16.0, 26.5), (12.0, -16.0, 33.5)],
    "bells_ring": [(12.0, -16.0, 26.5), (8.6, -16.0, 30.6), (8.6, -16.0, 36.4), (12.0, -16.0, 33.5), (15.4, -16.0, 36.4),
                   (15.4, -16.0, 30.6), (12.0, -16.0, 26.5)],
    "to_lightwell": [(24.0, -18.0, 5.5), (31.0, -18.0, 7.0), (34.75, -18.0, 9.0), (34.75, -18.0, 13.0), (34.75, -20.0, 20.0),
                     (34.75, -20.0, 23.5), (32.2, -20.0, 26.2)],
    "lightwell_mirror_b": [(34.75, -20.0, 23.5), (34.6, -20.0, 26.4)],
    "lightwell_reset": [(34.75, -20.0, 23.5), (28.6, -20.0, 22.6)],
    "lightwell_alcove": [(32.2, -20.0, 26.2), (32.0, -20.0, 31.0), (32.0, -20.0, 35.4)],
    "to_shortcut": [(24.0, -18.0, 5.5), (23.2, -18.0, -8.0), (21.25, -18.0, -11.0), (21.25, -18.0, -13.0), (21.25, -15.6, -17.0)],
    "refuge_record": [(23.2, -18.0, -8.0), (20.6, -18.0, -5.6)],
    "refuge_wheel": [(23.2, -18.0, -8.0), (24.6, -18.0, -10.6)],
    "refuge_cp": [(23.2, -18.0, -8.0), (25.4, -18.0, -3.8)],
    "to_east_door": [(24.0, -18.0, 5.5), (33.0, -18.0, 5.0), (38.0, -18.0, 1.0), (39.2, -18.0, 0.0), (40.3, -18.0, 0.0)],
    # deep rooms (data/works_layout_deep.gd CRITICAL_PATH, split where the side paths join)
    "deep": [(40.3, -18.0, 0.0), (42.0, -18.0, 0.0), (45.0, -18.0, 0.0), (52.0, -18.0, 2.0), (55.0, -18.0, 1.0),
             (60.4, -18.0, 0.0), (63.5, -18.0, 0.0), (66.5, -18.0, 0.0), (69.0, -18.0, 0.0), (74.0, -18.0, 0.0),
             (88.0, -18.0, 0.0), (102.0, -18.0, 0.0), (106.0, -18.0, 0.0), (107.9, -18.0, 0.0), (113.0, -20.0, 0.0),
             (117.8, -21.9, 0.0), (120.0, -22.0, 0.0), (123.0, -22.0, 1.0), (126.0, -22.0, 3.0), (129.0, -22.0, 8.0),
             (129.0, -22.0, 12.0), (129.0, -22.0, 17.0), (129.0, -22.0, 20.0), (133.0, -22.0, 27.0), (136.5, -22.0, 33.5),
             (139.8, -22.0, 33.5), (146.0, -25.0, 33.5), (151.8, -27.9, 33.5), (154.0, -28.0, 33.5), (157.0, -28.0, 33.5),
             (157.0, -28.0, 37.0), (157.0, -28.0, 43.8), (157.0, -30.0, 48.0), (157.0, -32.0, 52.3), (157.0, -32.0, 58.0),
             (157.0, -32.0, 65.0)],
    "winch_nook": [(52.0, -18.0, 2.0), (49.0, -18.0, 4.0), (49.0, -18.0, 8.0), (49.0, -18.0, 11.2)],
    "winch_cage": [(55.0, -18.0, 1.0), (58.0, -18.0, -1.5), (58.0, -18.0, -5.4)],
    "crossing_cp": [(63.5, -18.0, 0.0), (65.2, -18.0, -0.3)],
    "lift_real": [(123.0, -22.0, 1.0), (123.0, -22.0, -2.0), (123.0, -22.0, -8.2)],
    "lift_false": [(126.0, -22.0, 3.0), (133.0, -22.0, -2.0), (133.0, -22.0, -8.2)],
    "siding": [(146.0, -22.0, -7.5), (146.0, -22.0, 2.4), (142.0, -22.0, 2.4), (139.0, -22.0, 2.4), (134.0, -22.0, 2.0),
               (129.0, -22.0, 8.0)],
    "lift_landing": [(123.0, -22.0, -7.6), (123.0, -22.0, -2.0)],
    "pit_stair": [(69.5, -18.0, 10.5), (72.5, -18.2, 10.5), (82.0, -22.0, 10.5), (91.8, -25.9, 10.5), (95.0, -26.0, 10.5),
                  (88.0, -26.0, 0.0)],
    "pit_top": [(69.0, -18.0, 0.0), (69.5, -18.0, 10.5)],
    "porch_flame": [(133.0, -22.0, 27.0), (136.0, -22.0, 29.6)],
    "throat_cp": [(154.0, -28.0, 33.5), (154.4, -28.0, 30.6)],
    "throat_practice": [(157.0, -28.0, 33.5), (157.0, -28.0, 27.0), (157.0, -28.0, 25.6)],
    "throat_supplies": [(157.0, -28.0, 33.5), (159.4, -28.0, 36.5)],
    "throat_note": [(157.0, -28.0, 33.5), (159.6, -28.0, 29.2)],
    "throat_board": [(157.0, -28.0, 33.5), (160.4, -28.0, 31.75)],
    "throat_lift": [(157.0, -28.0, 37.0), (159.4, -28.0, 39.4)],
    "vault_exit": [(157.0, -32.0, 65.0), (155.3, -32.0, 69.5), (155.3, -32.0, 74.5), (157.0, -32.0, 77.6), (157.0, -32.0, 80.0)],
}

# Choir Vault ring: the safe perimeter walk (radius 11.2 round (157, 65)), 12 points, joined to the entry and exit.
VAULT_C = (157.0, -32.0, 65.0)
VAULT_RING_R = 11.3


def _vault_ring():
    pts = []
    for i in range(12):
        a = math.radians(-90.0 + i * 30.0)
        pts.append((VAULT_C[0] + math.cos(a) * VAULT_RING_R, -32.0, VAULT_C[2] + math.sin(a) * VAULT_RING_R))
    pts.append(pts[0])
    return pts


WORKS_LINES["vault_ring"] = _vault_ring()
WORKS_LINES["vault_entry"] = [(157.0, -32.0, 52.3), (157.0, -32.0, 53.7)]

REACH_LINES = {
    "conservatory_in": [(0.0, 0.0, 17.0), (0.0, 0.0, 13.6), (0.0, 0.0, 11.0), (0.0, 0.0, 8.4)],
    "conservatory_east": [(0.0, 0.0, 8.4), (1.9, 0.0, 7.2), (1.9, 0.0, 4.6), (0.9, 0.0, 1.6), (0.0, 0.0, -0.5), (0.0, 0.0, -3.5)],
    "north_road": [(0.0, 0.0, -3.5), (0.5, 0.0, -12.0), (2.5, 0.0, -24.0), (5.0, 0.0, -34.0), (8.1, 0.0, -44.3),
                   (10.0, 0.0, -50.0), (11.2, 0.0, -53.6)],
    "bellhouse_road": [(5.0, 0.0, -34.0), (6.5, 0.0, -38.0), (20.0, 0.0, -44.0), (34.0, 0.0, -50.0), (46.0, 0.0, -58.0),
                       (58.0, 0.0, -66.0), (66.0, 0.0, -70.0), (70.0, 0.0, -71.0), (72.0, 0.0, -72.0)],
    "bellhouse_stair": [(72.0, 0.0, -72.0), (72.0, 0.0, -75.5), (72.0, 0.0, -78.0), (72.0, 0.0, -81.0), (72.0, 0.0, -83.3)],
    "bellhouse_down": [(72.0, 0.0, -83.3), (72.0, 0.0, -85.6)],
    "main_road": [(0.0, 0.0, 17.0), (0.0, 0.0, 22.0), (-0.8, 0.0, 30.0), (0.0, 0.0, 38.0), (0.0, 0.0, 44.0), (0.0, 0.0, 50.0),
                  (3.6, 0.0, 55.0), (3.6, 0.0, 65.0), (0.0, 0.0, 70.0), (0.0, 0.0, 75.0), (0.0, 0.0, 78.0)],
    "refuge_spur": [(0.0, 0.0, 17.0), (6.5, 0.0, 15.0), (9.3, 0.0, 8.0), (14.0, 0.0, 5.0), (20.0, 0.0, 4.0), (21.0, 0.0, 3.0)],
    "conservatory_arch": [(0.0, 0.0, 17.0), (0.0, 0.0, 18.2)],
}


class Graph:
    def __init__(self, lines: dict, merge: float = 0.35):
        self.nodes: list[tuple] = []
        self.adj: dict[int, list[tuple[int, float]]] = {}
        self.merge = merge
        for pts in lines.values():
            prev = None
            for p in pts:
                i = self._node(p)
                if prev is not None and prev != i:
                    d = self._d3(self.nodes[prev], self.nodes[i])
                    self.adj.setdefault(prev, []).append((i, d))
                    self.adj.setdefault(i, []).append((prev, d))
                prev = i

    @staticmethod
    def _d3(a, b):
        return math.sqrt((a[0] - b[0]) ** 2 + ((a[1] - b[1]) * 0.5) ** 2 + (a[2] - b[2]) ** 2)

    def _node(self, p):
        for i, q in enumerate(self.nodes):
            if abs(q[0] - p[0]) < self.merge and abs(q[2] - p[2]) < self.merge and abs(q[1] - p[1]) < 1.0:
                return i
        self.nodes.append(tuple(p))
        return len(self.nodes) - 1

    def nearest(self, p, ignore_y: bool = False) -> int:
        best, bi = 1e18, 0
        for i, q in enumerate(self.nodes):
            dy = 0.0 if ignore_y else abs(q[1] - p[1])
            d = math.hypot(q[0] - p[0], q[2] - p[2]) + (dy * 3.0 if dy > 1.6 else 0.0)
            if d < best:
                best, bi = d, i
        return bi

    def path(self, a: int, b: int) -> list[tuple]:
        dist = {a: 0.0}
        prev: dict[int, int] = {}
        pq = [(0.0, a)]
        while pq:
            d, u = heapq.heappop(pq)
            if u == b:
                break
            if d > dist.get(u, 1e18):
                continue
            for v, w in self.adj.get(u, []):
                nd = d + w
                if nd < dist.get(v, 1e18):
                    dist[v] = nd
                    prev[v] = u
                    heapq.heappush(pq, (nd, v))
        if b not in dist:
            return []
        out = [b]
        while out[-1] != a:
            out.append(prev[out[-1]])
        return [self.nodes[i] for i in reversed(out)]

    def route(self, frm, to, ignore_y: bool = False) -> list[tuple]:
        return self.path(self.nearest(frm, ignore_y), self.nearest(to, ignore_y))


WORKS = Graph(WORKS_LINES)
REACH = Graph(REACH_LINES)
