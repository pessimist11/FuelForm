#!/usr/bin/env python3
"""Structural validation only; does not replace xcodebuild or simulator tests."""
from pathlib import Path
import json
import plistlib
import subprocess
import xml.etree.ElementTree as ET
root=Path(__file__).resolve().parents[1]
project=root/'ios/FuelForm.xcodeproj/project.pbxproj'
result=subprocess.run(['plutil','-convert','json','-o','-',str(project)],check=True,capture_output=True)
p=json.loads(result.stdout); objects=p['objects']
file_refs=[v for v in objects.values() if v['isa']=='PBXFileReference' and v.get('sourceTree')=='<group>']
for ref in file_refs: assert (root/'ios'/ref['path']).exists(),ref['path']
source_paths={v['path'] for v in file_refs if v.get('lastKnownFileType')=='sourcecode.swift'}
for path in (root/'ios/FuelForm').rglob('*.swift'): assert str(path.relative_to(root/'ios')) in source_paths
for path in (root/'ios/Tests').rglob('*.swift'):
 if path.name!='Runner.swift': assert str(path.relative_to(root/'ios')) in source_paths
for v in objects.values():
 for key in ('fileRef','mainGroup','productReference','buildConfigurationList','containerPortal','targetProxy'):
  if key in v: assert v[key] in objects
 for key in ('children','files','buildPhases','buildConfigurations','targets','dependencies'):
  if key in v: assert all(x in objects for x in v[key])
assert len([v for v in objects.values() if v['isa']=='PBXNativeTarget'])==2
for config in ('Debug','Release'):
 data=plistlib.loads((root/f'ios/FuelForm/Info-{config}.plist').read_bytes())
 assert 'NSCameraUsageDescription' in data and 'NSLocalNetworkUsageDescription' in data
 ats=data.get('NSAppTransportSecurity',{});assert not ats.get('NSAllowsArbitraryLoads')
 if config=='Release': assert not ats.get('NSAllowsLocalNetworking')
ET.parse(root/'ios/FuelForm.xcodeproj/xcshareddata/xcschemes/FuelForm.xcscheme')
backend=json.loads((root/'backend/data/foods.v1.json').read_text());ios=json.loads((root/'ios/FuelForm/Resources/foods.v1.json').read_text());assert ios==backend
subprocess.run(['swiftc','-frontend','-parse',*[str(p) for p in (root/'ios/FuelForm').rglob('*.swift')]],check=True)
print('PASS: project references, resources, targets, shared scheme, Debug-only local HTTP, and Swift syntax (not an iOS build)')
