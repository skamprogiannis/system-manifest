import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import vm from "node:vm";

// Run the packaged selection and visibility code with two compositor outputs.
// QML binding reevaluation is simulated; rendered/Wayland behavior needs a session.
const sourceRoot = process.argv[2];
const read = path => readFileSync(join(sourceRoot, path), "utf8");
function library(path) {
    const context = vm.createContext({});
    vm.runInContext(read(path).replace(/^\.(pragma|import).*$/gm, ""), context);
    return context;
}
function fn(source, name) {
    const match = source.match(new RegExp(`    function ${name}\\([^]*?\\n    }`));
    assert.ok(match, `Missing function ${name}`);
    return match[0];
}
const qml = read("Modules/DBar/Widgets/FocusedApp.qml");
const service = read("Services/CompositorService.qml");
const defaults = library("Common/settings/BarWidgetDefaults.js");
const model = library("Modules/DBar/WidgetModel.js");
const windows = library("Common/WindowModel.js");
const first = { title: "First app", appId: "first", screen: "DP-1" };
const second = { title: "Second app", appId: "second", screen: "DP-2" };
const firstWorkspace = { id: 1 };
const secondWorkspace = { id: 2 };
const Hyprland = {
    focusedMonitor: { name: "DP-1" },
    focusedWorkspace: firstWorkspace,
    toplevels: { values: [
        { wayland: first, workspace: firstWorkspace },
        { wayland: second, workspace: secondWorkspace }
    ] }
};
const ToplevelManager = { activeToplevel: first };
const compositor = vm.createContext({
    compositor: "hyprland", isAqueous: false, isHyprland: true,
    Hyprland, ToplevelManager, WindowModel: windows,
    filterCurrentDisplay: (items, screen) => items.filter(win => win.screen === screen),
    _windowAlive: win => win === first || win === second,
    _fallbackActiveWindow: () => null,
    _retainedWindow: (_screen, previous) => previous,
    windowStateRevision: 0
});
for (const name of ["getFocusedScreenName", "activeWindowForScreen", "windowOnActiveWorkspace"])
    vm.runInContext(fn(service, name), compositor);

function widget(follow) {
    const data = model.normalize([{ id: "focusedWindow", focusedWindowFollowFocus: follow }])[0];
    assert.equal(data.focusedWindowFollowFocus, follow, "Normalization must preserve the opt-in");
    const context = vm.createContext({
        widgetData: data, parentScreen: { name: "DP-1" }, activeWindow: null,
        popoutVisible: false, CompositorService: compositor,
        SettingsData: { widgetOption: defaults.option }
    });
    context.root = context;
    const followExpression = qml.match(/property bool followFocus: (.*)/)?.[1] ?? "false";
    const screenExpression = qml.match(/readonly property string screenName: (.*)/)[1];
    Object.defineProperty(context, "followFocus", { get: () => vm.runInContext(followExpression, context) });
    Object.defineProperty(context, "screenName", { get: () => vm.runInContext(screenExpression, context) });
    vm.runInContext(fn(qml, "updateActiveWindow"), context);
    context.updateActiveWindow();
    return context;
}
function visible(context) {
    const body = qml.match(/readonly property bool hasWindowsOnCurrentWorkspace: \{([^]*?)\n    }/)[1];
    return vm.runInContext(`(function() {${body}\n})()`, context);
}
const following = widget(true);
const local = widget(false);
assert.equal(visible(following), true);
Hyprland.focusedMonitor = { name: "DP-2" };
Hyprland.focusedWorkspace = secondWorkspace;
ToplevelManager.activeToplevel = second;
following.updateActiveWindow();
local.updateActiveWindow();
assert.equal(following.activeWindow, second, "Main-only bar must show the app focused on the other output");
assert.equal(visible(following), true, "Main-only focused-app widget must stay visible");
assert.equal(local.activeWindow, first, "Per-monitor selection must remain unchanged");
assert.equal(visible(local), false, "Per-monitor visibility must remain unchanged");
assert.equal(following.parentScreen.name, "DP-1", "The physical popup anchor must not follow focus");
const popupPositions = [];
Object.assign(following, {
    BarWidgetService: { registrationForItem: () => null },
    visualContent: { mapToItem: () => ({ x: 10, y: 20 }) },
    axis: { edge: "top" }, barThickness: 48, visualWidth: 200, barSpacing: 4,
    barConfig: {}, section: "left"
});
following.SettingsData.getPopupTriggerPosition = () => ({ x: 10, y: 20, width: 200 });
vm.runInContext(fn(read("Modules/SurfaceWidgets/BarPill.qml"), "positionPopout"), following);
following.positionPopout({ setTriggerPosition: (...args) => popupPositions.push(args) });
assert.equal(popupPositions[0][4], following.parentScreen, "Fallback popup must open on the physical bar");

// A monitor transition can occur without a new active-toplevel event.
Hyprland.focusedMonitor = { name: "DP-1" };
ToplevelManager.activeToplevel = first;
Hyprland.focusedWorkspace = firstWorkspace;
const monitorHandler = qml.match(/onScreenNameChanged: (.*)/)?.[1];
assert.ok(monitorHandler, "Screen changes must refresh selection independently");
vm.runInContext(monitorHandler, following);
assert.equal(following.activeWindow, first);
assert.equal(visible(following), true);
Hyprland.focusedWorkspace = { id: 3 };
ToplevelManager.activeToplevel = null;
following.updateActiveWindow();
assert.equal(visible(following), false, "An empty focused workspace must hide the widget");
following.widgetData = { focusedWindowFollowFocus: false };
assert.equal(following.screenName, "DP-1", "Changing widget settings must restore its physical screen");
assert.equal(defaults.option("focusedWindow", null, "focusedWindowFollowFocus"), false);
assert.equal(defaults.option("focusedWindow", {}, "focusedWindowFollowFocus"), false);
assert.match(fn(qml, "syncPopoutState"), /root\.positionPopout\(popout\)/);
assert.match(qml, /const currentScreen = root\.parentScreen;/);
console.log("Focused-app selection, visibility, normalization and monitor-change checks passed.");
