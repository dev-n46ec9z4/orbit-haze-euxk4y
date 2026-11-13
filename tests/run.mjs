// Runs the standalone Luau tests: node tests/run.mjs
// Each test runs in a temp dir holding copies of the src/Shared modules it requires.
// Roblox datatypes (Vector3, Color3) are prepended as local stubs, because the Luau CLI
// sandboxes each module's globals.
import { execFileSync } from "node:child_process";
import { copyFileSync, mkdtempSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const root = new URL("..", import.meta.url).pathname;
const shared = join(root, "src/Shared");
const luau = process.env.LUAU ?? "luau";
const stubs = [
	"local Vector3 = { new = function(x, y, z) return { X = x, Y = y, Z = z } end }",
	"local Color3 = { fromRGB = function(r, g, b) return { R = r, G = g, B = b } end }",
	"",
].join("\n");

let failed = false;
for (const test of readdirSync(join(root, "tests")).filter((f) => f.endsWith(".test.luau"))) {
	const dir = mkdtempSync(join(tmpdir(), "ft-test-"));
	for (const module of readdirSync(shared).filter((f) => f.endsWith(".luau"))) {
		writeFileSync(join(dir, module), stubs + readFileSync(join(shared, module), "utf8"));
	}
	copyFileSync(join(root, "tests", test), join(dir, test));
	try {
		process.stdout.write(execFileSync(luau, [join(dir, test)], { encoding: "utf8" }));
	} catch (err) {
		failed = true;
		process.stdout.write(err.stdout ?? "");
		process.stderr.write(err.stderr ?? String(err));
	}
}
process.exit(failed ? 1 : 0);
