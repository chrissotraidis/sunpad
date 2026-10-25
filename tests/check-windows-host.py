#!/usr/bin/env python3
"""Public native Windows path probe; no game inputs or module compilation."""
import argparse
import ctypes
import importlib.util
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('builder', ROOT / 'scripts/windows/build.py')
builder = importlib.util.module_from_spec(spec); spec.loader.exec_module(builder)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tool', type=Path, default=builder.DESKTOP_BUILD / 'dolrecomp.exe')
    args = parser.parse_args()
    if os.name != 'nt':
        parser.error('this probe runs native Windows tools')
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding='utf-8')
    with tempfile.TemporaryDirectory(prefix='Sun Unicode 雪 ') as temporary:
        root = Path(temporary)
        os.environ['TEMP'] = os.environ['TMP'] = str(root)
        env = builder.visual_studio_env()
        assert env['TEMP'] == env['TMP'] == str(root), 'vcvars changed Unicode TEMP'
        tool = args.tool.resolve()
        mt = shutil.which('mt', path=env.get('PATH', env.get('Path')))
        assert mt, 'Visual Studio manifest tool is missing'
        manifest = root / 'readback.manifest'
        subprocess.run([mt, '-nologo', f'-inputresource:{tool};#1', f'-out:{manifest}'], check=True, env=env)
        tree = ET.parse(manifest)
        nodes = {node.tag.rsplit('}', 1)[-1]: node for node in tree.iter()}
        assert nodes['activeCodePage'].text == 'UTF-8'
        assert nodes['requestedExecutionLevel'].get('level') == 'asInvoker'
        # The maintained DolRecomp test_dol fixture: li r3,1; blr.
        dol = bytearray(0x108)
        for offset, value in ((0, 0x100), (0x48, 0x80003100), (0x90, 8),
                              (0xe0, 0x80003100), (0x100, 0x38600001), (0x104, 0x4e800020)):
            struct.pack_into('>I', dol, offset, value)
        outputs = []
        for name in ('ascii', 'cwd 雪'):
            cwd = root / name; cwd.mkdir()
            source = cwd / 'public.dol'; source.write_bytes(dol)
            output = cwd / 'output'
            subprocess.run([str(tool), '-j1', '--backend=c', '--cpu', 'gekko', '--gamecube',
                            str(source), str(output)], cwd=cwd, env=env, check=True)
            files = {p.relative_to(output).as_posix(): p.read_bytes() for p in output.rglob('*') if p.is_file()}
            assert {'generated/generated.c', 'generated/generated.h'} <= files.keys()
            chunks = [data for name, data in files.items() if name.startswith('generated/chunks/') and name.endswith('.c')]
            assert len(chunks) == 1 and b'func_80003100' in chunks[0]
            outputs.append(files)
            assert source.read_bytes() == dol
        assert outputs[0] == outputs[1], 'Unicode paths changed generated source bytes'
        parent_cp = (ctypes.windll.kernel32.GetConsoleCP(), ctypes.windll.kernel32.GetConsoleOutputCP())
        def host(command):
            builder.run(command, env=env, host=True)
        literal = 'literal & %PATH% ! 雪'
        host([sys.executable, '-X', 'utf8', '-c',
              "import ctypes,sys; assert sys.argv[1]=='literal & %PATH% ! \u96ea'; "
              "assert ctypes.windll.kernel32.GetConsoleCP()==65001; "
              "assert ctypes.windll.kernel32.GetConsoleOutputCP()==65001", literal])
        try:
            host([sys.executable, '-c', 'raise SystemExit(17)'])
        except SystemExit as error:
            assert error.code == 1
        else:
            raise AssertionError('host command failure was not propagated')
        # A successful first compilation can still poison Ninja's next build
        # if MSVC /showIncludes has replaced Unicode header paths with '?'.
        project = root / 'header source 雪'; project.mkdir()
        (project / 'value.h').write_text('#define VALUE 7\n')
        (project / 'main.c').write_text('#include "value.h"\nint main(void) { return VALUE-7; }\n')
        (project / 'CMakeLists.txt').write_text(
            'cmake_minimum_required(VERSION 3.19)\nproject(HeaderPath C)\n'
            'add_executable(header_probe main.c)\n')
        build = root / 'header build 雪'
        host(['cmake', '-S', str(project), '-B', str(build), '-G', 'Ninja', '-DCMAKE_C_COMPILER=cl'])
        host(['cmake', '--build', str(build), '--parallel', '1'])
        executable = build / 'header_probe.exe'
        stamp = executable.stat().st_mtime_ns
        host(['cmake', '--build', str(build), '--parallel', '1'])
        assert executable.stat().st_mtime_ns == stamp, 'unchanged header fixture rebuilt'
        assert parent_cp == (ctypes.windll.kernel32.GetConsoleCP(), ctypes.windll.kernel32.GetConsoleOutputCP())

        print(json.dumps({'result':'PASS', 'tool':str(tool), 'generated_files':len(outputs[0]),
                          'manifest':'UTF-8 and asInvoker', 'unicode_temp_preserved':True, 'parent_console_preserved':True,
                          'literal_arguments_and_failure':True, 'header_warm_build':'no work'}))


if __name__ == '__main__':
    main()
