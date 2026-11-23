.pragma library

function escapeHtml(text) {
    return String(text ?? "")
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;");
}

function unescapeHtmlEntities(text) {
    return String(text ?? "")
        .replace(/&quot;/g, "\"")
        .replace(/&#39;/g, "'")
        .replace(/&gt;/g, ">")
        .replace(/&lt;/g, "<")
        .replace(/&amp;/g, "&");
}

function encodeWikilinkTarget(rawTarget) {
    return encodeURIComponent(unescapeHtmlEntities(rawTarget));
}

function safeDecodeUriComponent(raw) {
    const str = String(raw ?? "");
    try {
        return decodeURIComponent(str);
    } catch (_e) {
        return str;
    }
}

function _applyLatexReplacements(raw) {
    let s = String(raw ?? "");
    const symbols = {
        "\\alpha": "α", "\\beta": "β", "\\gamma": "γ", "\\delta": "δ",
        "\\epsilon": "ε", "\\varepsilon": "ϵ", "\\zeta": "ζ", "\\eta": "η",
        "\\theta": "θ", "\\vartheta": "ϑ", "\\iota": "ι", "\\kappa": "κ",
        "\\lambda": "λ", "\\mu": "μ", "\\nu": "ν", "\\xi": "ξ",
        "\\pi": "π", "\\rho": "ρ", "\\sigma": "σ", "\\tau": "τ",
        "\\upsilon": "υ", "\\phi": "φ", "\\varphi": "ϕ", "\\chi": "χ",
        "\\psi": "ψ", "\\omega": "ω",
        "\\Gamma": "Γ", "\\Delta": "Δ", "\\Theta": "Θ", "\\Lambda": "Λ",
        "\\Xi": "Ξ", "\\Pi": "Π", "\\Sigma": "Σ", "\\Upsilon": "Υ",
        "\\Phi": "Φ", "\\Psi": "Ψ", "\\Omega": "Ω",
        "\\infty": "∞", "\\partial": "∂", "\\nabla": "∇", "\\sum": "∑",
        "\\prod": "∏", "\\int": "∫", "\\oint": "∮", "\\iint": "∬",
        "\\approx": "≈", "\\neq": "≠", "\\ne": "≠", "\\equiv": "≡",
        "\\leq": "≤", "\\le": "≤", "\\geq": "≥", "\\ge": "≥",
        "\\ll": "≪", "\\gg": "≫", "\\times": "×", "\\cdot": "·",
        "\\div": "÷", "\\pm": "±", "\\mp": "∓", "\\ast": "∗",
        "\\to": "→", "\\rightarrow": "→", "\\leftarrow": "←", "\\leftrightarrow": "↔",
        "\\Rightarrow": "⇒", "\\Leftarrow": "⇐", "\\Leftrightarrow": "⇔",
        "\\mapsto": "↦", "\\forall": "∀", "\\exists": "∃", "\\nexists": "∄",
        "\\in": "∈", "\\notin": "∉", "\\subset": "⊂", "\\subseteq": "⊆",
        "\\supset": "⊃", "\\supseteq": "⊇", "\\cup": "∪", "\\cap": "∩",
        "\\emptyset": "∅", "\\varnothing": "∅", "\\land": "∧", "\\lor": "∨",
        "\\lnot": "¬", "\\neg": "¬", "\\therefore": "∴", "\\because": "∵",
        "\\propto": "∝", "\\perp": "⊥", "\\parallel": "∥", "\\angle": "∠",
        "\\degree": "°", "\\circ": "∘", "\\star": "★", "\\ldots": "…", "\\cdots": "⋯",
        "\\mathbb{R}": "ℝ", "\\mathbb{N}": "ℕ", "\\mathbb{Z}": "ℤ",
        "\\mathbb{Q}": "ℚ", "\\mathbb{C}": "ℂ",
        "\\quad": "  ", "\\qquad": "    ", "\\,": " ", "\\;": " ", "\\!": ""
    };

    // Braced macros first (handles nested flat groups iteratively)
    for (let pass = 0; pass < 3; ++pass) {
        s = s.replace(/\\frac\{([^{}]+)\}\{([^{}]+)\}/g, "<sup>$1</sup>⁄<sub>$2</sub>");
        s = s.replace(/\\sqrt\{([^{}]+)\}/g, "√($1)");
        s = s.replace(/\\text\{([^{}]+)\}/g, "<span>$1</span>");
        s = s.replace(/\\mathrm\{([^{}]+)\}/g, "<span>$1</span>");
        s = s.replace(/\\mathbf\{([^{}]+)\}/g, "<b>$1</b>");
        s = s.replace(/\\textbf\{([^{}]+)\}/g, "<b>$1</b>");
        s = s.replace(/\\mathit\{([^{}]+)\}/g, "<i>$1</i>");
        s = s.replace(/\\hat\{([^{}]+)\}/g, "$1&#770;");
        s = s.replace(/\\bar\{([^{}]+)\}/g, "$1&#772;");
        s = s.replace(/\\vec\{([^{}]+)\}/g, "$1&#8407;");
        s = s.replace(/\\left([(\[{|])/g, "$1");
        s = s.replace(/\\right([)\]}|])/g, "$1");
        s = s.replace(/\\left\./g, "").replace(/\\right\./g, "");
    }

    const keys = Object.keys(symbols).sort((a, b) => b.length - a.length);
    for (let i = 0; i < keys.length; ++i) {
        const k = keys[i];
        s = s.split(k).join(symbols[k]);
    }

    // Superscripts & subscripts (braced then single char)
    s = s.replace(/\^\{([^{}]+)\}/g, "<sup>$1</sup>");
    s = s.replace(/_\{([^{}]+)\}/g, "<sub>$1</sub>");
    s = s.replace(/\^([A-Za-z0-9+\-*])/g, "<sup>$1</sup>");
    s = s.replace(/_([A-Za-z0-9+\-*])/g, "<sub>$1</sub>");
    s = s.replace(/\\\\/g, "<br/>");
    return s;
}

function renderLatexToHtml(expr, isBlock, accentColor, textColor) {
    const clean = String(expr ?? "").replace(/^\$\$|\$\$$/g, "").replace(/^\$|\$$/g, "").trim();
    const esc = escapeHtml(clean);
    const rendered = _applyLatexReplacements(esc);
    const col = String(textColor ?? "#e2e8f0");
    const acc = String(accentColor ?? "#7dd3fc");
    if (isBlock) {
        return "<div style=\"color:" + col + "; font-family: serif; font-size: 15px; line-height: 1.45;\">" + rendered + "</div>";
    }
    return "<span style=\"color:" + acc + "; font-family: serif;\">" + rendered + "</span>";
}

function renderInlineMarkdownToHtml(rawText, textColor, accentColor, mutedColor) {
    let s = escapeHtml(String(rawText ?? ""));
    const acc = String(accentColor ?? "#7dd3fc");
    const mut = String(mutedColor ?? "#94a3b8");

    // Inline math $...$ (preserve outside code)
    s = s.replace(/\$([^$\n]+)\$/g, function(_m, inner) {
        return "<span style=\"color:" + acc + "; font-family: serif;\">" + _applyLatexReplacements(inner) + "</span>";
    });
    // Inline code `...`
    s = s.replace(/`([^`\n]+)`/g, "<code style=\"background-color:rgba(148,163,184,0.16); color:" + acc + "; font-family:monospace;\">&nbsp;$1&nbsp;</code>");
    // Highlight ==...==
    s = s.replace(/==([^=\n]+)==/g, "<span style=\"background-color:rgba(250,204,21,0.24);\">$1</span>");
    // Bold **...** and __...__
    s = s.replace(/\*\*([^*\n]+)\*\*/g, "<b>$1</b>");
    s = s.replace(/__([^_\n]+)__/g, "<b>$1</b>");
    // Italic *...*
    s = s.replace(/(^|[\s(])\*([^*\n]+)\*(?=[\s).,!?:;]|$)/g, "$1<i>$2</i>");
    // Strikethrough ~~...~~
    s = s.replace(/~~([^~\n]+)~~/g, "<s>$1</s>");
    // Wikilinks [[Target|Alias]] or [[Target]] as clickable links
    s = s.replace(/\[\[([^\]|\n]+)\|([^\]\n]+)\]\]/g, function(_m, target, alias) {
        return "<a href=\"wikilink://" + escapeHtml(encodeWikilinkTarget(target)) + "\" style=\"color:" + acc + "; text-decoration:underline;\">" + alias + "</a>";
    });
    s = s.replace(/\[\[([^\]\n]+)\]\]/g, function(_m, target) {
        return "<a href=\"wikilink://" + escapeHtml(encodeWikilinkTarget(target)) + "\" style=\"color:" + acc + "; text-decoration:underline;\">" + target + "</a>";
    });
    // External HTTP links [label](https://...) and bare https://...
    s = s.replace(/\[([^\]\n]+)\]\((https?:\/\/[^)\s]+)\)/g, "<a href=\"$2\" style=\"color:" + acc + "; text-decoration:underline;\">$1</a>");
    s = s.replace(/(^|[\s(])(https?:\/\/[^\s<)]+)/g, "$1<a href=\"$2\" style=\"color:" + acc + "; text-decoration:underline;\">$2</a>");
    // Inline #tags
    s = s.replace(/(^|\s)(#[A-Za-z][A-Za-z0-9_/-]*)/g, "$1<span style=\"color:" + mut + ";\">$2</span>");
    return "<span style=\"color:" + String(textColor ?? "#e2e8f0") + ";\">" + s + "</span>";
}

function highlightCodeToHtml(code, lang, palette) {
    const p = palette || {};
    const textCol = String(p.text || "#e2e8f0");
    const kwCol = String(p.keyword || "#7dd3fc");
    const strCol = String(p.string || "#86efac");
    const numCol = String(p.number || "#fca5a5");
    const cmtCol = String(p.comment || "#64748b");
    const typeCol = String(p.type || "#c4b5fd");
    const lowerLang = String(lang ?? "").toLowerCase();
    const lines = String(code ?? "").split(/\r?\n/);

    const kwSet = {
        "fn": true, "let": true, "mut": true, "pub": true, "struct": true, "enum": true,
        "impl": true, "match": true, "if": true, "else": true, "for": true, "while": true,
        "loop": true, "return": true, "use": true, "mod": true, "const": true, "var": true,
        "function": true, "class": true, "import": true, "from": true, "export": true,
        "property": true, "readonly": true, "signal": true, "required": true, "def": true,
        "async": true, "await": true, "try": true, "catch": true, "except": true, "true": true,
        "false": true, "null": true, "none": true, "None": true, "True": true, "False": true,
        "self": true, "this": true, "in": true, "of": true, "SELECT": true, "FROM": true,
        "WHERE": true, "JOIN": true, "ORDER": true, "GROUP": true, "BY": true
    };

    const outLines = [];
    for (let li = 0; li < lines.length; ++li) {
        const line = lines[li];
        const trimmed = line.trim();
        if (trimmed.startsWith("//") || trimmed.startsWith("#") && lowerLang !== "markdown" && lowerLang !== "md"
                || trimmed.startsWith("--") && lowerLang === "sql") {
            outLines.push("<span style=\"color:" + cmtCol + "; font-style:italic;\">" + escapeHtml(line) + "</span>");
            continue;
        }
        let html = "";
        let i = 0;
        while (i < line.length) {
            const ch = line.charAt(i);
            // Inline comment
            if (ch === "/" && i + 1 < line.length && line.charAt(i + 1) === "/") {
                html += "<span style=\"color:" + cmtCol + "; font-style:italic;\">" + escapeHtml(line.slice(i)) + "</span>";
                break;
            }
            if (ch === "\"" || ch === "'" || ch === "`") {
                const quote = ch;
                let j = i + 1;
                while (j < line.length) {
                    if (line.charAt(j) === "\\" && j + 1 < line.length) {
                        j += 2;
                        continue;
                    }
                    if (line.charAt(j) === quote) {
                        j += 1;
                        break;
                    }
                    j += 1;
                }
                html += "<span style=\"color:" + strCol + ";\">" + escapeHtml(line.slice(i, j)) + "</span>";
                i = j;
                continue;
            }
            if ((ch >= "0" && ch <= "9")) {
                let j = i;
                while (j < line.length && /[0-9a-fA-Fx._]/.test(line.charAt(j)))
                    j += 1;
                html += "<span style=\"color:" + numCol + ";\">" + escapeHtml(line.slice(i, j)) + "</span>";
                i = j;
                continue;
            }
            if (/[A-Za-z_]/.test(ch)) {
                let j = i;
                while (j < line.length && /[A-Za-z0-9_]/.test(line.charAt(j)))
                    j += 1;
                const word = line.slice(i, j);
                if (kwSet[word]) {
                    html += "<span style=\"color:" + kwCol + "; font-weight:600;\">" + escapeHtml(word) + "</span>";
                } else if (/^[A-Z][A-Za-z0-9_]*$/.test(word)) {
                    html += "<span style=\"color:" + typeCol + ";\">" + escapeHtml(word) + "</span>";
                } else {
                    html += escapeHtml(word);
                }
                i = j;
                continue;
            }
            html += escapeHtml(ch);
            i += 1;
        }
        outLines.push(html.length > 0 ? html : "&nbsp;");
    }
    return "<pre style=\"margin:0; font-family:monospace; font-size:12px; color:" + textCol + ";\">" + outLines.join("<br/>") + "</pre>";
}

function parseMermaid(src) {
    const raw = String(src ?? "").trim();
    const lines = raw.split(/\r?\n/);
    if (lines.length === 0)
        return { kind: "unknown", supported: false, nodes: [], edges: [], participants: [], messages: [] };

    const first = lines[0].trim();
    if (/^(flowchart|graph)\b/i.test(first)) {
        const dirMatch = first.match(/^(?:flowchart|graph)\s+(TD|TB|LR|RL|BT)/i);
        const direction = dirMatch ? dirMatch[1].toUpperCase() : "TD";
        const nodeMap = {};
        const nodes = [];
        const edges = [];

        function ensureNode(token) {
            const cleaned = String(token ?? "").trim();
            if (!cleaned)
                return null;
            let id = cleaned;
            let label = cleaned;
            let shape = "rect";
            let m;
            if ((m = cleaned.match(/^([A-Za-z0-9_.-]+)\(\((.+)\)\)$/))) {
                id = m[1]; label = m[2].replace(/^["']|["']$/g, ""); shape = "circle";
            } else if ((m = cleaned.match(/^([A-Za-z0-9_.-]+)\[\[(.+)\]\]$/))) {
                id = m[1]; label = m[2].replace(/^["']|["']$/g, ""); shape = "subroutine";
            } else if ((m = cleaned.match(/^([A-Za-z0-9_.-]+)\{(.+)\}$/))) {
                id = m[1]; label = m[2].replace(/^["']|["']$/g, ""); shape = "diamond";
            } else if ((m = cleaned.match(/^([A-Za-z0-9_.-]+)\((.+)\)$/))) {
                id = m[1]; label = m[2].replace(/^["']|["']$/g, ""); shape = "round";
            } else if ((m = cleaned.match(/^([A-Za-z0-9_.-]+)\[(.+)\]$/))) {
                id = m[1]; label = m[2].replace(/^["']|["']$/g, ""); shape = "rect";
            }
            if (!nodeMap[id]) {
                nodeMap[id] = { id: id, label: label, shape: shape };
                nodes.push(nodeMap[id]);
            } else if (label !== id) {
                nodeMap[id].label = label;
                nodeMap[id].shape = shape;
            }
            return nodeMap[id];
        }

        for (let i = 1; i < lines.length; ++i) {
            const line = lines[i].trim();
            if (!line || line.startsWith("%%") || /^(subgraph|end|classDef|class|style|linkStyle)\b/i.test(line))
                continue;
            // Split chained edges like A --> B --> C or A -. label .-> B or A -->|label| B
            const arrowRe = /\s+(-->|==>|-\.->|---|-.-)(?:\|([^|]+)\|)?\s+|\s+--\s+([^->]+)\s+-->\s+/;
            let remaining = line;
            let seg = remaining.match(/^(.+?)\s+(-->|==>|\.-+\->|-\.->|---)\s*(?:\|([^|]+)\|)?\s*(.+)$/);
            if (seg) {
                const leftTok = seg[1].trim();
                const arrow = seg[2];
                const edgeLabel = String(seg[3] ?? "").trim();
                const rightTok = seg[4].trim();
                const fromN = ensureNode(leftTok);
                const toN = ensureNode(rightTok);
                if (fromN && toN) {
                    edges.push({
                        from: fromN.id,
                        to: toN.id,
                        label: edgeLabel,
                        dashed: arrow.indexOf(".") !== -1,
                        thick: arrow === "==>"
                    });
                }
            } else {
                ensureNode(line);
            }
        }
        return {
            kind: "flowchart",
            supported: nodes.length > 0,
            direction: direction,
            nodes: nodes,
            edges: edges,
            participants: [],
            messages: []
        };
    }

    if (/^sequenceDiagram\b/i.test(first)) {
        const partsMap = {};
        const participants = [];
        const messages = [];
        function ensurePart(name) {
            const clean = String(name ?? "").trim();
            if (!clean)
                return;
            if (!partsMap[clean]) {
                partsMap[clean] = { id: clean, label: clean };
                participants.push(partsMap[clean]);
            }
        }
        for (let i = 1; i < lines.length; ++i) {
            const line = lines[i].trim();
            if (!line || line.startsWith("%%"))
                continue;
            let pm = line.match(/^(?:participant|actor)\s+([A-Za-z0-9_.-]+)(?:\s+as\s+(.+))?$/i);
            if (pm) {
                const pid = pm[1].trim();
                const plabel = String(pm[2] ?? pid).trim();
                if (!partsMap[pid]) {
                    partsMap[pid] = { id: pid, label: plabel };
                    participants.push(partsMap[pid]);
                } else {
                    partsMap[pid].label = plabel;
                }
                continue;
            }
            let mm = line.match(/^([A-Za-z0-9_.-]+)\s*(-->>|->>|-->|->)\s*([A-Za-z0-9_.-]+)\s*:\s*(.*)$/);
            if (mm) {
                ensurePart(mm[1]);
                ensurePart(mm[3]);
                messages.push({
                    from: mm[1].trim(),
                    to: mm[3].trim(),
                    label: String(mm[4] ?? "").trim(),
                    dashed: mm[2].startsWith("--")
                });
            }
        }
        return {
            kind: "sequence",
            supported: participants.length > 0,
            direction: "LR",
            nodes: [],
            edges: [],
            participants: participants,
            messages: messages
        };
    }

    return { kind: "unknown", supported: false, nodes: [], edges: [], participants: [], messages: [] };
}
