"""Extract anonymous reveal vector paths. Usage: measure_reveal.py recording.mov output.mask. Requires numpy, opencv-python-headless and ffmpeg."""
import cv2, subprocess, numpy as np, struct, sys
from pathlib import Path
# Contours contain only motion/mask geometry, never artwork RGB.
proc=subprocess.Popen(['ffmpeg','-v','error','-ss','16.6','-i',sys.argv[1],'-t','1.15','-vf','fps=59,crop=680:740:20:380','-pix_fmt','rgb24','-f','rawvideo','-'],stdout=subprocess.PIPE)
frames=[]
while raw:=proc.stdout.read(680*740*3):
 a=np.frombuffer(raw,np.uint8).reshape(740,680,3)
 # A low threshold retains dim blue particles; the reveal no longer has text/badge.
 mask=((a.max(axis=2)>12) & ((a[:,:,2].astype(float)>np.maximum(a[:,:,0],a[:,:,1])*1.25+2) if len(frames)/59+16.6<17.2 else True)).astype('uint8')
 mask[:5]=0
 contours,_=cv2.findContours(mask,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
 paths=[]
 for contour in contours:
  if cv2.contourArea(contour)<.5:continue
  x,y,w,h=cv2.boundingRect(contour)
  patch=a[y:y+h,x:x+w].reshape(-1,3)
  color=patch[np.argsort(patch.max(axis=1))[-min(4,len(patch)):]].mean(axis=0)
  image=not(color[2]>max(color[0],color[1])*1.25+2)
  polygon=cv2.approxPolyDP(contour,.3,True)[:,0,:].astype(float)
  if len(polygon)<3:continue
  polygon[:,0]=(polygon[:,0]-6)*430/720
  polygon[:,1]=(polygon[:,1]-5)*430/720
  paths.append((image,color,polygon))
 frames.append(paths)
assert proc.wait()==0
data=bytearray(b'LSMASK01'+struct.pack('<HH',len(frames),59))
for paths in frames:
 data.extend(struct.pack('<H',len(paths)))
 for image,color,polygon in paths:
  data.extend(struct.pack('<BBBBH',int(image),*np.clip(color,0,255).astype(int),len(polygon)))
  data.extend(polygon.astype('<f4').tobytes())
Path(sys.argv[2]).write_bytes(data)
print('Reveal vector frames',len(frames),'bytes',len(data))


