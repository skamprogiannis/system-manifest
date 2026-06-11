{
  patchPython = let
    raw = ''
    from pathlib import Path
    import os

    def replace_all(text: str, old: str, new: str) -> str:
        if old not in text:
            raise SystemExit(f"pattern not found: {old[:80]!r}")
        return text.replace(old, new)

    def insert_after(text: str, anchor: str, addition: str) -> str:
        if anchor not in text:
            raise SystemExit(f"anchor not found: {anchor[:80]!r}")
        if addition in text:
            return text
        return text.replace(anchor, anchor + addition, 1)

    def append_before_final_closing(text: str, addition: str) -> str:
        suffix = "\n}\n"
        if not text.endswith(suffix):
            raise SystemExit("expected QML file to end with a single closing brace")
        if addition in text:
            return text
        return text[:-len(suffix)] + "\n" + addition + suffix

    out = Path(os.environ["OUT_PATH"])
    base = Path(os.environ["BASE_PATH"])
    helper = os.environ["HELPER_DIR"]
    wallpaper_selector = Path(os.environ["QML_PATH"])
    settings_qml = Path(os.environ["SETTINGS_QML"])
    filter_bar_qml = Path(os.environ["FILTER_BAR_QML"])
    filter_button_qml = Path(os.environ["FILTER_BUTTON_QML"])
    settings_toggle_qml = Path(os.environ["SETTINGS_TOGGLE_QML"])
    settings_input_qml = Path(os.environ["SETTINGS_INPUT_QML"])
    settings_combo_qml = Path(os.environ["SETTINGS_COMBO_QML"])
    keybinds_qml = Path(os.environ["KEYBINDS_QML"])
    selector_service_qml = Path(os.environ["SELECTOR_SERVICE_QML"])
    slice_delegate_qml = Path(os.environ["SLICE_DELEGATE_QML"])
    hex_delegate_qml = Path(os.environ["HEX_DELEGATE_QML"])
    tag_cloud_qml = Path(os.environ["TAG_CLOUD_QML"])
    secrets_file = os.environ["SECRETS_FILE_PATH"]

    # selector navigation
    selector_text = wallpaper_selector.read_text()
    selector_text = replace_all(
        selector_text,
        """  function _focusActiveList() {
        if (wallpaperSelector.tagCloudVisible) return
        if (isHexMode) hexListView.forceActiveFocus()
        else if (isGridMode) thumbGridView.forceActiveFocus()
        else sliceListView.forceActiveFocus()
      }""",
        """  function _focusActiveList() {
        if (wallpaperSelector.tagCloudVisible) return
        if (isHexMode) hexListView.forceActiveFocus()
        else if (isGridMode) thumbGridView.forceActiveFocus()
        else if (isMosaicMode) mosaicView.forceActiveFocus()
        else sliceListView.forceActiveFocus()
      }""",
    )
    selector_text = replace_all(
        selector_text,
        """  function _doApply(item, outputs, audioMap, volumeMap) {
        if (item.type === "we") service.applyWE(item.weId, outputs, audioMap, volumeMap)
        else if (item.type === "video") service.applyVideo(item.path, outputs, audioMap, volumeMap)
        else service.applyStatic(item.path, outputs)
      }

      function resetScroll() {""",
        """  function _doApply(item, outputs, audioMap, volumeMap) {
        if (item.type === "we") service.applyWE(item.weId, outputs, audioMap, volumeMap)
        else if (item.type === "video") service.applyVideo(item.path, outputs, audioMap, volumeMap)
        else service.applyStatic(item.path, outputs)
      }

      function _setTypeFilter(type) {
        service.selectedTypeFilter = type
      }

      function _cycleTypeFilter(step) {
        var filters = ["", "static", "video", "we"]
        var current = filters.indexOf(service.selectedTypeFilter)
        if (current < 0)
          current = 0
        service.selectedTypeFilter = filters[(current + step + filters.length) % filters.length]
      }

      function _setSortMode(mode) {
        if (service.sortMode === mode)
          return
        service.sortMode = mode
        service.updateFilteredModel()
      }

      function _toggleSortMode() {
        _setSortMode(service.sortMode === "date" ? "color" : "date")
      }

      function _clearColorFilter() {
        if (service.selectedColorFilter === -1)
          return false
        service.selectedColorFilter = -1
        return true
      }

      function _closeTagCloud() {
        if (!tagCloudVisible)
          return false
        tagCloudVisible = false
        focusTimer.restart()
        return true
      }

      function _openTagCloud() {
        if (tagCloudVisible)
          return false
        settingsOpen = false
        effectsOpen = false
        wallhavenBrowserOpen = false
        steamWorkshopBrowserOpen = false
        tagCloudVisible = true
        return true
      }

      function _toggleTagCloud() {
        if (tagCloudVisible)
          return _closeTagCloud()
        return _openTagCloud()
      }

      function _setDisplayMode(mode) {
        if (Config.displayMode === mode)
          return false
        effectsOpen = false
        if (gridBackOverlay.overlayOpen)
          gridBackOverlay.hide()
        if (hexBackOverlay.overlayOpen)
          hexBackOverlay.hide()
        if (tagCloudVisible)
          _closeTagCloud()
        Config.saveKey("components.wallpaperSelector.displayMode", mode)
        Config._configFile.reload()
        focusTimer.restart()
        return true
      }

      function _focusSettingsPanel() {
        if (!settingsLoader.item)
          return
        if (settingsLoader.item.focusPreferredControl)
          settingsLoader.item.focusPreferredControl()
        else if (settingsLoader.item.forceActiveFocus)
          settingsLoader.item.forceActiveFocus()
      }

      function _toggleSettings() {
        effectsOpen = false
        wallhavenBrowserOpen = false
        steamWorkshopBrowserOpen = false
        if (tagCloudVisible)
          _closeTagCloud()
        settingsOpen = !settingsOpen
        if (settingsOpen)
          Qt.callLater(function() { _focusSettingsPanel() })
        else
          _focusActiveList()
      }

      function _toggleEffects() {
        settingsOpen = false
        wallhavenBrowserOpen = false
        steamWorkshopBrowserOpen = false
        if (tagCloudVisible)
          _closeTagCloud()
        if (gridBackOverlay.overlayOpen)
          gridBackOverlay.hide()
        if (hexBackOverlay.overlayOpen)
          hexBackOverlay.hide()
        effectsOpen = !effectsOpen
        if (!effectsOpen)
          _focusActiveList()
      }

      function _toggleWallhavenBrowser() {
        settingsOpen = false
        effectsOpen = false
        if (tagCloudVisible)
          _closeTagCloud()
        steamWorkshopBrowserOpen = false
        wallhavenBrowserOpen = !wallhavenBrowserOpen
        if (!wallhavenBrowserOpen)
          _focusActiveList()
        return true
      }

      function _toggleSteamWorkshopBrowser() {
        settingsOpen = false
        effectsOpen = false
        if (tagCloudVisible)
          _closeTagCloud()
        wallhavenBrowserOpen = false
        steamWorkshopBrowserOpen = !steamWorkshopBrowserOpen
        if (!steamWorkshopBrowserOpen)
          _focusActiveList()
        return true
      }

      function _setThemeMode(mode) {
        if (Config.matugenMode === mode)
          return false
        Config.saveKey("matugen.mode", mode)
        DaemonClient.retheme(Config.matugenScheme, mode, Config.matugenColorIndex)
        Quickshell.execDetached([Config.scriptsDir + "/sync-dms-wallpaper.sh"])
        return true
      }

      function _findChildByProp(rootItem, propName, propValue) {
        if (!rootItem || !rootItem.children)
          return null
        for (var i = 0; i < rootItem.children.length; i++) {
          var child = rootItem.children[i]
          if (child && child[propName] === propValue)
            return child
          var nested = _findChildByProp(child, propName, propValue)
          if (nested)
            return nested
        }
        return null
      }

      function _currentSliceItem() {
        return sliceListView.currentItem ? sliceListView.currentItem : null
      }

      function _currentGridData() {
        if (thumbGridView.hoveredIdx < 0 || thumbGridView.hoveredIdx >= service.filteredModel.count)
          return null
        return service.filteredModel.get(thumbGridView.hoveredIdx)
      }

      function _currentHexFlatIndex() {
        return hexListView._selectedCol * hexListView._rows + hexListView._selectedRow
      }

      function _currentHexData() {
        var flatIdx = _currentHexFlatIndex()
        if (flatIdx < 0 || flatIdx >= service.filteredModel.count)
          return null
        return service.filteredModel.get(flatIdx)
      }

      function _showGridDetails(data) {
        var delegate = _findChildByProp(thumbGridView.contentItem ? thumbGridView.contentItem : thumbGridView, "index", thumbGridView.hoveredIdx)
        if (!data || !delegate)
          return false
        var gpos = delegate.mapToItem(null, delegate.width / 2, delegate.height / 2)
        gridBackOverlay.show({
          name: data.name,
          path: data.path,
          thumb: data.thumb,
          type: data.type,
          weId: data.weId || "",
          favourite: data.favourite,
          videoFile: data.videoFile || ""
        }, gpos.x, gpos.y, delegate)
        return true
      }

      function _showHexDetails(data) {
        var flatIdx = _currentHexFlatIndex()
        var delegate = _findChildByProp(hexListView.contentItem ? hexListView.contentItem : hexListView, "flatIdx", flatIdx)
        if (!data || !delegate)
          return false
        var gpos = delegate.mapToItem(null, delegate.width / 2, delegate.height / 2)
        hexBackOverlay.show(data, gpos.x, gpos.y, delegate)
        return true
      }

      function _toggleCurrentDetails() {
        if (settingsOpen)
          return false
        if (isGridMode) {
          if (gridBackOverlay.overlayOpen) {
            gridBackOverlay.hide()
            return true
          }
          return _showGridDetails(_currentGridData())
        }
        if (isHexMode) {
          if (hexBackOverlay.overlayOpen) {
            hexBackOverlay.hide()
            return true
          }
          return _showHexDetails(_currentHexData())
        }
        var item = _currentSliceItem()
        if (!item || !item.toggleDetails)
          return false
        item.toggleDetails()
        return true
      }

      function _toggleCurrentFavourite() {
        if (isGridMode) {
          var gridData = gridBackOverlay.overlayOpen && gridBackOverlay.overlayData ? gridBackOverlay.overlayData : _currentGridData()
          if (!gridData)
            return false
          wallpaperSelector.selectorService.toggleFavourite(gridData.name, gridData.weId || "")
          if (gridBackOverlay.overlayOpen && gridBackOverlay.overlayData)
            gridFavToggle.checked = !gridFavToggle.checked
          return true
        }
        if (isHexMode) {
          var hexData = hexBackOverlay.overlayOpen && hexBackOverlay.overlayData ? hexBackOverlay.overlayData : _currentHexData()
          if (!hexData)
            return false
          wallpaperSelector.selectorService.toggleFavourite(hexData.name, hexData.weId || "")
          if (hexBackOverlay.overlayOpen && hexBackOverlay.overlayData)
            overlayFavToggle.checked = !overlayFavToggle.checked
          return true
        }
        var item = _currentSliceItem()
        if (!item || !item.toggleFavourite)
          return false
        item.toggleFavourite()
        return true
      }

      function _focusCurrentTagEditor() {
        if (isGridMode) {
          if (!gridBackOverlay.overlayOpen)
            return false
          Qt.callLater(function() { gridTagField.forceActiveFocus() })
          return true
        }
        if (isHexMode) {
          if (!hexBackOverlay.overlayOpen)
            return false
          Qt.callLater(function() { overlayTagField.forceActiveFocus() })
          return true
        }
        var item = _currentSliceItem()
        if (!item || !item.focusTagInput)
          return false
        return item.focusTagInput()
      }

      function _handleFilterKey(event) {
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
          wallpaperSelector._pendingBrowserKey = ""
          browserKeyTimer.stop()
          if (filterBarBg && ((event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier)) ? filterBarBg.focusLastButton() : filterBarBg.focusFirstButton())) {
            event.accepted = true
            return true
          }
          return false
        }

        if (wallpaperSelector._pendingBrowserKey !== "" && event.modifiers !== Qt.NoModifier) {
          wallpaperSelector._pendingBrowserKey = ""
          browserKeyTimer.stop()
        }

        if ((event.modifiers & Qt.ShiftModifier) && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
          if (event.key === Qt.Key_F || event.text === "F") {
            service.favouriteFilterActive = !service.favouriteFilterActive
            event.accepted = true
            return true
          }
          if (event.key === Qt.Key_C || event.text === "C") {
            if (!_clearColorFilter())
              return false
            event.accepted = true
            return true
          }
          if (event.key === Qt.Key_L || event.text === "L") {
            if (!_setThemeMode("light"))
              return false
            event.accepted = true
            return true
          }
          if (event.key === Qt.Key_D || event.text === "D") {
            if (!_setThemeMode("dark"))
              return false
            event.accepted = true
            return true
          }
        }

        if (event.modifiers !== Qt.NoModifier)
          return false

        if (wallpaperSelector._pendingBrowserKey === "b") {
          wallpaperSelector._pendingBrowserKey = ""
          browserKeyTimer.stop()
          if ((event.key === Qt.Key_W || event.text === "w" || event.text === "W") && Config.wallhavenEnabled) {
            _toggleWallhavenBrowser()
            event.accepted = true
            return true
          }
          if ((event.key === Qt.Key_S || event.text === "s" || event.text === "S") && Config.steamEnabled) {
            _toggleSteamWorkshopBrowser()
            event.accepted = true
            return true
          }
        }

        if (event.key === Qt.Key_B || event.text === "b" || event.text === "B") {
          wallpaperSelector._pendingBrowserKey = "b"
          browserKeyTimer.restart()
          event.accepted = true
          return true
        } else if (event.key === Qt.Key_Minus || event.text === "-" || event.key === Qt.Key_1) {
          _setTypeFilter("")
        } else if (event.key === Qt.Key_2 || event.key === Qt.Key_P || event.text === "p" || event.text === "P") {
          _setTypeFilter("static")
        } else if (event.key === Qt.Key_3 || event.key === Qt.Key_V || event.text === "v" || event.text === "V") {
          _setTypeFilter("video")
        } else if (event.key === Qt.Key_4 || event.key === Qt.Key_E || event.text === "e" || event.text === "E") {
          _setTypeFilter("we")
        } else if ((event.key === Qt.Key_W || event.text === "w" || event.text === "W") && Config.locale !== "" && service.weatherMetadataAvailable) {
          service.weatherFilterActive = !service.weatherFilterActive
        } else if (event.key === Qt.Key_N || event.text === "n") {
          _setSortMode("date")
        } else if (event.key === Qt.Key_C || event.text === "c") {
          _setSortMode("color")
        } else if (event.key === Qt.Key_S || event.text === "s") {
          _toggleSettings()
        } else if (event.key === Qt.Key_T || event.text === "t") {
          _toggleTagCloud()
        } else {
          return false
        }

        event.accepted = true
        return true
      }

      function _handleItemKey(event) {
        if ((event.modifiers & Qt.ControlModifier) && !(event.modifiers & (Qt.AltModifier | Qt.ShiftModifier | Qt.MetaModifier))) {
          var modeHandled = false
          if (event.key === Qt.Key_S) {
            modeHandled = _setDisplayMode("slices")
          } else if (event.key === Qt.Key_H) {
            modeHandled = _setDisplayMode("hex")
          } else if (event.key === Qt.Key_W) {
            modeHandled = _setDisplayMode("wall")
          }
          if (!modeHandled)
            return false
          event.accepted = true
          return true
        }
        if (event.key === Qt.Key_Alt && !(event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier | Qt.MetaModifier))) {
          var altHandled = _toggleCurrentDetails()
          if (!altHandled)
            return false
          event.accepted = true
          return true
        }
        if (event.modifiers !== Qt.NoModifier)
          return false

        var handled = false
        if (event.key === Qt.Key_Space) {
          handled = _toggleCurrentDetails()
        } else if (event.key === Qt.Key_F || event.text === "f") {
          handled = _toggleCurrentFavourite()
        } else if (event.key === Qt.Key_A || event.text === "a") {
          handled = _focusCurrentTagEditor()
        }

        if (!handled)
          return false

        event.accepted = true
        return true
      }

      function resetScroll() {""",
    )
    selector_text = replace_all(
        selector_text,
        """  property bool tagCloudVisible: false
      property bool _filterBarManuallyShown: Config.filterBarAlwaysVisible
      property bool _filterBarHoverRevealed: false
      readonly property bool _filterBarShown: _filterBarManuallyShown || _filterBarHoverRevealed
      property bool wallhavenBrowserOpen: false
      property bool steamWorkshopBrowserOpen: false
      property bool anyBrowserOpen: wallhavenBrowserOpen || steamWorkshopBrowserOpen""",
        """  property bool tagCloudVisible: false
      property bool _filterBarManuallyShown: Config.filterBarAlwaysVisible
      property bool _filterBarHoverRevealed: false
      readonly property bool _filterBarShown: _filterBarManuallyShown || _filterBarHoverRevealed
      property bool wallhavenBrowserOpen: false
      property bool steamWorkshopBrowserOpen: false
      property bool anyBrowserOpen: wallhavenBrowserOpen || steamWorkshopBrowserOpen
      property string _pendingBrowserKey: ""

      Timer {
        id: browserKeyTimer
        interval: 700
        repeat: false
        onTriggered: wallpaperSelector._pendingBrowserKey = ""
      }""",
    )
    selector_text = replace_all(
        selector_text,
        """      onWallhavenToggled: { wallpaperSelector.settingsOpen = false; wallpaperSelector.steamWorkshopBrowserOpen = false; wallpaperSelector.wallhavenBrowserOpen = !wallpaperSelector.wallhavenBrowserOpen }
          onSteamWorkshopToggled: { wallpaperSelector.settingsOpen = false; wallpaperSelector.wallhavenBrowserOpen = false; wallpaperSelector.steamWorkshopBrowserOpen = !wallpaperSelector.steamWorkshopBrowserOpen }
          onTagCloudToggled: {
            wallpaperSelector.tagCloudVisible = !wallpaperSelector.tagCloudVisible
            if (!wallpaperSelector.tagCloudVisible)
              wallpaperSelector._setSelectedTags([])
          }
          onModeToggled: function(mode) {
            Config.saveKey("matugen.mode", mode)
            DaemonClient.retheme(Config.matugenScheme, mode, Config.matugenColorIndex)
          }""",
        """      onWallhavenToggled: wallpaperSelector._toggleWallhavenBrowser()
          onSteamWorkshopToggled: wallpaperSelector._toggleSteamWorkshopBrowser()
          onTagCloudToggled: {
            wallpaperSelector.tagCloudVisible = !wallpaperSelector.tagCloudVisible
            if (!wallpaperSelector.tagCloudVisible)
              wallpaperSelector._setSelectedTags([])
          }
          onFocusListRequested: wallpaperSelector._focusActiveList()
          onModeToggled: function(mode) { wallpaperSelector._setThemeMode(mode) }""",
    )
    selector_text = replace_all(
        selector_text,
        '      property real _yOffset: Math.max(0, (height - _gridContentH) / 2)\n',
        '      property real _arcHeadroom: Config.hexArc ? (Config.hexArcIntensity * _r) : 0\n      property real _yOffset: Math.max(_arcHeadroom, (height - _gridContentH) / 2)\n',
    )
    selector_text = replace_all(
        selector_text,
        'if (event.key === Qt.Key_Down) {',
        'if (event.key === Qt.Key_Down || event.key === Qt.Key_J || event.text === "J") {',
    )
    selector_text = replace_all(
        selector_text,
        '} else if (event.key === Qt.Key_Left) {',
        '} else if (event.key === Qt.Key_Left || event.key === Qt.Key_H || event.text === "H") {',
    )
    selector_text = replace_all(
        selector_text,
        """      Keys.onPressed: function(event) {

            if (event.modifiers & Qt.ShiftModifier) {""",
        """      Keys.onPressed: function(event) {
             if (wallpaperSelector._handleFilterKey(event))
               return
             if (wallpaperSelector.settingsOpen) {
               event.accepted = true
               return
             }
             if (wallpaperSelector._handleItemKey(event))
               return

             if (event.modifiers & Qt.ShiftModifier) {""",
    )
    selector_text = replace_all(
        selector_text,
        '      highlightMoveDuration: Style.animNormal\n      highlight: Item {}',
        """      Keys.onPressed: function(event) {
             if (wallpaperSelector._handleFilterKey(event))
               return
             if (wallpaperSelector.settingsOpen) {
               event.accepted = true
               return
             }
              if (wallpaperSelector._handleItemKey(event))
                return
              if (event.modifiers & Qt.ShiftModifier) {
                if (event.key === Qt.Key_J || event.text === "J") {
                  wallpaperSelector._toggleTagCloud()
                  event.accepted = true
                  return
                }
               if (event.key === Qt.Key_Left) {
                 if (service.selectedColorFilter === -1) service.selectedColorFilter = 99
                 else if (service.selectedColorFilter === 99) service.selectedColorFilter = 11
                 else if (service.selectedColorFilter === 0) service.selectedColorFilter = 99
                 else service.selectedColorFilter--
                 event.accepted = true
                 return
               }
               if (event.key === Qt.Key_Right) {
                 if (service.selectedColorFilter === -1) service.selectedColorFilter = 0
                 else if (service.selectedColorFilter === 11) service.selectedColorFilter = 99
                 else if (service.selectedColorFilter === 99) service.selectedColorFilter = 0
                 else service.selectedColorFilter++
                 event.accepted = true
                  return
                }
              }
              if (event.modifiers & Qt.ShiftModifier)
                return
              if (event.key === Qt.Key_H || event.text === "h") {
               if (currentIndex > 0) {
                 currentIndex--
                 hoveredIdx = currentIndex
                 _ensureVisible(currentIndex)
               }
              event.accepted = true
              return
            }
            if (event.key === Qt.Key_L || event.text === "l") {
              if (currentIndex < count - 1) {
                currentIndex++
                hoveredIdx = currentIndex
                _ensureVisible(currentIndex)
              }
              event.accepted = true
              return
            }
            if (event.key === Qt.Key_K || event.text === "k") {
              var upIdx = currentIndex - Config.gridColumns
              if (upIdx >= 0) {
                currentIndex = upIdx
                hoveredIdx = upIdx
                _ensureVisible(upIdx)
              }
              event.accepted = true
              return
            }
            if (event.key === Qt.Key_J || event.text === "j") {
              var downIdx = currentIndex + Config.gridColumns
              if (downIdx < count) {
                currentIndex = downIdx
                hoveredIdx = downIdx
                _ensureVisible(downIdx)
              }
              event.accepted = true
              return
            }
          }

          highlightMoveDuration: Style.animNormal
          highlight: Item {}""",
    )
    selector_text = replace_all(
        selector_text,
        """      Keys.onPressed: function(event) {
            if (event.modifiers & Qt.ShiftModifier) {""",
        """      Keys.onPressed: function(event) {
             if (wallpaperSelector._handleFilterKey(event))
               return
             if (wallpaperSelector.settingsOpen) {
               event.accepted = true
               return
             }
             if (wallpaperSelector._handleItemKey(event))
               return
             if (event.modifiers & Qt.ShiftModifier) {""",
    )
    selector_text = replace_all(
        selector_text,
        '      onSettingsToggled: { wallpaperSelector.effectsOpen = false; wallpaperSelector.settingsOpen = !wallpaperSelector.settingsOpen; if (!wallpaperSelector.settingsOpen) wallpaperSelector._focusActiveList() }',
        '      onSettingsToggled: wallpaperSelector._toggleSettings()',
    )
    selector_text = replace_all(
        selector_text,
        '      onEffectsToggled: { wallpaperSelector.settingsOpen = false; wallpaperSelector.effectsOpen = !wallpaperSelector.effectsOpen; if (!wallpaperSelector.effectsOpen) wallpaperSelector._focusActiveList() }',
        '      onEffectsToggled: wallpaperSelector._toggleEffects()',
    )
    selector_text = replace_all(
        selector_text,
        """      onTagCloudToggled: {
            wallpaperSelector.tagCloudVisible = !wallpaperSelector.tagCloudVisible
            if (!wallpaperSelector.tagCloudVisible)
              wallpaperSelector._setSelectedTags([])
          }""",
        '      onTagCloudToggled: wallpaperSelector._toggleTagCloud()',
    )
    wallpaper_selector.write_text(selector_text)

    selector_service_text = selector_service_qml.read_text()
    selector_service_text = replace_all(
        selector_service_text,
        """  function applyVideo(path, outputs, audioMap, volumeMap) {
        var neighbors = _collectNeighbors(path)
        var screens = Quickshell.screens.map(function(s) { return s.name })
        DaemonClient.applyVideo(path, outputs, neighbors, screens, audioMap, volumeMap)
      }""",
        """  function applyVideo(path, outputs, audioMap, volumeMap) {
        var neighbors = _collectNeighbors(path)
        var screens = Quickshell.screens.map(function(s) { return s.name })
        DaemonClient.applyVideo(path, outputs, neighbors, screens, audioMap, volumeMap)
      }

      property var _pendingRename: null
      property var _renameCallback: null
      property var _renameProcess: Process {
        id: renameProcess
        command: ["bash", "-c", "true"]
        onExited: function(code) {
          var pending = service._pendingRename
          var callback = service._renameCallback
          service._pendingRename = null
          service._renameCallback = null
          if (!pending)
            return
          if (code !== 0) {
            if (callback) callback(false, "Rename failed")
            return
          }
          if (!service._applyLocalRename(pending.oldName, pending.newName, pending.newPath)) {
            if (callback) callback(false, "Rename succeeded but refresh failed")
            return
          }
          if (callback) callback(true, pending.newName)
        }
      }""",
    )
    selector_service_text = replace_all(
        selector_service_text,
        """        items.push({
              name: name, type: type, thumb: thumb,
              path: type === "static" ? service.wallpaperDir + "/" + name
                  : (type === "video" ? (videoFile || service.videoDir + "/" + name) : ""),
              weId: weId, videoFile: videoFile,
              mtime: mtime, hue: hue, saturation: sat, richness: richness, applyCount: applyCount,
              placeholder: false
            })""",
        """        items.push({
              name: name, type: type, thumb: thumb,
              path: type === "static" ? service.wallpaperDir + "/" + name
                  : (type === "video" ? (videoFile || service.videoDir + "/" + name) : ""),
              weId: weId, videoFile: videoFile,
              mtime: mtime, hue: hue, saturation: sat, richness: richness, applyCount: applyCount,
              favourite: r.favourite === 1,
              placeholder: false
            })""",
    )
    selector_service_text = replace_all(
        selector_service_text,
        """      var item = {
            name: name, type: type, thumb: thumb,
            path: path,
            weId: weId, videoFile: videoFile,
            mtime: mtime, hue: hue, saturation: sat, richness: richness, applyCount: applyCount,
            placeholder: false
          }""",
        """      var item = {
            name: name, type: type, thumb: thumb,
            path: path,
            weId: weId, videoFile: videoFile,
            mtime: mtime, hue: hue, saturation: sat, richness: richness, applyCount: applyCount,
            favourite: isFavourite(name, weId),
            placeholder: false
          }""",
    )
    selector_service_text = replace_all(
        selector_service_text,
        """  function isFavourite(name, weId) {
        var key = weId ? weId : name
        return !!favouritesDb[key]
      }""",
        """  function _setFavouriteState(name, weId, favourite) {
        var key = weId ? weId : name
        for (var i = 0; i < _wallpaperData.length; i++) {
          var itemKey = _wallpaperData[i].weId ? _wallpaperData[i].weId : _wallpaperData[i].name
          if (itemKey === key) {
            _wallpaperData[i].favourite = favourite
            break
          }
        }
        for (var j = 0; j < filteredModel.count; j++) {
          var filteredKey = filteredModel.get(j).weId ? filteredModel.get(j).weId : filteredModel.get(j).name
          if (filteredKey === key)
            filteredModel.setProperty(j, "favourite", favourite)
        }
      }

      function isFavourite(name, weId) {
        var key = weId ? weId : name
        return !!favouritesDb[key]
      }""",
    )
    selector_service_text = replace_all(
        selector_service_text,
        """  function toggleFavourite(name, weId) {
        var key = weId ? weId : name
        var db = JSON.parse(JSON.stringify(favouritesDb))
        if (db[key]) {
          delete db[key]
        } else {
          db[key] = true
        }
        favouritesDb = db
        DaemonClient.setFavourite(key, !!db[key])
        if (favouriteFilterActive) updateFilteredModel()
      }""",
        """  function toggleFavourite(name, weId) {
        var key = weId ? weId : name
        var db = JSON.parse(JSON.stringify(favouritesDb))
        if (db[key]) {
          delete db[key]
        } else {
          db[key] = true
        }
        favouritesDb = db
        _setFavouriteState(name, weId, !!db[key])
        DaemonClient.setFavourite(key, !!db[key])
        if (favouriteFilterActive) updateFilteredModel()
      }""",
    )
    selector_service_text = replace_all(
        selector_service_text,
        """      items.push({
            name: item.name, type: item.type, thumb: item.thumb, path: item.path,
            weId: item.weId, videoFile: item.videoFile, mtime: item.mtime,
            hue: hue, saturation: saturation,
            richness: (item.richness != null ? item.richness : 0),
            applyCount: (item.applyCount != null ? item.applyCount : 0),
            placeholder: !!item.placeholder
          })""",
        """      items.push({
            name: item.name, type: item.type, thumb: item.thumb, path: item.path,
            weId: item.weId, videoFile: item.videoFile, mtime: item.mtime,
            hue: hue, saturation: saturation,
            richness: (item.richness != null ? item.richness : 0),
            applyCount: (item.applyCount != null ? item.applyCount : 0),
            favourite: !!item.favourite,
            placeholder: !!item.placeholder
          })""",
    )
    selector_service_text = replace_all(
        selector_service_text,
        """  property var tagsDb: ({})
      property var colorsDb: ({})
      property var weatherDb: ({})
      property var favouritesDb: ({})
      property bool favouriteFilterActive: false
      property bool _favouritesLoaded: false""",
        """  property var tagsDb: ({})
      property var colorsDb: ({})
      property var weatherDb: ({})
      property var favouritesDb: ({})
      property bool favouriteFilterActive: false
      property bool _favouritesLoaded: false
      property bool weatherMetadataAvailable: false

      function _syncWeatherMetadataState() {
        var hasWeather = false
        for (var key in weatherDb) {
          var entry = weatherDb[key]
          if (entry && entry.length > 0) {
            hasWeather = true
            break
          }
        }
        weatherMetadataAvailable = hasWeather
        if (!hasWeather && weatherFilterActive)
          weatherFilterActive = false
      }""",
    )
    selector_service_text = replace_all(
        selector_service_text,
        """      tagsDb = newTags
          colorsDb = newColors
          weatherDb = newWeather
          if (!_favouritesLoaded) {""",
        """      tagsDb = newTags
          colorsDb = newColors
          weatherDb = newWeather
          _syncWeatherMetadataState()
          if (!_favouritesLoaded) {""",
    )
    selector_service_text = replace_all(
        selector_service_text,
        """  onWeatherFilterActiveChanged: {
        if (weatherFilterActive && currentWeather.length === 0) {
          _fetchWeather()
        } else {
          _debouncedUpdate.restart()
        }
      }""",
        """  onWeatherFilterActiveChanged: {
        if (!weatherMetadataAvailable) {
          if (weatherFilterActive)
            weatherFilterActive = false
          return
        }
        if (weatherFilterActive && currentWeather.length === 0) {
          _fetchWeather()
        } else {
          _debouncedUpdate.restart()
        }
      }""",
    )
    selector_service_text = replace_all(
        selector_service_text,
        """    function onItemAnalyzed(key, tags, colors, weather) {
          service.tagsDb[key] = tags
          service.colorsDb[key] = colors
          if (weather && weather.length > 0) service.weatherDb[key] = weather
          service._analysisItemsDirty = true
          if (!WallpaperAnalysisService.running) {
            service._analysisItemsDirty = false
            var tcopy = {}
            for (var tk in service.tagsDb) tcopy[tk] = service.tagsDb[tk]
            service.tagsDb = tcopy
            var ccopy = {}
            for (var ck in service.colorsDb) ccopy[ck] = service.colorsDb[ck]
            service.colorsDb = ccopy
            service._rebuildPopularTags()
          }
        }""",
        """    function onItemAnalyzed(key, tags, colors, weather) {
          service.tagsDb[key] = tags
          service.colorsDb[key] = colors
          if (weather && weather.length > 0) service.weatherDb[key] = weather
          else delete service.weatherDb[key]
          service._syncWeatherMetadataState()
          service._analysisItemsDirty = true
          if (!WallpaperAnalysisService.running) {
            service._analysisItemsDirty = false
            var tcopy = {}
            for (var tk in service.tagsDb) tcopy[tk] = service.tagsDb[tk]
            service.tagsDb = tcopy
            var ccopy = {}
            for (var ck in service.colorsDb) ccopy[ck] = service.colorsDb[ck]
            service.colorsDb = ccopy
            service._rebuildPopularTags()
          }
        }""",
    )
    selector_service_text = replace_all(
        selector_service_text,
        """    function onFileRenamed(oldName, newName) {
          console.log("[WSS] onFileRenamed: " + oldName + " -> " + newName)

          for (var i = 0; i < service.filteredModel.count; i++) {
            if (service.filteredModel.get(i).name === oldName) {
              service.filteredModel.setProperty(i, "name", newName)
              service.filteredModel.setProperty(i, "path", service.wallpaperDir + "/" + newName)
              break
            }
          }

          for (var j = 0; j < _wallpaperData.length; j++) {
            if (_wallpaperData[j].name === oldName) {
              _wallpaperData[j].name = newName
              _wallpaperData[j].path = service.wallpaperDir + "/" + newName
              break
            }
          }

          delete _wallpaperDataKeys[oldName]
          _wallpaperDataKeys[newName] = true
        }""",
        """    function onFileRenamed(oldName, newName) {
          console.log("[WSS] onFileRenamed: " + oldName + " -> " + newName)
          service._applyLocalRename(oldName, newName)
        }""",
    )
    selector_service_text = replace_all(
        selector_service_text,
        """  function deleteWallpaperItem(type, name, weId) {
        for (var i = filteredModel.count - 1; i >= 0; i--) {
          var fi = filteredModel.get(i)
          if (fi.name === name && (fi.weId || "") === (weId || "")) {
            filteredModel.remove(i)
            break
          }
        }

        for (var j = _wallpaperData.length - 1; j >= 0; j--) {
          var wi = _wallpaperData[j]
          if (wi.name === name && (wi.weId || "") === (weId || "")) {
            _wallpaperData.splice(j, 1)
            _wallpaperData = _wallpaperData
            break
          }
        }

        DaemonClient.deleteItem(name, type, weId || "")
      }""",
        """  function _fileExtension(name) {
        var dotIndex = name.lastIndexOf(".")
        return dotIndex === -1 ? "" : name.substring(dotIndex)
      }

      function _fileStem(name) {
        return name.replace(/\\.[^.]+$/, "")
      }

      function _findWallpaperDataIndex(name, weId) {
        for (var i = 0; i < _wallpaperData.length; i++) {
          var item = _wallpaperData[i]
          if (item.name === name && (item.weId || "") === (weId || ""))
            return i
        }
        return -1
      }

      function _itemPathFor(type, name, videoFile) {
        if (type === "video")
          return (videoFile && videoFile.length > 0) ? videoFile : (videoDir + "/" + name)
        return wallpaperDir + "/" + name
      }

      function _cloneValue(value) {
        return JSON.parse(JSON.stringify(value))
      }

      function _uniqueKeys(keys) {
        var seen = {}
        var out = []
        for (var i = 0; i < keys.length; i++) {
          var key = keys[i]
          if (!key || seen[key])
            continue
          seen[key] = true
          out.push(key)
        }
        return out
      }

      function _localLookupKeys(name, thumb) {
        return _uniqueKeys([
          name,
          _fileStem(name),
          ImageService.thumbKey(thumb, name)
        ])
      }

      function _firstDefinedValue(db, keys) {
        for (var i = 0; i < keys.length; i++) {
          var key = keys[i]
          if (key && db[key] !== undefined)
            return db[key]
        }
        return undefined
      }

      function _assignAliases(db, keys, value) {
        var next = JSON.parse(JSON.stringify(db))
        for (var i = 0; i < keys.length; i++) {
          var key = keys[i]
          if (key)
            next[key] = _cloneValue(value)
        }
        return next
      }

      function _syncRenamedItemState(item, newName) {
        var oldKeys = _localLookupKeys(item.name, item.thumb)
        var newKeys = _localLookupKeys(newName, item.thumb)

        var tags = _firstDefinedValue(tagsDb, oldKeys)
        if (tags !== undefined) {
          tagsDb = _assignAliases(tagsDb, newKeys, tags)
          _rebuildPopularTags()
        }

        var colors = _firstDefinedValue(colorsDb, oldKeys)
        if (colors !== undefined)
          colorsDb = _assignAliases(colorsDb, newKeys, colors)

        var weather = _firstDefinedValue(weatherDb, oldKeys)
        if (weather !== undefined) {
          weatherDb = _assignAliases(weatherDb, newKeys, weather)
          _syncWeatherMetadataState()
        }

        var favourite = favouritesDb[item.name]
        if (favourite !== undefined) {
          var nextFavs = JSON.parse(JSON.stringify(favouritesDb))
          nextFavs[newName] = favourite
          favouritesDb = nextFavs
          DaemonClient.setFavourite(newName, !!favourite)
          DaemonClient.setFavourite(item.name, false)
        }

        if (tags !== undefined || colors !== undefined)
          DaemonClient.updateAnalysis(_fileStem(newName), tags !== undefined ? tags : null, colors !== undefined ? colors : null, null, item.hue, item.saturation)
      }

      function _applyLocalRename(oldName, newName, forcedPath) {
        var itemIndex = _findWallpaperDataIndex(oldName, "")
        if (itemIndex === -1)
          return false

        var item = _wallpaperData[itemIndex]
        var newPath = forcedPath || _itemPathFor(item.type, newName, item.type === "video" ? item.path.replace(item.name, newName) : "")

        _syncRenamedItemState(item, newName)

        item.name = newName
        item.path = newPath
        if (item.type === "video")
          item.videoFile = newPath
        _wallpaperData = _wallpaperData

        for (var i = 0; i < filteredModel.count; i++) {
          var filtered = filteredModel.get(i)
          if (filtered.name === oldName && (filtered.weId || "") === "") {
            filteredModel.setProperty(i, "name", newName)
            filteredModel.setProperty(i, "path", newPath)
            if (item.type === "video")
              filteredModel.setProperty(i, "videoFile", newPath)
          }
        }

        delete _wallpaperDataKeys[oldName]
        _wallpaperDataKeys[newName] = true
        return true
      }

      function renameWallpaperItem(item, requestedBaseName, callback) {
        if (!item || item.type === "we") {
          if (callback) callback(false, "Only local pics and vids can be renamed")
          return
        }
        if (_pendingRename) {
          if (callback) callback(false, "Another rename is already running")
          return
        }

        var trimmed = requestedBaseName.replace(/^\\s+|\\s+$/g, "")
        if (!trimmed) {
          if (callback) callback(false, "Enter a new name")
          return
        }
        if (trimmed === "." || trimmed === ".." || /[\/\0]/.test(trimmed)) {
          if (callback) callback(false, "Name contains invalid characters")
          return
        }

        var newName = trimmed + _fileExtension(item.name)
        if (newName === item.name) {
          if (callback) callback(true, newName)
          return
        }
        if (_findWallpaperDataIndex(newName, "") !== -1) {
          if (callback) callback(false, "A wallpaper with that name already exists")
          return
        }

        var newPath = _itemPathFor(item.type, newName, item.type === "video" ? item.path.replace(item.name, newName) : "")
        _pendingRename = {
          oldName: item.name,
          newName: newName,
          newPath: newPath
        }
        _renameCallback = callback || null
        _renameProcess.command = ["mv", "--", item.path, newPath]
        _renameProcess.running = true
      }

      function deleteWallpaperItem(type, name, weId) {
        for (var i = filteredModel.count - 1; i >= 0; i--) {
          var fi = filteredModel.get(i)
          if (fi.name === name && (fi.weId || "") === (weId || "")) {
            filteredModel.remove(i)
            break
          }
        }

        for (var j = _wallpaperData.length - 1; j >= 0; j--) {
          var wi = _wallpaperData[j]
          if (wi.name === name && (wi.weId || "") === (weId || "")) {
            _wallpaperData.splice(j, 1)
            _wallpaperData = _wallpaperData
            break
          }
        }

        DaemonClient.deleteItem(name, type, weId || "")
      }""",
    )
    # filter bar keyboard
    filter_bar_text = filter_bar_qml.read_text()
    filter_bar_text = replace_all(
        filter_bar_text,
        """    property bool tagCloudOpen: false
        property bool weatherFilterActive: false

        signal settingsToggled()""",
        """    property bool tagCloudOpen: false
        property bool weatherFilterActive: false

        function _collectFocusableButtons(rootItem, out) {
            if (!rootItem || rootItem.visible === false || rootItem.enabled === false)
                return
            if (rootItem !== filterBar && rootItem.activeFocusOnTab && rootItem.forceActiveFocus)
                out.push(rootItem)
            if (!rootItem.children)
                return
            for (var i = 0; i < rootItem.children.length; i++)
                _collectFocusableButtons(rootItem.children[i], out)
        }

        function _focusButtonEdge(last) {
            var buttons = []
            _collectFocusableButtons(filterRow, buttons)
            if (buttons.length === 0)
                return false
            buttons[last ? buttons.length - 1 : 0].forceActiveFocus()
            return true
        }

        function focusFirstButton() { return _focusButtonEdge(false) }
        function focusLastButton() { return _focusButtonEdge(true) }

        function _restoreListFocusIfNeeded(focused) {
            if (!focused)
                return
            Qt.callLater(function() { filterBar.focusListRequested() })
        }

        signal focusListRequested()
        signal settingsToggled()""",
    )
    filter_bar_text = replace_all(
        filter_bar_text,
        """                onClicked: {
                        if (isActive) filterBar.service.selectedTypeFilter = ""
                        else filterBar.service.selectedTypeFilter = modelData.type
                    }""",
        """                onClicked: {
                        if (isActive) filterBar.service.selectedTypeFilter = ""
                        else filterBar.service.selectedTypeFilter = modelData.type
                        filterBar._restoreListFocusIfNeeded(activeFocus)
                    }""",
    )
    filter_bar_text = replace_all(
        filter_bar_text,
        """                onClicked: {
                        filterBar.service.sortMode = modelData.mode
                        filterBar.service.updateFilteredModel()
                    }""",
        """                onClicked: {
                        filterBar.service.sortMode = modelData.mode
                        filterBar.service.updateFilteredModel()
                        filterBar._restoreListFocusIfNeeded(activeFocus)
                    }""",
    )
    filter_bar_text = replace_all(
        filter_bar_text,
        """        FilterButton {
                colors: filterBar.colors
                icon: "\\u{f02d1}"
                tooltip: "Favourites"
                isActive: filterBar.service ? filterBar.service.favouriteFilterActive : false
                onClicked: filterBar.service.favouriteFilterActive = !filterBar.service.favouriteFilterActive
            }""",
        """        FilterButton {
                colors: filterBar.colors
                icon: "\\u{f02d1}"
                tooltip: "Favourites"
                isActive: filterBar.service ? filterBar.service.favouriteFilterActive : false
                onClicked: {
                    filterBar.service.favouriteFilterActive = !filterBar.service.favouriteFilterActive
                    filterBar._restoreListFocusIfNeeded(activeFocus)
                }
            }""",
    )
    filter_bar_text = replace_all(
        filter_bar_text,
        """        FilterButton {
                visible: Config.locale !== ""
                colors: filterBar.colors
                icon: "\\u{f0590}"
                tooltip: filterBar.weatherFilterActive
                    ? ("Weather filter ON" + (filterBar.service ? " (" + filterBar.service.currentWeather.join(", ") + ")" : ""))
                    : "Filter by local weather"
                isActive: filterBar.weatherFilterActive
                onClicked: {
                    filterBar.weatherFilterActive = !filterBar.weatherFilterActive
                    if (filterBar.service)
                        filterBar.service.weatherFilterActive = filterBar.weatherFilterActive
                }
            }""",
        """        FilterButton {
                visible: Config.locale !== "" && filterBar.service && filterBar.service.weatherMetadataAvailable
                colors: filterBar.colors
                icon: "\\u{f0590}"
                tooltip: filterBar.weatherFilterActive
                    ? ("Match current weather tags" + (filterBar.service ? " (" + filterBar.service.currentWeather.join(", ") + ")" : ""))
                    : "Match current local weather against wallpaper weather tags"
                isActive: filterBar.weatherFilterActive
                onClicked: {
                    filterBar.weatherFilterActive = !filterBar.weatherFilterActive
                    if (filterBar.service)
                        filterBar.service.weatherFilterActive = filterBar.weatherFilterActive
                    filterBar._restoreListFocusIfNeeded(activeFocus)
                }
            }""",
    )
    filter_bar_text = replace_all(
        filter_bar_text,
        """        FilterButton {
                colors: filterBar.colors
                icon: "\\u{f0599}"
                tooltip: "Light mode"
                isActive: Config.matugenMode === "light"
                onClicked: filterBar.modeToggled("light")
            }""",
        """        FilterButton {
                colors: filterBar.colors
                icon: "\\u{f0599}"
                tooltip: "Light mode"
                isActive: Config.matugenMode === "light"
                onClicked: {
                    filterBar.modeToggled("light")
                    filterBar._restoreListFocusIfNeeded(activeFocus)
                }
            }""",
    )
    filter_bar_text = replace_all(
        filter_bar_text,
        """        FilterButton {
                colors: filterBar.colors
                icon: "\\u{f0594}"
                tooltip: "Dark mode"
                isActive: Config.matugenMode === "dark"
                onClicked: filterBar.modeToggled("dark")
            }""",
        """        FilterButton {
                colors: filterBar.colors
                icon: "\\u{f0594}"
                tooltip: "Dark mode"
                isActive: Config.matugenMode === "dark"
                onClicked: {
                    filterBar.modeToggled("dark")
                    filterBar._restoreListFocusIfNeeded(activeFocus)
                }
            }""",
    )
    filter_bar_qml.write_text(filter_bar_text)
    # tag cloud keyboard
    tag_cloud_text = tag_cloud_qml.read_text()
    tag_cloud_text = replace_all(
        tag_cloud_text,
        """    readonly property bool searchFocused: tagSearchInput.activeFocus

        signal escapePressed()
        signal closeRequested()

        function reset() {
            tagSearchInput.text = ""
            _tagSearchQuery = ""
            if (service) {
                service.selectedTags = []
                service.updateFilteredModel(true)
            }
            _recomputeTags()
        }""",
        """    readonly property bool searchFocused: tagSearchInput.activeFocus
        readonly property bool chipFocusActive: chipFocusScope.activeFocus

        signal escapePressed()
        signal closeRequested()

        function reset() {
            _focusedChipIndex = -1
            tagSearchInput.text = ""
            _tagSearchQuery = ""
            if (service) {
                service.selectedTags = []
                service.updateFilteredModel(true)
            }
            _recomputeTags()
        }

        function _chipItems() {
            var items = []
            if (!tagCloudFlow || !tagCloudFlow.children)
                return items
            for (var i = 0; i < tagCloudFlow.children.length; i++) {
                var child = tagCloudFlow.children[i]
                if (child && child._isTagChip === true)
                    items.push(child)
            }
            return items
        }

        function _chipItemAt(targetIndex) {
            var items = _chipItems()
            for (var i = 0; i < items.length; i++) {
                if (items[i].chipIndex === targetIndex)
                    return items[i]
            }
            return null
        }

        function focusSearchField() {
            _focusedChipIndex = -1
            Qt.callLater(function() { tagSearchInput.forceActiveFocus() })
        }

        function focusChipRow(fromEnd) {
            var items = _chipItems()
            if (items.length === 0)
                return false
            if (_focusedChipIndex < 0 || !_chipItemAt(_focusedChipIndex))
                _focusedChipIndex = fromEnd ? items[items.length - 1].chipIndex : items[0].chipIndex
            Qt.callLater(function() { chipFocusScope.forceActiveFocus() })
            return true
        }

        function moveChipFocus(step) {
            var items = _chipItems()
            if (items.length === 0)
                return false
            var currentPos = -1
            for (var i = 0; i < items.length; i++) {
                if (items[i].chipIndex === _focusedChipIndex) {
                    currentPos = i
                    break
                }
            }
            if (currentPos === -1)
                currentPos = step < 0 ? items.length : -1
            var nextPos = (currentPos + step + items.length) % items.length
            _focusedChipIndex = items[nextPos].chipIndex
            Qt.callLater(function() { chipFocusScope.forceActiveFocus() })
            return true
        }

        function moveChipFocusVertical(direction) {
            var currentItem = _chipItemAt(_focusedChipIndex)
            if (!currentItem)
                return focusChipRow(direction < 0)

            var currentRowY = currentItem.y
            var currentCenterX = currentItem.x + currentItem.width / 2
            var bestItem = null
            var bestRowDelta = 0
            var bestDistance = 0
            var items = _chipItems()

            for (var i = 0; i < items.length; i++) {
                var candidate = items[i]
                if (!candidate || candidate === currentItem)
                    continue

                var rowDelta = candidate.y - currentRowY
                if (direction < 0) {
                    if (rowDelta >= -1)
                        continue
                } else {
                    if (rowDelta <= 1)
                        continue
                }

                rowDelta = Math.abs(rowDelta)
                var distance = Math.abs((candidate.x + candidate.width / 2) - currentCenterX)
                if (!bestItem || rowDelta < bestRowDelta - 1 || (Math.abs(rowDelta - bestRowDelta) <= 1 && distance < bestDistance)) {
                    bestItem = candidate
                    bestRowDelta = rowDelta
                    bestDistance = distance
                }
            }

            if (!bestItem) {
                if (direction < 0) {
                    focusSearchField()
                    return true
                }
                return false
            }

            _focusedChipIndex = bestItem.chipIndex
            Qt.callLater(function() { chipFocusScope.forceActiveFocus() })
            return true
        }

        function _toggleTag(tag, preferChipFocus) {
            var svc = service
            if (!svc)
                return
            var tags = svc.selectedTags.slice()
            var idx = tags.indexOf(tag)
            var removing = idx !== -1
            if (removing)
                tags.splice(idx, 1)
            else
                tags.push(tag)
            svc.selectedTags = tags
            svc.updateFilteredModel(true)

            _syncingText = true
            if (removing) {
                var re = new RegExp('\\\\b' + tag + '\\\\b\\\\s*', 'i')
                tagSearchInput.text = tagSearchInput.text.replace(re, "").replace(/^\\s+/, "")
            } else {
                var cur = tagSearchInput.text
                var suffix = (cur.length > 0 && cur[cur.length - 1] !== " ") ? " " : ""
                tagSearchInput.text = cur + suffix + tag + ' '
            }
            _syncingText = false
            _recomputeTags()

            Qt.callLater(function() {
                if (preferChipFocus && tagCloud._visibleTagsCache.length > 0) {
                    if (tagCloud._focusedChipIndex < 0)
                        tagCloud._focusedChipIndex = 0
                    else if (tagCloud._focusedChipIndex >= tagCloud._visibleTagsCache.length)
                        tagCloud._focusedChipIndex = tagCloud._visibleTagsCache.length - 1
                    chipFocusScope.forceActiveFocus()
                } else {
                    tagSearchInput.forceActiveFocus()
                }
            })
        }

        function toggleFocusedTag() {
            if (_focusedChipIndex < 0 || _focusedChipIndex >= _visibleTagsCache.length)
                return false
            _toggleTag(_visibleTagsCache[_focusedChipIndex].tag, true)
            return true
        }""",
    )
    tag_cloud_text = replace_all(
        tag_cloud_text,
        """    onTagCloudVisibleChanged: {
            console.log("[TagCloud] tagCloudVisible=" + tagCloudVisible + " service=" + (service ? "yes" : "null") + " popularTags=" + (service ? service.popularTags.length : "n/a"))
            if (tagCloudVisible) {
                tagCloudFlow._settled = false
                _entranceActive = true
                _recomputeTags()
                _entranceTimer.start()
                _focusTimer.start()
            } else {
                _entranceActive = false
            }
        }

        Timer { id: _focusTimer; interval: 0; onTriggered: tagSearchInput.forceActiveFocus() }""",
        """    onTagCloudVisibleChanged: {
            console.log("[TagCloud] tagCloudVisible=" + tagCloudVisible + " service=" + (service ? "yes" : "null") + " popularTags=" + (service ? service.popularTags.length : "n/a"))
            if (tagCloudVisible) {
                _focusedChipIndex = -1
                tagCloudFlow._settled = false
                _entranceActive = true
                _recomputeTags()
                _entranceTimer.start()
                _focusTimer.start()
            } else {
                _focusedChipIndex = -1
                _entranceActive = false
            }
        }

        Timer { id: _focusTimer; interval: 0; onTriggered: tagCloud.focusSearchField() }""",
    )
    tag_cloud_text = replace_all(
        tag_cloud_text,
        """    property string _tagSearchQuery: ""
        property string _autoSuggestion: ""
        property var _visibleTagsCache: []
        property bool _syncingText: false
        property bool _tagsDirty: true
        property bool _entranceActive: false
        property var _pendingTagsCache: null

        Timer {""",
        """    property string _tagSearchQuery: ""
        property string _autoSuggestion: ""
        property var _visibleTagsCache: []
        property bool _syncingText: false
        property bool _tagsDirty: true
        property bool _entranceActive: false
        property var _pendingTagsCache: null
        property int _focusedChipIndex: -1

        Item {
            id: chipFocusScope
            width: 1
            height: 1
            opacity: 0
            activeFocusOnTab: true
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Left || event.key === Qt.Key_H || event.text === "h" || event.text === "H") {
                    if (!tagCloud.moveChipFocus(-1))
                        return
                } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L || event.text === "l" || event.text === "L") {
                    if (!tagCloud.moveChipFocus(1))
                        return
                } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K || event.text === "k" || event.text === "K") {
                    if (!tagCloud.moveChipFocusVertical(-1))
                        return
                } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J || event.text === "j" || event.text === "J") {
                    if (!tagCloud.moveChipFocusVertical(1))
                        return
                } else if (event.key === Qt.Key_Backtab) {
                    tagCloud.focusSearchField()
                } else if (event.key === Qt.Key_Tab) {
                    tagCloud.closeRequested()
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                    if (!tagCloud.toggleFocusedTag())
                        return
                } else if (event.key === Qt.Key_Escape) {
                    tagCloud.closeRequested()
                } else {
                    return
                }
                event.accepted = true
            }
        }

        Timer {""",
    )
    tag_cloud_text = replace_all(
        tag_cloud_text,
        """                Keys.onDownPressed: function(event) {
                        if (event.modifiers & Qt.ShiftModifier) {
                            tagCloud.closeRequested()
                            event.accepted = true
                        } else {
                            event.accepted = false
                        }
                    }
                    Keys.onUpPressed: function(event) { event.accepted = false }
                    Keys.onLeftPressed: function(event) {
                        if (event.modifiers & Qt.ShiftModifier) { event.accepted = false }
                    }
                    Keys.onRightPressed: function(event) {
                        if (event.modifiers & Qt.ShiftModifier) { event.accepted = false }
                    }
                    Keys.onTabPressed: function(event) {
                        event.accepted = true
                        var suggest = tagCloud._autoSuggestion
                        if (!suggest) return
                        var partial = tagCloud._tagSearchQuery
                        var raw = text.toLowerCase()
                        var lastIdx = raw.lastIndexOf(partial)
                        if (lastIdx !== -1)
                            tagSearchInput.text = text.substring(0, lastIdx) + suggest + " "
                    }""",
        """                Keys.onDownPressed: function(event) {
                        if (event.modifiers & Qt.ShiftModifier) {
                            tagCloud.closeRequested()
                            event.accepted = true
                        } else {
                            event.accepted = tagCloud.focusChipRow(false)
                        }
                    }
                    Keys.onUpPressed: function(event) { event.accepted = tagCloud.focusChipRow(true) }
                    Keys.onLeftPressed: function(event) {
                        if (event.modifiers & Qt.ShiftModifier) { event.accepted = false }
                    }
                    Keys.onRightPressed: function(event) {
                        if (event.modifiers & Qt.ShiftModifier) { event.accepted = false }
                    }
                    Keys.onTabPressed: function(event) {
                        event.accepted = tagCloud.focusChipRow(false)
                    }
                    Keys.onBacktabPressed: function(event) {
                        tagCloud.closeRequested()
                        event.accepted = true
                    }""",
    )
    tag_cloud_qml.write_text(tag_cloud_text)
    selector_service_qml.write_text(selector_service_text)

    slice_delegate_text = slice_delegate_qml.read_text()
    slice_delegate_text = replace_all(
        slice_delegate_text,
        '    readonly property var _listView: ListView.view\n',
        """    readonly property var _listView: ListView.view

        function toggleDetails() {
            if (delegateItem._listView)
                delegateItem._listView.currentIndex = index
            delegateItem.flipped = !delegateItem.flipped
        }

        function toggleFavourite() {
            favToggle.checked = !favToggle.checked
            delegateItem.service.toggleFavourite(delegateItem.model.name, delegateItem.model.weId || "")
        }

        property bool renameBusy: false
        property bool renameFailed: false
        property string renameNotice: ""

        function _currentRenameStem() {
            return delegateItem.model.name.replace(/\\.[^/.]+$/, "")
        }

        function _resetRenameInput() {
            renameBusy = false
            renameFailed = false
            renameNotice = ""
            renameField.text = _currentRenameStem()
        }

        function submitRename() {
            if (!delegateItem.service || delegateItem.model.type === "we")
                return false
            renameBusy = true
            renameFailed = false
            renameNotice = ""
            delegateItem.service.renameWallpaperItem(delegateItem.model, renameField.text, function(ok, detail) {
                renameBusy = false
                renameFailed = !ok
                renameNotice = ok ? "RENAMED" : detail
                renameNoticeTimer.restart()
                if (ok) {
                    renameField.text = delegateItem._currentRenameStem()
                    delegateItem.flipped = false
                    Qt.callLater(function() {
                        if (delegateItem._listView) {
                            delegateItem._listView.currentIndex = index
                            delegateItem._listView.forceActiveFocus()
                        }
                    })
                } else {
                    Qt.callLater(function() {
                        renameField.selectAll()
                        renameField.forceActiveFocus()
                    })
                }
            })
            return true
        }

         function focusTagInput() {
              if (!delegateItem.flipped)
                  return false
              Qt.callLater(function() { addTagField.forceActiveFocus() })
              return true
         }
         """,
    )
    slice_delegate_text = replace_all(
        slice_delegate_text,
        "    Rectangle {\n        id: typeBadge",
        """    Text {
            id: favouriteBadge
            y: 8
            x: delegateItem.skewOffset >= 0 ? delegateItem._topLeft + 12 : parent.width - delegateItem._skAbs - width - 12
            visible: delegateItem.model.favourite === true
            z: 10
            text: "♥"
            font.family: Style.fontFamily
            font.pixelSize: 18
            font.weight: Font.DemiBold
            color: delegateItem.colors ? delegateItem.colors.primary : "#ff6b81"
            style: Text.Outline
            styleColor: Qt.rgba(0, 0, 0, 0.45)
        }

        Rectangle {
        id: typeBadge""",
    )
    slice_delegate_text = replace_all(
        slice_delegate_text,
        """                        onClicked: {
                                var dir = delegateItem.model.path.substring(0, delegateItem.model.path.lastIndexOf("/"))
                                Qt.openUrlExternally(ImageService.fileUrl(dir))
                                delegateItem.flipped = false
                            }""",
        """                        onClicked: {
                                Qt.openUrlExternally(ImageService.fileUrl(delegateItem.model.path))
                                delegateItem.flipped = false
                            }""",
    )
    slice_delegate_text = replace_all(
        slice_delegate_text,
        """    Timer {
            id: _preheatTimer
            interval: 120
            repeat: false
            onTriggered: {
                if (delegateItem.model && delegateItem.model.path)
                    DaemonClient.preheat(delegateItem.model.path)
            }
        }""",
        """    Timer {
            id: _preheatTimer
            interval: 120
            repeat: false
            onTriggered: {
                if (delegateItem.model && delegateItem.model.path)
                    DaemonClient.preheat(delegateItem.model.path)
            }
        }

        Timer {
            id: renameNoticeTimer
            interval: 2200
            onTriggered: {
                delegateItem.renameNotice = ""
                delegateItem.renameFailed = false
            }
        }""",
    )
    slice_delegate_text = replace_all(
        slice_delegate_text,
        """                Item {
                        id: backTagsSection
                        width: parent.width
                        height: parent.height - y - backActionRow.height - parent.spacing
                        clip: true""",
        """                Item {
                        id: backRenameRow
                        width: parent.width
                        height: delegateItem.model.type === "we" ? 0 : 22
                        visible: delegateItem.model.type !== "we"

                        Rectangle {
                            anchors.fill: parent
                            color: (renameField.activeFocus || delegateItem.renameBusy)
                                ? (delegateItem.colors ? Qt.rgba(delegateItem.colors.surface.r, delegateItem.colors.surface.g, delegateItem.colors.surface.b, 0.5) : Qt.rgba(0, 0, 0, 0.3))
                                : "transparent"
                            border.width: 1
                            border.color: delegateItem.renameFailed
                                ? Qt.rgba(1, 0.4, 0.4, 0.85)
                                : ((renameField.activeFocus || delegateItem.renameBusy)
                                    ? (delegateItem.colors ? Qt.rgba(delegateItem.colors.primary.r, delegateItem.colors.primary.g, delegateItem.colors.primary.b, 0.5) : Qt.rgba(1, 1, 1, 0.3))
                                    : (delegateItem.colors ? Qt.rgba(delegateItem.colors.outline.r, delegateItem.colors.outline.g, delegateItem.colors.outline.b, 0.2) : Qt.rgba(1, 1, 1, 0.1)))
                            Behavior on color { ColorAnimation { duration: Style.animVeryFast } }
                            Behavior on border.color { ColorAnimation { duration: Style.animVeryFast } }
                        }

                        TextInput {
                            id: renameField
                            anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 42
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: Style.fontFamily; font.pixelSize: 10; font.letterSpacing: 0.3
                            color: delegateItem.colors ? delegateItem.colors.surfaceText : "#fff"
                            clip: true
                            selectByMouse: true
                            text: delegateItem._currentRenameStem()
                            onActiveFocusChanged: {
                                if (activeFocus)
                                    selectAll()
                            }
                            Keys.onPressed: function(event) {
                                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    event.accepted = delegateItem.submitRename()
                                } else if (event.key === Qt.Key_Escape) {
                                    delegateItem._resetRenameInput()
                                    if (delegateItem._listView)
                                        delegateItem._listView.forceActiveFocus()
                                    event.accepted = true
                                }
                            }

                            Text {
                                anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                text: "RENAME FILE"
                                font.family: Style.fontFamily; font.pixelSize: 10; font.letterSpacing: 1
                                color: delegateItem.colors ? Qt.rgba(delegateItem.colors.surfaceText.r, delegateItem.colors.surfaceText.g, delegateItem.colors.surfaceText.b, 0.25) : Qt.rgba(1, 1, 1, 0.2)
                                visible: !parent.text && !parent.activeFocus
                            }
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: delegateItem.renameBusy ? "…" : "SAVE"
                            color: delegateItem.renameBusy
                                ? (delegateItem.colors ? delegateItem.colors.primary : Style.fallbackAccent)
                                : (delegateItem.colors ? Qt.rgba(delegateItem.colors.tertiary.r, delegateItem.colors.tertiary.g, delegateItem.colors.tertiary.b, 0.7) : Qt.rgba(1, 1, 1, 0.45))
                            font.family: Style.fontFamily
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.6
                        }

                        MouseArea {
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.right: parent.right
                            width: 38
                            cursorShape: delegateItem.renameBusy ? Qt.ArrowCursor : Qt.PointingHandCursor
                            enabled: !delegateItem.renameBusy
                            onClicked: delegateItem.submitRename()
                        }
                    }

                    Text {
                        width: parent.width
                        height: visible ? implicitHeight : 0
                        visible: delegateItem.model.type !== "we" && delegateItem.renameNotice.length > 0
                        text: delegateItem.renameNotice
                        color: delegateItem.renameFailed
                            ? Qt.rgba(1, 0.45, 0.45, 0.95)
                            : (delegateItem.colors ? delegateItem.colors.primary : Style.fallbackAccent)
                        font.family: Style.fontFamily
                        font.pixelSize: 9
                        font.weight: Font.Medium
                        font.letterSpacing: 0.6
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Item {
                        id: backTagsSection
                        width: parent.width
                        height: parent.height - y - backActionRow.height - parent.spacing
                        clip: true""",
    )
    slice_delegate_qml.write_text(slice_delegate_text)

    hex_delegate_text = hex_delegate_qml.read_text()
    hex_delegate_text = replace_all(
        hex_delegate_text,
        """        Text {
                anchors.centerIn: parent; anchors.horizontalCenterOffset: 1
                text: "▶"; font.pixelSize: 8
                color: hexItem.videoActive
                    ? (hexItem.colors ? hexItem.colors.primaryText : "#000")
                    : (hexItem.colors ? hexItem.colors.primary : Style.fallbackAccent)
            }
        }

        MouseArea {""",
        """        Text {
                anchors.centerIn: parent; anchors.horizontalCenterOffset: 1
                text: "▶"; font.pixelSize: 8
                color: hexItem.videoActive
                    ? (hexItem.colors ? hexItem.colors.primaryText : "#000")
                    : (hexItem.colors ? hexItem.colors.primary : Style.fallbackAccent)
            }
        }

        Text {
            x: hexItem._cx - hexItem._r * hexItem._sin30 + 6
            y: hexItem._cy - hexItem._r * hexItem._cos30 + 7
            visible: hexItem.itemData && hexItem.itemData.favourite === true
            z: 5
            text: "♥"
            font.family: Style.fontFamily
            font.pixelSize: 17
            font.weight: Font.DemiBold
            color: hexItem.colors ? hexItem.colors.primary : "#ff6b81"
            style: Text.Outline
            styleColor: Qt.rgba(0,0,0,0.45)
        }

        MouseArea {""",
    )
    hex_delegate_text = replace_all(
        hex_delegate_text,
        '            opacity: (thumbImage.status === Image.Ready && thumbImage.source != "") ? 0 : 0.08',
        '            opacity: (!hexItem.itemData || hexItem.itemData.placeholder) ? 0 : (thumbImage.status === Image.Ready && thumbImage.source != "") ? 0 : 0.08',
    )
    hex_delegate_text = replace_all(
        hex_delegate_text,
        """            strokeColor: hexItem.isSelected
                    ? (hexItem.colors ? hexItem.colors.primary : Style.fallbackAccent)
                    : Qt.rgba(0, 0, 0, 0.5)""",
        """            strokeColor: (!hexItem.itemData || hexItem.itemData.placeholder)
                    ? "transparent"
                    : hexItem.isSelected
                        ? (hexItem.colors ? hexItem.colors.primary : Style.fallbackAccent)
                        : Qt.rgba(0, 0, 0, 0.5)""",
    )
    hex_delegate_qml.write_text(hex_delegate_text)

    selector_text = replace_all(
        selector_text,
        """          Text {
                anchors.top: parent.top; anchors.right: parent.right
                anchors.margins: 4
                text: "\\u{f0134}"
                font.family: Style.fontFamilyNerdIcons; font.pixelSize: 14
                color: wallpaperSelector.colors ? wallpaperSelector.colors.primary : "#ff8800"
                visible: gridThumbDelegate.model.favourite === true
              }""",
        """          Text {
                anchors.top: parent.top; anchors.right: parent.right
                anchors.margins: 4
                text: "\\u2665"
                font.family: Style.fontFamily; font.pixelSize: 14
                color: wallpaperSelector.colors ? wallpaperSelector.colors.primary : "#ff6b81"
                style: Text.Outline; styleColor: Qt.rgba(0,0,0,0.45)
                visible: gridThumbDelegate.model.favourite === true
              }""",
    )
    selector_text = replace_all(
        selector_text,
        'onClicked: { if (!gridBackOverlay.overlayData) return; var p = gridBackOverlay.overlayData.path; Qt.openUrlExternally(ImageService.fileUrl(p.substring(0, p.lastIndexOf("/")))); gridBackOverlay.hide() }',
        'onClicked: { if (!gridBackOverlay.overlayData) return; Qt.openUrlExternally(ImageService.fileUrl(gridBackOverlay.overlayData.path)); gridBackOverlay.hide() }',
    )
    selector_text = replace_all(
        selector_text,
        'onClicked: { if (!hexBackOverlay.overlayData) return; var p = hexBackOverlay.overlayData.path; Qt.openUrlExternally(ImageService.fileUrl(p.substring(0, p.lastIndexOf("/")))); hexBackOverlay.hide() }',
        'onClicked: { if (!hexBackOverlay.overlayData) return; Qt.openUrlExternally(ImageService.fileUrl(hexBackOverlay.overlayData.path)); hexBackOverlay.hide() }',
    )
    selector_text = replace_all(
        selector_text,
        """      anchors.horizontalCenter: cardContainer.horizontalCenter
          z: 5
          sourceComponent: Component {
            TagCloud {
              parentWidth: cardContainer.width""",
        """      anchors.left: selectorPanel.left
          anchors.right: selectorPanel.right
          z: 5
          sourceComponent: Component {
            TagCloud {
              parentWidth: selectorPanel.width""",
    )
    selector_text = replace_all(
        selector_text,
        """    MosaicView {
          id: mosaicView

          anchors.top: cardContainer.top
          anchors.topMargin: wallpaperSelector.topBarHeight + 35
          anchors.horizontalCenter: parent.horizontalCenter
          width: Config.mosaicWidth
          height: Config.mosaicHeight

          service: service
          colors: wallpaperSelector.colors
          active: wallpaperSelector.cardVisible && !wallpaperSelector.anyBrowserOpen && wallpaperSelector.isMosaicMode
          visible: active

          onItemActivated: function(item) {
            if (item) wallpaperSelector._applyItem(item)
          }
        }""",
        """    MosaicView {
          id: mosaicView

          anchors.top: cardContainer.top
          anchors.topMargin: wallpaperSelector.topBarHeight + 35
          anchors.horizontalCenter: parent.horizontalCenter
          width: Config.mosaicWidth
          height: Config.mosaicHeight

          service: service
          colors: wallpaperSelector.colors
          active: wallpaperSelector.cardVisible && !wallpaperSelector.anyBrowserOpen && wallpaperSelector.isMosaicMode
          visible: active
          activeFocusOnTab: true

          Keys.onEscapePressed: wallpaperSelector.showing = false
          Keys.onPressed: function(event) {
            if (wallpaperSelector._handleFilterKey(event))
              return
            if (wallpaperSelector.settingsOpen) {
              event.accepted = true
              return
            }
            if (wallpaperSelector._handleItemKey(event))
              return
            if (event.modifiers !== Qt.NoModifier)
              return
            if (event.key === Qt.Key_Left || event.key === Qt.Key_H || event.text === "h") {
              mosaicView._applyScroll(-Math.max(120, mosaicView.width * 0.08))
              event.accepted = true
              return
            }
            if (event.key === Qt.Key_Right || event.key === Qt.Key_L || event.text === "l") {
              mosaicView._applyScroll(Math.max(120, mosaicView.width * 0.08))
              event.accepted = true
            }
          }

          onItemActivated: function(item) {
            if (item) wallpaperSelector._applyItem(item)
          }
        }""",
    )
    selector_text = replace_all(
        selector_text,
        """        TagCloud {
              parentWidth: selectorPanel.width
              colors: wallpaperSelector.colors
              service: wallpaperSelector.selectorService
              tagCloudVisible: true
              onEscapePressed: wallpaperSelector._focusActiveList()
              onCloseRequested: {
                wallpaperSelector.tagCloudVisible = false
                wallpaperSelector._setSelectedTags([])
                wallpaperSelector._focusActiveList()
              }
            }""",
        """        TagCloud {
              parentWidth: selectorPanel.width
              colors: wallpaperSelector.colors
              service: wallpaperSelector.selectorService
              tagCloudVisible: true
              onEscapePressed: wallpaperSelector._closeTagCloud()
              onCloseRequested: wallpaperSelector._closeTagCloud()
            }""",
    )
    wallpaper_selector.write_text(selector_text)

    filter_button_text = filter_button_qml.read_text()
    filter_button_text = replace_all(
        filter_button_text,
        '    width: _label.implicitWidth + 24 * Config.uiScale + skew\n    height: 24 * Config.uiScale\n    z: isActive ? 10 : (isHovered ? 5 : 1)\n',
        '    width: _label.implicitWidth + 24 * Config.uiScale + skew\n    height: 24 * Config.uiScale\n    activeFocusOnTab: true\n    z: isActive ? 10 : ((isHovered || activeFocus) ? 5 : 1)\n',
    )
    filter_button_text = replace_all(
        filter_button_text,
        """        property color strokeColor: btn.isActive
                ? Qt.rgba(btn._resolvedActiveColor.r, btn._resolvedActiveColor.g, btn._resolvedActiveColor.b, 0.6)
                : (btn.colors ? Qt.rgba(btn.colors.primary.r, btn.colors.primary.g, btn.colors.primary.b, 0.15) : Qt.rgba(1, 1, 1, 0.08))""",
        """        property color strokeColor: btn.activeFocus
                ? (btn.colors ? Qt.rgba(btn.colors.primary.r, btn.colors.primary.g, btn.colors.primary.b, 0.8) : Qt.rgba(1, 1, 1, 0.45))
                : (btn.isActive
                    ? Qt.rgba(btn._resolvedActiveColor.r, btn._resolvedActiveColor.g, btn._resolvedActiveColor.b, 0.6)
                    : (btn.colors ? Qt.rgba(btn.colors.primary.r, btn.colors.primary.g, btn.colors.primary.b, 0.15) : Qt.rgba(1, 1, 1, 0.08)))""",
    )
    filter_button_text = replace_all(
        filter_button_text,
        '    opacity: btn.activeOpacity\n\n    MouseArea {',
        '    opacity: btn.activeOpacity\n\n    Keys.onReturnPressed: function(event) { btn.clicked(); event.accepted = true }\n    Keys.onSpacePressed: function(event) { btn.clicked(); event.accepted = true }\n\n    MouseArea {',
    )
    filter_button_qml.write_text(filter_button_text)

    # settings keyboard
    settings_toggle_text = settings_toggle_qml.read_text()
    settings_toggle_text = replace_all(
        settings_toggle_text,
        '    property real _skew: 4\n',
        '    property real _skew: 4\n    activeFocusOnTab: true\n',
    )
    settings_toggle_text = replace_all(
        settings_toggle_text,
        """                strokeColor: root.checked
                        ? (root.colors ? Qt.rgba(root.colors.primary.r, root.colors.primary.g, root.colors.primary.b, 0.8) : Style.fallbackAccent)
                        : (root.colors ? Qt.rgba(root.colors.outline.r, root.colors.outline.g, root.colors.outline.b, 0.3) : Qt.rgba(1, 1, 1, 0.1))""",
        """                strokeColor: root.activeFocus
                        ? (root.colors ? Qt.rgba(root.colors.primary.r, root.colors.primary.g, root.colors.primary.b, 0.9) : Qt.rgba(1, 1, 1, 0.6))
                        : (root.checked
                            ? (root.colors ? Qt.rgba(root.colors.primary.r, root.colors.primary.g, root.colors.primary.b, 0.8) : Style.fallbackAccent)
                            : (root.colors ? Qt.rgba(root.colors.outline.r, root.colors.outline.g, root.colors.outline.b, 0.3) : Qt.rgba(1, 1, 1, 0.1)))""",
    )
    settings_toggle_text = replace_all(
        settings_toggle_text,
        '    Text {\n        text: root.label\n',
        """    Keys.onReturnPressed: { if (root.onToggle) root.onToggle(!root.checked) }
        Keys.onSpacePressed: { if (root.onToggle) root.onToggle(!root.checked) }
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Left || event.key === Qt.Key_H || event.text === "h") {
                if (root.onToggle) root.onToggle(false)
                event.accepted = true
            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L || event.text === "l") {
                if (root.onToggle) root.onToggle(true)
                event.accepted = true
            }
        }

        Text {
            text: root.label
    """,
    )
    settings_toggle_qml.write_text(settings_toggle_text)

    settings_input_text = settings_input_qml.read_text()
    settings_input_text = replace_all(
        settings_input_text,
        '            validator: IntValidator { bottom: root.min; top: root.max }\n            onTextEdited: {\n',
        """            validator: IntValidator { bottom: root.min; top: root.max }
                function _commitDelta(delta) {
                    var current = parseInt(text)
                    if (isNaN(current)) current = root.value
                    var next = Math.max(root.min, Math.min(root.max, current + delta))
                    text = next.toString()
                    if (root.onCommit) root.onCommit(next)
                }
                Keys.onUpPressed: function(event) { _commitDelta(1); event.accepted = true }
                Keys.onDownPressed: function(event) { _commitDelta(-1); event.accepted = true }
                onTextEdited: {
    """,
    )
    settings_input_qml.write_text(settings_input_text)

    settings_combo_text = settings_combo_qml.read_text()
    settings_combo_text = replace_all(
        settings_combo_text,
        '    property var model: []\n    property var onSelect\n\n    width: parent ? parent.width : 0\n    spacing: 2 * Config.uiScale\n',
        """    property var model: []
        property var onSelect
        activeFocusOnTab: true

        function _selectOffset(step) {
            if (!root.model || root.model.length === 0)
                return
            var current = root.model.indexOf(root.value)
            if (current < 0)
                current = 0
            var next = (current + step + root.model.length) % root.model.length
            if (root.onSelect)
                root.onSelect(root.model[next])
        }

        width: parent ? parent.width : 0
        spacing: 2 * Config.uiScale

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Left || event.key === Qt.Key_H || event.text === "h") {
                root._selectOffset(-1)
                event.accepted = true
            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L || event.text === "l") {
                root._selectOffset(1)
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                root._selectOffset(1)
                event.accepted = true
            }
        }
    """,
    )
    settings_combo_text = replace_all(
        settings_combo_text,
        """                    property color strokeColor: parent._comboIsActive
                            ? Qt.rgba(fillColor.r, fillColor.g, fillColor.b, 0.6)
                            : (root.colors ? Qt.rgba(root.colors.primary.r, root.colors.primary.g, root.colors.primary.b, 0.15) : Qt.rgba(1, 1, 1, 0.08))""",
        """                    property color strokeColor: root.activeFocus && parent._comboIsActive
                            ? (root.colors ? Qt.rgba(root.colors.primary.r, root.colors.primary.g, root.colors.primary.b, 0.85) : Qt.rgba(1, 1, 1, 0.45))
                            : (parent._comboIsActive
                                ? Qt.rgba(fillColor.r, fillColor.g, fillColor.b, 0.6)
                                : (root.colors ? Qt.rgba(root.colors.primary.r, root.colors.primary.g, root.colors.primary.b, 0.15) : Qt.rgba(1, 1, 1, 0.08)))""",
    )
    settings_combo_qml.write_text(settings_combo_text)

    # keybind help
    keybinds_text = """import QtQuick
import "../.."
import "../../components"

Flow {
    id: root
    property var colors

    width: parent ? parent.width : 0
    spacing: 12

    SettingsCard {
        colors: root.colors
        title: "Navigation"
        width: (parent.width - parent.spacing) / 2

        Repeater {
            model: [
                { key: "← / →",      action: "Navigate items" },
                { key: "↑ / ↓",      action: "Navigate rows (hex/grid)" },
                { key: "H / J / K / L", action: "Navigate with vim-style movement" },
                { key: "Enter",      action: "Apply wallpaper" },
                { key: "Escape",     action: "Close panel / overlay" },
                { key: "Right-click", action: "Flip card (details)" },
                { key: "Space / Alt", action: "Toggle current wallpaper details" },
                { key: "F",          action: "Toggle current wallpaper favourite" },
                { key: "A",          action: "Focus current wallpaper tag editor" },
                { key: "Ctrl + S / H / W", action: "Switch Slices / Hex / Wall view" },
                { key: "Scroll",     action: "Browse wallpapers" }
            ]
            delegate: SettingsRow {
                colors: root.colors
                title: modelData.key
                description: modelData.action
            }
        }
    }

    SettingsCard {
        colors: root.colors
        title: "Settings controls"
        width: (parent.width - parent.spacing) / 2

        Repeater {
            model: [
                { key: "Tab / Shift + Tab", action: "Move focus between controls" },
                { key: "H / L",             action: "Switch tabs, toggles, and option rows" },
                { key: "J / ↓",             action: "Move from tabs into settings controls" },
                { key: "↑ / ↓",             action: "Adjust numeric inputs" },
                { key: "S / Escape",        action: "Close settings" }
            ]
            delegate: SettingsRow {
                colors: root.colors
                title: modelData.key
                description: modelData.action
            }
        }
    }

    SettingsCard {
        colors: root.colors
        title: "Filters"
        width: (parent.width - parent.spacing) / 2

        Repeater {
            model: [
                { key: "Shift + ← / →", action: "Cycle colour filters" },
                { key: "Shift + ↑",     action: "Toggle filter bar" },
                { key: "Shift + ↓",     action: "Toggle tag cloud" },
                { key: "S / T",         action: "Toggle settings / tag cloud" },
                { key: "1 / 2 / 3 / 4", action: "Filter all / static / video / Wallpaper Engine" },
                { key: "P / V / E",     action: "Filter static / video / Wallpaper Engine" },
                { key: "N / C",         action: "Sort newest / colour" },
                { key: "Shift + F / C", action: "Toggle favourites filter / clear colour filter" },
                { key: "W",             action: "Toggle weather filter when available" }
            ]
            delegate: SettingsRow {
                colors: root.colors
                title: modelData.key
                description: modelData.action
            }
        }
    }

    SettingsCard {
        colors: root.colors
        title: "Tags & browsers"
        width: (parent.width - parent.spacing) / 2

        Repeater {
            model: [
                { key: "Shift + L / D", action: "Set light / dark Matugen mode" },
                { key: "B then W / S",  action: "Open Wallhaven / Steam browser" },
                { key: "Tab",           action: "Auto-complete tag" },
                { key: "Enter",         action: "Add tag (in tag input)" },
                { key: "Escape",        action: "Clear search / close" }
            ]
            delegate: SettingsRow {
                colors: root.colors
                title: modelData.key
                description: modelData.action
            }
        }
    }
}
"""
    keybinds_qml.write_text(keybinds_text)

    settings_text = settings_qml.read_text()
    settings_text = replace_all(
        settings_text,
        """  signal closeRequested()

      Keys.onEscapePressed: closeRequested()
      focus: settingsOpen

      MouseArea {""",
        """  signal closeRequested()

      function _focusFirstControl(rootItem) {
        if (!rootItem || rootItem.visible === false || rootItem.enabled === false)
          return false
        if (rootItem !== settingsPanel && rootItem.activeFocusOnTab && rootItem.forceActiveFocus) {
          rootItem.forceActiveFocus()
          return true
        }
        if (!rootItem.children)
          return false
        for (var i = 0; i < rootItem.children.length; i++) {
          if (_focusFirstControl(rootItem.children[i]))
            return true
        }
        return false
      }

      function _focusCurrentTabButton() {
        if (!tabRepeater || tabRepeater.count === 0)
          return false
        for (var i = 0; i < tabRepeater.count; i++) {
          var button = tabRepeater.itemAt(i)
          if (button && button.isActive) {
            button.forceActiveFocus()
            return true
          }
        }
        var firstButton = tabRepeater.itemAt(0)
        if (!firstButton)
          return false
        firstButton.forceActiveFocus()
        return true
      }

      function _focusTabOffset(tabIndex, offset) {
        if (!tabRepeater || tabRepeater.count === 0)
          return false
        var nextIndex = (tabIndex + offset + tabRepeater.count) % tabRepeater.count
        var button = tabRepeater.itemAt(nextIndex)
        if (!button)
          return false
        activeTab = button.tabKey
        button.forceActiveFocus()
        return true
      }

      function focusPreferredControl() {
        if (_focusFirstControl(contentLoader))
          return true
        return _focusCurrentTabButton()
      }

      onSettingsOpenChanged: {
        if (settingsOpen)
          Qt.callLater(function() { focusPreferredControl() })
      }

      Keys.onEscapePressed: closeRequested()
      Keys.onPressed: function(event) {
        if (event.modifiers === Qt.NoModifier && (event.key === Qt.Key_S || event.text === "s")) {
          closeRequested()
          event.accepted = true
        }
      }
      focus: settingsOpen

      MouseArea {""",
    )
    settings_text = replace_all(
        settings_text,
        """    Repeater {
          model: {""",
        """    Repeater {
          id: tabRepeater
          model: {""",
    )
    settings_text = replace_all(
        settings_text,
        """      FilterButton {
            colors: settingsPanel.colors
            label: modelData.label
            skew: settingsPanel._tabSkew
            height: 28
            isActive: settingsPanel.activeTab === modelData.key
            onClicked: settingsPanel.activeTab = modelData.key
          }""",
        """      FilterButton {
            property string tabKey: modelData.key
            property int tabIndex: index
            colors: settingsPanel.colors
            label: modelData.label
            skew: settingsPanel._tabSkew
            height: 28
            isActive: settingsPanel.activeTab === modelData.key
            onClicked: settingsPanel.activeTab = modelData.key
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Left || event.key === Qt.Key_H || event.text === "h") {
                settingsPanel._focusTabOffset(tabIndex, -1)
                event.accepted = true
              } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L || event.text === "l") {
                settingsPanel._focusTabOffset(tabIndex, 1)
                event.accepted = true
              } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J || event.text === "j") {
                if (settingsPanel._focusFirstControl(contentLoader))
                  event.accepted = true
              }
            }
          }""",
    )
    settings_qml.write_text(settings_text)

    for name in ("skwd", "skwd-daemon", "skwd-wall"):
        wrapper = out / "bin" / name
        if not wrapper.exists():
            continue

        text = wrapper.read_text()
        text = text.replace(
            str(base / "share/skwd-wall/shell.qml"),
            str(out / "share/skwd-wall/shell.qml"),
        )
        text = text.replace(
            str(base / "share/skwd-wall/data"),
            str(out / "share/skwd-wall/data"),
        )
        text = text.replace(
            "\nexec ",
            f'\nPATH="{helper}:$PATH"\nexport PATH\nSKWD_SECRETS_FILE="{secrets_file}"\nif [ -f "$SKWD_SECRETS_FILE" ]; then\n  set -a\n  . "$SKWD_SECRETS_FILE"\n  set +a\nfi\nexec ',
            1,
        )
        wrapper.write_text(text)
    '';
  in
    builtins.substring 1 (builtins.stringLength raw) (builtins.replaceStrings ["\n    "] ["\n"] ("\n" + raw));
}
