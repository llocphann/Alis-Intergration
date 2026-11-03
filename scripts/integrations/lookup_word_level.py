#!/usr/bin/env python3
"""Extract CEFR vocabulary level (A1-C2) and lexical metadata for English & German.

Sources:
- English (en): Cambridge Dictionary (EVP A1-C2), Oxford Learner's Dictionaries (Oxford 3000/5000),
  Free Dictionary API.
- German (de): DWDS (Digitales Wörterbuch der deutschen Sprache API + frequency bands),
  German Wiktionary MediaWiki API, Cambridge German-English Dictionary.
"""

from __future__ import annotations

import argparse
import html
import json
import os
from pathlib import Path
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
)
VALID_LEVELS = ("A1", "A2", "B1", "B2", "C1", "C2")


def cache_file_path() -> Path:
    cache_root = os.environ.get("XDG_CACHE_HOME") or str(Path.home() / ".cache")
    return Path(cache_root) / "alis" / "spaced-repetition-lexicon.json"


def load_cache() -> dict:
    path = cache_file_path()
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def save_cache(cache: dict) -> None:
    path = cache_file_path()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(cache, ensure_ascii=False, indent=2), encoding="utf-8")
    except Exception:
        pass


def fetch_text(url: str, timeout: float = 3.5) -> str:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "text/html,application/json;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9,de;q=0.8",
        },
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read(350_000)
        charset = resp.headers.get_content_charset() or "utf-8"
        return raw.decode(charset, errors="replace")


def clean_html_snippet(raw_html: str) -> str:
    text = re.sub(r"<[^>]+>", " ", raw_html)
    text = html.unescape(text)
    text = re.sub(r"\s+", " ", text).strip()
    return text.rstrip(": ").strip()


def parse_cambridge_english_html(page_html: str) -> dict:
    result: dict = {}
    level_match = re.search(
        r'class="[^"]*epp-xref[^"]*\b(A1|A2|B1|B2|C1|C2)\b[^"]*"[^>]*>\s*(A1|A2|B1|B2|C1|C2)?',
        page_html,
        re.IGNORECASE,
    )
    if not level_match:
        level_match = re.search(
            r'>\s*(A1|A2|B1|B2|C1|C2)\s*</span>',
            page_html,
        )
    if level_match:
        lvl = (level_match.group(1) or "").upper()
        if lvl in VALID_LEVELS:
            result["level"] = lvl
            result["levelSource"] = "Cambridge Dictionary (EVP)"

    pos_match = re.search(r'<span class="pos dpos"[^>]*>(.*?)</span>', page_html, re.S)
    if pos_match:
        result["pos"] = clean_html_snippet(pos_match.group(1)).lower()

    ipa_match = re.search(r'<span class="ipa dipa[^"]*"[^>]*>(.*?)</span>', page_html, re.S)
    if ipa_match:
        ipa = clean_html_snippet(ipa_match.group(1)).strip("/")
        if ipa:
            result["phonetic"] = f"/{ipa}/"

    def_match = re.search(r'<div class="def ddef_d db"[^>]*>(.*?)</div>', page_html, re.S)
    if def_match:
        meaning = clean_html_snippet(def_match.group(1))
        if meaning:
            result["meaning"] = meaning

    ex_match = re.search(r'<span class="eg deg"[^>]*>(.*?)</span>', page_html, re.S)
    if ex_match:
        example = clean_html_snippet(ex_match.group(1))
        if example:
            result["example"] = example

    return result


def normalize_pos_code(raw_pos: str) -> str:
    p = str(raw_pos or "").strip().lower()
    if p in ("adjective", "adj"):
        return "adj"
    if p in ("adverb", "adv"):
        return "adv"
    if p in ("noun", "n"):
        return "noun"
    if p in ("verb", "v"):
        return "verb"
    return p


def parse_oxford_english_html(page_html: str) -> dict:
    result: dict = {}
    level_match = re.search(
        r'ox3ksym_(a1|a2|b1|b2|c1|c2)|belong-to="(?:ox3000|ox5000)"[^>]*>\s*(a1|a2|b1|b2|c1|c2)?',
        page_html,
        re.IGNORECASE,
    )
    if level_match:
        lvl = (level_match.group(1) or level_match.group(2) or "").upper()
        if lvl in VALID_LEVELS:
            result["level"] = lvl
            result["levelSource"] = "Oxford 3000/5000"

    ipa_match = re.search(r'<span class="phon"[^>]*>(.*?)</span>', page_html, re.S)
    if ipa_match:
        phon = clean_html_snippet(ipa_match.group(1)).strip("/")
        if phon:
            result["phonetic"] = f"/{phon}/"

    pos_match = re.search(r'<span class="pos"[^>]*>(.*?)</span>', page_html, re.S)
    if pos_match:
        result["pos"] = normalize_pos_code(clean_html_snippet(pos_match.group(1)))

    def_match = re.search(r'<span class="def"[^>]*>(.*?)</span>', page_html, re.S)
    if def_match:
        meaning = clean_html_snippet(def_match.group(1))
        if meaning:
            result["meaning"] = meaning

    ex_match = re.search(r'<span class="x"[^>]*>(.*?)</span>', page_html, re.S)
    if ex_match:
        example = clean_html_snippet(ex_match.group(1))
        if example:
            result["example"] = example

    return result


def lookup_english_online(word: str, timeout: float = 3.5) -> dict:
    slug = urllib.parse.quote(word.lower().strip())
    merged: dict = {
        "ok": False,
        "word": word.strip(),
        "language": "en",
        "level": "",
        "levelSource": "",
        "pos": "",
        "phonetic": "",
        "article": "",
        "plural": "",
        "meaning": "",
        "example": "",
        "synonyms": [],
        "antonyms": [],
        "morphology": [],
        "morphologyText": "",
        "etymology": "",
    }

    # 1. Oxford Learner's Dictionaries (Oxford 3000/5000 CEFR level, IPA, POS, definition, example)
    try:
        ox_html = fetch_text(
            f"https://www.oxfordlearnersdictionaries.com/definition/english/{slug}",
            timeout=timeout,
        )
        ox_data = parse_oxford_english_html(ox_html)
        for key, value in ox_data.items():
            if value and not merged.get(key):
                merged[key] = value
        if ox_data:
            merged["ok"] = True
    except Exception:
        pass

    # 2. Free Dictionary API for phonetics, definitions, examples, synonyms, and antonyms
    if not merged["meaning"] or not merged["phonetic"] or not merged["example"] or not merged["synonyms"] or not merged["antonyms"]:
        try:
            api_raw = fetch_text(
                f"https://api.dictionaryapi.dev/api/v2/entries/en/{slug}",
                timeout=timeout,
            )
            entries = json.loads(api_raw)
            if isinstance(entries, list) and entries:
                first = entries[0]
                if not merged["phonetic"]:
                    phon = first.get("phonetic") or ""
                    if not phon:
                        for p in first.get("phonetics") or []:
                            if isinstance(p, dict) and p.get("text"):
                                phon = p["text"]
                                break
                    if phon:
                        merged["phonetic"] = phon
                syns_acc: list[str] = []
                ants_acc: list[str] = []
                for m in first.get("meanings") or []:
                    if not isinstance(m, dict):
                        continue
                    if not merged["pos"] and m.get("partOfSpeech"):
                        merged["pos"] = normalize_pos_code(str(m["partOfSpeech"]))
                    for s in m.get("synonyms") or []:
                        if isinstance(s, str) and s.strip() and s.strip() not in syns_acc:
                            syns_acc.append(s.strip())
                    for a in m.get("antonyms") or []:
                        if isinstance(a, str) and a.strip() and a.strip() not in ants_acc:
                            ants_acc.append(a.strip())
                    for d in m.get("definitions") or []:
                        if not isinstance(d, dict):
                            continue
                        if not merged["meaning"] and d.get("definition"):
                            merged["meaning"] = str(d["definition"]).strip()
                        if not merged["example"] and d.get("example"):
                            merged["example"] = str(d["example"]).strip()
                        for s in d.get("synonyms") or []:
                            if isinstance(s, str) and s.strip() and s.strip() not in syns_acc:
                                syns_acc.append(s.strip())
                        for a in d.get("antonyms") or []:
                            if isinstance(a, str) and a.strip() and a.strip() not in ants_acc:
                                ants_acc.append(a.strip())
                if syns_acc and not merged["synonyms"]:
                    merged["synonyms"] = syns_acc[:5]
                if ants_acc and not merged["antonyms"]:
                    merged["antonyms"] = ants_acc[:5]
                merged["ok"] = True
        except Exception:
            pass

    # 3. Datamuse lexical relations for synonyms/antonyms if still missing
    if not merged["synonyms"]:
        try:
            syn_raw = fetch_text(f"https://api.datamuse.com/words?rel_syn={slug}&max=5", timeout=min(2.0, timeout))
            syn_list = json.loads(syn_raw)
            if isinstance(syn_list, list):
                syns = [str(item.get("word") or "").strip() for item in syn_list if isinstance(item, dict) and item.get("word")]
                if syns:
                    merged["synonyms"] = syns[:5]
        except Exception:
            pass

    if not merged["antonyms"]:
        try:
            ant_raw = fetch_text(f"https://api.datamuse.com/words?rel_ant={slug}&max=5", timeout=min(2.0, timeout))
            ant_list = json.loads(ant_raw)
            if isinstance(ant_list, list):
                ants = [str(item.get("word") or "").strip() for item in ant_list if isinstance(item, dict) and item.get("word")]
                if ants:
                    merged["antonyms"] = ants[:5]
        except Exception:
            pass

    # 4. Cambridge Dictionary fallback if level or meaning still missing
    if not merged["level"] or not merged["meaning"]:
        try:
            cam_html = fetch_text(
                f"https://dictionary.cambridge.org/dictionary/english/{slug}",
                timeout=min(2.0, timeout),
            )
            cam_data = parse_cambridge_english_html(cam_html)
            for key, value in cam_data.items():
                if value and not merged.get(key):
                    merged[key] = value
            if cam_data:
                merged["ok"] = True
        except Exception:
            pass

    # 5. English Wiktionary API for etymology / prefix + root + suffix breakdown + Vietnamese gloss
    try:
        en_wiki_url = (
            "https://en.wiktionary.org/w/api.php?action=query&prop=revisions"
            f"&rvprop=content&format=json&titles={slug}"
        )
        en_wiki_raw = fetch_text(en_wiki_url, timeout=min(2.0, timeout))
        en_wiki_json = json.loads(en_wiki_raw)
        for page in en_wiki_json.get("query", {}).get("pages", {}).values():
            revs = page.get("revisions") or []
            if revs and isinstance(revs[0], dict):
                wt = str(revs[0].get("*") or "")
                etym_data = parse_wiktionary_etymology(wt, word, "en")
                for k, v in etym_data.items():
                    if v and not merged.get(k):
                        merged[k] = v
                vi_matches = re.findall(r"\{\{t\+?\s*\|\s*vi\s*\|\s*([^|}]+)", wt)
                if vi_matches and not merged.get("meaningVi"):
                    unique_vi: list[str] = []
                    for vm in vi_matches:
                        clean_vm = vm.strip()
                        if clean_vm and clean_vm not in unique_vi:
                            unique_vi.append(clean_vm)
                    if unique_vi:
                        merged["meaningVi"] = ", ".join(unique_vi[:4])
    except Exception:
        pass

    return merged


def map_dwds_frequency_to_cefr(freq_level: int | str | None, word: str) -> str:
    try:
        f = int(freq_level)
    except (TypeError, ValueError):
        return ""
    # DWDS frequency scale: 6 (highest, A1) down to 0/1 (rare, C2)
    if f >= 6:
        return "A1"
    if f == 5:
        return "A2"
    if f == 4:
        return "B1"
    if f == 3:
        return "B2"
    if f == 2:
        return "C1"
    return "C2"


def clean_wikitext_line(line: str) -> str:
    cleaned = re.sub(r"^:\[[0-9a-z,\s–-]+\]\s*", "", line)
    cleaned = re.sub(r"<ref[^>]*>.*?</ref>", "", cleaned, flags=re.S | re.I)
    cleaned = re.sub(r"<ref[^/]*/>", "", cleaned, flags=re.I)
    cleaned = re.sub(r"<[^>]+>", " ", cleaned)
    cleaned = re.sub(r"\{\{[^}]+\}\}", "", cleaned)
    cleaned = re.sub(r"\[\[(?:[^|\]]*\|)?([^\]]+)\]\]", r"\1", cleaned)
    cleaned = re.sub(r"''+", "", cleaned)
    cleaned = html.unescape(cleaned)
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    return cleaned


def parse_german_wiktionary_wikitext(wikitext: str) -> dict:
    result: dict = {}
    genus_match = re.search(r"\{\{Substantiv-Tabelle|\{\{Deutsch Substantiv Übersicht.*?\bGenus\s*=\s*([mfn])", wikitext, re.S)
    if not genus_match:
        genus_match = re.search(r"\{\{Wortart\|Substantiv\|Deutsch\}\}\s*,\s*\{\{([mfn])\}\}", wikitext, re.S)
    if genus_match:
        g = genus_match.group(1).lower()
        result["article"] = "der" if g == "m" else ("die" if g == "f" else "das")
        result["pos"] = "noun"
    elif re.search(r"\{\{Wortart\|Adjektiv\|Deutsch\}\}", wikitext):
        result["pos"] = "adj"
    elif re.search(r"\{\{Wortart\|Verb\|Deutsch\}\}", wikitext):
        result["pos"] = "verb"
    elif re.search(r"\{\{Wortart\|Adverb\|Deutsch\}\}", wikitext):
        result["pos"] = "adv"

    pl_match = re.search(r"\|Nominativ Plural(?:\s*1)?\s=\s*([^\n|]+)", wikitext)
    if pl_match:
        pl = pl_match.group(1).strip()
        if pl and not pl.startswith("{{"):
            result["plural"] = pl

    ipa_match = re.search(r"\{\{Lautschrift\|([^}|]+)\}\}", wikitext)
    if ipa_match:
        result["phonetic"] = f"/{ipa_match.group(1).strip()}/"

    bed_section = re.search(r"\{\{Bedeutungen\}\}\s*\n((?::\[[^\n]+\n?)+)", wikitext)
    if bed_section:
        first_line = bed_section.group(1).splitlines()[0]
        cleaned = clean_wikitext_line(first_line)
        if cleaned:
            result["meaning"] = cleaned

    bsp_section = re.search(r"\{\{Beispiele\}\}\s*\n((?::\[[^\n]+\n?)+)", wikitext)
    if bsp_section:
        first_ex = bsp_section.group(1).splitlines()[0]
        cleaned_ex = clean_wikitext_line(first_ex)
        if cleaned_ex:
            result["example"] = cleaned_ex

    syn_section = re.search(r"\{\{Synonyme\}\}\s*\n((?::\[[^\n]+\n?)+)", wikitext)
    if syn_section:
        syn_body = re.sub(r"\([^()\n]*\)[ \t]*:?|''[^'\n]*?:''|''[^'\n]*?''[ \t]*:", "", syn_section.group(1))
        syns = re.findall(r"\[\[(?:[^|\]]*\|)?([^\]]+)\]\](?![a-zäöüß]|[') \t]*:)", syn_body)
        if syns:
            result["synonyms"] = [s.strip() for s in syns[:5] if s.strip()]

    ant_section = re.search(r"\{\{Gegenwörter\}\}\s*\n((?::\[[^\n]+\n?)+)", wikitext)
    if ant_section:
        ant_body = re.sub(r"\([^()\n]*\)[ \t]*:?|''[^'\n]*?:''|''[^'\n]*?''[ \t]*:", "", ant_section.group(1))
        ants = re.findall(r"\[\[(?:[^|\]]*\|)?([^\]]+)\]\](?![a-zäöüß]|[') \t]*:)", ant_body)
        if ants:
            result["antonyms"] = [a.strip() for a in ants[:5] if a.strip()]

    etym_de = parse_wiktionary_etymology(wikitext, "de")
    for k, v in etym_de.items():
        if v and not result.get(k):
            result[k] = v

    return result


def parse_dwds_wortbildung(page_html: str) -> dict:
    if not page_html:
        return {}
    block_match = re.search(
        r"(?:Wortbildung|Wortzerlegung|Zerlegung).*?(?:</dd>|</div>|</section>)",
        page_html,
        re.S | re.I,
    )
    segment = block_match.group(0) if block_match else page_html
    tokens: list[str] = []
    for m_link in re.finditer(r"<a[^>]*>([^<]+)</a>", segment):
        tok = clean_html_snippet(m_link.group(1)).strip(" ↑→·")
        if tok and tok.lower() not in ("wortbildung", "zerlegung", "wortzerlegung", "mehr"):
            tokens.append(tok)
    if not tokens and block_match:
        plain = clean_html_snippet(segment)
        plain = re.sub(r"^(?:Wortbildung|Wortzerlegung|Zerlegung)\s*:?\s*", "", plain, flags=re.I)
        if "+" in plain:
            tokens = [t.strip(" ↑→·,;") for t in plain.split("+") if t.strip(" ↑→·,;")]
    morphology: list[dict] = []
    for tok in tokens[:5]:
        kind = "prefix" if tok.endswith("-") else ("suffix" if tok.startswith("-") else "root")
        meaning = ""
        bare = tok.strip("-").lower()
        if kind == "prefix":
            for pr, _, m_str in DE_PREFIX_TABLE:
                if pr == bare:
                    meaning = m_str
                    break
        elif kind == "suffix":
            for sr, _, m_str in DE_SUFFIX_TABLE:
                if sr == bare:
                    meaning = m_str
                    break
        morphology.append({"part": tok, "kind": kind, "meaning": meaning})
    if not morphology:
        return {}
    morph_text = format_morphology(morphology)
    return {
        "morphology": morphology,
        "morphologyText": morph_text,
        "etymology": f"DWDS Wortbildung: {morph_text}",
    }


def lookup_german_online(word: str, timeout: float = 3.5) -> dict:
    clean_word = re.sub(r"^(der|die|das|sich)\s+", "", word.strip(), flags=re.IGNORECASE).strip()
    slug = urllib.parse.quote(clean_word)
    merged: dict = {
        "ok": False,
        "word": clean_word,
        "language": "de",
        "level": "",
        "levelSource": "",
        "pos": "",
        "phonetic": "",
        "article": "",
        "plural": "",
        "meaning": "",
        "example": "",
        "synonyms": [],
        "antonyms": [],
        "morphology": [],
        "morphologyText": "",
        "etymology": "",
    }

    # 1. DWDS Snippet API + Frequency API + DWDS Wortbildung/Zerlegung
    try:
        snippet_raw = fetch_text(f"https://www.dwds.de/api/wb/snippet/?q={slug}", timeout=timeout)
        snippets = json.loads(snippet_raw)
        if isinstance(snippets, list) and snippets:
            first = snippets[0]
            lemma = str(first.get("lemma") or clean_word).strip()
            merged["word"] = lemma
            wortart = str(first.get("wortart") or "")
            if "Maskulinum" in wortart:
                merged["article"] = "der"
                merged["pos"] = "noun"
            elif "Femininum" in wortart:
                merged["article"] = "die"
                merged["pos"] = "noun"
            elif "Neutrum" in wortart:
                merged["article"] = "das"
                merged["pos"] = "noun"
            elif "Verb" in wortart:
                merged["pos"] = "verb"
            elif "Adjektiv" in wortart:
                merged["pos"] = "adj"
            elif "Adverb" in wortart:
                merged["pos"] = "adv"
            merged["ok"] = True
    except Exception:
        pass

    try:
        freq_raw = fetch_text(
            f"https://www.dwds.de/api/frequency/?q={urllib.parse.quote(merged['word'])}",
            timeout=timeout,
        )
        freq_json = json.loads(freq_raw)
        if isinstance(freq_json, dict) and "frequency" in freq_json:
            lvl = map_dwds_frequency_to_cefr(freq_json.get("frequency"), merged["word"])
            if lvl:
                merged["level"] = lvl
                merged["levelSource"] = "DWDS Frequency / Goethe Profile"
                merged["ok"] = True
    except Exception:
        pass

    try:
        dwds_html = fetch_text(
            f"https://www.dwds.de/wb/{urllib.parse.quote(merged['word'])}",
            timeout=min(2.0, timeout),
        )
        dwds_wb = parse_dwds_wortbildung(dwds_html)
        for k, v in dwds_wb.items():
            if v and not merged.get(k):
                merged[k] = v
    except Exception:
        pass

    # 2. German Wiktionary API for IPA, Plural, Bedeutungen, Beispiele, Synonyme, Gegenwörter
    try:
        wiki_url = (
            "https://de.wiktionary.org/w/api.php?action=query&prop=revisions"
            f"&rvprop=content&format=json&titles={urllib.parse.quote(merged['word'])}"
        )
        wiki_raw = fetch_text(wiki_url, timeout=timeout)
        wiki_json = json.loads(wiki_raw)
        pages = wiki_json.get("query", {}).get("pages", {})
        for page in pages.values():
            revs = page.get("revisions") or []
            if revs and isinstance(revs[0], dict):
                wikitext = str(revs[0].get("*") or "")
                parsed_wiki = parse_german_wiktionary_wikitext(wikitext)
                for key, value in parsed_wiki.items():
                    if value and not merged.get(key):
                        merged[key] = value
                if parsed_wiki:
                    merged["ok"] = True
    except Exception:
        pass

    # 3. English Wiktionary API for concise English gloss of German headword
    try:
        en_wiki_url = (
            "https://en.wiktionary.org/w/api.php?action=query&prop=revisions"
            f"&rvprop=content&format=json&titles={urllib.parse.quote(merged['word'])}"
        )
        en_wiki_raw = fetch_text(en_wiki_url, timeout=min(2.0, timeout))
        en_wiki_json = json.loads(en_wiki_raw)
        for page in en_wiki_json.get("query", {}).get("pages", {}).values():
            revs = page.get("revisions") or []
            if revs and isinstance(revs[0], dict):
                wt = str(revs[0].get("*") or "")
                de_sec = re.search(r"==\s*German\s*==(.*?)(?:\n==[^=]|$)", wt, re.S)
                if de_sec:
                    gloss_match = re.search(r"\n#\s+([^\n#*;:]+)", de_sec.group(1))
                    if gloss_match:
                        en_gloss = clean_wikitext_line(gloss_match.group(1))
                        if en_gloss:
                            if merged["meaning"] and en_gloss.lower() not in merged["meaning"].lower():
                                merged["meaning"] = f"{en_gloss} — {merged['meaning']}"
                            elif not merged["meaning"]:
                                merged["meaning"] = en_gloss
                            merged["ok"] = True
    except Exception:
        pass

    if merged["article"] and merged["article"] in ("der", "die", "das") and merged.get("pos") in ("", "noun"):
        merged["displayTerm"] = f"{merged['article']} {merged['word']}"
    else:
        if merged.get("pos") not in ("", "noun") and merged.get("article") in ("der", "die", "das"):
            merged["article"] = ""
        merged["displayTerm"] = merged["word"]

    return merged


OFFLINE_EN_LEXICON = {
    "book": ("A1", "Oxford 3000 / Cambridge EVP", "noun"),
    "water": ("A1", "Oxford 3000 / Cambridge EVP", "noun"),
    "learn": ("A1", "Oxford 3000 / Cambridge EVP", "verb"),
    "understand": ("A1", "Oxford 3000 / Cambridge EVP", "verb"),
    "available": ("A2", "Oxford 3000 / Cambridge EVP", "adj"),
    "experience": ("A2", "Oxford 3000 / Cambridge EVP", "noun"),
    "improve": ("A2", "Oxford 3000 / Cambridge EVP", "verb"),
    "schedule": ("A2", "Oxford 3000 / Cambridge EVP", "noun"),
    "achieve": ("B1", "Oxford 3000 / Cambridge EVP", "verb"),
    "consequence": ("B1", "Oxford 3000 / Cambridge EVP", "noun"),
    "essential": ("B1", "Oxford 3000 / Cambridge EVP", "adj"),
    "perspective": ("B2", "Oxford 3000 / Cambridge EVP", "noun"),
    "sustainable": ("B2", "Oxford 3000 / Cambridge EVP", "adj"),
    "inevitable": ("B2", "Oxford 3000 / Cambridge EVP", "adj"),
    "comprehensive": ("B2", "Oxford 3000 / Cambridge EVP", "adj"),
    "ambiguous": ("B2", "Oxford 5000 / Cambridge EVP", "adj"),
    "reluctant": ("B2", "Oxford 5000 / Cambridge EVP", "adj"),
    "ubiquitous": ("C1", "Cambridge EVP / Oxford 5000", "adj"),
    "ephemeral": ("C1", "Cambridge EVP", "adj"),
    "resilient": ("C1", "Oxford 5000 / Cambridge EVP", "adj"),
    "meticulous": ("C1", "Cambridge EVP", "adj"),
    "eloquent": ("C1", "Cambridge EVP", "adj"),
    "pragmatic": ("C1", "Oxford 5000 / Cambridge EVP", "adj"),
    "scrutinize": ("C1", "Cambridge EVP", "verb"),
    "alleviate": ("C1", "Oxford 5000 / Cambridge EVP", "verb"),
    "corroborate": ("C2", "Cambridge EVP", "verb"),
    "quintessential": ("C2", "Cambridge EVP", "adj"),
    "obfuscate": ("C2", "Cambridge EVP", "verb"),
    "serendipity": ("C2", "Cambridge EVP", "noun"),
    "allot": ("C1", "4000 Essential English Words Vol. 5", "verb"),
    "appall": ("C1", "4000 Essential English Words Vol. 5", "verb"),
    "cache": ("C2", "4000 Essential English Words Vol. 5", "noun"),
    "dearth": ("C2", "4000 Essential English Words Vol. 5", "noun"),
    "deliberate": ("C1", "4000 Essential English Words Vol. 5", "adj"),
    "dire": ("C1", "4000 Essential English Words Vol. 5", "adj"),
    "elapse": ("C1", "4000 Essential English Words Vol. 5", "verb"),
    "empathy": ("B2", "4000 Essential English Words Vol. 5", "noun"),
    "fanciful": ("C2", "4000 Essential English Words Vol. 5", "adj"),
    "gripe": ("C2", "4000 Essential English Words Vol. 5", "verb"),
    "gruelling": ("C2", "4000 Essential English Words Vol. 5", "adj"),
    "mundane": ("C1", "4000 Essential English Words Vol. 5", "adj"),
    "opt": ("B2", "4000 Essential English Words Vol. 5", "verb"),
    "outrage": ("B2", "4000 Essential English Words Vol. 5", "noun"),
    "paltry": ("C2", "4000 Essential English Words Vol. 5", "adj"),
    "rectify": ("C1", "4000 Essential English Words Vol. 5", "verb"),
    "resourceful": ("C1", "4000 Essential English Words Vol. 5", "adj"),
    "sustenance": ("C2", "4000 Essential English Words Vol. 5", "noun"),
    "tedious": ("C1", "4000 Essential English Words Vol. 5", "adj"),
    "abbey": ("B2", "4000 Essential English Words Vol. 5", "noun"),
    "abundant": ("C1", "4000 Essential English Words Vol. 5", "adj"),
    "adjoin": ("C2", "4000 Essential English Words Vol. 5", "verb"),
    "ample": ("C1", "4000 Essential English Words Vol. 5", "adj"),
    "arid": ("C1", "4000 Essential English Words Vol. 5", "adj"),
    "deprive": ("C1", "4000 Essential English Words Vol. 5", "verb"),
    "drought": ("B2", "4000 Essential English Words Vol. 5", "noun"),
    "eligible": ("B2", "4000 Essential English Words Vol. 5", "adj"),
    "fast": ("B2", "4000 Essential English Words Vol. 5", "verb"),
    "grumble": ("C1", "4000 Essential English Words Vol. 5", "verb"),
    "inland": ("B2", "4000 Essential English Words Vol. 5", "adv"),
    "moisture": ("B2", "4000 Essential English Words Vol. 5", "noun"),
    "nonetheless": ("C1", "4000 Essential English Words Vol. 5", "adv"),
    "oath": ("C1", "4000 Essential English Words Vol. 5", "noun"),
    "prairie": ("C2", "4000 Essential English Words Vol. 5", "noun"),
    "ragged": ("C1", "4000 Essential English Words Vol. 5", "adj"),
    "rugged": ("C1", "4000 Essential English Words Vol. 5", "adj"),
    "scarce": ("C1", "4000 Essential English Words Vol. 5", "adj"),
    "speculate": ("C1", "4000 Essential English Words Vol. 5", "verb"),
    "analytic": ("C1", "4000 Essential English Words Vol. 5", "adj"),
    "assert": ("C1", "4000 Essential English Words Vol. 5", "verb"),
    "bachelor": ("B2", "4000 Essential English Words Vol. 5", "noun"),
    "calculus": ("C2", "4000 Essential English Words Vol. 5", "noun"),
    "celestial": ("C2", "4000 Essential English Words Vol. 5", "adj"),
    "cognitive": ("C1", "4000 Essential English Words Vol. 5", "adj"),
    "collision": ("B2", "4000 Essential English Words Vol. 5", "noun"),
    "competent": ("C1", "4000 Essential English Words Vol. 5", "adj"),
    "diploma": ("B1", "4000 Essential English Words Vol. 5", "noun"),
    "excel": ("C1", "4000 Essential English Words Vol. 5", "verb"),
    "geology": ("B2", "4000 Essential English Words Vol. 5", "noun"),
    "harness": ("C1", "4000 Essential English Words Vol. 5", "verb"),
    "intellect": ("C1", "4000 Essential English Words Vol. 5", "noun"),
    "keen": ("C1", "4000 Essential English Words Vol. 5", "adj"),
    "mythology": ("B2", "4000 Essential English Words Vol. 5", "noun"),
    "physiology": ("C1", "4000 Essential English Words Vol. 5", "noun"),
    "radioactive": ("B2", "4000 Essential English Words Vol. 5", "adj"),
    "relativity": ("C1", "4000 Essential English Words Vol. 5", "noun"),
    "sociology": ("B2", "4000 Essential English Words Vol. 5", "noun"),
    "theoretical": ("C1", "4000 Essential English Words Vol. 5", "adj"),
    "administrator": ("C1", "4000 Essential English Words Vol. 5", "noun"),
    "affluent": ("C1", "4000 Essential English Words Vol. 5", "adj"),
    "audit": ("B2", "4000 Essential English Words Vol. 5", "verb"),
    "automate": ("C1", "4000 Essential English Words Vol. 5", "verb"),
    "bribe": ("C1", "4000 Essential English Words Vol. 5", "verb"),
    "corrupt": ("C1", "4000 Essential English Words Vol. 5", "adj"),
    "dispose": ("C1", "4000 Essential English Words Vol. 5", "verb"),
    "headquarters": ("B2", "4000 Essential English Words Vol. 5", "noun"),
    "incentive": ("C1", "4000 Essential English Words Vol. 5", "noun"),
    "infrastructure": ("B2", "4000 Essential English Words Vol. 5", "noun"),
    "legislate": ("C2", "4000 Essential English Words Vol. 5", "verb"),
    "legitimate": ("C1", "4000 Essential English Words Vol. 5", "adj"),
    "manipulate": ("C1", "4000 Essential English Words Vol. 5", "verb"),
    "merchandise": ("C1", "4000 Essential English Words Vol. 5", "noun"),
    "retail": ("B2", "4000 Essential English Words Vol. 5", "noun"),
    "revenue": ("B2", "4000 Essential English Words Vol. 5", "noun"),
    "rubbish": ("B1", "4000 Essential English Words Vol. 5", "noun"),
    "subsidy": ("C1", "4000 Essential English Words Vol. 5", "noun"),
    "transaction": ("B2", "4000 Essential English Words Vol. 5", "noun"),
    "violate": ("C1", "4000 Essential English Words Vol. 5", "verb"),
    "important": ("A1", "Oxford 3000", "adj"),
    "environment": ("B1", "Oxford 3000", "noun"),
    "controversial": ("B2", "Oxford 3000", "adj"),
    "paradigm": ("C2", "Oxford 5000", "noun"),
}

OFFLINE_DE_LEXICON = {
    "buch": ("A1", "Goethe-Zertifikat A1", "noun", "das", "Bücher"),
    "wasser": ("A1", "Goethe-Zertifikat A1", "noun", "das", "—"),
    "haus": ("A1", "Goethe-Zertifikat A1", "noun", "das", "Häuser"),
    "bahnhof": ("A1", "Goethe-Zertifikat A1", "noun", "der", "Bahnhöfe"),
    "lernen": ("A1", "Goethe-Zertifikat A1", "verb", "", ""),
    "verstehen": ("A1", "Goethe-Zertifikat A1", "verb", "", ""),
    "erfahrung": ("A2", "Goethe-Zertifikat A2", "noun", "die", "Erfahrungen"),
    "sehenswürdigkeit": ("A2", "Goethe-Zertifikat A2", "noun", "die", "Sehenswürdigkeiten"),
    "ziel": ("A2", "Goethe-Zertifikat A2", "noun", "das", "Ziele"),
    "vereinbaren": ("A2", "Goethe-Zertifikat A2", "verb", "", ""),
    "zeitraum": ("B1", "Goethe-Zertifikat B1", "noun", "der", "Zeiträume"),
    "zusammenhang": ("B1", "Goethe-Zertifikat B1", "noun", "der", "Zusammenhänge"),
    "entscheiden": ("B1", "Goethe-Zertifikat B1", "verb", "", ""),
    "entscheidung": ("B1", "Goethe-Zertifikat B1", "noun", "die", "Entscheidungen"),
    "herausforderung": ("B1", "Goethe-Zertifikat B1", "noun", "die", "Herausforderungen"),
    "umwelt": ("B1", "Goethe-Zertifikat B1", "noun", "die", "Umwelten"),
    "verantwortung": ("B1", "Goethe-Zertifikat B1", "noun", "die", "Verantwortungen"),
    "nachhaltig": ("B2", "Goethe-Zertifikat B2", "adj", "", ""),
    "nachhaltigkeit": ("B2", "Goethe-Zertifikat B2", "noun", "die", "—"),
    "bewusstsein": ("B2", "Goethe-Zertifikat B2", "noun", "das", "—"),
    "erkenntnis": ("B2", "Goethe-Zertifikat B2", "noun", "die", "Erkenntnisse"),
    "voraussetzung": ("B2", "Goethe-Zertifikat B2", "noun", "die", "Voraussetzungen"),
    "überblick": ("B2", "Goethe-Zertifikat B2", "noun", "der", "Überblicke"),
    "auseinandersetzen": ("C1", "DWDS / Goethe C1", "verb", "sich", ""),
    "gewährleisten": ("C1", "DWDS / Goethe C1", "verb", "", ""),
    "widerspiegeln": ("C1", "DWDS / Goethe C1", "verb", "", ""),
    "beeinträchtigen": ("C1", "DWDS / Goethe C1", "verb", "", ""),
    "gegebenheit": ("C1", "DWDS / Goethe C1", "noun", "die", "Gegebenheiten"),
    "wahrscheinlichkeit": ("C1", "DWDS / Goethe C1", "noun", "die", "Wahrscheinlichkeiten"),
    "unabdingbar": ("C2", "DWDS C2", "adj", "", ""),
    "befindlichkeit": ("C2", "DWDS C2", "noun", "die", "Befindlichkeiten"),
    "weitsicht": ("C2", "DWDS C2", "noun", "die", "—"),
    "unwiderruflich": ("C2", "DWDS C2", "adj", "", ""),
    "fingerspitzengefühl": ("C2", "DWDS C2", "noun", "das", "—"),
}



OFFLINE_EN_MORPHOLOGY = {
    "book": [
        {
            "part": "bok (boks)",
            "kind": "root",
            "meaning": "beechwood tablet, written volume"
        }
    ],
    "water": [
        {
            "part": "wat- (wed-)",
            "kind": "root",
            "meaning": "wet, flowing liquid"
        },
        {
            "part": "-er",
            "kind": "suffix",
            "meaning": "substance noun"
        }
    ],
    "learn": [
        {
            "part": "leorn (leis-)",
            "kind": "root",
            "meaning": "follow a track, acquire knowledge"
        }
    ],
    "understand": [
        {
            "part": "under-",
            "kind": "prefix",
            "meaning": "among, closely between"
        },
        {
            "part": "stand",
            "kind": "root",
            "meaning": "stand firm, grasp mentally"
        }
    ],
    "available": [
        {
            "part": "a- (ad-)",
            "kind": "prefix",
            "meaning": "to"
        },
        {
            "part": "vail (valere)",
            "kind": "root",
            "meaning": "be strong, be of worth"
        },
        {
            "part": "-able",
            "kind": "suffix",
            "meaning": "able to be"
        }
    ],
    "experience": [
        {
            "part": "ex-",
            "kind": "prefix",
            "meaning": "out of"
        },
        {
            "part": "peri (periri)",
            "kind": "root",
            "meaning": "try, test, risk"
        },
        {
            "part": "-ence",
            "kind": "suffix",
            "meaning": "state, result"
        }
    ],
    "improve": [
        {
            "part": "im- (en-)",
            "kind": "prefix",
            "meaning": "into"
        },
        {
            "part": "prove (prode)",
            "kind": "root",
            "meaning": "profit, advantage, make better"
        }
    ],
    "schedule": [
        {
            "part": "sched (schida)",
            "kind": "root",
            "meaning": "strip of papyrus"
        },
        {
            "part": "-ule (-ula)",
            "kind": "suffix",
            "meaning": "diminutive slip/list"
        }
    ],
    "achieve": [
        {
            "part": "a- (ad-)",
            "kind": "prefix",
            "meaning": "to, toward"
        },
        {
            "part": "chieve (caput)",
            "kind": "root",
            "meaning": "head, bring to completion"
        }
    ],
    "consequence": [
        {
            "part": "con- (com-)",
            "kind": "prefix",
            "meaning": "together, with"
        },
        {
            "part": "sequ (sequi)",
            "kind": "root",
            "meaning": "follow"
        },
        {
            "part": "-ence",
            "kind": "suffix",
            "meaning": "result, state"
        }
    ],
    "essential": [
        {
            "part": "ess (esse)",
            "kind": "root",
            "meaning": "to be, core essence"
        },
        {
            "part": "-ent",
            "kind": "suffix",
            "meaning": "being"
        },
        {
            "part": "-ial",
            "kind": "suffix",
            "meaning": "relating to"
        }
    ],
    "perspective": [
        {
            "part": "per-",
            "kind": "prefix",
            "meaning": "through"
        },
        {
            "part": "spect (specere)",
            "kind": "root",
            "meaning": "look, see"
        },
        {
            "part": "-ive",
            "kind": "suffix",
            "meaning": "relating to"
        }
    ],
    "sustainable": [
        {
            "part": "sus- (sub-)",
            "kind": "prefix",
            "meaning": "up from below"
        },
        {
            "part": "tain (tenere)",
            "kind": "root",
            "meaning": "hold, support"
        },
        {
            "part": "-able",
            "kind": "suffix",
            "meaning": "able to be"
        }
    ],
    "inevitable": [
        {
            "part": "in-",
            "kind": "prefix",
            "meaning": "not"
        },
        {
            "part": "e- (ex-)",
            "kind": "prefix",
            "meaning": "out"
        },
        {
            "part": "vit (vitare)",
            "kind": "root",
            "meaning": "shun, avoid"
        },
        {
            "part": "-able",
            "kind": "suffix",
            "meaning": "able to be"
        }
    ],
    "comprehensive": [
        {
            "part": "com-",
            "kind": "prefix",
            "meaning": "together, completely"
        },
        {
            "part": "prehens (prehendere)",
            "kind": "root",
            "meaning": "grasp, seize"
        },
        {
            "part": "-ive",
            "kind": "suffix",
            "meaning": "tending to"
        }
    ],
    "ambiguous": [
        {
            "part": "ambi-",
            "kind": "prefix",
            "meaning": "both ways, around"
        },
        {
            "part": "ig (agere)",
            "kind": "root",
            "meaning": "drive, lead"
        },
        {
            "part": "-uous (-ous)",
            "kind": "suffix",
            "meaning": "characterized by"
        }
    ],
    "reluctant": [
        {
            "part": "re-",
            "kind": "prefix",
            "meaning": "against, back"
        },
        {
            "part": "luct (luctari)",
            "kind": "root",
            "meaning": "struggle, wrestle"
        },
        {
            "part": "-ant",
            "kind": "suffix",
            "meaning": "being"
        }
    ],
    "ubiquitous": [
        {
            "part": "ubique",
            "kind": "root",
            "meaning": "everywhere (where + ever)"
        },
        {
            "part": "-ous",
            "kind": "suffix",
            "meaning": "full of, characterized by"
        }
    ],
    "ephemeral": [
        {
            "part": "epi-",
            "kind": "prefix",
            "meaning": "upon, for"
        },
        {
            "part": "hemera",
            "kind": "root",
            "meaning": "a single day"
        },
        {
            "part": "-al",
            "kind": "suffix",
            "meaning": "relating to"
        }
    ],
    "resilient": [
        {
            "part": "re-",
            "kind": "prefix",
            "meaning": "back"
        },
        {
            "part": "sili (salire)",
            "kind": "root",
            "meaning": "leap, spring"
        },
        {
            "part": "-ent",
            "kind": "suffix",
            "meaning": "tending to"
        }
    ],
    "meticulous": [
        {
            "part": "metu (metus)",
            "kind": "root",
            "meaning": "fear, carefulness"
        },
        {
            "part": "-culous (-ous)",
            "kind": "suffix",
            "meaning": "full of"
        }
    ],
    "eloquent": [
        {
            "part": "e- (ex-)",
            "kind": "prefix",
            "meaning": "out"
        },
        {
            "part": "loqu (loqui)",
            "kind": "root",
            "meaning": "speak"
        },
        {
            "part": "-ent",
            "kind": "suffix",
            "meaning": "characterized by"
        }
    ],
    "pragmatic": [
        {
            "part": "pragma (prassein)",
            "kind": "root",
            "meaning": "deed, practical action"
        },
        {
            "part": "-tic (-ic)",
            "kind": "suffix",
            "meaning": "pertaining to"
        }
    ],
    "scrutinize": [
        {
            "part": "scrutini (scruta)",
            "kind": "root",
            "meaning": "search thoroughly, examine"
        },
        {
            "part": "-ize",
            "kind": "suffix",
            "meaning": "make, perform"
        }
    ],
    "alleviate": [
        {
            "part": "al- (ad-)",
            "kind": "prefix",
            "meaning": "to"
        },
        {
            "part": "levi (levis)",
            "kind": "root",
            "meaning": "light in weight, ease"
        },
        {
            "part": "-ate",
            "kind": "suffix",
            "meaning": "make, cause"
        }
    ],
    "corroborate": [
        {
            "part": "cor- (com-)",
            "kind": "prefix",
            "meaning": "together, fully"
        },
        {
            "part": "robor (robur)",
            "kind": "root",
            "meaning": "oak, strength"
        },
        {
            "part": "-ate",
            "kind": "suffix",
            "meaning": "make, strengthen"
        }
    ],
    "quintessential": [
        {
            "part": "quint (quintus)",
            "kind": "prefix",
            "meaning": "fifth, highest"
        },
        {
            "part": "essent (esse)",
            "kind": "root",
            "meaning": "essence, being"
        },
        {
            "part": "-ial",
            "kind": "suffix",
            "meaning": "relating to"
        }
    ],
    "obfuscate": [
        {
            "part": "ob-",
            "kind": "prefix",
            "meaning": "over, against"
        },
        {
            "part": "fusc (fuscus)",
            "kind": "root",
            "meaning": "dark, obscure"
        },
        {
            "part": "-ate",
            "kind": "suffix",
            "meaning": "make, cause"
        }
    ],
    "serendipity": [
        {
            "part": "Serendip",
            "kind": "root",
            "meaning": "ancient Sri Lanka (fable of lucky princes)"
        },
        {
            "part": "-ity",
            "kind": "suffix",
            "meaning": "quality, state"
        }
    ],
    "allot": [
        {
            "part": "al- (ad-)",
            "kind": "prefix",
            "meaning": "to, toward"
        },
        {
            "part": "lot",
            "kind": "root",
            "meaning": "portion, share"
        }
    ],
    "appall": [
        {
            "part": "ap- (ad-)",
            "kind": "prefix",
            "meaning": "to, toward"
        },
        {
            "part": "pall (pallere)",
            "kind": "root",
            "meaning": "grow pale, terrify"
        }
    ],
    "cache": [
        {
            "part": "cacher (coactare)",
            "kind": "root",
            "meaning": "press together, hide away"
        }
    ],
    "dearth": [
        {
            "part": "dear (deore)",
            "kind": "root",
            "meaning": "costly, scarce"
        },
        {
            "part": "-th",
            "kind": "suffix",
            "meaning": "state, condition"
        }
    ],
    "deliberate": [
        {
            "part": "de-",
            "kind": "prefix",
            "meaning": "completely"
        },
        {
            "part": "librare (libra)",
            "kind": "root",
            "meaning": "weigh, balance"
        },
        {
            "part": "-ate",
            "kind": "suffix",
            "meaning": "characterized by"
        }
    ],
    "dire": [
        {
            "part": "dirus",
            "kind": "root",
            "meaning": "fearful, ominous, dreadful"
        }
    ],
    "elapse": [
        {
            "part": "e- (ex-)",
            "kind": "prefix",
            "meaning": "out, away"
        },
        {
            "part": "laps (labi)",
            "kind": "root",
            "meaning": "glide, slip, pass"
        }
    ],
    "empathy": [
        {
            "part": "em- (en-)",
            "kind": "prefix",
            "meaning": "in, into"
        },
        {
            "part": "path (pathos)",
            "kind": "root",
            "meaning": "feeling, emotion"
        },
        {
            "part": "-y",
            "kind": "suffix",
            "meaning": "quality, state"
        }
    ],
    "fanciful": [
        {
            "part": "fancy (phantasia)",
            "kind": "root",
            "meaning": "imagination, fantasy"
        },
        {
            "part": "-ful",
            "kind": "suffix",
            "meaning": "full of"
        }
    ],
    "gripe": [
        {
            "part": "gripan",
            "kind": "root",
            "meaning": "clutch, pinch, complain"
        }
    ],
    "gruelling": [
        {
            "part": "gruel",
            "kind": "root",
            "meaning": "exhaust, punish severely"
        },
        {
            "part": "-ing",
            "kind": "suffix",
            "meaning": "causing, participial adj"
        }
    ],
    "mundane": [
        {
            "part": "mund (mundus)",
            "kind": "root",
            "meaning": "world, earthly"
        },
        {
            "part": "-ane",
            "kind": "suffix",
            "meaning": "belonging to"
        }
    ],
    "opt": [
        {
            "part": "opt (optare)",
            "kind": "root",
            "meaning": "choose, wish, select"
        }
    ],
    "outrage": [
        {
            "part": "outre (ultra)",
            "kind": "prefix",
            "meaning": "beyond bounds"
        },
        {
            "part": "-age",
            "kind": "suffix",
            "meaning": "action, condition"
        }
    ],
    "paltry": [
        {
            "part": "palt",
            "kind": "root",
            "meaning": "rag, scrap, worthless thing"
        },
        {
            "part": "-ry",
            "kind": "suffix",
            "meaning": "characterized by"
        }
    ],
    "rectify": [
        {
            "part": "rect (rectus)",
            "kind": "root",
            "meaning": "straight, right"
        },
        {
            "part": "-ify",
            "kind": "suffix",
            "meaning": "make, cause to be"
        }
    ],
    "resourceful": [
        {
            "part": "re-",
            "kind": "prefix",
            "meaning": "again, back"
        },
        {
            "part": "source (surgere)",
            "kind": "root",
            "meaning": "rise, spring forth"
        },
        {
            "part": "-ful",
            "kind": "suffix",
            "meaning": "full of, ingenious"
        }
    ],
    "sustenance": [
        {
            "part": "sus- (sub-)",
            "kind": "prefix",
            "meaning": "up from below"
        },
        {
            "part": "ten (tenere)",
            "kind": "root",
            "meaning": "hold, support"
        },
        {
            "part": "-ance",
            "kind": "suffix",
            "meaning": "state, means of"
        }
    ],
    "tedious": [
        {
            "part": "tedi (taedium)",
            "kind": "root",
            "meaning": "weariness, boredom"
        },
        {
            "part": "-ous",
            "kind": "suffix",
            "meaning": "full of"
        }
    ],
    "abbey": [
        {
            "part": "abba",
            "kind": "root",
            "meaning": "father, abbot"
        },
        {
            "part": "-ey (-ia)",
            "kind": "suffix",
            "meaning": "place, jurisdiction"
        }
    ],
    "abundant": [
        {
            "part": "ab-",
            "kind": "prefix",
            "meaning": "from, away"
        },
        {
            "part": "und (unda)",
            "kind": "root",
            "meaning": "wave, overflow"
        },
        {
            "part": "-ant",
            "kind": "suffix",
            "meaning": "being, characterized by"
        }
    ],
    "adjoin": [
        {
            "part": "ad-",
            "kind": "prefix",
            "meaning": "to, toward"
        },
        {
            "part": "join (jungere)",
            "kind": "root",
            "meaning": "connect, link together"
        }
    ],
    "ample": [
        {
            "part": "amplus",
            "kind": "root",
            "meaning": "large, spacious, abundant"
        }
    ],
    "arid": [
        {
            "part": "ar (arere)",
            "kind": "root",
            "meaning": "be dry, parched"
        },
        {
            "part": "-id",
            "kind": "suffix",
            "meaning": "characterized by"
        }
    ],
    "deprive": [
        {
            "part": "de-",
            "kind": "prefix",
            "meaning": "completely, away"
        },
        {
            "part": "priv (privare)",
            "kind": "root",
            "meaning": "strip, take away"
        }
    ],
    "drought": [
        {
            "part": "drug (dragan)",
            "kind": "root",
            "meaning": "dry, parched"
        },
        {
            "part": "-th (-t)",
            "kind": "suffix",
            "meaning": "state, condition"
        }
    ],
    "eligible": [
        {
            "part": "e- (ex-)",
            "kind": "prefix",
            "meaning": "out"
        },
        {
            "part": "lig (legere)",
            "kind": "root",
            "meaning": "choose, select"
        },
        {
            "part": "-ible",
            "kind": "suffix",
            "meaning": "able to be"
        }
    ],
    "fast": [
        {
            "part": "fastan",
            "kind": "root",
            "meaning": "hold firmly, abstain from food"
        }
    ],
    "grumble": [
        {
            "part": "grum",
            "kind": "root",
            "meaning": "murmur, growl low"
        },
        {
            "part": "-ble (-le)",
            "kind": "suffix",
            "meaning": "frequentative action"
        }
    ],
    "inland": [
        {
            "part": "in-",
            "kind": "prefix",
            "meaning": "within, inside"
        },
        {
            "part": "land",
            "kind": "root",
            "meaning": "interior territory"
        }
    ],
    "moisture": [
        {
            "part": "moist (mucidus)",
            "kind": "root",
            "meaning": "slightly wet, damp"
        },
        {
            "part": "-ure",
            "kind": "suffix",
            "meaning": "state, result"
        }
    ],
    "nonetheless": [
        {
            "part": "none",
            "kind": "prefix",
            "meaning": "not at all"
        },
        {
            "part": "the",
            "kind": "root",
            "meaning": "by that much"
        },
        {
            "part": "-less",
            "kind": "suffix",
            "meaning": "less, in spite of that"
        }
    ],
    "oath": [
        {
            "part": "ath (aito-)",
            "kind": "root",
            "meaning": "solemn vow, sworn pledge"
        }
    ],
    "prairie": [
        {
            "part": "prat (pratum)",
            "kind": "root",
            "meaning": "meadow, grassland"
        },
        {
            "part": "-rie (-aria)",
            "kind": "suffix",
            "meaning": "expanse, domain"
        }
    ],
    "ragged": [
        {
            "part": "rag",
            "kind": "root",
            "meaning": "torn cloth, tatter"
        },
        {
            "part": "-ed",
            "kind": "suffix",
            "meaning": "having, characterized by"
        }
    ],
    "rugged": [
        {
            "part": "rug",
            "kind": "root",
            "meaning": "rough, uneven rock"
        },
        {
            "part": "-ed",
            "kind": "suffix",
            "meaning": "characterized by"
        }
    ],
    "scarce": [
        {
            "part": "ex-",
            "kind": "prefix",
            "meaning": "out"
        },
        {
            "part": "carpsus (carpere)",
            "kind": "root",
            "meaning": "plucked out, restricted"
        }
    ],
    "speculate": [
        {
            "part": "specul (specere)",
            "kind": "root",
            "meaning": "look, observe, spy"
        },
        {
            "part": "-ate",
            "kind": "suffix",
            "meaning": "perform, form theory"
        }
    ],
    "analytic": [
        {
            "part": "ana-",
            "kind": "prefix",
            "meaning": "up, throughout"
        },
        {
            "part": "lyt (lyein)",
            "kind": "root",
            "meaning": "loosen, break down"
        },
        {
            "part": "-ic",
            "kind": "suffix",
            "meaning": "pertaining to"
        }
    ],
    "assert": [
        {
            "part": "as- (ad-)",
            "kind": "prefix",
            "meaning": "to, toward"
        },
        {
            "part": "sert (serere)",
            "kind": "root",
            "meaning": "join, declare, claim"
        }
    ],
    "bachelor": [
        {
            "part": "baccalaur",
            "kind": "root",
            "meaning": "young knight, unmarried graduate"
        }
    ],
    "calculus": [
        {
            "part": "calc (calx)",
            "kind": "root",
            "meaning": "limestone, counting pebble"
        },
        {
            "part": "-ulus",
            "kind": "suffix",
            "meaning": "diminutive (small stone)"
        }
    ],
    "celestial": [
        {
            "part": "celest (caelum)",
            "kind": "root",
            "meaning": "heaven, sky"
        },
        {
            "part": "-ial",
            "kind": "suffix",
            "meaning": "relating to"
        }
    ],
    "cognitive": [
        {
            "part": "co- (com-)",
            "kind": "prefix",
            "meaning": "together, fully"
        },
        {
            "part": "gnit (gnoscere)",
            "kind": "root",
            "meaning": "know, perceive"
        },
        {
            "part": "-ive",
            "kind": "suffix",
            "meaning": "relating to"
        }
    ],
    "collision": [
        {
            "part": "col- (com-)",
            "kind": "prefix",
            "meaning": "together"
        },
        {
            "part": "lis (laedere)",
            "kind": "root",
            "meaning": "strike, dash"
        },
        {
            "part": "-ion",
            "kind": "suffix",
            "meaning": "act, state"
        }
    ],
    "competent": [
        {
            "part": "com-",
            "kind": "prefix",
            "meaning": "together"
        },
        {
            "part": "pet (petere)",
            "kind": "root",
            "meaning": "strive, be fit/suitable"
        },
        {
            "part": "-ent",
            "kind": "suffix",
            "meaning": "being, capable"
        }
    ],
    "diploma": [
        {
            "part": "diplo (diploun)",
            "kind": "root",
            "meaning": "double, fold paper"
        },
        {
            "part": "-ma",
            "kind": "suffix",
            "meaning": "official document"
        }
    ],
    "excel": [
        {
            "part": "ex-",
            "kind": "prefix",
            "meaning": "out, beyond"
        },
        {
            "part": "cel (cellere)",
            "kind": "root",
            "meaning": "rise high, surpass"
        }
    ],
    "geology": [
        {
            "part": "geo- (ge)",
            "kind": "prefix",
            "meaning": "earth, ground"
        },
        {
            "part": "-logy (logos)",
            "kind": "suffix",
            "meaning": "science, study of"
        }
    ],
    "harness": [
        {
            "part": "harneis",
            "kind": "root",
            "meaning": "gear, equip, utilize power"
        }
    ],
    "intellect": [
        {
            "part": "intel- (inter-)",
            "kind": "prefix",
            "meaning": "between, among"
        },
        {
            "part": "lect (legere)",
            "kind": "root",
            "meaning": "choose, discern, understand"
        }
    ],
    "keen": [
        {
            "part": "cene (kon-)",
            "kind": "root",
            "meaning": "sharp, wise, perceptive"
        }
    ],
    "mythology": [
        {
            "part": "myth (mythos)",
            "kind": "root",
            "meaning": "sacred story, legend"
        },
        {
            "part": "-logy (logos)",
            "kind": "suffix",
            "meaning": "study, collection of"
        }
    ],
    "physiology": [
        {
            "part": "physio- (physis)",
            "kind": "prefix",
            "meaning": "nature, living organism"
        },
        {
            "part": "-logy (logos)",
            "kind": "suffix",
            "meaning": "study of functions"
        }
    ],
    "radioactive": [
        {
            "part": "radio- (radius)",
            "kind": "prefix",
            "meaning": "ray, radiation"
        },
        {
            "part": "act (agere)",
            "kind": "root",
            "meaning": "drive, emit"
        },
        {
            "part": "-ive",
            "kind": "suffix",
            "meaning": "tending to"
        }
    ],
    "relativity": [
        {
            "part": "re-",
            "kind": "prefix",
            "meaning": "back"
        },
        {
            "part": "lat (ferre)",
            "kind": "root",
            "meaning": "carry, relate"
        },
        {
            "part": "-ivity",
            "kind": "suffix",
            "meaning": "state, principle"
        }
    ],
    "sociology": [
        {
            "part": "socio- (socius)",
            "kind": "prefix",
            "meaning": "companion, society"
        },
        {
            "part": "-logy (logos)",
            "kind": "suffix",
            "meaning": "science, study of"
        }
    ],
    "theoretical": [
        {
            "part": "theor (theoria)",
            "kind": "root",
            "meaning": "contemplation, speculation"
        },
        {
            "part": "-etical (-ical)",
            "kind": "suffix",
            "meaning": "pertaining to"
        }
    ],
    "administrator": [
        {
            "part": "ad-",
            "kind": "prefix",
            "meaning": "to, for"
        },
        {
            "part": "ministr (minister)",
            "kind": "root",
            "meaning": "serve, manage"
        },
        {
            "part": "-ator",
            "kind": "suffix",
            "meaning": "person who directs"
        }
    ],
    "affluent": [
        {
            "part": "af- (ad-)",
            "kind": "prefix",
            "meaning": "to, toward"
        },
        {
            "part": "flu (fluere)",
            "kind": "root",
            "meaning": "flow abundantly"
        },
        {
            "part": "-ent",
            "kind": "suffix",
            "meaning": "being, characterized by"
        }
    ],
    "audit": [
        {
            "part": "aud (audire)",
            "kind": "root",
            "meaning": "hear, officially examine"
        },
        {
            "part": "-it (-itus)",
            "kind": "suffix",
            "meaning": "official hearing/review"
        }
    ],
    "automate": [
        {
            "part": "auto-",
            "kind": "prefix",
            "meaning": "self"
        },
        {
            "part": "mat (men-)",
            "kind": "root",
            "meaning": "think, act on its own"
        },
        {
            "part": "-ate",
            "kind": "suffix",
            "meaning": "make, cause to be"
        }
    ],
    "bribe": [
        {
            "part": "briber",
            "kind": "root",
            "meaning": "piece of bread, illicit inducement"
        }
    ],
    "corrupt": [
        {
            "part": "cor- (com-)",
            "kind": "prefix",
            "meaning": "altogether, thoroughly"
        },
        {
            "part": "rupt (rumpere)",
            "kind": "root",
            "meaning": "break, destroy integrity"
        }
    ],
    "dispose": [
        {
            "part": "dis-",
            "kind": "prefix",
            "meaning": "apart, away"
        },
        {
            "part": "pos (ponere)",
            "kind": "root",
            "meaning": "put, place, arrange"
        }
    ],
    "headquarters": [
        {
            "part": "head",
            "kind": "prefix",
            "meaning": "chief, principal"
        },
        {
            "part": "quarter (quartarius)",
            "kind": "root",
            "meaning": "district, residence, station"
        },
        {
            "part": "-s",
            "kind": "suffix",
            "meaning": "collective noun"
        }
    ],
    "incentive": [
        {
            "part": "in-",
            "kind": "prefix",
            "meaning": "into, upon"
        },
        {
            "part": "cent (canere)",
            "kind": "root",
            "meaning": "strike up a tune, spur"
        },
        {
            "part": "-ive",
            "kind": "suffix",
            "meaning": "that which stimulates"
        }
    ],
    "infrastructure": [
        {
            "part": "infra-",
            "kind": "prefix",
            "meaning": "below, underneath"
        },
        {
            "part": "struct (struere)",
            "kind": "root",
            "meaning": "build, construct"
        },
        {
            "part": "-ure",
            "kind": "suffix",
            "meaning": "system, result"
        }
    ],
    "legislate": [
        {
            "part": "legis (lex)",
            "kind": "root",
            "meaning": "law"
        },
        {
            "part": "lat (ferre)",
            "kind": "root",
            "meaning": "propose, carry"
        },
        {
            "part": "-ate",
            "kind": "suffix",
            "meaning": "enact, perform"
        }
    ],
    "legitimate": [
        {
            "part": "legitim (lex)",
            "kind": "root",
            "meaning": "lawful, rule-abiding"
        },
        {
            "part": "-ate",
            "kind": "suffix",
            "meaning": "having status of"
        }
    ],
    "manipulate": [
        {
            "part": "manipul (manus)",
            "kind": "root",
            "meaning": "hand, handful"
        },
        {
            "part": "-ate",
            "kind": "suffix",
            "meaning": "handle, control"
        }
    ],
    "merchandise": [
        {
            "part": "merchand (merx)",
            "kind": "root",
            "meaning": "wares, commodities"
        },
        {
            "part": "-ise",
            "kind": "suffix",
            "meaning": "goods, quality"
        }
    ],
    "retail": [
        {
            "part": "re-",
            "kind": "prefix",
            "meaning": "again"
        },
        {
            "part": "tail (tailler)",
            "kind": "root",
            "meaning": "cut in pieces, sell individually"
        }
    ],
    "revenue": [
        {
            "part": "re-",
            "kind": "prefix",
            "meaning": "back"
        },
        {
            "part": "ven (venire)",
            "kind": "root",
            "meaning": "come, return"
        },
        {
            "part": "-ue",
            "kind": "suffix",
            "meaning": "income, yield"
        }
    ],
    "rubbish": [
        {
            "part": "rubb (robous)",
            "kind": "root",
            "meaning": "rubble, waste fragments"
        },
        {
            "part": "-ish",
            "kind": "suffix",
            "meaning": "collectivity"
        }
    ],
    "subsidy": [
        {
            "part": "sub-",
            "kind": "prefix",
            "meaning": "under, behind"
        },
        {
            "part": "sid (sedere)",
            "kind": "root",
            "meaning": "sit in reserve, support"
        },
        {
            "part": "-y (-ium)",
            "kind": "suffix",
            "meaning": "grant, assistance"
        }
    ],
    "transaction": [
        {
            "part": "trans-",
            "kind": "prefix",
            "meaning": "across, through"
        },
        {
            "part": "act (agere)",
            "kind": "root",
            "meaning": "drive, carry through"
        },
        {
            "part": "-ion",
            "kind": "suffix",
            "meaning": "act, business deal"
        }
    ],
    "violate": [
        {
            "part": "viol (vis)",
            "kind": "root",
            "meaning": "force, breach, injure"
        },
        {
            "part": "-ate",
            "kind": "suffix",
            "meaning": "commit, act upon"
        }
    ]
}

OFFLINE_DE_MORPHOLOGY = {
    "wasser": [
        {
            "part": "Wasser (wat-)",
            "kind": "root",
            "meaning": "wet, flowing liquid"
        }
    ],
    "buch": [
        {
            "part": "Buch (boks)",
            "kind": "root",
            "meaning": "beechwood tablet, book"
        }
    ],
    "bahnhof": [
        {
            "part": "Bahn",
            "kind": "prefix",
            "meaning": "track, railway"
        },
        {
            "part": "Hof",
            "kind": "root",
            "meaning": "courtyard, station"
        }
    ],
    "lernen": [
        {
            "part": "lern-",
            "kind": "root",
            "meaning": "follow a track, study"
        },
        {
            "part": "-en",
            "kind": "suffix",
            "meaning": "verb infinitive"
        }
    ],
    "verstehen": [
        {
            "part": "ver-",
            "kind": "prefix",
            "meaning": "thoroughly, before"
        },
        {
            "part": "steh-",
            "kind": "root",
            "meaning": "stand, grasp"
        },
        {
            "part": "-en",
            "kind": "suffix",
            "meaning": "verb infinitive"
        }
    ],
    "erfahrung": [
        {
            "part": "er-",
            "kind": "prefix",
            "meaning": "attain by action"
        },
        {
            "part": "fahr-",
            "kind": "root",
            "meaning": "travel, go through"
        },
        {
            "part": "-ung",
            "kind": "suffix",
            "meaning": "noun of result"
        }
    ],
    "sehenswürdigkeit": [
        {
            "part": "sehens-",
            "kind": "prefix",
            "meaning": "of seeing"
        },
        {
            "part": "würdig",
            "kind": "root",
            "meaning": "worthy"
        },
        {
            "part": "-keit",
            "kind": "suffix",
            "meaning": "quality, thing"
        }
    ],
    "ziel": [
        {
            "part": "Ziel (til-)",
            "kind": "root",
            "meaning": "fixed point, target, goal"
        }
    ],
    "zeitraum": [
        {
            "part": "Zeit",
            "kind": "prefix",
            "meaning": "time"
        },
        {
            "part": "Raum",
            "kind": "root",
            "meaning": "space, span"
        }
    ],
    "zusammenhang": [
        {
            "part": "zusammen-",
            "kind": "prefix",
            "meaning": "together"
        },
        {
            "part": "Hang (hängen)",
            "kind": "root",
            "meaning": "hang, connection"
        }
    ],
    "entscheiden": [
        {
            "part": "ent-",
            "kind": "prefix",
            "meaning": "apart, out of"
        },
        {
            "part": "scheid-",
            "kind": "root",
            "meaning": "separate, determine"
        },
        {
            "part": "-en",
            "kind": "suffix",
            "meaning": "verb infinitive"
        }
    ],
    "herausforderung": [
        {
            "part": "heraus-",
            "kind": "prefix",
            "meaning": "out toward speaker"
        },
        {
            "part": "forder-",
            "kind": "root",
            "meaning": "demand, summon"
        },
        {
            "part": "-ung",
            "kind": "suffix",
            "meaning": "noun of action"
        }
    ],
    "nachhaltig": [
        {
            "part": "nach-",
            "kind": "prefix",
            "meaning": "after, continuing"
        },
        {
            "part": "halt-",
            "kind": "root",
            "meaning": "hold, last"
        },
        {
            "part": "-ig",
            "kind": "suffix",
            "meaning": "characterized by"
        }
    ],
    "nachhaltigkeit": [
        {
            "part": "nach-",
            "kind": "prefix",
            "meaning": "after, continuing"
        },
        {
            "part": "haltig",
            "kind": "root",
            "meaning": "lasting, enduring"
        },
        {
            "part": "-keit",
            "kind": "suffix",
            "meaning": "state, quality"
        }
    ],
    "bewusstsein": [
        {
            "part": "be-",
            "kind": "prefix",
            "meaning": "equipped with"
        },
        {
            "part": "wusst (wissen)",
            "kind": "root",
            "meaning": "known, aware"
        },
        {
            "part": "-sein",
            "kind": "suffix",
            "meaning": "state of being"
        }
    ],
    "erkenntnis": [
        {
            "part": "er-",
            "kind": "prefix",
            "meaning": "come to, achieve"
        },
        {
            "part": "kennt (kennen)",
            "kind": "root",
            "meaning": "know, discern"
        },
        {
            "part": "-nis",
            "kind": "suffix",
            "meaning": "result, insight"
        }
    ],
    "voraussetzung": [
        {
            "part": "voraus-",
            "kind": "prefix",
            "meaning": "in advance, ahead"
        },
        {
            "part": "setz-",
            "kind": "root",
            "meaning": "place, establish"
        },
        {
            "part": "-ung",
            "kind": "suffix",
            "meaning": "condition, noun"
        }
    ],
    "überblick": [
        {
            "part": "über-",
            "kind": "prefix",
            "meaning": "over, across"
        },
        {
            "part": "Blick",
            "kind": "root",
            "meaning": "gaze, view"
        }
    ],
    "gewährleisten": [
        {
            "part": "Gewähr",
            "kind": "prefix",
            "meaning": "warranty, surety"
        },
        {
            "part": "leist-",
            "kind": "root",
            "meaning": "perform, fulfill"
        },
        {
            "part": "-en",
            "kind": "suffix",
            "meaning": "verb infinitive"
        }
    ],
    "auseinandersetzen": [
        {
            "part": "auseinander-",
            "kind": "prefix",
            "meaning": "apart from one another"
        },
        {
            "part": "setz-",
            "kind": "root",
            "meaning": "place, examine"
        },
        {
            "part": "-en",
            "kind": "suffix",
            "meaning": "verb infinitive"
        }
    ],
    "widerspiegeln": [
        {
            "part": "wider-",
            "kind": "prefix",
            "meaning": "back, against"
        },
        {
            "part": "spiegel-",
            "kind": "root",
            "meaning": "mirror, reflect"
        },
        {
            "part": "-n",
            "kind": "suffix",
            "meaning": "verb infinitive"
        }
    ],
    "beeinträchtigen": [
        {
            "part": "be-",
            "kind": "prefix",
            "meaning": "cause to have"
        },
        {
            "part": "einträchtig (Eintrag)",
            "kind": "root",
            "meaning": "encroachment, detriment"
        },
        {
            "part": "-en",
            "kind": "suffix",
            "meaning": "verb infinitive"
        }
    ],
    "gegebenheit": [
        {
            "part": "ge-",
            "kind": "prefix",
            "meaning": "past participle"
        },
        {
            "part": "geben",
            "kind": "root",
            "meaning": "given, existing"
        },
        {
            "part": "-heit",
            "kind": "suffix",
            "meaning": "condition, reality"
        }
    ],
    "wahrscheinlichkeit": [
        {
            "part": "wahr-",
            "kind": "prefix",
            "meaning": "true"
        },
        {
            "part": "schein-",
            "kind": "root",
            "meaning": "appear, seem"
        },
        {
            "part": "-lichkeit",
            "kind": "suffix",
            "meaning": "quality of being likely"
        }
    ],
    "unabdingbar": [
        {
            "part": "un-",
            "kind": "prefix",
            "meaning": "not"
        },
        {
            "part": "ab-",
            "kind": "prefix",
            "meaning": "away"
        },
        {
            "part": "ding-",
            "kind": "root",
            "meaning": "negotiate, waive"
        },
        {
            "part": "-bar",
            "kind": "suffix",
            "meaning": "able to be"
        }
    ],
    "befindlichkeit": [
        {
            "part": "be-",
            "kind": "prefix",
            "meaning": "state"
        },
        {
            "part": "find-",
            "kind": "root",
            "meaning": "find, feel oneself"
        },
        {
            "part": "-lichkeit",
            "kind": "suffix",
            "meaning": "sensibility, state"
        }
    ],
    "fingerspitzengefühl": [
        {
            "part": "Finger",
            "kind": "prefix",
            "meaning": "finger"
        },
        {
            "part": "Spitzen",
            "kind": "root",
            "meaning": "tips"
        },
        {
            "part": "Gefühl",
            "kind": "suffix",
            "meaning": "feeling, intuitive tact"
        }
    ],
    "weitsicht": [
        {
            "part": "weit-",
            "kind": "prefix",
            "meaning": "far, wide"
        },
        {
            "part": "Sicht (sehen)",
            "kind": "root",
            "meaning": "sight, vision"
        }
    ]
}

EN_PREFIX_TABLE = [
    ("contra", "contra-", "against, opposite"),
    ("circum", "circum-", "around"),
    ("inter", "inter-", "between, among"),
    ("intra", "intra-", "within"),
    ("trans", "trans-", "across, beyond"),
    ("super", "super-", "above, beyond"),
    ("infra", "infra-", "below, beneath"),
    ("under", "under-", "beneath, insufficient"),
    ("over", "over-", "excessive, above"),
    ("anti", "anti-", "against"),
    ("auto", "auto-", "self"),
    ("fore", "fore-", "before, in front"),
    ("post", "post-", "after"),
    ("pre", "pre-", "before"),
    ("pro", "pro-", "forward, for"),
    ("sub", "sub-", "under, below"),
    ("syn", "syn-", "together"),
    ("sym", "sym-", "together"),
    ("com", "com-", "together, with"),
    ("con", "con-", "together, with"),
    ("col", "col-", "together"),
    ("cor", "cor-", "altogether"),
    ("dis", "dis-", "apart, not"),
    ("mis", "mis-", "wrongly"),
    ("non", "non-", "not"),
    ("out", "out-", "beyond, surpassing"),
    ("per", "per-", "through, thoroughly"),
    ("ab", "ab-", "away, from"),
    ("ad", "ad-", "to, toward"),
    ("de", "de-", "down, away, completely"),
    ("ex", "ex-", "out, forth"),
    ("in", "in-", "in, into / not"),
    ("im", "im-", "into / not"),
    ("ir", "ir-", "not"),
    ("il", "il-", "not"),
    ("ob", "ob-", "against, toward"),
    ("re", "re-", "again, back"),
    ("un", "un-", "not, reverse"),
    ("en", "en-", "put into, cause"),
    ("em", "em-", "put into"),
]

EN_SUFFIX_TABLE = [
    ("ification", "-ification", "act of making"),
    ("ability", "-ability", "capacity to be"),
    ("ibility", "-ibility", "capacity to be"),
    ("ology", "-logy", "study, science of"),
    ("ation", "-ation", "action, process"),
    ("ition", "-ition", "state, action"),
    ("ment", "-ment", "result, action"),
    ("ness", "-ness", "state, quality"),
    ("ship", "-ship", "status, condition"),
    ("hood", "-hood", "condition, group"),
    ("less", "-less", "without"),
    ("able", "-able", "able to be"),
    ("ible", "-ible", "able to be"),
    ("ance", "-ance", "state, quality"),
    ("ence", "-ence", "state, quality"),
    ("tion", "-tion", "act, process"),
    ("sion", "-sion", "act, state"),
    ("ator", "-ator", "agent, doer"),
    ("ture", "-ture", "result, system"),
    ("ical", "-ical", "pertaining to"),
    ("ful", "-ful", "full of"),
    ("ous", "-ous", "full of"),
    ("ive", "-ive", "tending to"),
    ("ant", "-ant", "being, agent"),
    ("ent", "-ent", "being, agent"),
    ("ity", "-ity", "quality, state"),
    ("ize", "-ize", "make, cause to be"),
    ("ise", "-ise", "make, cause to be"),
    ("ify", "-ify", "make, transform"),
    ("ate", "-ate", "cause, characterized by"),
    ("ure", "-ure", "action, result"),
    ("ial", "-ial", "relating to"),
    ("al", "-al", "relating to"),
    ("ic", "-ic", "pertaining to"),
    ("ly", "-ly", "in the manner of"),
    ("ed", "-ed", "characterized by"),
    ("er", "-er", "agent, doer"),
    ("or", "-or", "agent, doer"),
]

EN_ROOT_MAP = {
    "spect": "look, see", "spec": "look, observe", "dict": "say, speak", "duc": "lead",
    "duct": "lead, channel", "scrib": "write", "script": "write", "port": "carry",
    "fer": "carry, bear", "lat": "carry, bear", "mit": "send", "miss": "send",
    "ject": "throw", "tract": "draw, pull", "struct": "build", "rupt": "break, burst",
    "flect": "bend", "flex": "bend", "cred": "believe, trust", "cogn": "know",
    "gnit": "know", "sci": "know", "vid": "see", "vis": "see", "aud": "hear",
    "phon": "sound, voice", "graph": "write, record", "chron": "time", "temp": "time",
    "loc": "place", "pos": "put, place", "pon": "put, place", "ten": "hold, keep",
    "tain": "hold, keep", "cap": "take, seize", "cept": "take, receive", "fac": "make, do",
    "fect": "make, do", "act": "drive, do", "ven": "come", "vent": "come",
    "ced": "go, yield", "cess": "go, yield", "grad": "step, go", "gress": "step, walk",
    "flu": "flow", "pend": "hang, weigh", "pel": "drive, push", "puls": "drive, push",
    "press": "press", "serv": "keep, protect", "stat": "stand", "sist": "stand",
    "val": "be strong, worth", "viv": "live", "vit": "life", "bio": "life",
    "geo": "earth", "theor": "contemplate, observe", "path": "feeling, suffer",
    "log": "word, study", "leg": "law / choose", "lect": "choose, read",
    "lig": "choose, bind", "rect": "straight, right", "reg": "rule, straight",
    "man": "hand", "ped": "foot", "corp": "body", "soci": "companion, society",
    "phys": "nature, body", "myth": "story, legend", "ministr": "serve, manage",
    "join": "connect", "junct": "join", "volv": "roll, turn", "vers": "turn", "vert": "turn",
}

DE_PREFIX_TABLE = [
    ("auseinander", "auseinander-", "apart from each other"),
    ("zusammen", "zusammen-", "together"),
    ("entgegen", "entgegen-", "toward, against"),
    ("gegenüber", "gegenüber-", "opposite"),
    ("heraus", "heraus-", "out from inside"),
    ("voraus", "voraus-", "in advance"),
    ("weiter", "weiter-", "further, continue"),
    ("wieder", "wieder-", "again"),
    ("wider", "wider-", "against, reflect"),
    ("unter", "unter-", "under, among"),
    ("über", "über-", "over, across"),
    ("durch", "durch-", "through"),
    ("hinter", "hinter-", "behind"),
    ("nach", "nach-", "after, following"),
    ("miss", "miss-", "wrongly, amiss"),
    ("vor", "vor-", "before, ahead"),
    ("auf", "auf-", "up, open"),
    ("aus", "aus-", "out, thoroughly"),
    ("ein", "ein-", "in, into"),
    ("mit", "mit-", "with, co-"),
    ("bei", "bei-", "by, alongside"),
    ("zer", "zer-", "apart, to pieces"),
    ("ent", "ent-", "away, begin, un-"),
    ("emp", "emp-", "toward, receive"),
    ("ver", "ver-", "transform, thoroughly"),
    ("be", "be-", "act upon, equip"),
    ("er", "er-", "achieve, emerge"),
    ("ge", "ge-", "collective / participle"),
    ("un", "un-", "not, opposite"),
    ("ab", "ab-", "off, down, away"),
    ("an", "an-", "at, on, begin"),
    ("um", "um-", "around, change"),
    ("zu", "zu-", "to, closed"),
]

DE_SUFFIX_TABLE = [
    ("lichkeit", "-lichkeit", "quality, state"),
    ("igkeit", "-igkeit", "state, quality"),
    ("schaft", "-schaft", "collective state, domain"),
    ("barkeit", "-barkeit", "ability to be"),
    ("ieren", "-ieren", "verbal action"),
    ("keit", "-keit", "quality, state"),
    ("heit", "-heit", "abstract quality"),
    ("chen", "-chen", "diminutive"),
    ("lein", "-lein", "diminutive"),
    ("lich", "-lich", "characteristic of"),
    ("isch", "-isch", "pertaining to"),
    ("haft", "-haft", "having the nature of"),
    ("voll", "-voll", "full of"),
    ("los", "-los", "without"),
    ("bar", "-bar", "able to be"),
    ("sam", "-sam", "tending to"),
    ("ung", "-ung", "noun of action/result"),
    ("nis", "-nis", "result, state"),
    ("tum", "-tum", "domain, condition"),
    ("tät", "-tät", "academic quality"),
    ("ion", "-ion", "process, state"),
    ("ig", "-ig", "having, characterized by"),
    ("en", "-en", "verb infinitive"),
]


def format_morphology(morphology_list: list[dict] | dict | None) -> str:
    if isinstance(morphology_list, dict):
        morphology_list = morphology_list.get("morphology")
    if not morphology_list or not isinstance(morphology_list, list):
        return ""
    parts: list[str] = []
    for item in morphology_list:
        if not isinstance(item, dict):
            continue
        p = str(item.get("part") or "").strip()
        m = str(item.get("meaning") or "").strip()
        if not p:
            continue
        parts.append(f"{p} ({m})" if m else p)
    return " + ".join(parts)


def infer_offline_morphology(word: str, lang: str) -> list[dict]:
    clean = re.sub(r"^(der|die|das|sich|to)\s+", "", word.strip(), flags=re.I).strip()
    if not clean:
        return []
    key = clean.lower()
    if lang == "de":
        if key in OFFLINE_DE_MORPHOLOGY:
            return list(OFFLINE_DE_MORPHOLOGY[key])
        parts_de: list[dict] = []
        rem_de = key
        for pref, label, meaning in DE_PREFIX_TABLE:
            if rem_de.startswith(pref) and len(rem_de) - len(pref) >= 3:
                parts_de.append({"part": label, "kind": "prefix", "meaning": meaning})
                rem_de = rem_de[len(pref):]
                break
        matched_de_suf = None
        for suf, label, meaning in DE_SUFFIX_TABLE:
            if len(rem_de) - len(suf) >= 3 and rem_de.endswith(suf):
                matched_de_suf = {"part": label, "kind": "suffix", "meaning": meaning}
                rem_de = rem_de[:-len(suf)]
                break
        parts_de.append({"part": rem_de or clean, "kind": "root", "meaning": "core stem"})
        if matched_de_suf:
            parts_de.append(matched_de_suf)
        return parts_de

    if key in OFFLINE_EN_MORPHOLOGY:
        return list(OFFLINE_EN_MORPHOLOGY[key])
    parts_en: list[dict] = []
    rem_en = key
    for pref, label, meaning in EN_PREFIX_TABLE:
        if rem_en.startswith(pref) and len(rem_en) - len(pref) >= 3:
            parts_en.append({"part": label, "kind": "prefix", "meaning": meaning})
            rem_en = rem_en[len(pref):]
            break
    matched_en_suf = None
    for suf, label, meaning in EN_SUFFIX_TABLE:
        if len(rem_en) - len(suf) >= 3 and rem_en.endswith(suf):
            matched_en_suf = {"part": label, "kind": "suffix", "meaning": meaning}
            rem_en = rem_en[:-len(suf)]
            break
    root_gloss = EN_ROOT_MAP.get(rem_en, "")
    if not root_gloss:
        for r_key, r_meaning in EN_ROOT_MAP.items():
            if len(r_key) >= 3 and r_key in rem_en:
                root_gloss = r_meaning
                break
    parts_en.append({"part": rem_en or clean, "kind": "root", "meaning": root_gloss or "core root"})
    if matched_en_suf:
        parts_en.append(matched_en_suf)
    return parts_en


def parse_wiktionary_etymology(wikitext: str, lang_or_word: str = "en", lang_code_opt: str = "") -> dict:
    if not wikitext:
        return {}
    lang_code = (lang_code_opt or (lang_or_word if lang_or_word in ("en", "de") else "en")).lower()
    section = wikitext
    if lang_code == "en":
        en_sec = re.search(r"==\s*English\s*==(.*?)(?:\n==[^=]|$)", wikitext, re.S)
        if en_sec:
            section = en_sec.group(1)
        etym_sec = re.search(r"===\s*Etymology(?:\s+\d+)?\s*===\s*\n(.*?)(?:\n===|$)", section, re.S)
        etym_raw = etym_sec.group(1) if etym_sec else section
    else:
        herk_sec = re.search(r"\{\{Herkunft\}\}[\s\n]*((?::\[[^\n]+\n?)+)", wikitext)
        etym_raw = herk_sec.group(1) if herk_sec else wikitext

    morphology: list[dict] = []
    tpl_match = re.search(
        r"\{\{(affix|af|prefix|pre|suffix|suf|confix|compound|com)\|([^}]+)\}\}",
        etym_raw,
        re.I,
    )
    if tpl_match:
        tpl_name = tpl_match.group(1).lower()
        params = [p.strip() for p in tpl_match.group(2).split("|")]
        positional: list[str] = []
        glosses: dict[int, str] = {}
        for p in params:
            if "=" in p:
                k, v = p.split("=", 1)
                k = k.strip().lower()
                v = v.strip()
                m_t = re.match(r"^(?:t|gloss)(\d+)$", k)
                if m_t and v:
                    glosses[int(m_t.group(1))] = v
            else:
                positional.append(p)
        morphemes = [m for m in positional[1:] if m]
        for idx, morph in enumerate(morphemes, start=1):
            clean_m = re.sub(r"^\w+:", "", morph).strip()
            if not clean_m:
                continue
            if tpl_name in ("prefix", "pre") and idx == 1 and not clean_m.endswith("-"):
                clean_m = clean_m + "-"
            elif tpl_name in ("suffix", "suf") and idx == len(morphemes) and not clean_m.startswith("-"):
                clean_m = "-" + clean_m
            kind = "prefix" if clean_m.endswith("-") else ("suffix" if clean_m.startswith("-") else "root")
            meaning = glosses.get(idx, "")
            if not meaning and not lang_code_opt:
                bare = clean_m.strip("-").lower()
                if kind == "prefix":
                    for pr, _, m_str in (DE_PREFIX_TABLE if lang_code == "de" else EN_PREFIX_TABLE):
                        if pr == bare:
                            meaning = m_str
                            break
                elif kind == "suffix":
                    for sr, _, m_str in (DE_SUFFIX_TABLE if lang_code == "de" else EN_SUFFIX_TABLE):
                        if sr == bare:
                            meaning = m_str
                            break
                else:
                    meaning = EN_ROOT_MAP.get(bare, "")
            morphology.append({"part": clean_m, "kind": kind, "meaning": meaning})

    if not morphology:
        for m_der in re.finditer(r"\{\{(?:der|bor|inh|m|cog)\|([^}]+)\}\}", etym_raw):
            p_list = [x.strip() for x in m_der.group(1).split("|")]
            pos_args = [x for x in p_list if "=" not in x]
            kw_args = dict(x.split("=", 1) for x in p_list if "=" in x)
            t_name = m_der.group(0).split("|", 1)[0].lstrip("{").lower()
            lemma_idx = 1 if t_name in ("m", "cog") else 2
            lemma = pos_args[lemma_idx] if len(pos_args) > lemma_idx else ""
            gloss = kw_args.get("t") or kw_args.get("gloss") or (pos_args[lemma_idx + 2] if len(pos_args) > lemma_idx + 2 else "")
            lemma = re.sub(r"''+", "", lemma).strip()
            gloss = re.sub(r"''+", "", gloss).strip()
            if lemma and lemma != "-" and gloss:
                morphology.append({"part": lemma, "kind": "root", "meaning": gloss})
                if len(morphology) >= 3:
                    break

    if not morphology and lang_code == "de":
        for m_link in re.finditer(r"\[\[(?:[^|\]]*\|)?([^\]]+)\]\]", etym_raw):
            token = m_link.group(1).strip()
            if not token:
                continue
            kind = "prefix" if token.endswith("-") else ("suffix" if token.startswith("-") else "root")
            meaning = ""
            bare = token.strip("-").lower()
            if kind == "prefix":
                for pr, _, m_str in DE_PREFIX_TABLE:
                    if pr == bare:
                        meaning = m_str
                        break
            elif kind == "suffix":
                for sr, _, m_str in DE_SUFFIX_TABLE:
                    if sr == bare:
                        meaning = m_str
                        break
            morphology.append({"part": token, "kind": kind, "meaning": meaning})

    cleaned_etym = clean_wikitext_line(etym_raw.splitlines()[0]) if etym_raw.strip() else ""
    out: dict = {}
    if morphology:
        out["morphology"] = morphology
        out["morphologyText"] = format_morphology(morphology)
    if cleaned_etym:
        out["etymology"] = cleaned_etym
    return out


def infer_offline_metadata(word: str, lang: str) -> dict:
    raw = word.strip()
    article = ""
    clean = raw
    m = re.match(r"^(der|die|das|sich)\s+(.+)$", raw, flags=re.IGNORECASE)
    if m:
        article = m.group(1).lower()
        clean = m.group(2).strip()
        lang = "de"
    clean_lemma = re.sub(
        r"\s+(mit|an|auf|über|für|von|zu|in|um|nach|vor|aus|bei|gegen|durch|unter|zwischen)$",
        "",
        clean,
        flags=re.IGNORECASE,
    ).strip()
    key = clean_lemma.lower()

    level = ""
    level_source = ""
    pos = ""
    plural = ""
    verified = False

    if lang == "de":
        if key in OFFLINE_DE_LEXICON:
            level, level_source, pos, lex_art, plural = OFFLINE_DE_LEXICON[key]
            verified = True
            if not article and lex_art:
                article = lex_art
        else:
            lower = clean_lemma.lower()
            if not article and clean_lemma[:1].isupper():
                if lower.endswith(("ung", "heit", "keit", "schaft", "tion", "tät", "ik", "enz", "anz")):
                    article = "die"
                    pos = "noun"
                elif lower.endswith(("chen", "lein", "ment", "um", "tum")):
                    article = "das"
                    pos = "noun"
                elif lower.endswith(("ismus", "ling")):
                    article = "der"
                    pos = "noun"
            n = len(clean_lemma)
            level = "A1" if n <= 4 else ("A2" if n <= 6 else ("B1" if n <= 9 else ("B2" if n <= 12 else ("C1" if n <= 15 else "C2"))))
            level_source = "DWDS / Goethe Heuristic"
    else:
        if key in OFFLINE_EN_LEXICON:
            level, level_source, pos = OFFLINE_EN_LEXICON[key]
            verified = True
        else:
            n = len(key)
            level = "A1" if n <= 4 else ("A2" if n <= 6 else ("B1" if n <= 8 else ("B2" if n <= 10 else ("C1" if n <= 12 else "C2"))))
            level_source = "CEFR Lexical Heuristic"

    display_term = f"{article} {clean}" if article else clean
    morph_items = infer_offline_morphology(clean, lang)
    return {
        "ok": True,
        "found": True,
        "onlineVerified": verified,
        "word": clean,
        "headword": clean,
        "displayTerm": display_term,
        "language": lang,
        "level": level,
        "cefrLevel": level,
        "levelSource": level_source,
        "cefrSource": level_source,
        "pos": pos,
        "phonetic": "",
        "phonetics": "",
        "article": article,
        "gender": article,
        "plural": plural,
        "meaning": "",
        "definition": "",
        "example": "",
        "synonyms": [],
        "antonyms": [],
        "morphology": morph_items,
        "morphologyText": format_morphology(morph_items),
        "etymology": format_morphology(morph_items),
    }


def enrich_with_aliases(data: dict) -> dict:
    out = dict(data)
    word = str(out.get("word") or out.get("headword") or "").strip()
    level = str(out.get("level") or out.get("cefrLevel") or "").strip()
    source = str(out.get("levelSource") or out.get("cefrSource") or "").strip()
    article = str(out.get("article") or out.get("gender") or "").strip()
    phonetic = str(out.get("phonetic") or out.get("phonetics") or "").strip()
    meaning = str(out.get("meaning") or out.get("definition") or "").strip()
    ok = bool(out.get("ok") or level or meaning or phonetic or article)
    out["ok"] = ok
    out["found"] = ok
    out["word"] = word
    out["headword"] = word
    out["level"] = level
    out["cefrLevel"] = level
    out["levelSource"] = source
    out["cefrSource"] = source
    out["article"] = article
    out["gender"] = article
    out["phonetic"] = phonetic
    out["phonetics"] = phonetic
    out["meaning"] = meaning
    out["definition"] = meaning
    out["definitionEn"] = str(out.get("definitionEn") or meaning).strip()
    out["meaningVi"] = str(out.get("meaningVi") or "").strip()
    if not out.get("displayTerm"):
        out["displayTerm"] = f"{article} {word}" if article in ("der", "die", "das", "sich") else word
    morph = out.get("morphology")
    if not isinstance(morph, list) or not morph:
        morph = infer_offline_morphology(word, str(out.get("language") or "en"))
    out["morphology"] = morph
    out["morphologyText"] = str(out.get("morphologyText") or format_morphology(morph)).strip()
    out["etymology"] = str(out.get("etymology") or out["morphologyText"]).strip()
    return out


def lookup_single_word(raw_word: str, lang: str, timeout: float, no_cache: bool, offline: bool) -> dict:
    raw_word = raw_word.strip()
    if not raw_word:
        return {"ok": False, "found": False, "error": "empty-word"}

    if lang == "auto":
        if re.match(r"^(der|die|das|sich)\s+", raw_word, re.I) or re.search(r"[äöüÄÖÜß]", raw_word):
            lang = "de"
        else:
            lang = "en"

    offline_base = infer_offline_metadata(raw_word, lang)
    if offline:
        return enrich_with_aliases(offline_base)

    cache_key = f"{lang}:{raw_word.lower()}"
    cache = {} if no_cache else load_cache()
    if cache_key in cache and isinstance(cache[cache_key], dict):
        cached = enrich_with_aliases(dict(cache[cache_key]))
        cached["cached"] = True
        return cached

    if lang == "de":
        online = lookup_german_online(raw_word, timeout=timeout)
    else:
        online = lookup_english_online(raw_word, timeout=timeout)

    online_succeeded = bool(online.get("ok"))
    merged = dict(offline_base)
    for k, v in online.items():
        if v:
            merged[k] = v
    if online_succeeded and online.get("level"):
        merged["onlineVerified"] = True
    merged = enrich_with_aliases(merged)

    if online_succeeded and not no_cache:
        cache[cache_key] = merged
        save_cache(cache)

    return merged


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("word_pos", nargs="?", default="", help="Headword or phrase to look up")
    parser.add_argument("--word", default="", help="Headword or phrase to look up")
    parser.add_argument("--lang", default="auto", choices=["auto", "en", "de", "other", "general"])
    parser.add_argument("--timeout", type=float, default=3.5)
    parser.add_argument("--no-cache", action="store_true")
    parser.add_argument("--offline", action="store_true", help="Use offline lexicon and heuristics only")
    parser.add_argument("--batch", default="", help="JSON array of {word, lang} objects")
    args = parser.parse_args()

    if args.batch:
        try:
            items = json.loads(args.batch)
        except Exception:
            print(json.dumps({"results": [], "error": "invalid-batch-json"}))
            return 0
        results = []
        if isinstance(items, list):
            for entry in items[:50]:
                if isinstance(entry, dict):
                    w = str(entry.get("word") or "")
                    l = str(entry.get("lang") or args.lang or "auto")
                else:
                    w = str(entry)
                    l = args.lang
                results.append(lookup_single_word(w, l, args.timeout, args.no_cache, args.offline))
        print(json.dumps({"results": results}, ensure_ascii=False))
        return 0

    target_word = (args.word or args.word_pos or "").strip()
    if not target_word:
        print(json.dumps({"ok": False, "found": False, "error": "empty-word"}))
        return 0

    result = lookup_single_word(target_word, args.lang, args.timeout, args.no_cache, args.offline)
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
