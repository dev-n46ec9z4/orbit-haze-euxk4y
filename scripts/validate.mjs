// Static checks: project JSON parses, the expected tree mapping exists, and every
// require(...) in src/ resolves to a real module file.
// Usage: node scripts/validate.mjs
import { readFileSync, readdirSync, existsSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const root = new URL("..", import.meta.url).pathname;
const errors = [];

let project;
try {
	project = JSON.parse(readFileSync(join(root, "default.project.json"), "utf8"));
} catch (err) {
	errors.push(`default.project.json is not valid JSON: ${err.message}`);
}

if (project) {
	const tree = project.tree ?? {};
	const expect = [
		[tree.$className, "DataModel", "tree.$className"],
		[tree.ReplicatedStorage?.Shared?.$path, "src/Shared", "ReplicatedStorage.Shared"],
		[tree.ServerScriptService?.Server?.$path, "src/Server", "ServerScriptService.Server"],
		[tree.StarterPlayer?.StarterPlayerScripts?.Client?.$path, "src/Client", "StarterPlayer.StarterPlayerScripts.Client"],
	];
	for (const [actual, wanted, label] of expect) {
		if (actual !== wanted) errors.push(`${label}: expected ${wanted}, got ${actual}`);
	}
}

const walk = (dir) =>
	readdirSync(dir).flatMap((name) => {
		const full = join(dir, name);
		return statSync(full).isDirectory() ? walk(full) : [full];
	});

const moduleExists = (dir, name) => existsSync(join(dir, `${name}.luau`));
const files = walk(join(root, "src")).filter((f) => f.endsWith(".luau"));
let requireCount = 0;

for (const file of files) {
	const rel = relative(root, file);
	if (!/\.(server|client)\.luau$|\.luau$/.test(rel)) errors.push(`${rel}: unexpected extension`);
	const source = readFileSync(file, "utf8");
	const sharedVars = new Set(
		[...source.matchAll(/local\s+(\w+)\s*=\s*ReplicatedStorage:WaitForChild\("Shared"\)\s*$/gm)].map((m) => m[1]),
	);

	for (const match of source.matchAll(/require\(([^\n]*)\)\s*$/gm)) {
		requireCount++;
		const expr = match[1];
		const name = expr.match(/WaitForChild\("(\w+)"\)\)?$/)?.[1];
		let dir;
		if (/^ReplicatedStorage:WaitForChild\("Shared"\):WaitForChild\(/.test(expr)) dir = "src/Shared";
		else if ([...sharedVars].some((v) => expr.startsWith(`${v}:WaitForChild(`))) dir = "src/Shared";
		else if (expr.startsWith("script.Parent:WaitForChild(")) dir = relative(root, join(file, ".."));
		if (!dir || !name) {
			errors.push(`${rel}: unrecognised require ${expr}`);
		} else if (!moduleExists(join(root, dir), name)) {
			errors.push(`${rel}: require target ${dir}/${name}.luau not found`);
		} else if (rel.startsWith("src/Client") && dir !== "src/Shared") {
			errors.push(`${rel}: client may only require ReplicatedStorage.Shared modules`);
		}
	}
}

if (errors.length) {
	console.error(errors.map((e) => `✗ ${e}`).join("\n"));
	process.exit(1);
}
console.log(`✓ default.project.json valid; ${files.length} Luau files, ${requireCount} requires resolved`);
