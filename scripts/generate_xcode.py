#!/usr/bin/env python3
"""Deterministic Xcode project generation using only Python stdlib. No XcodeGen dependency."""
from pathlib import Path
import hashlib
import argparse
import json
import plistlib
parser=argparse.ArgumentParser()
parser.add_argument('--bundle-id', default='personal.FuelForm')
parser.add_argument('--team-id', default='')
args=parser.parse_args()
root = Path(__file__).resolve().parents[1] / 'ios'
project = root / 'FuelForm.xcodeproj'
project.mkdir(exist_ok=True)
objects = {}
def ident(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def add(name, text):
    key = ident(name); objects[key] = text; return key
def refs(ids): return '(' + ', '.join(ids) + (',' if ids else '') + ')'
def quote(s): return json.dumps(s)
app_id = ident('app'); test_id = ident('tests'); project_id = ident('project')
app_product = add('appProduct', '{isa = PBXFileReference; explicitFileType = wrapper.application; path = FuelForm.app; sourceTree = BUILT_PRODUCTS_DIR;}')
test_product = add('testProduct', '{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = FuelFormTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;}')
files=[]; app_sources=[]; test_sources=[]; resources=[]; test_resources=[]
def file(path, type_, phase):
    ref=add('file:'+str(path), '{isa = PBXFileReference; lastKnownFileType = '+type_+'; path = '+quote(str(path))+'; sourceTree = "<group>";}')
    files.append(ref)
    if phase is not None: phase.append(add('build:'+str(path), '{isa = PBXBuildFile; fileRef = '+ref+';}'))
for p in sorted((root/'FuelForm').rglob('*.swift')): file(p.relative_to(root), 'sourcecode.swift', app_sources)
for p in sorted((root/'Tests').rglob('*.swift')):
    if p.name != 'Runner.swift': file(p.relative_to(root), 'sourcecode.swift', test_sources)
for name in ['foods.v1.json','exercises.v1.json']: file(Path('FuelForm/Resources')/name, 'text.json', resources)
file(Path('FuelForm/Resources/Assets.xcassets'), 'folder.assetcatalog', resources)
for name in ['Info-Debug.plist','Info-Release.plist']: file(Path('FuelForm')/name, 'text.plist.xml', None)
file(Path('FuelForm/FuelForm-Simulator.entitlements'), 'text.plist.entitlements', None)
for p in sorted((root/'Tests/Fixtures').glob('*.json')): file(p.relative_to(root), 'text.json', test_resources)
products = add('products','{isa = PBXGroup; children = '+refs([app_product,test_product])+'; name = Products; sourceTree = "<group>";}')
group = add('group','{isa = PBXGroup; children = '+refs(files+[products])+'; sourceTree = "<group>";}')
def phase(name,isa,items): return add(name,'{isa = '+isa+'; buildActionMask = 2147483647; files = '+refs(items)+'; runOnlyForDeploymentPostprocessing = 0;}')
app_phases=[phase('appSources','PBXSourcesBuildPhase',app_sources),phase('appFrameworks','PBXFrameworksBuildPhase',[]),phase('appResources','PBXResourcesBuildPhase',resources)]
test_phases=[phase('testSources','PBXSourcesBuildPhase',test_sources),phase('testFrameworks','PBXFrameworksBuildPhase',[]),phase('testResources','PBXResourcesBuildPhase',test_resources)]
def configlist(name, settings):
    ids=[]
    for config,values in settings.items():
        serialized=' '.join(quote(k)+' = '+quote(str(v))+';' for k,v in values.items())
        ids.append(add(name+config,'{isa = XCBuildConfiguration; name = '+config+'; buildSettings = {'+serialized+'};}'))
    return add(name+'list','{isa = XCConfigurationList; buildConfigurations = '+refs(ids)+'; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}')
base={'IPHONEOS_DEPLOYMENT_TARGET':'17.0','SDKROOT':'iphoneos','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','ENABLE_TESTABILITY':'YES'}
pconfigs=configlist('projectConfig',{'Debug':dict(base,SWIFT_OPTIMIZATION_LEVEL='-Onone',SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG'), 'Release':dict(base,SWIFT_OPTIMIZATION_LEVEL='-O',ENABLE_TESTABILITY='NO')})
common={'PRODUCT_NAME':'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER':args.bundle_id,'CODE_SIGN_STYLE':'Automatic','TARGETED_DEVICE_FAMILY':'1','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME':'AccentColor','GENERATE_INFOPLIST_FILE':'NO','MARKETING_VERSION':'1.0','CURRENT_PROJECT_VERSION':'1','SWIFT_EMIT_LOC_STRINGS':'YES'}
# Simulator has no provisioning profile to inject the app's private Keychain identity.
# Device builds continue to get their identifier from the user's real signing team.
common['CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]']='FuelForm/FuelForm-Simulator.entitlements'
if args.team_id: common['DEVELOPMENT_TEAM']=args.team_id
aconfigs=configlist('appConfig', {c:dict(common,INFOPLIST_FILE=f'FuelForm/Info-{c}.plist') for c in ['Debug','Release']})
tconfigs=configlist('testConfig', {c:{'PRODUCT_NAME':'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER':args.bundle_id+'.tests','GENERATE_INFOPLIST_FILE':'YES','CODE_SIGN_STYLE':'Automatic','TARGETED_DEVICE_FAMILY':'1','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/FuelForm.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/FuelForm','BUNDLE_LOADER':'$(TEST_HOST)'} for c in ['Debug','Release']})
if args.team_id:
    for key, value in list(objects.items()):
        if 'PRODUCT_BUNDLE_IDENTIFIER' in value and args.bundle_id+'.tests' in value: objects[key]=value.replace('buildSettings = {', 'buildSettings = {DEVELOPMENT_TEAM = '+quote(args.team_id)+';')
proxy=add('proxy','{isa = PBXContainerItemProxy; containerPortal = '+project_id+'; proxyType = 1; remoteGlobalIDString = '+app_id+'; remoteInfo = FuelForm;}')
dep=add('dependency','{isa = PBXTargetDependency; target = '+app_id+'; targetProxy = '+proxy+';}')
add('app','{isa = PBXNativeTarget; name = FuelForm; productName = FuelForm; productReference = '+app_product+'; productType = "com.apple.product-type.application"; buildConfigurationList = '+aconfigs+'; buildPhases = '+refs(app_phases)+'; buildRules = (); dependencies = ();}')
add('tests','{isa = PBXNativeTarget; name = FuelFormTests; productName = FuelFormTests; productReference = '+test_product+'; productType = "com.apple.product-type.bundle.unit-test"; buildConfigurationList = '+tconfigs+'; buildPhases = '+refs(test_phases)+'; buildRules = (); dependencies = '+refs([dep])+';}')
add('project','{isa = PBXProject; attributes = {BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1500; TargetAttributes = {'+app_id+' = {CreatedOnToolsVersion = 15.0;}; '+test_id+' = {CreatedOnToolsVersion = 15.0; TestTargetID = '+app_id+';};};}; buildConfigurationList = '+pconfigs+'; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh-Hans; hasScannedForEncodings = 0; knownRegions = ("zh-Hans", en, Base); mainGroup = '+group+'; productRefGroup = '+products+'; projectDirPath = ""; projectRoot = ""; targets = '+refs([app_id,test_id])+';}')
text='// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'
text+='\n'.join(k+' = '+v+';' for k,v in sorted(objects.items()))
text+='\n}; rootObject = '+project_id+';}\n'
(project/'project.pbxproj').write_text(text)
schemes=project/'xcshareddata/xcschemes';schemes.mkdir(parents=True,exist_ok=True)
def buildref(id,name,product): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{id}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:FuelForm.xcodeproj"/>'
(schemes/'FuelForm.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1500" version="1.7">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildref(app_id,'FuelForm','FuelForm.app')}</BuildActionEntry></BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{buildref(test_id,'FuelFormTests','FuelFormTests.xctest')}</TestableReference></Testables></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildref(app_id,'FuelForm','FuelForm.app')}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO"><BuildableProductRunnable runnableDebuggingMode="0">{buildref(app_id,'FuelForm','FuelForm.app')}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
info={'CFBundleDevelopmentRegion':'zh-Hans','CFBundleDisplayName':'FuelForm','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleInfoDictionaryVersion':'6.0','CFBundleName':'$(PRODUCT_NAME)','CFBundlePackageType':'APPL','CFBundleShortVersionString':'$(MARKETING_VERSION)','CFBundleVersion':'$(CURRENT_PROJECT_VERSION)','LSRequiresIPhoneOS':True,'UILaunchScreen':{},'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False},'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait'],'NSCameraUsageDescription':'拍摄你主动选择记录的食物，照片保存在本机；点击后端分析时才上传。','NSPhotoLibraryUsageDescription':'仅导入你选中的食物照片到本机记录。','NSLocalNetworkUsageDescription':'连接你配置的本地 FuelForm 分析服务，只有请求分析时才发送照片。'}
for c in ['Debug','Release']:
    data=dict(info)
    if c=='Debug':
        data['NSAppTransportSecurity']={'NSAllowsLocalNetworking':True, 'NSExceptionDomains': {
            address: {'NSExceptionAllowsInsecureHTTPLoads':True}
            for address in ['127.0.0.1','10.0.0.0/8','172.16.0.0/12','192.168.0.0/16']
        }}
    (root/'FuelForm'/f'Info-{c}.plist').write_bytes(plistlib.dumps(data))
print('Generated FuelForm.xcodeproj, shared scheme, app + XCTest targets (iOS 17)')
