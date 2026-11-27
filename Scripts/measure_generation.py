"""Measure the November 27 reference at 59 Hz. Usage: measure_generation.py recording.mov output.dots. Requires ffmpeg and numpy; no source pixels are bundled."""
from pathlib import Path
import subprocess, struct, math, numpy as np
import sys
video=sys.argv[1]
fps=59; start=1.85; duration=14.95
cx=np.array([round(17.8+c*22.3) for row in range(30) for c in range(22)])
cy=np.array([round(62+row*22.3) for row in range(30) for c in range(22)])
dy,dx=np.mgrid[-7:8,-7:8]
proc=subprocess.Popen(['ffmpeg','-v','error','-ss',str(start),'-i',video,'-t',str(duration),'-vf',f'fps={fps},crop=504:740:26:390','-pix_fmt','rgb24','-f','rawvideo','-'],stdout=subprocess.PIPE)
data=bytearray(); count=0
while True:
 raw=proc.stdout.read(504*740*3)
 if not raw: break
 im=np.frombuffer(raw,np.uint8).reshape(740,504,3)
 patches=im[cy[:,None,None]+dy,cx[:,None,None]+dx].reshape(660,-1,3).astype(float)
 chroma=patches[:,:,2]>np.maximum(patches[:,:,0],patches[:,:,1])*1.25+2
 patches=np.where(chroma[:,:,None],patches,0)
 blue=patches[:,:,2]; best=np.argpartition(blue,-4,axis=1)[:,-4:]
 colors=np.take_along_axis(patches,best[:,:,None],axis=1).mean(axis=1)
 areas=blue.sum(axis=1)/np.maximum(colors[:,2],1)
 rad=np.sqrt(areas/math.pi)*430/720; rad[colors[:,2]<9]=0
 enc=np.empty((660,4),np.uint8); enc[:,0]=np.clip(np.rint(rad*64),0,255); enc[:,1:]=np.clip(np.rint(colors),0,255)
 gray=im[:40].min(axis=2).max(axis=0).astype(float); valid=np.where(gray>22)[0]
 profile=np.interp(np.arange(504),valid,gray[valid]) if len(valid) else np.zeros(504)
 profile=np.convolve(np.pad(profile,4,mode='edge'),np.ones(9)/9,mode='valid')
 data.extend(enc.tobytes()); data.extend(np.interp(np.linspace(0,503,64),np.arange(504),profile).astype(np.uint8).tobytes()); count+=1
assert proc.wait()==0
Path(sys.argv[2]).write_bytes(b'LSDOTS02'+struct.pack('<HHHH',22,30,count,fps)+data)
print(count,'frames',len(data)+16,'bytes')
