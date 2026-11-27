"""Export review images through logs; the sole downloadable build artifact is IPA."""
import base64
from pathlib import Path
import subprocess
import sys
import tempfile

for index, path in enumerate(sorted(Path(sys.argv[1]).rglob('*.png'))[:16]):
    with tempfile.TemporaryDirectory() as folder:
        target = Path(folder) / 'review.jpg'
        subprocess.run(['sips', '-s', 'format', 'jpeg', '-s', 'formatOptions', '70', '-Z', '1400', str(path), '--out', str(target)], check=True, capture_output=True)
        print(f'VISUAL_REVIEW_START {index:02d} {path.name}')
        print(base64.b64encode(target.read_bytes()).decode())
        print('VISUAL_REVIEW_END')
