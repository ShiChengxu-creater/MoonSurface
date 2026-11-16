"""Bounded JS file-host scaling measurements, including startup and serialization.

Memory is an OS process-counter peak observed every 20 ms, a sampled lower bound;
it includes Node and is not an algorithm-only allocation count or RSS guarantee.
"""
import argparse
from hashlib import sha256
import json
import os
from pathlib import Path
import statistics
import subprocess
import tempfile
import threading
import time

from common import ROOT, evidence_base, run
from model_verify import np
from geometry_checks import check_model


def peak_reader(process):
    if os.name=='nt':
        import ctypes as c
        from ctypes import wintypes as w
        class Counters(c.Structure):
            _fields_=[('cb',w.DWORD),('faults',w.DWORD)]+[(n,c.c_size_t) for n in
                ['peak','working','peak_paged','paged','peak_nonpaged','nonpaged','pagefile','peak_pagefile']]
        api=c.WinDLL('psapi').GetProcessMemoryInfo
        api.argtypes=[w.HANDLE,c.POINTER(Counters),w.DWORD];api.restype=w.BOOL
        def read():
            counters=Counters();counters.cb=c.sizeof(counters)
            return int(counters.peak) if api(int(process._handle),c.byref(counters),counters.cb) else 0
        return read,'Windows PeakWorkingSetSize, sampled'
    if Path('/proc').is_dir():
        def read():
            try:
                for line in Path(f'/proc/{process.pid}/status').read_text().splitlines():
                    if line.startswith('VmHWM:'):return int(line.split()[1])*1024
            except (FileNotFoundError,ProcessLookupError): pass
            return 0
        return read,'Linux /proc VmHWM, sampled'
    return lambda:0,'unavailable'


def measure(command,stdout,stderr):
    start=time.perf_counter()
    with stdout.open('wb') as out,stderr.open('wb') as err:
        process=subprocess.Popen(command,cwd=ROOT,stdout=out,stderr=err)
        reader,method=peak_reader(process)
        peaks=[];stop=threading.Event()
        def sample():
            while not stop.is_set():
                peaks.append(reader());stop.wait(.02)
        thread=threading.Thread(target=sample,daemon=True);thread.start()
        try:
            process.wait(timeout=180)
            peaks.append(reader())
        except subprocess.TimeoutExpired:
            process.kill();process.wait();raise
        finally:
            stop.set();thread.join()
    assert process.returncode==0,stderr.read_text(encoding='utf-8')
    return dict(seconds_host_included=time.perf_counter()-start,
                sampled_peak_process_bytes=max(peaks,default=0),memory_method=method)


def grid(size):
    # A deterministic uneven planar grid with an analytic field and original UV.
    t=np.linspace(0,1,size+1)
    xs=t+.10*np.sin(2*np.pi*t)/(2*np.pi)
    ys=t+.08*np.sin(4*np.pi*t)/(4*np.pi)
    p=[[float(x),float(y),0.] for y in ys for x in xs]
    faces=[]
    for y in range(size):
        for x in range(size):
            a=y*(size+1)+x
            faces.extend([[a,a+1,a+size+2],[a,a+size+2,a+size+1]])
    return dict(format='moonsurface-model/1',positions=p,triangles=faces,
        attributes=[dict(name='position_probe',width=3,interpolation='linear',values=p)],
        corner_uvs=[[[p[v][0],p[v][1]] for v in f] for f in faces],
        operations=[dict(kind='remesh',target_edge_length=1.12/size,iterations=2,max_operations=10000)])


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--sizes',nargs='+',type=int,default=[32,64,128])
    parser.add_argument('--repeats',type=int,default=3)
    args=parser.parse_args()
    assert all(2<=n<=128 for n in args.sizes) and 1<=args.repeats<=5
    run(['moon','build','--target','js','--deny-warn'],target='js')
    base=ROOT/'artifacts';base.mkdir(exist_ok=True)
    work=Path(tempfile.mkdtemp(prefix='scale-',dir=base));cases=[]
    for size in args.sizes:
        job=grid(size)
        path=work/f'grid-{size}.json'
        path.write_text(json.dumps(job,separators=(',',':')),encoding='utf-8')
        assert path.stat().st_size<=16*1024*1024
        measurements=[];digests=[];first=None
        for repeat in range(args.repeats):
            output=work/f'{size}-{repeat}-output.json'
            m=measure(['node',str(ROOT/'tools/moonsurface.mjs'),str(path)],output,work/f'{size}-{repeat}-stderr.txt')
            digests.append(sha256(output.read_bytes()).hexdigest())
            measurements.append(m)
            if first is None:first=json.loads(output.read_bytes())
        assert len(set(digests))==1,'repeated output changed'
        checked=check_model(job,first)
        cases.append(dict(size=size,input_sha256=sha256(path.read_bytes()).hexdigest(),
            output_sha256=digests[0],input_bytes=path.stat().st_size,**checked,measurements=measurements,
            median_seconds=statistics.median(m['seconds_host_included'] for m in measurements),
            maximum_sampled_peak_bytes=max(m['sampled_peak_process_bytes'] for m in measurements)))
        print(f'Scale F={len(job["triangles"])}: {cases[-1]["median_seconds"]:.3f}s, '
              f'{cases[-1]["maximum_sampled_peak_bytes"]/1024**2:.1f} MiB sampled process peak; '
              f'stop={first["operations"][0]["stop"]}',flush=True)
    report=dict(evidence_base('js',[['python','tools/benchmark.py','--sizes',*map(str,args.sizes),
                                    '--repeats',str(args.repeats)]]),status='passed',cases=cases,
        workspace=str(work),hardware=dict(machine=__import__('platform').machine(),cpu_count=os.cpu_count()),
        measurement='fresh Node processes; includes file IO, parsing, core work and serialization; '
                    '20 ms OS peak-counter observations are lower bounds, not algorithm-only RSS')
    (base/'scale-js.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')


if __name__=='__main__':main()
