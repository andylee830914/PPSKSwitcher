#!/usr/bin/env python3
"""Regenerate the standalone Xcode project. No third-party dependencies."""
from hashlib import md5
from pathlib import Path
p = Path(__file__).resolve().parent
swift_files = ["PPSKSwitcherApp.swift", "PPSKProfile.swift", "PPSKCSVImporter.swift", "PPSKImportService.swift", "CredentialStore.swift", "WiFiSwitcher.swift", "PPSKModel.swift", "SettingsView.swift"]
frameworks = ["CoreWLAN", "CoreLocation", "Security"]
def uid(s): return md5(("PPSKSwitcher::" + s).encode()).hexdigest().upper()[:24]
def ref(s): return uid('ref:'+s)
def bld(s): return uid('build:'+s)
root=uid('root'); group=uid('group'); code_group=uid('codegroup'); fw_group=uid('fwgroup'); product_group=uid('products'); target=uid('target'); product=uid('product'); sources=uid('sources'); fwphase=uid('fwphase'); resources=uid('resources'); proj_cfgs=uid('projcfgs'); target_cfgs=uid('targetcfgs'); debug=uid('debug'); release=uid('release'); tdebug=uid('tdebug'); trelease=uid('trelease')
parts=[]
def obj(key, comment, content): parts.append(f'\t\t{key} /* {comment} */ = {{\n{content}\n\t\t}};')
for fn in swift_files:
    obj(bld(fn), fn+" in Sources", f'\t\t\tisa = PBXBuildFile; fileRef = {ref(fn)} /* {fn} */;')
for fw in frameworks:
    obj(bld(fw), fw+".framework in Frameworks", f'\t\t\tisa = PBXBuildFile; fileRef = {ref(fw)} /* {fw}.framework */;')
obj(bld('AppIcon.icon'), 'AppIcon.icon in Resources', f'\t\t\tisa = PBXBuildFile; fileRef = {ref("AppIcon.icon")} /* AppIcon.icon */;')
obj(ref('AppIcon.icon'), 'AppIcon.icon', '\t\t\tisa = PBXFileReference; lastKnownFileType = folder.iconcomposer.icon; path = AppIcon.icon; sourceTree = "<group>";')
for fn in swift_files:
    obj(ref(fn), fn, f'\t\t\tisa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {fn}; sourceTree = "<group>";')
obj(ref('Info.plist'), 'Info.plist', '\t\t\tisa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>";')
for fw in frameworks:
    obj(ref(fw), fw+'.framework', f'\t\t\tisa = PBXFileReference; lastKnownFileType = wrapper.framework; name = {fw}.framework; path = System/Library/Frameworks/{fw}.framework; sourceTree = SDKROOT;')
obj(product, 'PPSKSwitcher.app', '\t\t\tisa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = PPSKSwitcher.app; sourceTree = BUILT_PRODUCTS_DIR;')
obj(root,'Project object',f'''\t\t\tisa = PBXProject;
\t\t\tattributes = {{ LastUpgradeCheck = 2700; TargetAttributes = {{ {target} = {{ CreatedOnToolsVersion = 27.0; }}; }}; }};
\t\t\tbuildConfigurationList = {proj_cfgs} /* Build configuration list for PBXProject */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (en, Base);
\t\t\tmainGroup = {group};
\t\t\tproductRefGroup = {product_group};
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = ({target} /* PPSKSwitcher */);''')
obj(group,'Project files',f'''\t\t\tisa = PBXGroup;
\t\t\tchildren = ({code_group} /* PPSKSwitcher */, {fw_group} /* Frameworks */, {product_group} /* Products */);
\t\t\tsourceTree = "<group>";''')
obj(code_group,'PPSKSwitcher',f'''\t\t\tisa = PBXGroup;
\t\t\tchildren = ({", ".join(ref(x)+" /* "+x+" */" for x in swift_files + ["Info.plist", "AppIcon.icon"])});
\t\t\tpath = PPSKSwitcher;
\t\t\tsourceTree = "<group>";''')
obj(fw_group,'Frameworks',f'''\t\t\tisa = PBXGroup;
\t\t\tchildren = ({", ".join(ref(x)+" /* "+x+".framework */" for x in frameworks)});
\t\t\tname = Frameworks;
\t\t\tsourceTree = "<group>";''')
obj(product_group,'Products',f'''\t\t\tisa = PBXGroup;
\t\t\tchildren = ({product} /* PPSKSwitcher.app */);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";''')
obj(target,'PPSKSwitcher',f'''\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {target_cfgs};
\t\t\tbuildPhases = ({sources} /* Sources */, {fwphase} /* Frameworks */, {resources} /* Resources */);
\t\t\tbuildRules = ();
\t\t\tdependencies = ();
\t\t\tname = PPSKSwitcher;
\t\t\tproductName = PPSKSwitcher;
\t\t\tproductReference = {product} /* PPSKSwitcher.app */;
\t\t\tproductType = "com.apple.product-type.application";''')
obj(sources,'Sources',f'''\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = ({", ".join(bld(x)+" /* "+x+" in Sources */" for x in swift_files)});
\t\t\trunOnlyForDeploymentPostprocessing = 0;''')
obj(fwphase,'Frameworks',f'''\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = ({", ".join(bld(x)+" /* "+x+".framework in Frameworks */" for x in frameworks)});
\t\t\trunOnlyForDeploymentPostprocessing = 0;''')
obj(resources,'Resources',f'\t\t\tisa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({bld("AppIcon.icon")} /* AppIcon.icon in Resources */); runOnlyForDeploymentPostprocessing = 0;')
common='''\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\tSDKROOT = macosx;
\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;
\t\t\tSWIFT_VERSION = 5.0;
\t\t\tSUPPORTED_PLATFORMS = macosx;'''
for key, name, opt in [(debug,'Debug','-Onone'),(release,'Release','-O')]:
    obj(key,name,f'''\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{common}
\t\t\tSWIFT_OPTIMIZATION_LEVEL = {opt};
\t\t\t}};
\t\t\tname = {name};''')
for key, name in [(tdebug,'Debug'),(trelease,'Release')]:
    obj(key,name,f'''\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\tCODE_SIGN_IDENTITY = "-";
\t\t\tCURRENT_PROJECT_VERSION = 2;
\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\tINFOPLIST_FILE = PPSKSwitcher/Info.plist;
\t\t\tLD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/../Frameworks");
\t\t\tPRODUCT_BUNDLE_IDENTIFIER = app.local.PPSKSwitcher;
\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\tSWIFT_VERSION = 5.0;
\t\t\t}};
\t\t\tname = {name};''')
obj(proj_cfgs,'Project configs',f'''\t\t\tisa = XCConfigurationList; buildConfigurations = ({debug} /* Debug */, {release} /* Release */); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;''')
obj(target_cfgs,'Target configs',f'''\t\t\tisa = XCConfigurationList; buildConfigurations = ({tdebug} /* Debug */, {trelease} /* Release */); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;''')
content='// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n' + '\n'.join(parts) + '\n\t};\n\trootObject = '+root+' /* Project object */;\n}\n'
(p/'PPSKSwitcher.xcodeproj'/'project.pbxproj').write_text(content)
print('Wrote Xcode project:',len(content),'bytes')
