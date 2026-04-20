{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  skwdWallBase = inputs.skwd-wall.packages.${pkgs.stdenv.hostPlatform.system}.default;
  homeDir = config.home.homeDirectory;
  steamLibraryDir = "${homeDir}/games/SteamLibrary";
  steamWorkshopDir = "${steamLibraryDir}/steamapps/workshop/content/431960";
  steamWeAssetsDir = "${steamLibraryDir}/steamapps/common/wallpaper_engine/assets";
  skwdScriptDir = "${homeDir}/.config/skwd-wall/scripts";
  skwdSecretsFile = "${homeDir}/.config/skwd-wall/secrets.env";
  skwdDefaultMonitor = "DP-1";

  # Patch QML/runtime: vim keys, per-monitor apply, live config reload
  skwdWallPkg = pkgs.runCommand "skwd-wall-patched" {} ''
    cp -rL ${skwdWallBase} $out
    chmod -R u+w $out

    qml=$out/share/skwd-wall/qml/wallpaper/WallpaperSelector.qml
    settingsQml=$out/share/skwd-wall/qml/wallpaper/SettingsPanel.qml
    filterBarQml=$out/share/skwd-wall/qml/wallpaper/FilterBar.qml
    filterButtonQml=$out/share/skwd-wall/qml/wallpaper/FilterButton.qml
    settingsToggleQml=$out/share/skwd-wall/qml/wallpaper/SettingsToggle.qml
    settingsInputQml=$out/share/skwd-wall/qml/wallpaper/SettingsInput.qml
    settingsComboQml=$out/share/skwd-wall/qml/wallpaper/SettingsCombo.qml
    applyQml=$out/share/skwd-wall/qml/services/WallpaperApplyService.qml
    selectorServiceQml=$out/share/skwd-wall/qml/wallpaper/WallpaperSelectorService.qml
    sliceDelegateQml=$out/share/skwd-wall/qml/wallpaper/SliceDelegate.qml
    hexDelegateQml=$out/share/skwd-wall/qml/wallpaper/HexDelegate.qml
    desktopFile=$out/share/applications/skwd-wall.desktop

    # --- vim-style hjkl aliases for arrow keys ---
    substituteInPlace $qml \
      --replace-fail \
        'event.key === Qt.Key_Left && !(event.modifiers & Qt.ShiftModifier)' \
        '(event.key === Qt.Key_Left || event.key === Qt.Key_H || event.text === "h") && !(event.modifiers & Qt.ShiftModifier)' \
      --replace-fail \
        'event.key === Qt.Key_Right && !(event.modifiers & Qt.ShiftModifier)' \
        '(event.key === Qt.Key_Right || event.key === Qt.Key_L || event.text === "l") && !(event.modifiers & Qt.ShiftModifier)' \
      --replace-fail \
        'event.key === Qt.Key_Up && !(event.modifiers & Qt.ShiftModifier)' \
        '(event.key === Qt.Key_Up || event.key === Qt.Key_K || event.text === "k") && !(event.modifiers & Qt.ShiftModifier)' \
      --replace-fail \
        'event.key === Qt.Key_Down && !(event.modifiers & Qt.ShiftModifier)' \
        '(event.key === Qt.Key_Down || event.key === Qt.Key_J || event.text === "j") && !(event.modifiers & Qt.ShiftModifier)'

    substituteInPlace $desktopFile \
      --replace-fail 'Name=Skwd-wall' 'Name=skwd-wall'
    if grep -q '^GenericName=Skwd-wall$' "$desktopFile"; then
      substituteInPlace $desktopFile \
        --replace-fail 'GenericName=Skwd-wall' 'GenericName=skwd-wall'
    fi

    mkdir -p $out/libexec/skwd-wall
    cat > $out/libexec/skwd-wall/linux-wallpaperengine <<'EOF'
#!${pkgs.bash}/bin/bash
set -euo pipefail

real_engine="${pkgs.linux-wallpaperengine}/bin/linux-wallpaperengine"
workshop_dir="${steamWorkshopDir}"
assets_dir="${steamWeAssetsDir}"

args=()
rewrote_background=0
has_assets_dir=0
expect_bg_value=0
rewrite_background_output=""

rewrite_background() {
  local value="$1"
  rewrite_background_output="$value"
  if [[ "$value" =~ ^[0-9]+$ ]] && [ -d "$workshop_dir/$value" ]; then
    rewrote_background=1
    rewrite_background_output="$workshop_dir/$value"
  fi
}

for arg in "$@"; do
  if [ "$expect_bg_value" -eq 1 ]; then
    rewrite_background "$arg"
    args+=("$rewrite_background_output")
    expect_bg_value=0
    continue
  fi

  case "$arg" in
    --assets-dir)
      has_assets_dir=1
      args+=("$arg")
      ;;
    --bg|-b)
      expect_bg_value=1
      args+=("$arg")
      ;;
    *)
      args+=("$arg")
      ;;
  esac
done

if [ "''${#args[@]}" -gt 0 ]; then
  last_index=$((''${#args[@]} - 1))
  rewrite_background "''${args[$last_index]}"
  args[$last_index]="$rewrite_background_output"
fi

if [ "$rewrote_background" -eq 1 ] && [ "$has_assets_dir" -eq 0 ] && [ -d "$assets_dir" ]; then
  args=(--assets-dir "$assets_dir" "''${args[@]}")
fi

exec "$real_engine" "''${args[@]}"
EOF
    chmod +x $out/libexec/skwd-wall/linux-wallpaperengine

    export OUT_PATH="$out"
    export BASE_PATH="${skwdWallBase}"
    export HELPER_DIR="$out/libexec/skwd-wall"
    export QML_PATH="$qml"
    export SETTINGS_QML="$settingsQml"
    export FILTER_BAR_QML="$filterBarQml"
    export FILTER_BUTTON_QML="$filterButtonQml"
    export SETTINGS_TOGGLE_QML="$settingsToggleQml"
    export SETTINGS_INPUT_QML="$settingsInputQml"
    export SETTINGS_COMBO_QML="$settingsComboQml"
    export APPLY_QML="$applyQml"
    export SELECTOR_SERVICE_QML="$selectorServiceQml"
    export SLICE_DELEGATE_QML="$sliceDelegateQml"
    export HEX_DELEGATE_QML="$hexDelegateQml"
    export SECRETS_FILE_PATH="${skwdSecretsFile}"
    ${pkgs.python3}/bin/python3 <<'PY'
from pathlib import Path
import os

def replace_all(text: str, old: str, new: str) -> str:
    if old not in text:
        raise SystemExit(f"pattern not found: {old[:80]!r}")
    return text.replace(old, new)

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
apply_qml = Path(os.environ["APPLY_QML"])
selector_service_qml = Path(os.environ["SELECTOR_SERVICE_QML"])
slice_delegate_qml = Path(os.environ["SLICE_DELEGATE_QML"])
hex_delegate_qml = Path(os.environ["HEX_DELEGATE_QML"])
secrets_file = os.environ["SECRETS_FILE_PATH"]

selector_text = wallpaper_selector.read_text()
selector_text = replace_all(
    selector_text,
    '    if (item.type === "we") service.applyWE(item.weId)\n',
    '    if (item.type === "we") service.applyWE(item.weId, outputs)\n',
)
selector_text = replace_all(
    selector_text,
    """  function _doApply(item, outputs) {
    if (item.type === "we") service.applyWE(item.weId, outputs)
    else if (item.type === "video") service.applyVideo(item.path, outputs)
    else service.applyStatic(item.path, outputs)
  }

  function resetScroll() {""",
    """  function _doApply(item, outputs) {
    if (item.type === "we") service.applyWE(item.weId, outputs)
    else if (item.type === "video") service.applyVideo(item.path, outputs)
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

  function _toggleSettings() {
    settingsOpen = !settingsOpen
    if (!settingsOpen)
      _focusActiveList()
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
      if (!gridBackOverlay.overlayOpen && !_showGridDetails(_currentGridData()))
        return false
      Qt.callLater(function() { gridTagField.forceActiveFocus() })
      return true
    }
    if (isHexMode) {
      if (!hexBackOverlay.overlayOpen && !_showHexDetails(_currentHexData()))
        return false
      Qt.callLater(function() { overlayTagField.forceActiveFocus() })
      return true
    }
    var item = _currentSliceItem()
    if (!item || !item.focusTagInput)
      return false
    item.focusTagInput()
    return true
  }

  function _handleFilterKey(event) {
    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      _cycleTypeFilter((event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier)) ? -1 : 1)
      event.accepted = true
      return true
    }

    if ((event.modifiers & Qt.ShiftModifier) && (event.key === Qt.Key_L || event.text === "L") && Config.locale !== "" && service.weatherMetadataAvailable) {
      service.weatherFilterActive = !service.weatherFilterActive
      event.accepted = true
      return true
    }

    if ((event.modifiers & Qt.ShiftModifier) && (event.key === Qt.Key_F || event.text === "F")) {
      service.favouriteFilterActive = !service.favouriteFilterActive
      event.accepted = true
      return true
    }

    if (event.key === Qt.Key_W || event.text === "w" || event.text === "W" || event.key === Qt.Key_4) {
      _setTypeFilter("we")
      event.accepted = true
      return true
    }

    if (event.modifiers !== Qt.NoModifier)
      return false

    if (event.key === Qt.Key_1) {
      _setTypeFilter("")
    } else if (event.key === Qt.Key_2) {
      _setTypeFilter("static")
    } else if (event.key === Qt.Key_3) {
      _setTypeFilter("video")
    } else if (event.key === Qt.Key_N || event.text === "n") {
      _setSortMode("date")
    } else if (event.key === Qt.Key_C || event.text === "c") {
      _setSortMode("color")
    } else if (event.key === Qt.Key_S || event.text === "s") {
      _toggleSortMode()
    } else if (event.key === Qt.Key_O || event.text === "o") {
      _toggleSettings()
    } else {
      return false
    }

    event.accepted = true
    return true
  }

  function _handleItemKey(event) {
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
    """      delegate: SliceDelegate {
        colors: wallpaperSelector.colors
        expandedWidth: wallpaperSelector.expandedWidth
        sliceWidth: wallpaperSelector.sliceWidth
        skewOffset: wallpaperSelector.skewOffset
        service: wallpaperSelector.selectorService
        suppressWidthAnim: wallpaperSelector.suppressWidthAnim
      }""",
    """      delegate: SliceDelegate {
        colors: wallpaperSelector.colors
        expandedWidth: wallpaperSelector.expandedWidth
        sliceWidth: wallpaperSelector.sliceWidth
        skewOffset: wallpaperSelector.skewOffset
        service: wallpaperSelector.selectorService
        applyItem: function(item) { wallpaperSelector._applyItem(item) }
        suppressWidthAnim: wallpaperSelector.suppressWidthAnim
      }""",
)
selector_text = replace_all(
    selector_text,
    """            pulledOut: hexBackOverlay.overlayItemKey !== "" && hexBackOverlay.overlayItemKey === ((itemData && ((itemData.weId || "") !== "")) ? itemData.weId : (itemData ? itemData.name : ""))

            onFlipRequested: function(data, gx, gy, sourceItem) {""",
    """            pulledOut: hexBackOverlay.overlayItemKey !== "" && hexBackOverlay.overlayItemKey === ((itemData && ((itemData.weId || "") !== "")) ? itemData.weId : (itemData ? itemData.name : ""))
            applyItem: function(item) { wallpaperSelector._applyItem(item) }

            onFlipRequested: function(data, gx, gy, sourceItem) {""",
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
    '} else if (event.key === Qt.Key_Right) {',
    '} else if (event.key === Qt.Key_Right) {',
)
selector_text = replace_all(
    selector_text,
    """      Keys.onPressed: function(event) {

        if (event.modifiers & Qt.ShiftModifier) {""",
    """      Keys.onPressed: function(event) {
         if (wallpaperSelector._handleFilterKey(event))
           return
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
         if (wallpaperSelector._handleItemKey(event))
           return
         if (event.modifiers & Qt.ShiftModifier) {
           if (event.key === Qt.Key_J || event.text === "J") {
             wallpaperSelector.tagCloudVisible = !wallpaperSelector.tagCloudVisible
             if (!wallpaperSelector.tagCloudVisible)
               wallpaperSelector._setSelectedTags([])
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
         if (wallpaperSelector._handleItemKey(event))
           return
         if (event.modifiers & Qt.ShiftModifier) {""",
)
wallpaper_selector.write_text(selector_text)

selector_service_text = selector_service_qml.read_text()
selector_service_text = replace_all(
    selector_service_text,
    """  function applyWE(id) {
    var screens = Quickshell.screens.map(function(s) { return s.name })
    DaemonClient.applyWE(id, screens)
  }""",
    """  function applyWE(id, screens) {
    var targetScreens = (screens && screens.length > 0)
      ? screens
      : Quickshell.screens.map(function(s) { return s.name })
    DaemonClient.applyWE(id, targetScreens)
  }""",
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
    }""",
    """    function onItemAnalyzed(key, tags, colors, weather) {
      service.tagsDb[key] = tags
      service.colorsDb[key] = colors
      if (weather && weather.length > 0) service.weatherDb[key] = weather
      else delete service.weatherDb[key]
      service._syncWeatherMetadataState()
      service._analysisItemsDirty = true
    }""",
)
filter_bar_text = filter_bar_qml.read_text()
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
            }
        }""",
)
filter_bar_qml.write_text(filter_bar_text)
selector_service_qml.write_text(selector_service_text)

slice_delegate_text = slice_delegate_qml.read_text()
slice_delegate_text = replace_all(
    slice_delegate_text,
    '    property var service\n',
    '    property var service\n    property var applyItem\n',
)
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

    function focusTagInput() {
        if (!delegateItem.flipped)
            delegateItem.toggleDetails()
        Qt.callLater(function() { addTagField.forceActiveFocus() })
    }
    """,
)
slice_delegate_text = replace_all(
    slice_delegate_text,
    """                    if (delegateItem.model.type === "we") {
                        delegateItem.service.applyWE(delegateItem.model.weId)
                    } else if (delegateItem.model.type === "video") {
                        delegateItem.service.applyVideo(delegateItem.model.path)
                    } else {
                        delegateItem.service.applyStatic(delegateItem.model.path)
                    }""",
    """                    if (delegateItem.applyItem) {
                        delegateItem.applyItem(delegateItem.model)
                    } else if (delegateItem.model.type === "we") {
                        delegateItem.service.applyWE(delegateItem.model.weId)
                    } else if (delegateItem.model.type === "video") {
                        delegateItem.service.applyVideo(delegateItem.model.path)
                    } else {
                        delegateItem.service.applyStatic(delegateItem.model.path)
                    }""",
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
slice_delegate_qml.write_text(slice_delegate_text)

hex_delegate_text = hex_delegate_qml.read_text()
hex_delegate_text = replace_all(
    hex_delegate_text,
    '    property var service\n',
    '    property var service\n    property var applyItem\n',
)
hex_delegate_text = replace_all(
    hex_delegate_text,
    """                if (hexItem.itemData.type === "we") {
                    hexItem.service.applyWE(hexItem.itemData.weId)
                } else if (hexItem.itemData.type === "video") {
                    hexItem.service.applyVideo(hexItem.itemData.path)
                } else {
                    hexItem.service.applyStatic(hexItem.itemData.path)
                }""",
    """                if (hexItem.applyItem) {
                    hexItem.applyItem(hexItem.itemData)
                } else if (hexItem.itemData.type === "we") {
                    hexItem.service.applyWE(hexItem.itemData.weId)
                } else if (hexItem.itemData.type === "video") {
                    hexItem.service.applyVideo(hexItem.itemData.path)
                } else {
                    hexItem.service.applyStatic(hexItem.itemData.path)
                }""",
)
hex_delegate_qml.write_text(hex_delegate_text)

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
wallpaper_selector.write_text(selector_text)

filter_button_text = filter_button_qml.read_text()
filter_button_text = replace_all(
    filter_button_text,
    '    width: _label.implicitWidth + 24 + skew\n    height: 24\n    z: isActive ? 10 : (isHovered ? 5 : 1)\n',
    '    width: _label.implicitWidth + 24 + skew\n    height: 24\n    activeFocusOnTab: true\n    z: isActive ? 10 : ((isHovered || activeFocus) ? 5 : 1)\n',
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
    '    opacity: btn.activeOpacity\n\n    Keys.onReturnPressed: btn.clicked()\n    Keys.onSpacePressed: btn.clicked()\n\n    MouseArea {',
)
filter_button_qml.write_text(filter_button_text)

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
    '    property var model: []\n    property var onSelect\n\n    width: parent ? parent.width : 0\n    spacing: 2\n',
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
    spacing: 2

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

settings_text = settings_qml.read_text()
settings_text = replace_all(
    settings_text,
    '_selectorConfigFile.setText(JSON.stringify(data, null, 2) + "\\n")',
    '_selectorConfigFile.setText(JSON.stringify(data, null, 2) + "\\n")\n    Config._configFile.reload()',
)
settings_text = replace_all(
    settings_text,
    '          text: "WIP — Video and WE support coming."',
    '          text: "Choose target outputs before applying a wallpaper."',
)
settings_text = replace_all(
    settings_text,
    '          label: "Locale (weather filter)"',
    '          label: "Weather location"',
)
settings_text = replace_all(
    settings_text,
    '          placeholder: "e.g. London"',
    '          placeholder: "Used by the weather filter, e.g. Athens"',
)
settings_text = replace_all(
    settings_text,
    '{ key: "← / →",         action: "Navigate items" },',
    '{ key: "h / l / ← / →", action: "Navigate items" },',
)
settings_text = replace_all(
    settings_text,
    '{ key: "↑ / ↓",         action: "Navigate rows (hex/grid)" },',
    '{ key: "j / k / ↑ / ↓", action: "Navigate rows (hex/grid)" },',
)
settings_text = replace_all(
    settings_text,
    '{ key: "Shift + ← / →",  action: "Cycle colour filters" },',
    '{ key: "Shift + ← / →", action: "Cycle colour filters" },',
)
settings_text = replace_all(
    settings_text,
    '{ key: "Shift + ↓",      action: "Toggle tag cloud" },',
    '{ key: "Shift + j / ↓", action: "Toggle tag cloud" },',
)
settings_text = replace_all(
    settings_text,
    """          model: [
            { key: "Shift + ← / →", action: "Cycle colour filters" },
            { key: "Shift + j / ↓", action: "Toggle tag cloud" },
            { key: "Tab",            action: "Auto-complete tag" },
            { key: "Enter",          action: "Add tag (in tag input)" },
            { key: "Escape",         action: "Clear search / close" }
          ]""",
    """          model: [
            { key: "1 / 2 / 3 / 4",               action: "Set ALL / PIC / VID / WE" },
            { key: "Tab / Shift + Tab",           action: "Cycle type filters" },
            { key: "W",                           action: "Set Wallpaper Engine filter" },
            { key: "Shift + F",                   action: "Toggle favourites filter" },
            { key: "Shift + L",                   action: "Toggle weather-tag filter" },
            { key: "n / c / s",                   action: "Newest / colour / toggle sort" },
            { key: "o",                           action: "Open settings" },
            { key: "Space",                       action: "Flip current item / close details" },
            { key: "f",                           action: "Toggle favourite for current item" },
            { key: "a",                           action: "Focus add-tag input for current item" },
            { key: "Shift + ← / →",               action: "Cycle colour filters" },
            { key: "Shift + j / ↓",               action: "Toggle tag cloud" },
            { key: "Tag input: Tab",              action: "Auto-complete tag" },
            { key: "Enter",                       action: "Apply current item / add tag in input" },
            { key: "Escape",                      action: "Clear search / close" },
            { key: "Settings: Tab / Shift + Tab", action: "Move between settings controls" },
            { key: "Settings: Enter / Space",     action: "Activate focused button or toggle" },
            { key: "Settings: ← / → / h / l",     action: "Change focused option values" },
            { key: "Settings: ↑ / ↓",             action: "Step focused numeric inputs" }
          ]""",
)
settings_qml.write_text(settings_text)

apply_text = apply_qml.read_text()
apply_text = replace_all(
    apply_text,
    '    function applyStatic(path) {',
    '    function applyStatic(path, outputs) {',
)
apply_text = replace_all(
    apply_text,
    '                "awww img " + JSON.stringify(path) +\n                " --transition-type wipe --transition-angle 45 --transition-duration 0.5"]',
    '                "awww img" + ((outputs && outputs.length > 0) ? (" -o " + JSON.stringify(outputs.join(","))) : "") + " " + JSON.stringify(path) +\n                " --transition-type wipe --transition-angle 45 --transition-duration 0.5"]',
)
apply_text = replace_all(
    apply_text,
    """    function applyVideo(path) {
        _saveState("video", path, "")
        if (Config.isKDE) {
            _applyKdeVideo(path)
        } else {
            mpvProcess.command = ["sh", "-c",
                "pkill awww 2>/dev/null; pkill awww-daemon 2>/dev/null; " +
                "pkill mpvpaper 2>/dev/null; " +
                "pkill -9 -f '[l]inux-wallpaperengine' 2>/dev/null; " +
                "rm -f " + JSON.stringify(videoDir + "/lockscreen-video.mp4") + "; " +
                "nohup setsid mpvpaper -o " + (wallpaperMute ? "'loop --mute=yes'" : "'loop'") + " '*' " + JSON.stringify(path) + " </dev/null >/dev/null 2>&1 &"]
            mpvProcess.running = true
        }
        _extractVideoThumb(path)
        wallpaperApplied("video", _basename(path), path)
    }

    function _applyKdeVideo(path) {""",
    """    function applyVideo(path, outputs) {
        _saveState("video", path, "")
        if (Config.isKDE) {
            _applyKdeVideo(path)
        } else {
            mpvProcess.command = ["sh", "-c",
                "pkill awww 2>/dev/null; pkill awww-daemon 2>/dev/null; " +
                "pkill mpvpaper 2>/dev/null; " +
                "pkill -9 -f '[l]inux-wallpaperengine' 2>/dev/null; " +
                "rm -f " + JSON.stringify(videoDir + "/lockscreen-video.mp4") + "; " +
                _mpvpaperLaunchCmd(path, outputs)]
            mpvProcess.running = true
        }
        _extractVideoThumb(path)
        wallpaperApplied("video", _basename(path), path)
    }

    function _mpvpaperLaunchCmd(path, outputs) {
        var targets = (outputs && outputs.length > 0) ? outputs : ["*"]
        var opts = wallpaperMute ? "'loop --mute=yes'" : "'loop'"
        var cmd = ""
        for (var i = 0; i < targets.length; i++)
            cmd += "nohup setsid mpvpaper -o " + opts + " " + JSON.stringify(targets[i]) + " " + JSON.stringify(path) + " </dev/null >/dev/null 2>&1 & "
        return cmd
    }

    function _applyKdeVideo(path) {""",
)
apply_text = replace_all(
    apply_text,
    """    function applyWE(weId) {
        _saveState("we", "", weId)
        _reclaimOllamaVram()""",
    """    function applyWE(weId, outputs) {
        _saveState("we", "", weId)
        _pendingWeOutputs = outputs || []
        _reclaimOllamaVram()""",
)
apply_text = replace_all(
    apply_text,
    '    property string _pendingWeId: ""\n    property var _weProjectStdout: []',
    '    property string _pendingWeId: ""\n    property var _pendingWeOutputs: []\n    property var _weProjectStdout: []',
)
apply_text = replace_all(
    apply_text,
    """                        var opts = "loop"
                        if (service.wallpaperMute) opts = "loop --mute=yes"
                        weProcess.command = ["sh", "-c",
                            "pkill mpvpaper 2>/dev/null; " +
                            "nohup setsid mpvpaper -o '" + opts + "' '*' " + JSON.stringify(videoPath) + " </dev/null >/dev/null 2>&1 &"]
                        weProcess.running = true""",
    """                        weProcess.command = ["sh", "-c", service._mpvpaperLaunchCmd(videoPath, service._pendingWeOutputs)]
                        weProcess.running = true""",
)
apply_text = replace_all(
    apply_text,
    '        var mons = Quickshell.screens.map(function(s) { return s.name })',
    '        var mons = (service._pendingWeOutputs && service._pendingWeOutputs.length > 0)\n            ? service._pendingWeOutputs\n            : Quickshell.screens.map(function(s) { return s.name })',
)
apply_text = replace_all(
    apply_text,
    '"cp " + JSON.stringify(path) + " " + JSON.stringify(cacheDir + "/wallpaper/current.jpg") + " 2>/dev/null; " +',
    '"${pkgs.imagemagick}/bin/magick " + JSON.stringify(path) + " -auto-orient -strip -background black -alpha remove -alpha off -quality 92 " + JSON.stringify("jpg:" + cacheDir + "/wallpaper/current.jpg.tmp") + " 2>/dev/null && mv -f " + JSON.stringify(cacheDir + "/wallpaper/current.jpg.tmp") + " " + JSON.stringify(cacheDir + "/wallpaper/current.jpg") + "; " +',
)
apply_text = replace_all(
    apply_text,
    '"cp " + JSON.stringify(thumbPath) + " " + JSON.stringify(cacheDir + "/wallpaper/current.jpg") + " 2>/dev/null; " +',
    '"${pkgs.imagemagick}/bin/magick " + JSON.stringify(thumbPath) + " -auto-orient -strip -background black -alpha remove -alpha off -quality 92 " + JSON.stringify("jpg:" + cacheDir + "/wallpaper/current.jpg.tmp") + " 2>/dev/null && mv -f " + JSON.stringify(cacheDir + "/wallpaper/current.jpg.tmp") + " " + JSON.stringify(cacheDir + "/wallpaper/current.jpg") + "; " +',
)
apply_text = replace_all(
    apply_text,
    '"cp " + JSON.stringify(preview) + " " + JSON.stringify(service.cacheDir + "/wallpaper/current.jpg") + " 2>/dev/null; " +',
    '"${pkgs.imagemagick}/bin/magick " + JSON.stringify(preview) + " -auto-orient -strip -background black -alpha remove -alpha off -quality 92 " + JSON.stringify("jpg:" + service.cacheDir + "/wallpaper/current.jpg.tmp") + " 2>/dev/null && mv -f " + JSON.stringify(service.cacheDir + "/wallpaper/current.jpg.tmp") + " " + JSON.stringify(service.cacheDir + "/wallpaper/current.jpg") + "; " +',
)
apply_text = replace_all(
    apply_text,
    """        onExited: function(code) {
            if (code === 2) { console.log("WallpaperApplyService: matugen output unchanged, skipping reloads"); return }
            service._propagateColors()
        }""",
    """        onExited: function(code) {
            if (code === 2)
                console.log("WallpaperApplyService: matugen output unchanged; still running reload hooks")
            service._propagateColors()
        }""",
)
apply_text = replace_all(
    apply_text,
    """    function _propagateColors() {
        if (!Config.matugenEnabled) return
        var integrations = Config.integrations""",
    """    function _propagateColors() {
        var integrations = Config.integrations""",
)
apply_qml.write_text(apply_text)

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
PY
  '';

  # Hyprland/DMS colors.conf — Material Design 3 tokens in DMS format
  hyprlandDmsTemplate = pkgs.writeText "hyprland-dms-colors.conf" ''
    $primary = rgba({{colors.primary.default.hex_stripped}}ff)
    $onPrimary = rgba({{colors.on_primary.default.hex_stripped}}ff)
    $primaryContainer = rgba({{colors.primary_container.default.hex_stripped}}ff)
    $onPrimaryContainer = rgba({{colors.on_primary_container.default.hex_stripped}}ff)
    $secondary = rgba({{colors.secondary.default.hex_stripped}}ff)
    $onSecondary = rgba({{colors.on_secondary.default.hex_stripped}}ff)
    $secondaryContainer = rgba({{colors.secondary_container.default.hex_stripped}}ff)
    $onSecondaryContainer = rgba({{colors.on_secondary_container.default.hex_stripped}}ff)
    $tertiary = rgba({{colors.tertiary.default.hex_stripped}}ff)
    $onTertiary = rgba({{colors.on_tertiary.default.hex_stripped}}ff)
    $tertiaryContainer = rgba({{colors.tertiary_container.default.hex_stripped}}ff)
    $onTertiaryContainer = rgba({{colors.on_tertiary_container.default.hex_stripped}}ff)
    $error = rgba({{colors.error.default.hex_stripped}}ff)
    $onError = rgba({{colors.on_error.default.hex_stripped}}ff)
    $errorContainer = rgba({{colors.error_container.default.hex_stripped}}ff)
    $onErrorContainer = rgba({{colors.on_error_container.default.hex_stripped}}ff)
    $surface = rgba({{colors.surface.default.hex_stripped}}ff)
    $onSurface = rgba({{colors.on_surface.default.hex_stripped}}ff)
    $surfaceVariant = rgba({{colors.surface_variant.default.hex_stripped}}ff)
    $onSurfaceVariant = rgba({{colors.on_surface_variant.default.hex_stripped}}ff)
    $surfaceDim = rgba({{colors.surface_dim.default.hex_stripped}}ff)
    $surfaceBright = rgba({{colors.surface_bright.default.hex_stripped}}ff)
    $surfaceContainerLowest = rgba({{colors.surface_container_lowest.default.hex_stripped}}ff)
    $surfaceContainerLow = rgba({{colors.surface_container_low.default.hex_stripped}}ff)
    $surfaceContainer = rgba({{colors.surface_container.default.hex_stripped}}ff)
    $surfaceContainerHigh = rgba({{colors.surface_container_high.default.hex_stripped}}ff)
    $surfaceContainerHighest = rgba({{colors.surface_container_highest.default.hex_stripped}}ff)
    $outline = rgba({{colors.outline.default.hex_stripped}}ff)
    $outlineVariant = rgba({{colors.outline_variant.default.hex_stripped}}ff)
    $inverseSurface = rgba({{colors.inverse_surface.default.hex_stripped}}ff)
    $inverseOnSurface = rgba({{colors.inverse_on_surface.default.hex_stripped}}ff)
    $inversePrimary = rgba({{colors.inverse_primary.default.hex_stripped}}ff)
    $scrim = rgba({{colors.scrim.default.hex_stripped}}ff)
    $shadow = rgba({{colors.shadow.default.hex_stripped}}ff)

    general {
      col.active_border   = $primary
      col.inactive_border = $outline
    }

    group {
      col.border_active   = $primary
      col.border_inactive = $outline
      col.border_locked_active   = $error
      col.border_locked_inactive = $outline

      groupbar {
        col.active         = $primary
        col.inactive       = $outline
        col.locked_active   = $error
        col.locked_inactive = $outline
      }
    }
  '';

  # Zathura color theme
  zathuraTemplate = pkgs.writeText "zathura-colors" ''
    set recolor "true"
    set completion-bg "{{colors.surface.default.hex}}"
    set completion-fg "{{colors.on_surface.default.hex}}"
    set completion-highlight-bg "{{colors.primary.default.hex}}"
    set completion-highlight-fg "{{colors.surface.default.hex}}"
    set recolor-lightcolor "{{colors.surface.default.hex}}"
    set recolor-darkcolor "{{colors.on_surface.default.hex}}"
    set default-bg "{{colors.surface.default.hex}}"
    set default-fg "{{colors.on_surface.default.hex}}"
    set statusbar-bg "{{colors.surface.default.hex}}"
    set statusbar-fg "{{colors.on_surface.default.hex}}"
    set inputbar-bg "{{colors.surface.default.hex}}"
    set inputbar-fg "{{colors.on_surface.default.hex}}"
    set notification-error-bg "#ff5555"
    set notification-error-fg "{{colors.on_surface.default.hex}}"
    set notification-warning-bg "#ffb86c"
    set notification-warning-fg "{{colors.on_surface.default.hex}}"
    set highlight-color "{{colors.primary.default.hex}}"
    set highlight-active-color "{{colors.primary.default.hex}}"
  '';

  # Merge bundled + custom matugen templates
  skwdTemplatesDir = pkgs.runCommand "skwd-wall-templates" {} ''
    mkdir -p $out
    cp ${skwdWallPkg}/share/skwd-wall/data/matugen/templates/* $out/
    cp ${hyprlandDmsTemplate} $out/hyprland-dms-colors.conf
    cp ${zathuraTemplate} $out/zathura-colors
  '';

  configJson = builtins.toJSON {
    compositor = "hyprland";
    monitor = skwdDefaultMonitor;
    general = {
      locale = "";
      closeOnSelection = false;
      reopenAtLastSelection = true;
    };
    paths = {
      wallpaper = "~/wallpapers";
      videoWallpaper = "~/videowalls";
      cache = "";
      templates = "${skwdTemplatesDir}";
      scripts = skwdScriptDir;
      steam = steamLibraryDir;
      steamWorkshop = steamWorkshopDir;
      steamWeAssets = steamWeAssetsDir;
    };
    features = {
      matugen = true;
      ollama = true;
      steam = true;
      wallhaven = true;
    };
    colorSource = "magick";
    ollama = {
      url = "http://localhost:11434";
      model = "gemma3:4b";
      consolidateEnabled = true;
    };
    steam = {
      apiKey = "";
      username = "";
    };
    wallhaven = {
      apiKey = "";
    };
    matugen = {
      schemeType = "scheme-fidelity";
      mode = "dark";
    };
    integrations = [
      {
        name = "skwd-wall";
        template = "quickshell-colors.json";
        output = "colors.json";
      }
      {
        name = "hyprland-dms";
        template = "hyprland-dms-colors.conf";
        output = "~/.config/hypr/dms/colors.conf";
        reload = "${skwdScriptDir}/sync-dms-wallpaper.sh";
      }
      {
        name = "zathura";
        template = "zathura-colors";
        output = "~/.config/zathura/skwd-colors";
      }
      {
        name = "vesktop";
        template = "vesktop.css";
        output = "vesktop.css";
        reload = "${skwdScriptDir}/reload-vesktop.sh";
      }
    ];
    components = {
      wallpaperSelector = {
        displayMode = "slices";
        sliceSpacing = -30;
        hexScrollStep = 1;
        customPresets = {};
      };
    };
    wallpaperMute = true;
    performance = {
      imageOptimizePreset = "balanced";
      imageOptimizeResolution = "2k";
      videoConvertPreset = "balanced";
      videoConvertResolution = "2k";
      autoOptimizeImages = false;
      autoConvertVideos = false;
      imageTrashDays = 7;
      videoTrashDays = 7;
      autoDeleteImageTrash = false;
      autoDeleteVideoTrash = false;
    };
  };

  skwdConfigDefaults = pkgs.writeText "skwd-wall-config-defaults.json" configJson;
  skwdSecretsTemplate = pkgs.writeText "skwd-wall-secrets.env.template" ''
    # Optional local secrets for skwd-wall.
    # STEAM_API_KEY=your_steam_web_api_key
    # WALLHAVEN_API_KEY=your_wallhaven_api_key
  '';

  skwdPrepareState = pkgs.writeShellScript "skwd-wall-prepare-state" ''
    set -euo pipefail

    config_dir="$HOME/.config/skwd-wall"
    config_file="$config_dir/config.json"
    defaults_file="${skwdConfigDefaults}"
    secrets_file="${skwdSecretsFile}"
    secrets_template="${skwdSecretsTemplate}"

    mkdir -p "$config_dir"

    tmp_file=$(mktemp)
    cp "$defaults_file" "$tmp_file"

    if [ -L "$config_file" ] || { [ -e "$config_file" ] && [ ! -w "$config_file" ]; }; then
      rm -f "$config_file"
    fi
    mv "$tmp_file" "$config_file"
    chmod 600 "$config_file"

    if [ ! -e "$secrets_file" ]; then
      cp "$secrets_template" "$secrets_file"
      chmod 600 "$secrets_file"
    fi
  '';
  skwdDmsSyncHook = pkgs.writeShellScript "sync-dms-wallpaper.sh" ''
    set -euo pipefail

    current_wallpaper="$HOME/.cache/skwd-wall/wallpaper/current.jpg"
    last_wallpaper_state="$HOME/.cache/skwd-wall/last-wallpaper.json"
    session_dir="$HOME/.local/state/DankMaterialShell"
    session_file="$session_dir/session.json"
    greeter_cache_dir="/var/cache/dms-greeter"
    greeter_override="$greeter_cache_dir/greeter_wallpaper_override.jpg"
    greeter_settings="$greeter_cache_dir/settings.json"

    if [ ! -f "$current_wallpaper" ] && [ ! -f "$last_wallpaper_state" ]; then
      echo "sync-dms-wallpaper: missing both $current_wallpaper and $last_wallpaper_state" >&2
      exit 0
    fi

    mkdir -p "$session_dir"
    mkdir -p "$(dirname "$current_wallpaper")"
    export CURRENT_WALLPAPER_PATH="$current_wallpaper"
    export LAST_WALLPAPER_STATE="$last_wallpaper_state"
    export SKWD_BIN="${skwdWallPkg}/bin/skwd"
    export MAGICK_BIN="${pkgs.imagemagick}/bin/magick"

    live_wallpaper="$(${pkgs.python3}/bin/python3 <<'PY'
from pathlib import Path
import json
import mimetypes
import os
import subprocess
import sys

current = Path(os.environ["CURRENT_WALLPAPER_PATH"]).expanduser()
state = Path(os.environ["LAST_WALLPAPER_STATE"]).expanduser()
skwd = os.environ["SKWD_BIN"]
magick = os.environ["MAGICK_BIN"]

def load_state():
    if not state.exists():
        return {}
    try:
        data = json.loads(state.read_text())
    except json.JSONDecodeError as exc:
        print(f"sync-dms-wallpaper: failed to parse {state}: {exc}", file=sys.stderr)
        return {}
    return data if isinstance(data, dict) else {}

def resolve_we_id(candidate):
    probes = [candidate, candidate.parent]
    for probe in probes:
        name = probe.name
        if name.isdigit():
            return name
    return ""

def resolve_thumb(candidate):
    we_id = resolve_we_id(candidate)
    if not we_id:
        return None
    try:
        output = subprocess.check_output([skwd, "wall", "list", "{}"], text=True)
        payload = json.loads(output)
    except Exception as exc:
        print(f"sync-dms-wallpaper: failed to list wallpapers while resolving {we_id}: {exc}", file=sys.stderr)
        return None

    walls = payload.get("wallpapers") if isinstance(payload, dict) else None
    if not isinstance(walls, list):
        return None

    for wall in walls:
        if not isinstance(wall, dict):
            continue
        if wall.get("we_id") != we_id and wall.get("key") != we_id:
            continue
        for field in ("thumb", "thumb_sm"):
            thumb = wall.get(field)
            if isinstance(thumb, str):
                thumb_path = Path(thumb).expanduser()
                if thumb_path.is_file():
                    return thumb_path
    return None

data = load_state()
candidate_raw = data.get("path")
candidate = Path(candidate_raw).expanduser() if isinstance(candidate_raw, str) and candidate_raw else None
live = current if current.is_file() else None
source = None
uses_original_live_path = False

if candidate is not None:
    mime, _ = mimetypes.guess_type(str(candidate))
    if candidate.is_file() and isinstance(mime, str) and mime.startswith("image/"):
        source = candidate
        live = candidate
        uses_original_live_path = True
    else:
        source = resolve_thumb(candidate)

if source is None and current.is_file():
    source = current

if source is not None:
    tmp = current.with_name(current.name + ".tmp")
    try:
        subprocess.run(
            [magick, f"{source}[0]", "-strip", "-colorspace", "sRGB", "-quality", "95", f"jpg:{tmp}"],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        message = exc.stderr.strip() or str(exc)
        print(f"sync-dms-wallpaper: failed to normalize preview {source}: {message}", file=sys.stderr)
        if tmp.exists():
            tmp.unlink()
    else:
        os.replace(tmp, current)
        current.chmod(0o644)
        if not uses_original_live_path:
            live = current

print(str(live) if live and live.exists() else "")
PY
    )"
    if [ -z "$live_wallpaper" ] || [ ! -e "$live_wallpaper" ]; then
      echo "sync-dms-wallpaper: no usable live wallpaper path" >&2
      exit 0
    fi
    export LIVE_WALLPAPER_PATH="$live_wallpaper"

    session_changed="$(${pkgs.python3}/bin/python3 <<'PY'
from pathlib import Path
import json
import os
import sys

wallpaper = Path(os.environ["LIVE_WALLPAPER_PATH"])
session_file = Path(os.path.expanduser("~/.local/state/DankMaterialShell/session.json"))

if session_file.exists():
    try:
        data = json.loads(session_file.read_text())
    except json.JSONDecodeError as exc:
        print(f"sync-dms-wallpaper: failed to parse {session_file}: {exc}", file=sys.stderr)
        sys.exit(1)
else:
    data = {}

wallpaper_path = str(wallpaper)
for key in ("wallpaperPath", "wallpaperPathLight", "wallpaperPathDark"):
    data[key] = wallpaper_path

for key in ("monitorWallpapers", "monitorWallpapersLight", "monitorWallpapersDark"):
    value = data.get(key)
    if isinstance(value, dict):
        data[key] = {monitor: wallpaper_path for monitor in value}
    else:
        data[key] = {}

payload = json.dumps(data, separators=(",", ":")) + "\n"
current_payload = session_file.read_text() if session_file.exists() else ""
if current_payload != payload:
    tmp_file = session_file.with_name(session_file.name + ".tmp")
    tmp_file.write_text(payload)
    tmp_file.chmod(0o600)
    os.replace(tmp_file, session_file)
    print("changed")
else:
    print("unchanged")
PY
    )"

    if [ "$session_changed" = "unchanged" ] && command -v dms >/dev/null 2>&1; then
      if ! dms ipc wallpaper set "$live_wallpaper"; then
        echo "sync-dms-wallpaper: failed to notify DMS wallpaper IPC fallback" >&2
      fi
    fi

    if [ ! -f "$current_wallpaper" ]; then
      echo "sync-dms-wallpaper: missing normalized current wallpaper preview" >&2
    elif [ -d "$greeter_cache_dir" ] && [ -w "$greeter_cache_dir" ]; then
      install -m 664 "$current_wallpaper" "$greeter_override.tmp"
      mv -f "$greeter_override.tmp" "$greeter_override"
      chmod 664 "$greeter_override"

      ${pkgs.python3}/bin/python3 <<'PY'
from pathlib import Path
import json
import os
import sys

settings_file = Path("/var/cache/dms-greeter/settings.json")
wallpaper = Path(os.path.expanduser("~/.cache/skwd-wall/wallpaper/current.jpg"))

if settings_file.exists():
    try:
        data = json.loads(settings_file.read_text())
    except json.JSONDecodeError as exc:
        print(f"sync-dms-wallpaper: failed to parse {settings_file}: {exc}", file=sys.stderr)
        sys.exit(1)
else:
    data = {}

data["greeterWallpaperPath"] = str(wallpaper)
payload = json.dumps(data, separators=(",", ":")) + "\n"
current_payload = settings_file.read_text() if settings_file.exists() else ""
if current_payload != payload:
    tmp_file = settings_file.with_name(settings_file.name + ".tmp")
    tmp_file.write_text(payload)
    tmp_file.chmod(0o664)
    os.replace(tmp_file, settings_file)
PY
      chmod 664 "$greeter_settings"
    else
      echo "sync-dms-wallpaper: greeter cache dir not writable: $greeter_cache_dir" >&2
    fi
  '';
in {
  home.packages = [skwdWallPkg];

  xdg.configFile."skwd-wall/scripts/sync-dms-wallpaper.sh".source = skwdDmsSyncHook;

  home.activation.ensureWritableSkwdConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
    run ${skwdPrepareState}
  '';

  # Include dynamic Zathura color file generated by skwd-wall's matugen
  programs.zathura.extraConfig = "include skwd-colors";

  systemd.user.services.skwd-daemon = {
    Unit = {
      Description = "skwd wallpaper daemon";
      After = ["hyprland-session.target"];
      PartOf = ["hyprland-session.target"];
    };
    Service = {
      Type = "simple";
      ExecStartPre = [
        "${pkgs.coreutils}/bin/mkdir -p %t/skwd"
        "-${pkgs.coreutils}/bin/rm -f %t/skwd/daemon.sock"
      ];
      ExecStart = "${skwdWallPkg}/bin/skwd-daemon";
      Restart = "on-failure";
      RestartSec = "2";
    };
    Install = {
      WantedBy = ["hyprland-session.target"];
    };
  };
}
