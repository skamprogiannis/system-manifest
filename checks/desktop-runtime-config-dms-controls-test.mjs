import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import vm from "node:vm";

const sourceRoot = process.argv[2];
const read = path => readFileSync(join(sourceRoot, path), "utf8");
function fn(source, name) {
    const match = source.match(new RegExp(`^([ \\t]*)function ${name}\\([^]*?^\\1}`, "m"));
    assert.ok(match, `Missing function ${name}`);
    return match[0].replace(/\): string\s*\{/, ") {");
}

test("notification IPC clears active notifications and history independently", () => {
    const calls = [];
    const context = vm.createContext({
        NotificationService: {
            clearAllNotifications: () => calls.push("active"),
            clearHistory: () => calls.push("history")
        }
    });
    const modal = read("Modals/NotificationModal.qml");
    for (const name of ["clearAll", "clearHistory"])
        vm.runInContext(fn(modal, name), context);
    assert.equal(context.clearAll(), "NOTIFICATION_MODAL_CLEAR_ALL_SUCCESS");
    assert.deepEqual(calls, ["active"]);
    assert.equal(context.clearHistory(), "NOTIFICATION_MODAL_CLEAR_HISTORY_SUCCESS");
    assert.deepEqual(calls, ["active", "history"]);
});

test("per-widget seconds override the global clock without losing AM/PM preferences", () => {
    const format = fn(read("Common/SettingsData.qml"), "getEffectiveTimeFormat");
    const cases = [
        [true, false, true, "hh:mm", "hh:mm:ss"],
        [false, false, true, "h:mm AP", "h:mm:ss AP"],
        [false, true, true, "hh:mm AP", "hh:mm:ss AP"],
        [false, false, false, "h:mm", "h:mm:ss"],
        [false, true, false, "hh:mm", "hh:mm:ss"]
    ];
    for (const [use24HourClock, padHours12Hour, showAmPm, minutes, seconds] of cases) {
        for (const showSeconds of [false, true]) {
            const context = vm.createContext({ use24HourClock, padHours12Hour, showAmPm, showSeconds });
            vm.runInContext(format, context);
            assert.equal(context.getEffectiveTimeFormat(), showSeconds ? seconds : minutes);
            assert.equal(context.getEffectiveTimeFormat(false), minutes);
            assert.equal(context.getEffectiveTimeFormat(true), seconds);
        }
    }
});
