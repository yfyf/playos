import sys
import os
import logging
import signal
from PyQt6.QtCore import Qt, QUrl, QObject, QEvent
from PyQt6.QtGui import QKeySequence
from PyQt6.QtWidgets import QApplication, QWidget
from PyQt6 import sip

from kiosk_browser import main_widget

class EventMonitor(QObject):
    def eventFilter(self, obj, event):
        ignored_types = [ QEvent.Type.Timer, QEvent.Type.Paint ]

        if event.type() in ignored_types:
            return False

        if "KbdWidget" in str(obj):
            print(f"{obj=} {event.type()=}\t{event=}")
       
       #print(f"{obj=}\t{event.type()=}\t{event=}")

        return False

# Workaround for https://bugreports.qt.io/browse/QTBUG-130273 in Qt 6.8.1
# Should be fixed with QT 6.8.2
# Note: doing this via env variables rather than passing `--webEngineArgs`,
# because the env variable overrides the args (and so is easy to break in tests,
# etc)
def tempFixAudioIssues():
    curFlags = os.environ.get('QTWEBENGINE_CHROMIUM_FLAGS', "")
    os.environ['QTWEBENGINE_CHROMIUM_FLAGS'] = curFlags + " --disable-features=FFmpegAllowLists"

def start(kiosk_url, settings_url, toggle_settings_key, fullscreen = True):

    logging.basicConfig(level=logging.INFO)

    tempFixAudioIssues()

    app = QApplication(sys.argv)
    app.setApplicationName("kiosk-browser")

    #monitor = EventMonitor()
    #app.installEventFilter(monitor)

    mainWidget = main_widget.MainWidget(
        kiosk_url = parseUrl(kiosk_url),
        settings_url = parseUrl(settings_url),
        toggle_settings_key = QKeySequence(toggle_settings_key),
        fullscreen = fullscreen
    )

    mainWidget.setContextMenuPolicy(Qt.ContextMenuPolicy.NoContextMenu)

    def focusChangedHandler(old, new):
        print(f"=== FOCUS CHANGED {old=} -> {new=}")
        print(f"=== KEYBOARD GRABBER: {mainWidget.keyboardGrabber()=}")

    app.focusChanged.connect(focusChangedHandler)
    # Note: Qt primary screen != xrandr primary screen
    # Qt will set primary when screen becomes visible, while on
    # xrandr it only changes when `--primary` is explicitly specified
    app.primaryScreenChanged.connect(mainWidget.handle_screen_change,
        type=Qt.ConnectionType.QueuedConnection)
    primary = app.primaryScreen()
    mainWidget.handle_screen_change(primary)

    def handleFocusWindowChanged(w):
        if w is None:
            print("=== WINDOW UNFOCUSED =======")
        else:
            print("=== WINDOW FOCUSED =========")

        print(f"    {QApplication.focusWidget()=}")
        print(f"    {QApplication.focusWindow()=}")
        print(f"    {QApplication.activeWindow()=}")

        windows = QApplication.allWindows()
        for window in windows:
            print(f"    {window=} {window.isActive()=}")

    app.focusWindowChanged.connect(handleFocusWindowChanged)

    app.applicationStateChanged.connect(lambda s: print(f"applicationStateChanged: {s}"))


    # Quit application gracefully when receiving SIGINT or SIGTERM
    # This is important to trigger flushing of in-memory DOM storage to disk
    def quit_on_signal(signum, _frame):
       print('Exiting…')
       app.quit()
       sys.exit(128+signum)

    signal.signal(signal.SIGINT, quit_on_signal)
    signal.signal(signal.SIGTERM, quit_on_signal)

    #mainWidget.clearFocus()
    #mainWidget.setFocus()
    #mainWidget.window().windowHandle().raise_()
    #mainWidget.setFocus()

    #mainWidget.window().windowHandle().raise_()


    def print_widget_tree(widget, indent=0):
        # Get widget class name
        cls_name = widget.metaObject().className()
        # Get Python id and C++ pointer address
        py_addr = hex(id(widget))
        cpp_addr = hex(sip.unwrapinstance(widget))
        
        # Print with indentation
        print(" " * indent + f"{cls_name} "
              f"(Python id: {py_addr}, cpp_addr: {cpp_addr} objectName: '{widget.objectName()}')")

        for child in widget.children():
            if isinstance(child, QWidget):
                print_widget_tree(child, indent + 4)

    print("====== WIDGET TREE =======")
    print_widget_tree(mainWidget)
    print("==========================")

    # Start application
    app.exec()

def parseUrl(url):
    parsed_url = QUrl(url)
    if not parsed_url.isValid():
        raise InvalidUrl('Failed to parse URL "%s"' % url) from Exception
    else:
        return parsed_url
