import assert from "node:assert/strict";
import { test } from "node:test";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { setTimeout as sleep } from "node:timers/promises";

const packageRoot = process.env.GRAFT_PACKAGE_ROOT;
assert.ok(packageRoot, "GRAFT_PACKAGE_ROOT must name the extracted npm package directory");
const load = (relative) => import(pathToFileURL(join(packageRoot, relative)).href);
const { warmGenericGrammars, extractGeneric, isWarm } = await load("dist/graph/generic.js");
const { resolveEdges } = await load("dist/graph/resolve.js");
const { enrichGraph } = await load("dist/graph/enrich.js");
const { buildContext } = await load("dist/context/build.js");

test("packaged WASM grammar and JavaScript preserve pointer function bodies", async () => {
  await warmGenericGrammars(["c"]);
  assert.equal(isWarm("c"), true);
  const source = "void helper(void) {}\nchar *\nrun(void)\n{\n helper();\n return 0;\n}\n";
  const { nodes, rawEdges } = extractGeneric("fixture.c", source, "c");
  const symbol = nodes.find((node) => node.name === "run");
  assert.equal(symbol.span, "L2-L7");
  assert.match(symbol.body_text, /helper\(\);/);
  const calls = resolveEdges(nodes, rawEdges).filter((edge) => edge.relation === "calls");
  assert.deepEqual(calls.map((edge) => [edge.source, edge.target]), [["fixture.c#run", "fixture.c#helper"]]);
});

test("packaged collector retries blanks and resolves an exact echoed target", async () => {
  const nodes = [{
    id: "fixture.c#run", name: "run", kind: "function", path: "fixture.c",
    span: "L1-L1", signature: "void run(void)", exported: true, origin: "generic",
    body_hash: "fixture", summary_state: "pending", summary: null, crux: null,
  }];
  let attempts = 0;
  const result = await enrichGraph(nodes, new Map(), new Map([["fixture.c", "void run(void) {}"]]), {
    concurrency: 1,
    summarizer: { async describeFile() {
      attempts++;
      return [{ id: "fixture.c#run | function | lines L1-L1", summary: attempts === 1 ? " " : "Runs the entry point.", crux_start: 0, crux_end: 0 }];
    } },
  });
  assert.equal(attempts, 2);
  assert.equal(result.computed, 1);
  assert.equal(nodes[0].summary_state, "ready");
});

test("packaged synthesis defaults to serial calls and reuses its bounded cache", async () => {
  const fixture = mkdtempSync(join(tmpdir(), "graft-package-synthesis-"));
  const originalError = console.error;
  console.error = () => {};
  try {
    mkdirSync(join(fixture, "src"));
    for (let index = 0; index < 6; index++) {
      writeFileSync(join(fixture, "src", `module${index}.ts`),
        `export const value${index} = 1;\n// ${"x".repeat(30_000)}\n`);
    }
    let summaryCalls = 0;
    let synthesisCalls = 0;
    let inFlight = 0;
    let peakInFlight = 0;
    const options = {
      model: "package-fixture", concurrency: 1,
      summarizer: { async summarize(code) { summaryCalls++; return code; } },
      synthesizer: { async synthesize(files) {
        synthesisCalls++;
        inFlight++;
        peakInFlight = Math.max(peakInFlight, inFlight);
        try {
          await sleep(1);
          return [{ name: files[0].path, type: "file", summary: "Fixture module.",
            sources: files.map((file) => file.path), links: [] }];
        } finally { inFlight--; }
      } },
    };
    const first = await buildContext(fixture, options);
    assert.equal(first.files, 6);
    assert.equal(first.batches, 6);
    assert.equal(summaryCalls, 6);
    assert.equal(synthesisCalls, 6);
    assert.equal(peakInFlight, 1);
    summaryCalls = synthesisCalls = 0;
    const second = await buildContext(fixture, options);
    assert.equal(second.cached, 6);
    assert.equal(summaryCalls, 0);
    assert.equal(synthesisCalls, 0);
    assert.equal(second.nodes, first.nodes);
  } finally {
    console.error = originalError;
    rmSync(fixture, { recursive: true, force: true });
  }
});

test("packaged CLI exposes the serial synthesis default and rejects invalid budgets", () => {
  const executable = join(packageRoot, "dist/cli.js");
  const help = execFileSync(process.execPath, [executable, "build", "--help"], { encoding: "utf8" });
  assert.match(help, /synthesis batches[\s\S]*default 1/);
  assert.match(help, /--synth-batch-chars/);
  const globalHelp = execFileSync(process.execPath, [executable, "--help"], { encoding: "utf8" });
  assert.match(globalHelp, /--synth-model/);
  for (const budget of ["0", "-1", "NaN"]) {
    const result = spawnSync(process.execPath, [executable, "build", "--synth-batch-chars", budget],
      { encoding: "utf8" });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /must be a positive number/);
  }
});
