import QtQuick
import QtQuick.Window
import QtQuick.VirtualKeyboard

// From Qt docs:
// The keyboard size is automatically calculated from the available width; that
// is, the keyboard maintains the aspect ratio specified by the current style.
// Therefore the application should only set the width and y coordinates of the
// InputPanel, and not the height.
InputPanel {
   // Hack to remove background
   //Component.onCompleted: {
   //     keyboard.style.keyboardBackground = null;
   //     keyboard.style.selectionListBackground = null;
   //}

   // Example of how to connect to InputContext for handling keyboard positioning
   // within QML
   //Connections {
   //     target: InputContext
   //     onCursorRectangleChanged: cursorRectangleChanged()
   //}
   //function cursorRectangleChanged() {
   //     console.log("InputContext.cursorRectangle" + InputContext.cursorRectangle)
   //}

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
        }
    }

    Keys.onPressed: (event) => {
        console.log("Keys.onPressed: " + event.key);
    }

    //function invokeKeyPress(key: int) : string {
    //    console.log("Got key:", key)
    //    InputEngine.virtualKeyPress(key, "", 0, false)
    //    InputEngine.virtualKeyRelease(key, "", 0, false)
    //    return "some return value"
    //}

    // Useful debugging prints
    onStateChanged: {
        console.log("State: " + state)
        console.log("inputPanel.y: " + inputPanel.y)
        console.log("Window.width: " + Window.width)
        console.log("Window.height: " + Window.height)
        console.log("visibleWidth:" + visibleWidth)
        console.log("InputContext.cursorRectangle" + InputContext.cursorRectangle)
        //InputContext.commit()
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
