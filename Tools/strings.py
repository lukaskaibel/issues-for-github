#!/usr/bin/env python3
"""Works with the app's String Catalog (Packages/GitIssuesKit/Sources/GitIssuesKit/Resources/Localizable.xcstrings).

Every text is a manually added string whose key is also its Swift symbol: the key `syncedMinutesAgo` is used as
`Text(.syncedMinutesAgo(minutes: 3))`. Xcode can edit the catalog too; this script is for the terminal.

    Tools/strings.py list [pattern]            keys, English and comment, filtered by a regular expression
    Tools/strings.py show KEY                  one entry with every translation
    Tools/strings.py add KEY ENGLISH COMMENT [--one SINGULAR]
                                               a new text; --one makes ENGLISH the plural "other" form
    Tools/strings.py rename OLD NEW            renames a key and its uses in the Swift sources
    Tools/strings.py remove KEY                removes a key
    Tools/strings.py export LANG [--missing]   JSON of key -> English, comment and current translation
    Tools/strings.py import LANG FILE          merges translations from JSON: {key: "text" | {"one": …, "other": …}}
    Tools/strings.py validate LANG FILE        checks such a file against the catalog without changing anything
    Tools/strings.py check                     the checks LocalizationTests runs, without building

English may name its placeholders, which become argument labels: "Synced %(minutes)lld min ago". Translations
use plain placeholders, numbered as soon as there is more than one ("%2$@: %1$lld"), since a translation that
reorders named placeholders crashes.
"""

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "Packages/GitIssuesKit/Sources/GitIssuesKit/Resources/Localizable.xcstrings")
SOURCES = os.path.join(ROOT, "Packages/GitIssuesKit/Sources/GitIssuesKit")
LANGUAGES = ["de", "es", "fr", "ja", "ko", "pt-BR", "ru", "zh-Hans"]
# The plural forms each language needs (CLDR). Spanish, French and Portuguese also have "many" for numbers like a
# million, which falls back to "other" when it's missing.
PLURALS = {"en": {"one", "other"}, "de": {"one", "other"}, "es": {"one", "other"}, "fr": {"one", "other"},
           "ja": {"other"}, "ko": {"other"}, "pt-BR": {"one", "other"}, "ru": {"one", "few", "many", "other"},
           "zh-Hans": {"other"}}
KEY = re.compile(r"^[a-z][A-Za-z0-9]*$")
SPECIFIER = re.compile(
    r"%%|%#@(?P<sub>\w+)@|%(?:(?P<pos>\d+)\$|\((?P<name>\w+)\))?[-+ 0#']*\d*(?:\.\d+)?(?P<len>hh|h|ll|l|q|z|t|j)?"
    r"(?P<conv>[@dDiuUxXoOfFeEgGaAcCsSp])"
)


def load():
    with open(CATALOG, encoding="utf-8") as f:
        return json.load(f)


def save(catalog):
    text = json.dumps(catalog, ensure_ascii=False, indent=2, separators=(",", " : "), sort_keys=True)
    with open(CATALOG, "w", encoding="utf-8") as f:
        f.write(text + "\n")


def kind(conv):
    if conv == "@":
        return "object"
    if conv in "fFeEgGaA":
        return "double"
    if conv in "sS":
        return "cstring"
    if conv == "p":
        return "pointer"
    return "int"


def units(localization):
    """Every (path, stringUnit) in a localization, including plural variations and substitutions."""
    found = []

    def walk(node, path):
        if not isinstance(node, dict):
            return
        if "stringUnit" in node:
            found.append((path, node["stringUnit"]))
        for name, variants in node.get("variations", {}).items():
            for case, child in variants.items():
                walk(child, f"{path}{name}.{case}/")
        for name, sub in node.get("substitutions", {}).items():
            walk(sub, f"{path}%#@{name}@/")

    walk(localization, "")
    return found


def placeholders(value, substitutions=None):
    """[(position, kind)] for the arguments a value uses; names are numbered in order of first appearance."""
    result, names, sequential = [], {}, 0
    for match in SPECIFIER.finditer(value):
        token = match.group(0)
        if token == "%%":
            continue
        if match.group("sub"):
            sub = (substitutions or {}).get(match.group("sub"))
            if sub is None:
                result.append((None, "missing substitution " + match.group("sub")))
            else:
                result.append((sub.get("argNum"), kind(sub.get("formatSpecifier", "@")[-1])))
            continue
        if match.group("pos"):
            position = int(match.group("pos"))
        elif match.group("name"):
            position = names.setdefault(match.group("name"), len(names) + 1)
        else:
            sequential += 1
            position = sequential
        result.append((position, kind(match.group("conv"))))
    return result


def english(entry):
    unit = entry.get("localizations", {}).get("en", {})
    for path, string_unit in units(unit):
        if path.endswith("other/") or path == "":
            return string_unit.get("value", "")
    found = units(unit)
    return found[0][1].get("value", "") if found else ""


def signature(localization):
    """position -> kind over every variant of a localization; problems as a list of strings."""
    positions, problems = {}, []
    for path, unit in units(localization):
        if path.startswith("%#@"):
            # Inside a substitution, %arg stands for the substitution's own argument.
            continue
        for position, what in placeholders(unit.get("value", ""), localization.get("substitutions")):
            if position is None:
                problems.append(what)
            elif positions.setdefault(position, what) != what:
                problems.append(f"argument {position} used as {positions[position]} and {what}")
    return positions, problems


def check(catalog):
    problems = []
    strings = catalog.get("strings", {})
    for key, entry in sorted(strings.items()):
        if not KEY.match(key):
            problems.append(f"{key}: keys are camelCase Swift names")
        if entry.get("extractionState") != "manual":
            problems.append(f"{key}: not a manual string, so Xcode makes no symbol for it")
        if not entry.get("comment"):
            problems.append(f"{key}: no comment saying where it appears")
        localizations = entry.get("localizations", {})
        if "en" not in localizations:
            problems.append(f"{key}: no English")
            continue
        source, source_problems = signature(localizations["en"])
        problems += [f"{key} (en): {p}" for p in source_problems]
        for language in LANGUAGES:
            localization = localizations.get(language)
            if localization is None:
                problems.append(f"{key} ({language}): not translated")
                continue
            found = units(localization)
            if not found:
                problems.append(f"{key} ({language}): empty")
            for path, unit in found:
                if unit.get("state") != "translated":
                    problems.append(f"{key} ({language}) {path}: state is {unit.get('state')}")
                if not unit.get("value", "").strip():
                    problems.append(f"{key} ({language}) {path}: empty text")
            for name, variants in localization.get("variations", {}).items():
                if name == "plural":
                    missing = PLURALS[language] - set(variants)
                    if missing:
                        problems.append(f"{key} ({language}): plural forms missing: {', '.join(sorted(missing))}")
            translated, translation_problems = signature(localization)
            problems += [f"{key} ({language}): {p}" for p in translation_problems]
            for position, what in translated.items():
                if source.get(position) != what:
                    problems.append(f"{key} ({language}): argument {position} is {what}, English has {source.get(position)}")
            for path, unit in found:
                value = unit.get("value", "")
                if "%(" in value:
                    problems.append(f"{key} ({language}): named placeholder; use %lld, %@ or numbered ones")
                if len(source) > 1 and not path.startswith("%#@"):
                    for match in SPECIFIER.finditer(value):
                        if match.group("conv") and not match.group("pos"):
                            problems.append(f"{key} ({language}): several arguments, so number them: {value!r}")
                            break
    return problems


def unused(catalog):
    code = []
    for folder, _, files in os.walk(SOURCES):
        for name in files:
            if name.endswith(".swift"):
                with open(os.path.join(folder, name), encoding="utf-8") as f:
                    code.append(f.read())
    code = "\n".join(code)
    return [key for key in catalog.get("strings", {}) if not re.search(r"\." + re.escape(key) + r"\b", code)]


def main(args):
    if not args:
        print(__doc__)
        return 1
    command, rest = args[0], args[1:]
    catalog = load()
    strings = catalog.setdefault("strings", {})

    if command == "list":
        pattern = re.compile(rest[0], re.I) if rest else None
        for key, entry in sorted(strings.items()):
            text = english(entry)
            if pattern and not (pattern.search(key) or pattern.search(text)):
                continue
            print(f"{key:40} {text!r:50} {entry.get('comment', '')[:90]}")
    elif command == "show":
        print(json.dumps(strings.get(rest[0]), ensure_ascii=False, indent=2))
    elif command == "add":
        key, text, comment = rest[0], rest[1], rest[2]
        one = rest[rest.index("--one") + 1] if "--one" in rest else None
        if not KEY.match(key):
            sys.exit(f"{key}: use a camelCase Swift name")
        if key in strings and english(strings[key]) != text:
            sys.exit(f"{key} exists with {english(strings[key])!r}")
        same = [k for k, e in strings.items() if english(e) == text and k != key]
        if same:
            print(f"note: {text!r} is also {', '.join(same)}; reuse it if it means the same here", file=sys.stderr)
        if one is None:
            english_unit = {"stringUnit": {"state": "translated", "value": text}}
        else:
            english_unit = {"variations": {"plural": {
                "one": {"stringUnit": {"state": "translated", "value": one}},
                "other": {"stringUnit": {"state": "translated", "value": text}},
            }}}
        entry = strings.setdefault(key, {})
        entry["comment"] = comment
        entry["extractionState"] = "manual"
        entry.setdefault("localizations", {})["en"] = english_unit
        save(catalog)
    elif command == "rename":
        old, new = rest
        if new in strings:
            sys.exit(f"{new} exists; remove {old} and replace its uses by hand")
        strings[new] = strings.pop(old)
        save(catalog)
        for folder, _, files in os.walk(os.path.join(ROOT, "Packages/GitIssuesKit")):
            if "/.build" in folder:
                continue
            for name in files:
                if name.endswith(".swift"):
                    path = os.path.join(folder, name)
                    with open(path, encoding="utf-8") as f:
                        text = f.read()
                    changed = re.sub(r"(?<![\w.])\." + re.escape(old) + r"\b", "." + new, text)
                    changed = re.sub(r"\bLocalizedStringResource\." + re.escape(old) + r"\b", "LocalizedStringResource." + new, changed)
                    if changed != text:
                        with open(path, "w", encoding="utf-8") as f:
                            f.write(changed)
                        print("updated", os.path.relpath(path, ROOT))
    elif command == "remove":
        strings.pop(rest[0])
        save(catalog)
    elif command == "export":
        language, missing = rest[0], "--missing" in rest
        out = {}
        for key, entry in sorted(strings.items()):
            current = entry.get("localizations", {}).get(language)
            if missing and current:
                continue
            item = {"comment": entry.get("comment", ""), "en": simplify(entry["localizations"]["en"])}
            arguments = argument_names(entry["localizations"]["en"])
            if arguments:
                item["placeholders"] = arguments
            if current:
                item[language] = simplify(current)
            out[key] = item
        print(json.dumps(out, ensure_ascii=False, indent=2))
    elif command == "import":
        language, path = rest
        with open(path, encoding="utf-8") as f:
            translations = json.load(f)
        unknown = [k for k in translations if k not in strings]
        if unknown:
            sys.exit("unknown keys: " + ", ".join(unknown))
        for key, value in translations.items():
            strings[key].setdefault("localizations", {})[language] = expand(value)
        save(catalog)
        print(f"{len(translations)} texts in {language}")
    elif command == "validate":
        language, path = rest
        with open(path, encoding="utf-8") as f:
            translations = json.load(f)
        unknown = [k for k in translations if k not in strings]
        for key, value in translations.items():
            if key in strings:
                strings[key].setdefault("localizations", {})[language] = expand(value)
        missing = [k for k, e in strings.items() if language not in e.get("localizations", {})]
        problems = [p for p in check(catalog) if f"({language})" in p and "not translated" not in p]
        problems += [f"{k}: not in the catalog" for k in unknown] + [f"{k}: missing" for k in missing]
        for problem in problems:
            print(problem)
        print(f"{len(translations)} texts, {len(missing)} missing, {len(problems)} problems")
        return 1 if problems else 0
    elif command == "check":
        problems = check(catalog) + [f"{k}: not used in the sources" for k in unused(catalog)]
        for problem in problems:
            print(problem)
        print(f"{len(strings)} texts, {len(problems)} problems")
        return 1 if problems else 0
    else:
        print(__doc__)
        return 1
    return 0


def argument_names(localization):
    """How a translation refers to each placeholder: {"%1$@": "name (text)", "%2$lld": "count (number)"}."""
    names, found = {}, {}
    for _, unit in units(localization):
        for match in SPECIFIER.finditer(unit.get("value", "")):
            if not match.group("conv"):
                continue
            label = match.group("name") or match.group("pos") or str(len(names) + 1)
            if label not in names:
                names[label] = len(names) + 1
                what = "text" if match.group("conv") == "@" else "number"
                spec = "%" + str(names[label]) + "$" + (match.group("len") or "") + match.group("conv")
                found[spec] = f"{label} ({what})" if match.group("name") else what
    return found


def simplify(localization):
    """A localization as plain JSON: a string, {plural case: string}, or the raw entry if it has substitutions."""
    if "substitutions" in localization:
        return localization
    if "stringUnit" in localization:
        return localization["stringUnit"]["value"]
    plural = localization.get("variations", {}).get("plural")
    if plural and all("stringUnit" in v for v in plural.values()):
        return {case: v["stringUnit"]["value"] for case, v in plural.items()}
    return localization


def expand(value):
    if isinstance(value, str):
        return {"stringUnit": {"state": "translated", "value": value}}
    if all(isinstance(v, str) for v in value.values()) and set(value) <= {"zero", "one", "two", "few", "many", "other"}:
        return {"variations": {"plural": {case: {"stringUnit": {"state": "translated", "value": text}}
                                          for case, text in value.items()}}}
    return value


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
