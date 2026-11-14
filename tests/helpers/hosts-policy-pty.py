import re, os, pty, termios, fcntl, struct, subprocess, select, time, sys, signal
from pathlib import Path
mode=sys.argv[1]
master,slave=pty.openpty()
original=termios.tcgetattr(slave)
fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack('HHHH',24 if mode!='small' else 8,100,0,0))
env=os.environ.copy();env['TERM']='xterm-256color';env['NO_COLOR']='1'
env.pop('COLORTERM',None)
if mode in ['color','slate-truecolor','slate-fallback']: env.pop('NO_COLOR',None)
if mode=='slate-truecolor': env['COLORTERM']='truecolor'
if mode=='slate-fallback': env['TERM']='vt100'
script='''source "$1"
DRY_RUN=false
is_root() { return 1; }
if [ "$4" = failed-stty ]; then stty() { return 1; }; fi
if [ "$4" = missing-stty ]; then command() { if [ "$*" = '-v stty' ]; then return 1; fi; builtin command "$@"; }; fi
trap ':' INT TERM
ui_rc=0
cmd_hosts edit --root "$2/target" --policy "$2/policy" || ui_rc=$?
printf '\nEDITOR_RETURNED\n'
IFS= read -r release
exit "$ui_rc"
'''
p=subprocess.Popen(['/bin/bash','-euo','pipefail','-c',script,'hosts-pty',env['HOSTS_TEST_DEFS'],env['HOSTS_TEST_ROOT'],'unused',mode],stdin=slave,stdout=slave,stderr=slave,env=env,start_new_session=True,preexec_fn=lambda: fcntl.ioctl(0,termios.TIOCSCTTY,0))
output=b''
def until(needle):
    global output
    deadline=time.monotonic()+12
    while needle not in output:
        if time.monotonic()>deadline: raise AssertionError('Timed out: '+repr(output[-2000:]))
        ready,_,_=select.select([master],[],[],.1)
        if ready:
            try: chunk=os.read(master,65536)
            except OSError: chunk=b''
            if not chunk: raise AssertionError('Exited early: '+repr(output[-2000:]))
            output+=chunk
try:
    if mode in ['arrows','resize','interrupt','color','slate-truecolor','slate-fallback']:
        until(b'\x1b[?1049h')
        os.write(master,b' ')
        until(b'Type OFF to confirm: ')
        os.write(master,b'OFF\n')
        until(b'manual override')
        if mode=='resize':
            output=b''
            fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack('HHHH',8,100,0,0))
            os.write(master,b'\x1b[B')
            until(b'Choose: ')
            assert b'manual override' in output
            os.write(master,b'q\n')
        elif mode=='interrupt':
            os.write(master,b'\x03')
        else:
            output=b'' if mode not in ['color','slate-truecolor','slate-fallback'] else output
            os.write(master,b'n')
            until(b'Choose: ')
            assert b'manual override' in output
            os.write(master,b'q\n')
    else:
        until(b'Choose: ')
        assert b'\x1b[?1049h' not in output
        os.write(master,b'q\n')
    # Headings are display-only: numbering remains continuous across sections.
    assert re.search(rb'CORE .*?OPTIONAL ', output, re.S)
    assert b'On by default' in output and b'Off by default' in output
    until(b'EDITOR_RETURNED')
    assert termios.tcgetattr(slave)==original,'Terminal attributes were not restored'
    os.write(master,b'\n')
    deadline=time.monotonic()+8
    while p.poll() is None and time.monotonic()<deadline:
        ready,_,_=select.select([master],[],[],.05)
        if ready:
            try: output+=os.read(master,65536)
            except OSError: break
    if p.poll() is None: raise AssertionError('Did not exit: '+repr(output[-3000:]))
    p.wait(timeout=1)
    assert p.returncode==0 or (mode=='interrupt' and p.returncode in [-2,130]),p.returncode
    if mode=='color': assert b'\x1b[38;5;110m' in output
    elif mode=='slate-truecolor': assert b'\x1b[38;2;143;175;199m' in output
    elif mode=='slate-fallback': assert b'\x1b[37m' in output and b'\x1b[38;' not in output
    else: assert b'\x1b[36m' not in output and b'\x1b[31m' not in output
    root=Path(env['HOSTS_TEST_ROOT'])/'target/private/etc'
    assert not (root/'unleash-hosts.conf').exists()
    assert (root/'hosts').read_text()==Path(env['HOSTS_TEST_ROOT'],'original').read_text()
    print('PTY '+mode+': input, restoration and no-write checks passed')
finally:
    if p.poll() is None:
        os.close(master); master=None
        try: p.kill();p.wait(timeout=2)
        except (PermissionError, subprocess.TimeoutExpired): pass
    if master is not None: os.close(master)
    os.close(slave)
