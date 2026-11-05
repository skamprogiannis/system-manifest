import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import vm from "node:vm";

// Exercise the packaged resolver. QML binding updates still need a session check.
const sourceRoot = process.argv[2];
const read = path => readFileSync(join(sourceRoot, path), "utf8");
const service = read("Services/WellbeingService.qml");
function fn(source, name) {
    const match = source.match(new RegExp(`    function ${name}\\([^]*?\\n    }`));
    assert.ok(match, `Missing function ${name}`);
    return match[0];
}
const context = vm.createContext({
    gameTitleAliases: JSON.parse(service.match(/readonly property var gameTitleAliases: \((.*)\)/)?.[1] ?? "{}"),
    steamGameTitles: {},
    steamTitlesProcess: { running: false },
    desktopEntry: id => id === "com.mitchellh.ghostty" ? { name: "Ghostty" } : null,
    console: { warn() {} },
});
context.root = context;
const paths = read("Common/Paths.qml");
context.Paths = vm.createContext({ isDmsAppId: () => false });
vm.runInContext(fn(paths, "getAppName").replace(/: (string|var)/g, ""), context.Paths);
vm.runInContext(fn(service, "appName"), context);
if (service.includes("    function gameTitle("))
    vm.runInContext(fn(service, "gameTitle"), context);
// This is also the original bug reproduction against an unpatched package.
assert.equal(context.appName("steam_app_0"), "Crowns & Blades");
for (const name of ["refreshGameTitles", "acceptGameTitles"])
    vm.runInContext(fn(service, name), context);
context.acceptGameTitles(JSON.stringify({ steam_app_1158310: "Crusader Kings III", steam_app_365360: "Battle Brothers" }));
assert.equal(context.appName("steam_app_1158310"), "Crusader Kings III");
assert.equal(context.appName("steam_app_365360"), "Battle Brothers");
assert.equal(context.appName("com.mitchellh.ghostty"), "Ghostty");
assert.equal(context.appName("steam_app_99999999"), "steam_app_99999999");
assert.equal(context.appName("constructor"), "constructor");
assert.equal(context.appName(""), "");
context.steamGameTitles.steam_app_0 = "Wrong title";
assert.equal(context.appName("steam_app_0"), "Crowns & Blades", "Aliases take precedence");
for (const invalid of ["", "{", "null", "[]", '{"steam_app_4":null}', '{"steam_app_4":""}', '{"other":"Bad"}']) {
    const previous = context.steamGameTitles;
    context.acceptGameTitles(invalid);
    assert.equal(context.steamGameTitles, previous, "Invalid output must preserve known titles");
}
context.acceptGameTitles('{"steam_app_1158310":"Updated title"}');
assert.equal(context.appName("steam_app_1158310"), "Updated title", "Subsequent scans replace the title map");
assert.equal(context.appName("steam_app_365360"), "steam_app_365360", "Removed games use the existing fallback");
context.refreshGameTitles();
assert.equal(context.steamTitlesProcess.running, true);
context.refreshGameTitles();
assert.equal(context.steamTitlesProcess.running, true);
assert.match(service, /Component.onCompleted: \{\s*refreshGameTitles\(\);/);
assert.match(service, /onStreamFinished: root.acceptGameTitles\(text\)/);
assert.match(service, /command: \["\/nix\/store\/[^"\n]+-dms-steam-titles"\]/);
assert.match(read("Modules/DDash/WellbeingTab.qml"), /WellbeingService.refreshGameTitles\(\);\s*chart.showCurrentWeek\(\);/);
console.log("DMS game title resolution passed");
