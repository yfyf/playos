import QtQuick
import QtQuick.Window
import QtQuick.VirtualKeyboard

// From Qt docs:
// The keyboard size is automatically calculated from the available width; that
// is, the keyboard maintains the aspect ratio specified by the current style.
// Therefore the application should only set the width and y coordinates of the
// InputPanel, and not the height.
InputPanel {
    property int visibleWidth

    id: inputPanel
    x: 0
    z: 0
    y: 0
    width: 0
    states: State {
        name: "visible"
        when: inputPanel.active
        // TODO: can try to debounce here with `StateChangeScript`?
        PropertyChanges {
            z: 99
            target: inputPanel
            width: inputPanel.visibleWidth
        }
    }
    onStateChanged: {
        console.log("State: " + state)
        console.log("inputPanel.y: " + inputPanel.y)
        console.log("Window.width: " + Window.width)
        console.log("Window.height: " + Window.height)
    }

    transitions: Transition {
        from: ""
        to: "visible"
        reversible: true
        ParallelAnimation {
            NumberAnimation {
                properties: "y"
                duration: 250
                easing.type: Easing.InOutQuad
            }
        }
    }
}
