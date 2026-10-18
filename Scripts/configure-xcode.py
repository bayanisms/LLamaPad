"""Attach the app icon catalog to xtool's generated application target."""
import json
from pathlib import Path
import plistlib
import subprocess

root = Path(__file__).resolve().parents[1]
project = root / 'App/xtool/.xtool-tmp/LlamaPad.xcodeproj/project.pbxproj'
data = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(project)]))
objects = data['objects']
asset_id = 'A11A00000000000000000001'
build_id = 'A11A00000000000000000002'
phase_id = 'A11A00000000000000000003'
objects[asset_id] = {'isa': 'PBXFileReference', 'lastKnownFileType': 'folder.assetcatalog',
    'path': '../../Assets.xcassets', 'sourceTree': 'SOURCE_ROOT'}
objects[build_id] = {'isa': 'PBXBuildFile', 'fileRef': asset_id}
objects[phase_id] = {'isa': 'PBXResourcesBuildPhase', 'buildActionMask': '2147483647',
    'files': [build_id], 'runOnlyForDeploymentPostprocessing': '0'}
target = next(obj for obj in objects.values() if obj.get('isa') == 'PBXNativeTarget' and obj.get('name') == 'LlamaPad-App')
if phase_id not in target['buildPhases']:
    target['buildPhases'].append(phase_id)
configs = objects[target['buildConfigurationList']]['buildConfigurations']
for config_id in configs:
    objects[config_id]['buildSettings']['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
project.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_XML, sort_keys=False))
print('Configured app icon catalog in the Xcode app target.')
