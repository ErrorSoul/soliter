"""Run on the Deck: mutate a disposable copy, never the working tree."""
from pathlib import Path
import shutil
import subprocess
import tempfile

source=Path('/tmp/shenzhen-check-1105/project')
with tempfile.TemporaryDirectory(prefix='shenzhen-ui-guard-') as tmp:
    root=Path(tmp)
    for name in ['main','gui','solver']:
        shutil.copytree(source/name,root/name)
    script=root/'gui/ui.gui_script'
    old='if consumed then return true end'
    content=script.read_text()
    assert content.count(old)==1
    script.write_text(content.replace(old,'if consumed then return end'))
    result=subprocess.run(['lua','-e','local h=require("solver.tests.test_layout"); h.report(); os.exit(h.failed==1 and 0 or 1)'],cwd=root,text=True,capture_output=True)
    print(result.stdout)
    print(result.stderr)
    assert result.returncode==0
    assert 'press leaked to the game' in result.stdout
    print('PASS: removing on_input consumption is caught in disposable copy')
