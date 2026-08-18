#!/usr/bin/env node
/**
 * Measure a draft against the writing rules, before a human has to.
 *
 * The rules live in ~/.claude/CLAUDE.md and are followed about as often as they are read,
 * which is the reason this exists. Reading a rule and applying it while generating text
 * are different acts. A check that measures the output closes that gap; another rule does
 * not.
 *
 * What it flags, all from the ASD-STE100 section and the banned-vocabulary section:
 *   - sentences over 25 words
 *   - a short bold label used in place of a clause
 *   - banned words: matters, crucial, leverage, robust, seamless, footgun and the rest
 *   - hard-wrapped paragraphs
 *   - sentences that talk about the document itself
 *
 * Usage: node tools/check-prose.js FILE...
 * Exits non-zero when anything is flagged, so it can gate a commit.
 */

const fs = require('fs');
const path = require('path');

// RULES ARE DATA, NOT CODE. They live in rules.json beside this file so the
// asd-ste100 skill and this checker read ONE list. Hand-copying them into the
// script is how three copies drifted apart: the hardcoded array did not know
// about "honest", "not just X but Y", or reflexive em-dash hedging, all of which
// Jonathan had explicitly banned in his own CLAUDE.md. Adding a word is now an
// edit to rules.json, not a code change.
//
// A repo may override or extend by placing .check-prose.json at its root — merged
// over the defaults, so a project can add its own tells without forking the tool.
function loadRules() {
    const base = JSON.parse(fs.readFileSync(path.join(__dirname, 'rules.json'), 'utf8'));
    const local = path.join(process.cwd(), '.check-prose.json');
    if (fs.existsSync(local)) {
        try {
            const over = JSON.parse(fs.readFileSync(local, 'utf8'));
            for (const k of Object.keys(over)) {
                if (Array.isArray(base[k]) && Array.isArray(over[k])) base[k] = base[k].concat(over[k]);
                else base[k] = over[k];
            }
        } catch (e) {
            console.error(`check-prose: ${local} is unreadable (${e.message}) — refusing to run on partial rules`);
            process.exit(2);
        }
    }
    return base;
}

const RULES = loadRules();
const BANNED = RULES.banned_words.concat(RULES.banned_phrases);
const SELF_REFERENTIAL = RULES.self_referential.patterns.map(p => new RegExp(p, 'i'));
const CANDOR = (RULES.candor_disclaimers ? RULES.candor_disclaimers.patterns : []).map(p => new RegExp(p, 'i'));
const LABEL_VERBISH = new RegExp(RULES.label_fragment.verbish, 'i');

function sentences(text) {
    return text.split(/(?<=[.!?])\s+/).map(s => s.trim()).filter(Boolean);
}

function check(file) {
    const raw = fs.readFileSync(file, 'utf8');
    const lines = raw.split('\n');
    const problems = [];
    let inFence = false;

    lines.forEach((line, i) => {
        const n = i + 1;
        if (/^\s*```/.test(line)) { inFence = !inFence; return; }
        if (inFence) return;
        if (/^\s*\|/.test(line)) return;              // tables
        if (/^\s{0,3}#{1,6}\s/.test(line)) return;    // headings
        if (!line.trim()) return;

        const prose = line.replace(/`[^`]*`/g, 'X').replace(/\[([^\]]*)\]\([^)]*\)/g, '$1');

        for (const word of BANNED) {
            if (new RegExp('\\b' + word + '\\b', 'i').test(prose)) {
                problems.push([n, 'banned word "' + word + '"', line.slice(0, 70)]);
            }
        }
        for (const re of CANDOR) {
            if (re.test(prose)) {
                problems.push([n, 'candor disclaimer — implies your default is to guess', line.slice(0, 70)]);
                break;
            }
        }
        for (const re of SELF_REFERENTIAL) {
            if (re.test(prose.trim())) {
                problems.push([n, 'sentence about the document itself', line.slice(0, 70)]);
            }
        }

        for (const s of sentences(prose)) {
            const words = s.split(/\s+/).filter(Boolean);
            if (words.length > 25) {
                problems.push([n, words.length + '-word sentence, limit is 25', s.slice(0, 70)]);
            }
        }

        // Bold label followed by a fragment is the shape to kill.
        const m = prose.match(/^\s*\*\*([^*]{3,60})\*\*[.:]?\s+(.*)$/);
        if (m && !LABEL_VERBISH.test(m[1])) {
            problems.push([n, 'bold label standing in for a clause', m[1].slice(0, 60)]);
        }

        // Hard wrap: a short prose line whose neighbour continues the paragraph.
        const next = lines[i + 1];
        if (next && next.trim() && !/^\s*[-*+>#|]|^\s*\d+[.)]|^\s*```/.test(next)
            && line.length > 40 && line.length < 100 && !/^\s*[-*+>#|]/.test(line)) {
            problems.push([n, 'looks hard-wrapped', line.slice(0, 60)]);
        }
    });

    console.log(file);
    if (!problems.length) { console.log('    clean'); return 0; }
    for (const [n, what, sample] of problems) {
        console.log('    line ' + String(n).padEnd(4) + what.padEnd(38) + sample);
    }
    return problems.length;
}

const files = process.argv.slice(2);
if (!files.length) { console.error('usage: node tools/check-prose.js FILE...'); process.exit(2); }
let total = 0;
for (const f of files) total += check(f);
console.log('\n' + total + ' item(s) flagged');
process.exit(total ? 1 : 0);
