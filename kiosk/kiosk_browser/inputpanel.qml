import QtQuick
import QtQuick.Window
import QtQuick.VirtualKeyboard
import QtQuick.VirtualKeyboard.Settings

// From Qt docs:
// The keyboard size is automatically calculated from the available width; that
// is, the keyboard maintains the aspect ratio specified by the current style.
// Therefore the application should only set the width and y coordinates of the
// InputPanel, and not the height.
InputPanel {
    property int visibleWidth

    id: inputPanel
    x: 0
    y: 0
    z: 99
    width: visibleWidth

    states: State {
        name: "visible"
        when: inputPanel.active
        // TODO: can try to debounce here with `StateChangeScript`?
        PropertyChanges {
            target: inputPanel
            width: visibleWidth
        }
    }

   Component.onCompleted: {
        // Hack to remove background
        //keyboard.style.keyboardBackground = null;
        //keyboard.style.selectionListBackground = null;

        // TODO: review
        VirtualKeyboardSettings.activeLocales = [
            "cs_CZ",
            "de_DE",
            // "de_CH", ?
            "en_US",
            // "en_GB", ?
            "es_ES",
            "fi_FI",
            // "fr_CH", ?
            "fr_FR",
            "it_IT",
            // "it_CH", ?
            "nl_NL",
            "pl_PL"
        ];
        VirtualKeyboardSettings.closeOnReturn = true; // TODO: yes, temporarily?
        VirtualKeyboardSettings.handwritingModeDisabled = true;
        VirtualKeyboardSettings.defaultDictionaryDisabled = true;
   }

   Connections {
       target: InputContext
       // Override the `ImhFormattedNumbersOnly` inputMethodHint to
       // `ImhDialableCharactersOnly` to show a more minimal keyboard without
       // extra formula inputs, which are useless in Play's context.
       //
       // Note 1: the input method hints are defined in `toQtInputMethodHints` of
       // qtwebengine: https://github.com/qt/qtwebengine/blob/6.9.1/src/core/type_conversion.cpp#L294
       //
       // Note 2: for some reason overriding with Qt.ImhDigitsOnly  has no effect.
       function onInputMethodHintsChanged() {
           const hints = InputContext.inputMethodHints;
           const digitsHintsToOverride = Qt.ImhFormattedNumbersOnly | Qt.ImhDigitsOnly;
           if (hints & digitsHintsToOverride) {
               // unset the overridable hints and set ImhDialableCharactersOnly
               let updatedHints = hints & ~digitsHintsToOverride | Qt.ImhDialableCharactersOnly;
               VirtualKeyboardSettings.inputMethodHints = updatedHints;
           }
           else {
               // this is a persistent property, so it needs to be explicitly set
               VirtualKeyboardSettings.inputMethodHints = hints;
           }
       }
   }


    // Useful debugging prints
    onStateChanged: {
        console.log("State: " + state)
        console.log("inputPanel.y: " + inputPanel.y)
        console.log("Window.width: " + Window.width)
        console.log("Window.height: " + Window.height)
        console.log("visibleWidth:" + visibleWidth)
        console.log("InputContext.cursorRectangle" + InputContext.cursorRectangle)
    }

    // TODO: this would look good for `height`, but since height is initially unset
    // it does not work - need to explicitly construct a variable?
    //transitions: Transition {
    //    from: ""
    //    to: "visible"
    //    reversible: true
    //    ParallelAnimation {
    //        NumberAnimation {
    //            properties: "height"
    //            duration: 250
    //            easing.type: Easing.InOutQuad
    //        }
    //    }
    //}
}
