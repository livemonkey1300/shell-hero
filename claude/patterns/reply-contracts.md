# Reply contracts

The last thing in a prompt is the exact shape of the answer. Three kinds cover almost everything.
Why: `../prompt-engineering.md` §8–11.

## 1. Text only, written straight into something

For output that lands verbatim in a file, a commit box or a ticket.

```text
Reply with the commit message only: no code fences, no quotes, no commentary.
```

```text
Output contract:
- Only code. No explanation, no preamble, no markdown fences, no line numbers, no markers.
- Complete lines. Every line carries its full indentation from column 0, in the file's style.
- Only the region. Never repeat the lines before or after it, and never close a bracket the code
  after the region already closes.
- The reply replaces the whole region: any line you leave out is deleted.
```

Pair it with a **sentinel for "nothing"** so the model is never forced to produce something:

```text
If nothing useful should be inserted, reply with exactly <EMPTY>.
```

## 2. One JSON object a parser reads

```text
## Reply

One JSON object, exactly this shape:
{
  "schema": 1,
  "summary": "two to four sentences: what it does, and your overall judgement",
  "findings": [
    {
      "file": "the path as the diff names it",
      "line": 41,
      "quote": "the text of that line, copied exactly from the diff without its number or +/space",
      "severity": "critical | major | minor | nit",
      "category": "an id from the checklist, or one of: correctness, security, tests, docs",
      "title": "one line",
      "body": "the defect and the failure it causes"
    }
  ]
}

Rules:
- "line" is a line number the input shows. A finding about a whole file leaves out "line" and "quote".
- Only files in the input. A finding on any other file is dropped.
- No verdict and no approval: the tool works the verdict out from your findings.
- Plain JSON: no markdown around it, no comments inside it.
```

Notes:
- Every key is shown with **a description of its value in the value's place**, so the shape and its
  meaning are one thing.
- `"schema": 1` lets the parser refuse a reply written for another version of the prompt.
- `"quote"` exists so code can **check the model's citation** — see §11 of the guide.
- The "Rules" say what happens to a bad entry ("dropped"), which the model reads as a reason to
  comply.

The empty case for JSON: `If nothing follows, reply {"edits":[]}`.

## 3. A hand-back token an orchestrator matches

For a subagent or skill another agent dispatches and waits on.

```text
When you finish, your last line is exactly one of:
VERDICT_SATISFACTORY: <KEY> PR #<N>
VERDICT_CHANGES_REQUESTED: <KEY> PR #<N> — <one line>
BLOCKED: <KEY> — <what you need>
Then stop; do not poll, do not wait for a reply.
```

The tokens are **ids**: other prompts grep for them. Reword around them, never rename them.

## 4. The parse → validate → retry loop (code)

```ts
class ShapeError extends Error {}

/** The JSON object in a reply: the whole reply, or the one fenced block, or first { to last }. */
function extractJson(text: string): unknown {
  const t = text.trim();
  try { return JSON.parse(t); } catch {}
  const fenced = /```(?:json)?\s*\n([\s\S]*?)\n```/.exec(t);
  if (fenced) try { return JSON.parse(fenced[1]); } catch {}
  const a = t.indexOf('{'), b = t.lastIndexOf('}');
  if (a >= 0 && b > a) try { return JSON.parse(t.slice(a, b + 1)); } catch {}
  throw new ShapeError('the reply was not one JSON object');
}

async function ask<T>(prompt: string, validate: (v: unknown) => T, tries = 2): Promise<T> {
  let message = prompt;
  for (let n = 0; ; n++) {
    const reply = await model(message);
    try {
      return validate(extractJson(reply));
    } catch (e) {
      if (!(e instanceof ShapeError) || n + 1 >= tries) throw e;
      // The validation error goes back to the model, verbatim: it says exactly what to fix.
      message = `Your reply did not fit the shape: ${e.message}. Reply again with the whole JSON object, fixed.`;
    }
  }
}
```

**Lenient in what you extract, strict in what you accept**, and a retry that tells the model which
field was wrong is worth more than a longer prompt.
