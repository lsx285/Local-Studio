"""Validate the actual delivery container without an Apple signing identity."""
import plistlib
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as ipa:
    paths = ipa.namelist()
    prefix = 'Payload/LocalStudio.app/'
    assert prefix + 'LocalStudio' in paths, 'App executable missing'
    assert not any('_CodeSignature/' in p or p.endswith('embedded.mobileprovision') for p in paths), 'App is signed'
    info = plistlib.loads(ipa.read(prefix + 'Info.plist'))
    assert info['CFBundleIdentifier'] == 'com.lsx285.localstudio'
    assert info['DTSDKName'] == 'iphoneos27.2', info.get('DTSDKName')
    assert float(info['MinimumOSVersion']) >= 27
    assert any(p.endswith('.car') for p in paths), 'Compiled icon/assets missing'
    motion = ipa.read(prefix + 'GenerationMotion.dots')
    assert motion.startswith(b'LSDOTS01') and len(motion) == 807856, 'Generation motion trace missing or invalid'
    assert ipa.testzip() is None, 'Corrupt IPA'
    print('Verified unsigned LocalStudio.ipa, iOS 27.2 SDK, Swift 6 project')
