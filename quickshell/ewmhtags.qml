// In your Quickshell QML
import Quickshell
import Quickshell.Io

Item {
    property var currentTags: []
    property var tagNames: ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
    
    // Monitor EWMH properties
    Process {
        id: ewmhMonitor
        command: ["xprop", "-spy", "-root", "_NET_CURRENT_DESKTOP", "_NET_DESKTOP_NAMES"]
        running: true
        
        stdout: SplitParser {
            onParseResult: (data) => {
                if (data.includes("_NET_CURRENT_DESKTOP")) {
                    // Parse current desktop/tag
                    let match = data.match(/_NET_CURRENT_DESKTOP\(CARDINAL\) = (\d+)/)
                    if (match) {
                        currentTag = parseInt(match[1])
                    }
                }
            }
        }
    }
}
