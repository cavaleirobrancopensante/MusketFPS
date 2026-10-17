#!/usr/bin/env python3
"""The game's translations (see scripts/lang.gd).

    python3 tools/i18n.py wrap      wrap the player-facing text in the scripts
                                    in Lang.t(...) (only what isn't yet)
    python3 tools/i18n.py extract   list every piece of text (wrapped, or in
                                    the const tables marked for translation)
                                    in data/i18n/en.json
    python3 tools/i18n.py missing   what each table (pt_BR, es) lacks

Text is a string literal with a space and a word in it, or an upper-case
label (FIRE, LEAVE). Left alone: paths, dictionary keys, match patterns,
comparisons' operands are wrapped like the text they're compared with,
prints, node and signal names, and anything in a const (const tables are
translated where they're shown: see the list CONST_TABLES, whose strings
are extracted all the same).
"""
import json, os, re, sys, glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS = os.path.join(ROOT, "scripts")
I18N = os.path.join(ROOT, "data", "i18n")
LIT = re.compile(r'"((?:[^"\\]|\\.)*)"')
SKIP_LINE = re.compile(r'^\s*(#|print|prints|push_error|push_warning|assert|printerr)|\bfunc\s+\w+\s*\(.*\)\s*(->.*)?:\s*$|get_node\(|has_node\(|\.connect\(|preload\(|load\(|^\s*@')
SKIP_FILES = {"lang.gd", "tongue.gd", "music_catalogue.gd"}
# Const tables whose every value is something the player reads (single
# lower-case words too: "warriors", "1st").
WORD_TABLES = {"ORDINAL", "COMP_NAMES", "TRAIT_WORDS", "ATTR_NAMES", "WEAPON_LABELS", "SLOT_NAMES", "MAP_NAMES",
    "THEME_NAMES", "ROAD_NAMES", "DUTIES"}
# Words shown through Lang.t(variable): kinds of place, graphics levels...
EXTRA = ["village", "town", "city", "fort", "nest", "Low", "Medium", "High", "Musketeers", "Pikes", "Wagon",
    "Pikemen", "Bowmen", "Crossbowmen", "Cavalry", "Cannon", "Spearmen", "Archers", "Ensign", "Captain", "Major",
    "Count", "Margrave", "Thane", "Fallen", "Wounded", "Promoted", "Water", "Rations", "Cartridges", "Arrows", "Bolts",
    "battle", "battles", "kill", "kills", "cartridge", "cartridges", "arrow", "arrows", "bolt", "bolts", "shot", "shots",
    "day", "days", "rations", "muskets", "reliable", "bare-headed", "sick", "fit", "Mutinous", "They've", "LINE", "MAN", "WAGON"]


def is_text(s):
    if s.startswith(("res://", "user://", "http")) or "\\u" in s:
        return False
    if re.fullmatch(r"[A-Z][A-Z &'!.:?,\-]{2,}", s):
        return True
    return " " in s and re.search(r"[A-Za-z]{2}", s) is not None


def scan(path, wrap=False):
    """Returns (texts found, new source)."""
    found = []
    out = []
    depth = 0 # inside a const block: bracket depth
    in_const = False
    const_name = ""
    for line in open(path, encoding="utf-8").read().split("\n"):
        stripped = line.strip()
        mc = re.match(r"^\s*const\s+(\w+)", line)
        if not in_const and mc:
            in_const = True
            depth = 0
            const_name = mc.group(1)
        if in_const:
            for m in LIT.finditer(line):
                v = m.group(1)
                is_key = re.match(r"\s*:", line[m.end():]) is not None
                if is_text(v) or (not is_key and (re.fullmatch(r"[A-Z][a-z]+[a-z.!?]*", v) or (const_name in WORD_TABLES and re.fullmatch(r"[A-Za-z0-9 ]+", v)))):
                    found.append(v)
            depth += line.count("[") + line.count("{") + line.count("(") - line.count("]") - line.count("}") - line.count(")")
            if depth <= 0:
                in_const = False
            out.append(line)
            continue
        if SKIP_LINE.search(line):
            out.append(line)
            continue
        new = []
        last = 0
        for m in LIT.finditer(line):
            s = m.group(1)
            before = line[:m.start()]
            after = line[m.end():]
            if before.rstrip().endswith("Lang.t("):
                found.append(s)
                continue
            if not is_text(s):
                continue
            if re.match(r"\s*:", after) and not re.search(r"\?\s*$", before):
                continue # a dictionary key, or a match pattern
            if re.search(r"(\.get|\.has|has_meta|get_meta|set_meta|play_sound|_scene|begins_with|ends_with|find|replace|split)\(\s*$", before):
                continue
            found.append(s)
            if wrap:
                new.append(line[last:m.start()])
                new.append('Lang.t("%s")' % s)
                last = m.end()
        if wrap and new:
            new.append(line[last:])
            line = "".join(new)
        out.append(line)
    return found, "\n".join(out)


def files():
    return [f for f in sorted(glob.glob(os.path.join(SCRIPTS, "*.gd"))) if os.path.basename(f) not in SKIP_FILES]


def cmd_wrap():
    n = 0
    for f in files():
        found, src = scan(f, wrap=True)
        old = open(f, encoding="utf-8").read()
        if src != old:
            open(f, "w", encoding="utf-8").write(src)
            n += 1
    print("wrapped text in %d scripts" % n)


def all_texts():
    seen = {}
    for f in files():
        found, _ = scan(f)
        for s in found:
            seen.setdefault(s, os.path.basename(f))
    # Text looked up through a variable (Lang.t(kind)) that isn't caught above.
    for s in EXTRA:
        seen.setdefault(s, "extra")
    return seen


def unescape(s):
    return bytes(s, "utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8") if "\\" in s else s


def cmd_extract():
    os.makedirs(I18N, exist_ok=True)
    texts = all_texts()
    keys = {}
    for s, f in texts.items():
        keys[unescape(s)] = f
    json.dump(keys, open(os.path.join(I18N, "en.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=0, sort_keys=True)
    print("%d texts" % len(keys))


def cmd_missing():
    keys = json.load(open(os.path.join(I18N, "en.json"), encoding="utf-8"))
    for lang in ["pt_BR", "es"]:
        p = os.path.join(I18N, lang + ".json")
        have = json.load(open(p, encoding="utf-8")) if os.path.exists(p) else {}
        miss = [k for k in keys if k not in have]
        print("%s: %d of %d missing" % (lang, len(miss), len(keys)))
        if "-v" in sys.argv:
            for k in miss[:200]:
                print("   ", json.dumps(k, ensure_ascii=False))


if __name__ == "__main__":
    {"wrap": cmd_wrap, "extract": cmd_extract, "missing": cmd_missing}[sys.argv[1]]()
