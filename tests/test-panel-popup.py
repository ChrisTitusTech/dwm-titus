#!/usr/bin/python3
"""Check popup boundaries and click-away behavior in an isolated X11 session."""
import os, shutil, subprocess, sys, tempfile, time
from pathlib import Path
repo=Path(__file__).resolve().parents[1]
if os.environ.get("DWM_PANEL_POPUP_NESTED") != "1":
 nested = {**os.environ, "DWM_PANEL_POPUP_NESTED": "1"}
 raise SystemExit(subprocess.run(
  ["xvfb-run", "-a", sys.executable, str(Path(__file__).resolve())], env=nested).returncode)
shell_source=(repo/'config/quickshell/shell.qml').read_text()
selection=shell_source[shell_source.index('function selectPanelPopup'):shell_source.index('function openCommandMenu')]
for close in ('commandMenuModel.close();', 'launcherModel.close();',
              'notificationModel.closeHistory();', 'controlCenterModel.closeUtility();'):
 assert close in selection
for popup, close in (('bluetooth', 'bluetoothModel.close();'),
                     ('controlcenter', 'controlCenterModel.close();'),
                     ('controls', 'controlsModel.close();'),
                     ('network', 'networkModel.close();'),
                     ('power', 'powerMenuModel.close("panel");'),
                     ('updatecenter', 'updateCenterModel.close();')):
 assert f'if (popupId !== "{popup}") {close}' in selection
assert 'root.selectedPanelWindow = panel;' in selection
assert 'UpdateCenterWindow {' in shell_source
assert 'panelWindow: root.activePanelWindow' in shell_source
assert 'onExclusiveOpenRequested: root.selectPanelPopup(root.activePanelWindow, "updatecenter")' in shell_source
for handler in ('onVisibleChanged: if (visible) updateCenterModel.close()',
                'onUtilityVisibleChanged: if (utilityVisible) updateCenterModel.close()',
                'onHistoryVisibleChanged: if (historyVisible) updateCenterModel.close()'):
 assert handler in shell_source
assert shell_source.count('onVisibleChanged: if (visible) updateCenterModel.close()') >= 6
assert 'commandMenuModel.close();\n                updateCenterModel.close();' in shell_source
with tempfile.TemporaryDirectory(prefix='panel-popup-', dir=os.environ.get('TMPDIR', str(Path.home()/'tmp'))) as temp:
 base=Path(temp); config=base/'config'; qml=config/'quickshell'; qml.mkdir(parents=True)
 runtime=base/'runtime'; runtime.mkdir(mode=0o700)
 shutil.copytree(repo/'config/quickshell/core',qml/'core')
 (qml/'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
ShellRoot {
 PanelWindow { id: panel; implicitHeight: 30; anchors { top: true; left: true; right: true } color: "white"; exclusiveZone: 30 }
 ClickAwayPopup { id: popup; targetWindow: panel; visible: false; popupWidth: 280; popupHeight: 300; onDismissed: visible = false; Rectangle { anchors.fill: parent; color: "red" } }
 IpcHandler { target: "test"; function open(): void { popup.visible = true; } }
}''')
 env={**os.environ,'XDG_RUNTIME_DIR':str(runtime),'HOME':str(base),'XDG_CONFIG_HOME':str(config),'XDG_DATA_HOME':str(base/'data'),'XDG_STATE_HOME':str(base/'state'),'QT_QPA_PLATFORM':'xcb','QT_QPA_PLATFORMTHEME':''}
 log=(base/'runtime.log').open('w+')
 wm=subprocess.Popen([str(repo/'dwm')],env=env,stdout=log,stderr=log)
 shell=subprocess.Popen(['quickshell','--no-duplicate'],env=env,stdout=log,stderr=log)
 def run(*args): return subprocess.run(args,env=env,capture_output=True,text=True)
 try:
  for _ in range(100):
   if run('quickshell','ipc','call','test','open').returncode==0: break
   time.sleep(.05)
  else: raise AssertionError('IPC unavailable')
  time.sleep(.3)
  ids=run('xdotool','search','--onlyvisible','--pid',str(shell.pid)).stdout.split()
  geometries = [dict(line.split("=", 1) for line in run('xdotool', 'getwindowgeometry', '--shell', wid).stdout.splitlines()) for wid in ids]
  panel = next(g for g in geometries if int(g['HEIGHT']) == 30)
  popup = next(g for g in geometries if int(g['HEIGHT']) > 30)
  assert int(popup['Y']) == int(panel['Y']) + int(panel['HEIGHT']), "Popup covers the panel"
  assert int(popup['X']) == int(panel['X']) and popup['WIDTH'] == panel['WIDTH']
  run('xdotool', 'mousemove', '100', '100', 'click', '1').check_returncode()
  time.sleep(.1)
  assert popup['WINDOW'] in run('xdotool', 'search', '--onlyvisible', '--pid', str(shell.pid)).stdout.split(), "Content click dismissed popup"
  run('xdotool', 'mousemove', '500', '400', 'click', '1').check_returncode()
  time.sleep(.1)
  assert popup['WINDOW'] not in run('xdotool', 'search', '--onlyvisible', '--pid', str(shell.pid)).stdout.split(), "Outside click did not dismiss popup"
  run('quickshell', 'ipc', 'call', 'test', 'open').check_returncode()
  time.sleep(.1)
  run('xdotool', 'mousemove', '100', '15', 'click', '1').check_returncode()
  time.sleep(.1)
  assert popup['WINDOW'] not in run('xdotool', 'search', '--onlyvisible', '--pid', str(shell.pid)).stdout.split(), "Panel click did not dismiss popup"
  assert wm.poll() is None and shell.poll() is None
  print('Panel remains outside popup; content, desktop and panel click behavior: PASS')
 finally:
  shell.terminate(); shell.wait(timeout=5); wm.terminate(); wm.wait(timeout=5)
  log.seek(0); print(log.read()); log.close()
