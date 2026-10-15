#!/usr/bin/env python3
"""Generate a conventional, dependency-free Xcode project with stable object IDs."""
from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parents[1]
def uid(s): return hashlib.sha256(s.encode()).hexdigest()[:24].upper()
def q(v):return json.dumps(str(v))
objects={}
def obj(tag,isa,**values):
 i=uid(tag);objects[i]={'isa':isa,**values};return i
app_sources=[];test_sources=[];resources=[];refs=[]
for path in sorted((root/'App').rglob('*')):
 if not path.is_file() or path.name=='Info.plist' or '.xcassets/' in path.as_posix():continue
 rel=path.relative_to(root).as_posix();ext=path.suffix
 if ext not in ('.swift','.xcstrings','.xcprivacy','.png'):continue
 ref=obj('file:'+rel,'PBXFileReference',lastKnownFileType={'.swift':'sourcecode.swift','.xcstrings':'text.json.xcstrings','.xcprivacy':'text.xml','.png':'image.png'}[ext],path=rel,sourceTree='<group>');refs.append(ref)
 build=obj('build:'+rel,'PBXBuildFile',fileRef=ref)
 (app_sources if ext=='.swift' else resources).append(build)
for path in sorted((root/'Tests').glob('*.swift')):
 rel=path.relative_to(root).as_posix();ref=obj('file:'+rel,'PBXFileReference',lastKnownFileType='sourcecode.swift',path=rel,sourceTree='<group>');refs.append(ref);test_sources.append(obj('build:'+rel,'PBXBuildFile',fileRef=ref))
asset=obj('asset-catalog','PBXFileReference',lastKnownFileType='folder.assetcatalog',path='App/Resources/Assets.xcassets',sourceTree='<group>');refs.append(asset)
resources.append(obj('asset-build','PBXBuildFile',fileRef=asset))
localized=[]
for lang in ('en','zh-Hans'):
 rel=f'App/Resources/{lang}.lproj/InfoPlist.strings'
 localized.append(obj('file:'+rel,'PBXFileReference',lastKnownFileType='text.plist.strings',name=lang,path=rel,sourceTree='<group>'))
variant=obj('InfoPlist-strings','PBXVariantGroup',children=localized,name='InfoPlist.strings',sourceTree='<group>');refs.append(variant)
resources.append(obj('InfoPlist-strings-build','PBXBuildFile',fileRef=variant))
cfg=obj('config-ref','PBXFileReference',lastKnownFileType='text.xcconfig',path='Config/Development.xcconfig',sourceTree='<group>');refs.append(cfg)
app_product=obj('product','PBXFileReference',explicitFileType='wrapper.application',includeInIndex=0,path='PinHaoYun.app',sourceTree='BUILT_PRODUCTS_DIR')
test_product=obj('test-product','PBXFileReference',explicitFileType='wrapper.cfbundle',includeInIndex=0,path='PinHaoYunTests.xctest',sourceTree='BUILT_PRODUCTS_DIR')
products=obj('products','PBXGroup',children=[app_product,test_product],name='Products',sourceTree='<group>')
group=obj('main-group','PBXGroup',children=refs+[products],sourceTree='<group>')
project_id=uid('project');app_id=uid('app-target');test_id=uid('test-target')
def phase(name,isa,files):return obj(name,isa,buildActionMask=2147483647,files=files,runOnlyForDeploymentPostprocessing=0)
app_phases=[phase('sources','PBXSourcesBuildPhase',app_sources),phase('frameworks','PBXFrameworksBuildPhase',[]),phase('resources','PBXResourcesBuildPhase',resources)]
test_phases=[phase('test-sources','PBXSourcesBuildPhase',test_sources),phase('test-frameworks','PBXFrameworksBuildPhase',[])]
def configs(prefix,settings,base=False):
 ids=[]
 for name in ('Debug','Release'):
  extra={'SWIFT_OPTIMIZATION_LEVEL':'-Onone','DEBUG_INFORMATION_FORMAT':'dwarf','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG','ENABLE_TESTABILITY':'YES','ONLY_ACTIVE_ARCH':'YES'} if name=='Debug' else {'SWIFT_OPTIMIZATION_LEVEL':'-O','DEBUG_INFORMATION_FORMAT':'dwarf-with-dsym','SWIFT_COMPILATION_MODE':'wholemodule'}
  kw={'buildSettings':{**settings,**extra},'name':name}
  if base:kw['baseConfigurationReference']=cfg
  ids.append(obj(prefix+name,'XCBuildConfiguration',**kw))
 return obj(prefix+'list','XCConfigurationList',buildConfigurations=ids,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
common={'IPHONEOS_DEPLOYMENT_TARGET':'17.0','SDKROOT':'iphoneos','SWIFT_VERSION':'6.0','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','ENABLE_USER_SCRIPT_SANDBOXING':'YES','SWIFT_STRICT_CONCURRENCY':'complete','TARGETED_DEVICE_FAMILY':'1','CODE_SIGN_STYLE':'Automatic'}
project_config=configs('project-',common)
app_config=configs('app-',{'PRODUCT_NAME':'PinHaoYun','PRODUCT_MODULE_NAME':'PinHaoYun','PRODUCT_BUNDLE_IDENTIFIER':'com.jake177.pinhaoyun','INFOPLIST_FILE':'App/Info.plist','GENERATE_INFOPLIST_FILE':'NO','SWIFT_EMIT_LOC_STRINGS':'YES','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','MARKETING_VERSION':'0.1.0','CURRENT_PROJECT_VERSION':'1','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','SUPPORTS_MACCATALYST':'NO','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks'},True)
test_config=configs('tests-',{'PRODUCT_NAME':'PinHaoYunTests','PRODUCT_BUNDLE_IDENTIFIER':'com.jake177.pinhaoyun.tests','GENERATE_INFOPLIST_FILE':'YES','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/PinHaoYun.app/PinHaoYun','BUNDLE_LOADER':'$(TEST_HOST)'},True)
proxy=obj('test-proxy','PBXContainerItemProxy',containerPortal=project_id,proxyType=1,remoteGlobalIDString=app_id,remoteInfo='PinHaoYun')
dependency=obj('test-dependency','PBXTargetDependency',target=app_id,targetProxy=proxy)
obj('app-target','PBXNativeTarget',buildConfigurationList=app_config,buildPhases=app_phases,buildRules=[],dependencies=[],name='PinHaoYun',productName='PinHaoYun',productReference=app_product,productType='com.apple.product-type.application')
obj('test-target','PBXNativeTarget',buildConfigurationList=test_config,buildPhases=test_phases,buildRules=[],dependencies=[dependency],name='PinHaoYunTests',productName='PinHaoYunTests',productReference=test_product,productType='com.apple.product-type.bundle.unit-test')
obj('project','PBXProject',attributes={'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'2700','TargetAttributes':{app_id:{'CreatedOnToolsVersion':'27.0'},test_id:{'CreatedOnToolsVersion':'27.0','TestTargetID':app_id}}},buildConfigurationList=project_config,compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','Base','zh-Hans'],mainGroup=group,productRefGroup=products,projectDirPath='',projectRoot='',targets=[app_id,test_id])
def render(v,level=0):
 if isinstance(v,dict):return '{ '+ ' '.join(f'{q(k)} = {render(x,level+1)};' for k,x in v.items())+' }'
 if isinstance(v,list):return '( '+', '.join(render(x,level+1) for x in v)+(' ,' if v else '')+' )'
 if isinstance(v,int):return str(v)
 if isinstance(v,str) and len(v)==24 and v in objects:return v
 return q(v)
folder=root/'PinHaoYun.xcodeproj';folder.mkdir(exist_ok=True)
(folder/'project.pbxproj').write_text('// !$*UTF8*$!\n'+render({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':project_id})+'\n')
scheme=folder/'xcshareddata/xcschemes';scheme.mkdir(parents=True,exist_ok=True)
ref=lambda target,name:f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:PinHaoYun.xcodeproj"/>'
(scheme/'PinHaoYun.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref(app_id,'PinHaoYun.app')}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.PosixSpawn" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{ref(test_id,'PinHaoYunTests.xctest')}</TestableReference></Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref(app_id,'PinHaoYun.app')}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref(app_id,'PinHaoYun.app')}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
print('Generated PinHaoYun.xcodeproj (no project-generation dependencies).')
