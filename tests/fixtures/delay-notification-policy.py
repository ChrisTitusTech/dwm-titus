"""Delay the copied model's write so restart tests must await persistence."""
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
start = text.index('    function savePolicy() {')
end = text.index('    function setDoNotDisturb(', start)
block = text[start:end]
old = '        policyFile.setText(JSON.stringify({'
ending = '        }) + "\\n");'
if block.count(old) != 1 or block.count(ending) != 1:
    raise SystemExit('Notification policy fixture injection point changed')
block = block.replace(old, '        delayedPolicyWrite.text = JSON.stringify({')
block = block.replace(ending, '        }) + "\\n";\n        delayedPolicyWrite.restart();')
timer = '''    Timer {
        id: delayedPolicyWrite
        property string text: ""
        interval: 250
        onTriggered: policyFile.setText(text)
    }

'''
path.write_text(text[:start] + timer + block + text[end:])
