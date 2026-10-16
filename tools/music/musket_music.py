"""The MusketFPS soundtrack, composed and synthesized offline.

Built on the TCG-RPG music engine (synth.py and compose.py, copied from that
project): every piece grows out of one of four hand-written themes, with
modal melody, period phrasing, drones, harmony and percussion, rendered with
additive/modal synthesis and a convolution room, then written as Ogg Vorbis.

Themes (each has an anthem; the other pieces develop its first two bars):
  calder  the regiment: fife and drum marches, horns, a soldiers' chorus
  land    the unknown coast: dorian and lydian airs on lute, recorder, harp
  night   the camp at night: slow aeolian pieces for lute and recorder
  horde   the lizards: phrygian dominant, war drums, shawms and horns

Usage:  python3 tools/music/musket_music.py [track_id ...]
Writes music/<id>.ogg and data/music.json (the catalogue the game reads).
"""
import json
import os
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import compose as C  # noqa: E402
import synth  # noqa: E402
from synth import SR  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "music")
note = C.note

C.ANTHEMS = {
    "calder": {
        "title": "Colours of the Fourteenth", "tonic": note("G", 4), "mode": "ionian", "meter": 4, "bpm": 104,
        "A": ["1:1 1:0.5 2:0.5 3:1 1:1", "5:2 5:1 3:1", "4:1 4:0.5 5:0.5 6:1 4:1", "5:4",
              "6:1 6:0.5 5:0.5 4:1 3:1", "2:1 3:1 4:1 2:1", "5,:1 7,:1 2:1 7,:1", "1:4"],
        "B": ["5:1 5:1 1':1.5 7:0.5", "6:1 5:1 4:2", "3:1 4:1 5:1 6:1", "5:4",
              "1':1 7:0.5 6:0.5 5:1 4:1", "3:1 2:1 1:1 3:1", "2:1 5,:1 2:1 7,:1", "1:4"],
    },
    "land": {
        "title": "The Veiled Coast", "tonic": note("D", 4), "mode": "dorian", "meter": 6, "bpm": 180,
        "A": ["1:2 3:1 5:2 4:1", "3:3 2:3", "1:2 2:1 3:2 5:1", "4:6",
              "5:2 6:1 7:2 6:1", "5:3 3:3", "4:2 3:1 2:2 7,:1", "1:6"],
        "B": ["5:2 5:1 1':2 7:1", "6:3 5:3", "4:2 5:1 6:2 5:1", "5:6",
              "3:2 4:1 5:2 3:1", "2:3 4:3", "3:2 2:1 7,:2 2:1", "1:6"],
    },
    "night": {
        "title": "Watch Fires", "tonic": note("A", 3), "mode": "aeolian", "meter": 3, "bpm": 66,
        "A": ["5,:2 1:1", "3:2 2:1", "1:1 2:1 3:1", "2:3", "3:2 4:1", "5:2 3:1", "2:1 1:1 7,:1", "1:3"],
        "B": ["5:2 6:1", "5:1 4:1 3:1", "4:2 2:1", "3:3", "1':2 7:1", "6:1 5:1 4:1", "3:1 2:1 7,:1", "1:3"],
    },
    "horde": {
        "title": "Drums of the Horde", "tonic": note("E", 3), "mode": "phrygian_dom", "meter": 4, "bpm": 92,
        "A": ["1:2 2:1 1:1", "3:1 2:1 1:2", "1:1 2:1 3:1 4:1", "5:4",
              "6:2 5:1 4:1", "3:1 2:1 3:2", "2:1 1:1 7,:1 2:1", "1:4"],
        "B": ["5:1 5:1 6:1 5:1", "4:2 3:2", "4:1 3:1 2:1 3:1", "2:4",
              "1':2 7:1 6:1", "5:1 4:1 3:2", "2:1 3:1 2:1 7,:1", "1:4"],
    },
}

C.PROFILE = {
    "calder": {"reverb": (1.6, 0.4), "drone": "strings", "pad": "horn", "bells": False,
               "menu_lead": ["fife"], "combat_lead": "fife", "arp": "lute", "bass": "strings",
               "perc_menu": "march", "perc_combat": "drumline", "organum": False},
    "land": {"reverb": (2.2, 0.5), "drone": "hurdy", "pad": "strings", "bells": False,
             "menu_lead": ["recorder"], "combat_lead": "recorder", "arp": "harp", "bass": "lute",
             "perc_menu": "jig", "perc_combat": "hunt", "organum": False},
    "night": {"reverb": (2.8, 0.6), "drone": "strings", "pad": "choir_o", "bells": False,
              "menu_lead": ["lute"], "combat_lead": "lute", "arp": "lute", "bass": "strings",
              "perc_menu": "soft", "perc_combat": "soft", "organum": False},
    "horde": {"reverb": (3.4, 0.75), "drone": "choir_u", "pad": "organ", "bells": False,
              "menu_lead": ["shawm"], "combat_lead": "horn", "arp": "lute", "bass": "organ",
              "perc_menu": "war", "perc_combat": "war", "organum": True},
}

C.PERC.update({
    "march": {4: "B...S.S.B...S.rS", 3: "B...S.S.S.S."},
    "drumline": {4: "B.SSB.S.B.SrB.SS", 3: "B.SSS.B.S.r."},
})

# id, theme, kind, title, (mode, tonic shift, meter, bpm), lead, contexts
TRACKS = [
    ("calder_00", "calder", "anthem", "Colours of the Fourteenth", None, "fife", ["menu"]),
    ("calder_01", "calder", "menu", "Departure from Port", ("ionian", 0, 4, 96), "fife", ["map"]),
    ("calder_02", "calder", "menu", "The Long March", ("mixolydian", -2, 4, 100), "horn", ["map"]),
    ("calder_03", "calder", "combat", "Fix Bayonets!", ("aeolian", 0, 4, 138), "fife", ["battle"]),
    ("calder_04", "calder", "combat", "Hold the Line", ("dorian", -2, 4, 146), "horn", ["battle"]),
    ("land_00", "land", "anthem", "The Veiled Coast", None, "recorder", ["menu", "map"]),
    ("land_01", "land", "menu", "Unknown Rivers", ("lydian", 2, 4, 70), "harp", ["map"]),
    ("land_02", "land", "menu", "Through the Forest", ("dorian", -3, 6, 168), "recorder", ["map"]),
    ("land_03", "land", "menu", "Villages of Aurest", ("mixolydian", 0, 3, 112), "dulcimer", ["map"]),
    ("night_00", "night", "anthem", "Watch Fires", None, "lute", ["camp", "intro"]),
    ("night_01", "night", "menu", "The Sentry", ("dorian", -2, 4, 58), "recorder", ["camp"]),
    ("night_02", "night", "menu", "Letters Home", ("aeolian", 3, 3, 62), "strings", ["camp"]),
    ("horde_00", "horde", "anthem", "Drums of the Horde", None, "shawm", ["intro", "nest"]),
    ("horde_01", "horde", "combat", "They Come from the Swamp", ("phrygian_dom", 0, 4, 144), "shawm", ["battle"]),
    ("horde_02", "horde", "combat", "The Nest", ("phrygian", -2, 4, 118), "horn", ["battle", "nest"]),
]


def compose_track(tid, theme, kind, plan, lead, seed):
    prof = C.PROFILE[theme]
    an = C.ANTHEMS[theme]
    rng = np.random.default_rng(seed)
    A_an = C.parse(an["A"])
    B_an = C.parse(an["B"])
    if kind == "anthem":
        mode, tonic, meter, bpm = an["mode"], an["tonic"], an["meter"], an["bpm"]
        A, B = A_an, B_an
        form = [("intro", 1), ("A", 1), ("A", 2), ("B", 2), ("A", 3), ("outro", 1)]
        perc = prof["perc_menu"]
    else:
        mode, shift, meter, bpm = plan
        tonic = an["tonic"] + shift
        style = "lively" if (kind == "combat" or bpm >= 100) else "calm"
        perc = prof["perc_combat"] if kind == "combat" else prof["perc_menu"]
        A = C.develop_theme(rng, A_an[:2], meter, style)
        B = C.develop_theme(rng, C.gen_bars(rng, meter, style, 4, 2, 2, cadence=False), meter, style)
        if kind == "combat":
            form = [("intro", 2), ("A", 2), ("B", 3), ("A", 3), ("B", 2), ("A", 3), ("outro", 3)]
        else:
            form = [("intro", 1), ("A", 1), ("B", 1), ("A", 2), ("B", 2), ("A", 2), ("outro", 1)]
    sc = C.Score(tonic, mode, meter, bpm)
    sc.rng = np.random.default_rng(seed + 7)
    rA = C.harmonise(A)
    rB = C.harmonise(B)
    for name, inten in form:
        if name == "intro":
            C.arrange_section(sc, prof, [[] for _ in range(2)], [0, 4 if kind == "combat" else 0], inten, kind, lead, theme, perc)
        elif name == "outro":
            C.arrange_section(sc, prof, [[(0, meter, 0, 0)], []], [0, 0], max(1, inten - 1), kind, lead, theme, perc, final=True)
        elif name == "A":
            C.arrange_section(sc, prof, A, rA, inten, kind, lead, theme, perc)
        else:
            C.arrange_section(sc, prof, B, rB, inten, kind, lead, theme, perc)
    return sc


def write_ogg(path, L, R):
    pcm = np.stack([L, R], axis=1)
    pcm = (np.clip(pcm, -1, 1) * 32767).astype("<i2")
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", "-",
           "-c:a", "libvorbis", "-q:a", "-1", path]
    subprocess.run(cmd, input=pcm.tobytes(), check=True)


def main(only):
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(os.path.join(ROOT, "data"), exist_ok=True)
    cat_path = os.path.join(ROOT, "data", "music.json")
    catalogue = json.load(open(cat_path)) if os.path.exists(cat_path) else []
    catalogue = [t for t in catalogue if only and t["id"] not in only]
    for k, (tid, theme, kind, title, plan, lead, contexts) in enumerate(TRACKS):
        if only and tid not in only:
            continue
        seed = 5000 + k * 31
        sc = compose_track(tid, theme, kind, plan, lead, seed)
        L, R = C.render(sc, theme)
        write_ogg(os.path.join(OUT_DIR, tid + ".ogg"), L, R)
        synth.clear_cache()
        catalogue.append({"id": tid, "theme": theme, "kind": kind, "title": title,
                          "file": "res://music/%s.ogg" % tid, "seconds": round(len(L) / SR, 1),
                          "contexts": contexts})
        print(f"{tid:10s} {kind:7s} {len(L) / SR:6.1f}s  {title}", flush=True)
    order = [t[0] for t in TRACKS]
    catalogue.sort(key=lambda t: order.index(t["id"]))
    with open(cat_path, "w") as f:
        json.dump(catalogue, f, indent="\t", ensure_ascii=False)


if __name__ == "__main__":
    main([a for a in sys.argv[1:] if not a.startswith("--")])
