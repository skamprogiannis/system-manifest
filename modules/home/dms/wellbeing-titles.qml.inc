    // Resolve presentation names without changing tracking or limit keys.
    readonly property var gameTitleAliases: (@gameTitleAliases@)
    property var steamGameTitles: ({})

    function gameTitle(appId) {
        if (Object.prototype.hasOwnProperty.call(root.gameTitleAliases, appId))
            return root.gameTitleAliases[appId];
        return Object.prototype.hasOwnProperty.call(root.steamGameTitles, appId) ? root.steamGameTitles[appId] : "";
    }

    function refreshGameTitles() {
        if (!steamTitlesProcess.running)
            steamTitlesProcess.running = true;
    }

    function acceptGameTitles(text) {
        try {
            const titles = JSON.parse(text);
            if (!titles || typeof titles !== "object" || Array.isArray(titles))
                return;
            for (const appId in titles) {
                if (!/^steam_app_[1-9]\d*$/.test(appId) || typeof titles[appId] !== "string" || !titles[appId].trim())
                    return;
            }
            root.steamGameTitles = titles;
        } catch (error) {
            console.warn("Could not read local Steam game titles");
        }
    }

    Process {
        id: steamTitlesProcess
        command: ["@steamTitlesHelper@"]
        stdout: StdioCollector {
            onStreamFinished: root.acceptGameTitles(text)
        }
    }
