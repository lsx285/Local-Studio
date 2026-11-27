"""Derive anonymous vector-dot keyframes from the supplied UI reference recording.

Offline design tooling: Python, NumPy, and ffmpeg. The output holds dot radii and
colors, never recording frames, text, photos, or audio.
Usage: python Scripts/measure_generation.py reference.mov output.dots
"""
import math
from pathlib import Path
import struct
import subprocess
import sys

import numpy as np

columns, rows, fps = 22, 30, 15
start, duration = 2.8, 20.4
width, height = 504, 672
scale = 430 / 720
centers_x = np.array([round(17.5 + column * 22.3) for row in range(rows) for column in range(columns)])
centers_y = np.array([round(15.5 + row * 22.3) for row in range(rows) for column in range(columns)])
offset_y, offset_x = np.mgrid[-7:8, -7:8]
sample_x = centers_x[:, None, None] + offset_x
sample_y = centers_y[:, None, None] + offset_y
process = subprocess.Popen([
    'ffmpeg', '-v', 'error', '-ss', str(start), '-i', sys.argv[1],
    '-t', str(duration), '-vf', f'fps={fps},crop={width}:{height}:26:450',
    '-pix_fmt', 'rgb24', '-f', 'rawvideo', '-'
], stdout=subprocess.PIPE)
frames = bytearray()
frame_count = 0
while True:
    raw = process.stdout.read(width * height * 3)
    if not raw:
        break
    if len(raw) != width * height * 3:
        raise RuntimeError('Incomplete reference frame')
    image = np.frombuffer(raw, dtype=np.uint8).reshape(height, width, 3)
    patches = image[sample_y, sample_x].reshape(columns * rows, -1, 3).astype(np.float32)
    blue = patches[:, :, 2]
    brightest = np.argpartition(blue, -4, axis=1)[:, -4:]
    colors = np.take_along_axis(patches, brightest[:, :, None], axis=1).mean(axis=1)
    weights = np.maximum(blue - 4, 0)
    areas = weights.sum(axis=1) / np.maximum(colors[:, 2] - 4, 1)
    radii = np.sqrt(areas / math.pi) * scale
    radii[colors[:, 2] < 9] = 0
    encoded = np.empty((columns * rows, 4), dtype=np.uint8)
    encoded[:, 0] = np.clip(np.rint(radii * 64), 0, 255)
    encoded[:, 1:] = np.clip(np.rint(colors), 0, 255)
    frames.extend(encoded.tobytes())
    frame_count += 1
if process.wait() != 0:
    raise RuntimeError('Reference decoding failed')
header = b'LSDOTS01' + struct.pack('<HHHH', columns, rows, frame_count, fps)
Path(sys.argv[2]).write_bytes(header + frames)
print(f'{columns} × {rows}, {frame_count} frames at {fps} Hz; {len(header) + len(frames):,} bytes')
