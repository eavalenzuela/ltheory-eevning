#!/usr/bin/env python
import os
import sys
import shutil
import subprocess

windows = sys.platform == 'win32'

try:
    os.mkdir('build')
except Exception as e:
    pass

if len(sys.argv) > 1:
    if sys.argv[1] == 'build':
        args = ['cmake', '--build', './build', '--config', 'RelWithDebInfo']
        if not windows:
            args += ['--parallel', str(os.cpu_count() or 1)]
        sys.exit(subprocess.call(args))
    elif sys.argv[1] == 'clean':
        shutil.rmtree('bin', ignore_errors = True)
        shutil.rmtree('build', ignore_errors = True)
        shutil.rmtree('cache', ignore_errors = True)
    elif sys.argv[1] == 'run':
        exe = 'bin/launch.exe' if windows else 'bin/launch'
        sys.exit(subprocess.call([exe] + sys.argv[2:]))
else:
    if windows:
        subprocess.call(['cmake', '-A', 'Win32', '-S', './', '-B', './build'])
    else:
        subprocess.call(['cmake', '-DCMAKE_BUILD_TYPE=RelWithDebInfo', '-S', './', '-B', './build'])
