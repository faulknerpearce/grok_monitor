#!/usr/bin/env python3
"""Generate a reliable GrokUsage.xcodeproj with explicit file paths."""
from __future__ import annotations
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "GrokUsage"
TESTS = ROOT / "GrokUsageTests"
PROJ = ROOT / "GrokUsage.xcodeproj"
PROJ.mkdir(exist_ok=True)

SWIFT_VERSION = "5.10"


def uid(seed: str) -> str:
    return hashlib.md5(seed.encode()).hexdigest()[:24].upper()


swift_files = sorted(p.relative_to(ROOT) for p in SRC.rglob("*.swift"))
test_files = sorted(p.relative_to(ROOT) for p in TESTS.rglob("*.swift"))
asset = Path("GrokUsage/Resources/Assets.xcassets")
fixture = Path("GrokUsage/Fixtures/usage_fixture.json")
info = Path("GrokUsage/Resources/Info.plist")
ent = Path("GrokUsage/Resources/GrokUsage.entitlements")
privacy = Path("GrokUsage/Resources/PrivacyInfo.xcprivacy")

ids = {k: uid(f"id:{k}") for k in [
    "project", "main", "products", "src_group", "tests_group", "res_group",
    "sources", "resources", "frameworks",
    "app_target", "test_target", "app_product", "test_product",
    "app_cfgs", "test_cfgs", "proj_cfgs",
    "dbg_proj", "rel_proj", "dbg_app", "rel_app", "dbg_test", "rel_test",
    "test_sources", "test_frameworks", "dep", "proxy", "app_in_tests",
]}

file_refs = {str(p): uid(f"ref:{p}") for p in [*swift_files, *test_files, asset, fixture, info, ent, privacy]}
src_builds = [(uid(f"src_build:{p}"), file_refs[str(p)], p.name) for p in swift_files]
res_builds = [
    (uid(f"res_build:{asset}"), file_refs[str(asset)], "Assets.xcassets"),
    (uid(f"res_build:{fixture}"), file_refs[str(fixture)], "usage_fixture.json"),
    (uid(f"res_build:{privacy}"), file_refs[str(privacy)], "PrivacyInfo.xcprivacy"),
]
test_builds = [(uid(f"test_build:{p}"), file_refs[str(p)], p.name) for p in test_files]

out: list[str] = []
a = out.append

a("// !$*UTF8*$!")
a("{")
a("\tarchiveVersion = 1;")
a("\tclasses = {};")
a("\tobjectVersion = 56;")
a("\tobjects = {")

a("/* Begin PBXBuildFile section */")
for bid, ref, name in src_builds:
    a(f"\t\t{bid} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};")
for bid, ref, name in res_builds:
    a(f"\t\t{bid} /* {name} in Resources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};")
for bid, ref, name in test_builds:
    a(f"\t\t{bid} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};")
a(f"\t\t{ids['app_in_tests']} /* Grok Usage.app in Frameworks */ = {{isa = PBXBuildFile; fileRef = {ids['app_product']} /* Grok Usage.app */; }};")
a("/* End PBXBuildFile section */")

a("/* Begin PBXContainerItemProxy section */")
a(f"\t\t{ids['proxy']} /* PBXContainerItemProxy */ = {{")
a("\t\t\tisa = PBXContainerItemProxy;")
a(f"\t\t\tcontainerPortal = {ids['project']} /* Project object */;")
a("\t\t\tproxyType = 1;")
a(f"\t\t\tremoteGlobalIDString = {ids['app_target']};")
a("\t\t\tremoteInfo = GrokUsage;")
a("\t\t};")
a("/* End PBXContainerItemProxy section */")

a("/* Begin PBXFileReference section */")
a(f'\t\t{ids["app_product"]} /* Grok Usage.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "Grok Usage.app"; sourceTree = BUILT_PRODUCTS_DIR; }};')
a(f'\t\t{ids["test_product"]} /* GrokUsageTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = GrokUsageTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};')
for p in swift_files:
    a(f'\t\t{file_refs[str(p)]} /* {p.name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {p.as_posix()}; sourceTree = SOURCE_ROOT; }};')
for p in test_files:
    a(f'\t\t{file_refs[str(p)]} /* {p.name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {p.as_posix()}; sourceTree = SOURCE_ROOT; }};')
a(f'\t\t{file_refs[str(asset)]} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = {asset.as_posix()}; sourceTree = SOURCE_ROOT; }};')
a(f'\t\t{file_refs[str(fixture)]} /* usage_fixture.json */ = {{isa = PBXFileReference; lastKnownFileType = text.json; path = {fixture.as_posix()}; sourceTree = SOURCE_ROOT; }};')
a(f'\t\t{file_refs[str(info)]} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = {info.as_posix()}; sourceTree = SOURCE_ROOT; }};')
a(f'\t\t{file_refs[str(ent)]} /* GrokUsage.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = {ent.as_posix()}; sourceTree = SOURCE_ROOT; }};')
a(f'\t\t{file_refs[str(privacy)]} /* PrivacyInfo.xcprivacy */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = {privacy.as_posix()}; sourceTree = SOURCE_ROOT; }};')
a("/* End PBXFileReference section */")

a("/* Begin PBXGroup section */")
a(f"\t\t{ids['main']} = {{")
a("\t\t\tisa = PBXGroup;")
a("\t\t\tchildren = (")
a(f"\t\t\t\t{ids['src_group']} /* Sources */,")
a(f"\t\t\t\t{ids['res_group']} /* Resources */,")
a(f"\t\t\t\t{ids['tests_group']} /* GrokUsageTests */,")
a(f"\t\t\t\t{ids['products']} /* Products */,")
a("\t\t\t);")
a('\t\t\tsourceTree = "<group>";')
a("\t\t};")
a(f"\t\t{ids['products']} /* Products */ = {{")
a("\t\t\tisa = PBXGroup;")
a("\t\t\tchildren = (")
a(f"\t\t\t\t{ids['app_product']} /* Grok Usage.app */,")
a(f"\t\t\t\t{ids['test_product']} /* GrokUsageTests.xctest */,")
a("\t\t\t);")
a("\t\t\tname = Products;")
a('\t\t\tsourceTree = "<group>";')
a("\t\t};")
a(f"\t\t{ids['src_group']} /* Sources */ = {{")
a("\t\t\tisa = PBXGroup;")
a("\t\t\tchildren = (")
for p in swift_files:
    a(f"\t\t\t\t{file_refs[str(p)]} /* {p.name} */,")
a("\t\t\t);")
a("\t\t\tname = Sources;")
a('\t\t\tsourceTree = "<group>";')
a("\t\t};")
a(f"\t\t{ids['res_group']} /* Resources */ = {{")
a("\t\t\tisa = PBXGroup;")
a("\t\t\tchildren = (")
a(f"\t\t\t\t{file_refs[str(asset)]} /* Assets.xcassets */,")
a(f"\t\t\t\t{file_refs[str(fixture)]} /* usage_fixture.json */,")
a(f"\t\t\t\t{file_refs[str(info)]} /* Info.plist */,")
a(f"\t\t\t\t{file_refs[str(ent)]} /* GrokUsage.entitlements */,")
a(f"\t\t\t\t{file_refs[str(privacy)]} /* PrivacyInfo.xcprivacy */,")
a("\t\t\t);")
a("\t\t\tname = Resources;")
a('\t\t\tsourceTree = "<group>";')
a("\t\t};")
a(f"\t\t{ids['tests_group']} /* GrokUsageTests */ = {{")
a("\t\t\tisa = PBXGroup;")
a("\t\t\tchildren = (")
for p in test_files:
    a(f"\t\t\t\t{file_refs[str(p)]} /* {p.name} */,")
a("\t\t\t);")
a("\t\t\tname = GrokUsageTests;")
a('\t\t\tsourceTree = "<group>";')
a("\t\t};")
a("/* End PBXGroup section */")

a("/* Begin PBXNativeTarget section */")
a(f"\t\t{ids['app_target']} /* GrokUsage */ = {{")
a("\t\t\tisa = PBXNativeTarget;")
a(f"\t\t\tbuildConfigurationList = {ids['app_cfgs']} /* Build configuration list for PBXNativeTarget \"GrokUsage\" */;")
a("\t\t\tbuildPhases = (")
a(f"\t\t\t\t{ids['sources']} /* Sources */,")
a(f"\t\t\t\t{ids['frameworks']} /* Frameworks */,")
a(f"\t\t\t\t{ids['resources']} /* Resources */,")
a("\t\t\t);")
a("\t\t\tbuildRules = ();")
a("\t\t\tdependencies = ();")
a("\t\t\tname = GrokUsage;")
a("\t\t\tproductName = GrokUsage;")
a(f"\t\t\tproductReference = {ids['app_product']} /* Grok Usage.app */;")
a('\t\t\tproductType = "com.apple.product-type.application";')
a("\t\t};")
a(f"\t\t{ids['test_target']} /* GrokUsageTests */ = {{")
a("\t\t\tisa = PBXNativeTarget;")
a(f"\t\t\tbuildConfigurationList = {ids['test_cfgs']} /* Build configuration list for PBXNativeTarget \"GrokUsageTests\" */;")
a("\t\t\tbuildPhases = (")
a(f"\t\t\t\t{ids['test_sources']} /* Sources */,")
a(f"\t\t\t\t{ids['test_frameworks']} /* Frameworks */,")
a("\t\t\t);")
a("\t\t\tbuildRules = ();")
a("\t\t\tdependencies = (")
a(f"\t\t\t\t{ids['dep']} /* PBXTargetDependency */,")
a("\t\t\t);")
a("\t\t\tname = GrokUsageTests;")
a("\t\t\tproductName = GrokUsageTests;")
a(f"\t\t\tproductReference = {ids['test_product']} /* GrokUsageTests.xctest */;")
a('\t\t\tproductType = "com.apple.product-type.bundle.unit-test";')
a("\t\t};")
a("/* End PBXNativeTarget section */")

a("/* Begin PBXProject section */")
a(f"\t\t{ids['project']} /* Project object */ = {{")
a("\t\t\tisa = PBXProject;")
a("\t\t\tattributes = {")
a("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
a("\t\t\t\tLastSwiftUpdateCheck = 1600;")
a("\t\t\t\tLastUpgradeCheck = 1600;")
a("\t\t\t};")
a(f"\t\t\tbuildConfigurationList = {ids['proj_cfgs']} /* Build configuration list for PBXProject \"GrokUsage\" */;")
a('\t\t\tcompatibilityVersion = "Xcode 15.0";')
a("\t\t\tdevelopmentRegion = en;")
a("\t\t\thasScannedForEncodings = 0;")
a("\t\t\tknownRegions = (en, Base);")
a(f"\t\t\tmainGroup = {ids['main']};")
a(f"\t\t\tproductRefGroup = {ids['products']} /* Products */;")
a('\t\t\tprojectDirPath = "";')
a('\t\t\tprojectRoot = "";')
a("\t\t\ttargets = (")
a(f"\t\t\t\t{ids['app_target']} /* GrokUsage */,")
a(f"\t\t\t\t{ids['test_target']} /* GrokUsageTests */,")
a("\t\t\t);")
a("\t\t};")
a("/* End PBXProject section */")

a("/* Begin PBXResourcesBuildPhase section */")
a(f"\t\t{ids['resources']} /* Resources */ = {{")
a("\t\t\tisa = PBXResourcesBuildPhase;")
a("\t\t\tbuildActionMask = 2147483647;")
a("\t\t\tfiles = (")
for bid, _, name in res_builds:
    a(f"\t\t\t\t{bid} /* {name} in Resources */,")
a("\t\t\t);")
a("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
a("\t\t};")
a("/* End PBXResourcesBuildPhase section */")

a("/* Begin PBXSourcesBuildPhase section */")
a(f"\t\t{ids['sources']} /* Sources */ = {{")
a("\t\t\tisa = PBXSourcesBuildPhase;")
a("\t\t\tbuildActionMask = 2147483647;")
a("\t\t\tfiles = (")
for bid, _, name in src_builds:
    a(f"\t\t\t\t{bid} /* {name} in Sources */,")
a("\t\t\t);")
a("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
a("\t\t};")
a(f"\t\t{ids['test_sources']} /* Sources */ = {{")
a("\t\t\tisa = PBXSourcesBuildPhase;")
a("\t\t\tbuildActionMask = 2147483647;")
a("\t\t\tfiles = (")
for bid, _, name in test_builds:
    a(f"\t\t\t\t{bid} /* {name} in Sources */,")
a("\t\t\t);")
a("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
a("\t\t};")
a("/* End PBXSourcesBuildPhase section */")

a("/* Begin PBXFrameworksBuildPhase section */")
a(f"\t\t{ids['frameworks']} /* Frameworks */ = {{")
a("\t\t\tisa = PBXFrameworksBuildPhase;")
a("\t\t\tbuildActionMask = 2147483647;")
a("\t\t\tfiles = ();")
a("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
a("\t\t};")
a(f"\t\t{ids['test_frameworks']} /* Frameworks */ = {{")
a("\t\t\tisa = PBXFrameworksBuildPhase;")
a("\t\t\tbuildActionMask = 2147483647;")
a("\t\t\tfiles = (")
a(f"\t\t\t\t{ids['app_in_tests']} /* Grok Usage.app in Frameworks */,")
a("\t\t\t);")
a("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
a("\t\t};")
a("/* End PBXFrameworksBuildPhase section */")

a("/* Begin PBXTargetDependency section */")
a(f"\t\t{ids['dep']} /* PBXTargetDependency */ = {{")
a("\t\t\tisa = PBXTargetDependency;")
a(f"\t\t\ttarget = {ids['app_target']} /* GrokUsage */;")
a(f"\t\t\ttargetProxy = {ids['proxy']} /* PBXContainerItemProxy */;")
a("\t\t};")
a("/* End PBXTargetDependency section */")

a("/* Begin XCBuildConfiguration section */")


def cfg(cid: str, name: str, kind: str) -> None:
    a(f"\t\t{cid} /* {name} */ = {{")
    a("\t\t\tisa = XCBuildConfiguration;")
    a("\t\t\tbuildSettings = {")
    if kind == "project":
        a("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
        a("\t\t\t\tCLANG_ENABLE_MODULES = YES;")
        a("\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;")
        a("\t\t\t\tSDKROOT = macosx;")
        a(f"\t\t\t\tSWIFT_VERSION = {SWIFT_VERSION};")
        if name == "Debug":
            a("\t\t\t\tONLY_ACTIVE_ARCH = YES;")
            a('\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";')
    elif kind == "app":
        a("\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
        a("\t\t\t\tCODE_SIGN_ENTITLEMENTS = GrokUsage/Resources/GrokUsage.entitlements;")
        a("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
        a("\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;")
        a("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
        a("\t\t\t\tENABLE_HARDENED_RUNTIME = YES;")
        if name == "Debug":
            a("\t\t\t\tENABLE_TESTABILITY = YES;")
        a("\t\t\t\tGENERATE_INFOPLIST_FILE = NO;")
        a("\t\t\t\tINFOPLIST_FILE = GrokUsage/Resources/Info.plist;")
        a('\t\t\t\tLD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/../Frameworks");')
        a("\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;")
        a("\t\t\t\tMARKETING_VERSION = 1.0.0;")
        a("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.grokusage.app;")
        a("\t\t\t\tPRODUCT_MODULE_NAME = GrokUsage;")
        a('\t\t\t\tPRODUCT_NAME = "Grok Usage";')
        a("\t\t\t\tPRIVACY_MANIFEST_FILE = GrokUsage/Resources/PrivacyInfo.xcprivacy;")
        a(f"\t\t\t\tSWIFT_VERSION = {SWIFT_VERSION};")
    else:
        a('\t\t\t\tBUNDLE_LOADER = "$(TEST_HOST)";')
        a("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
        a("\t\t\t\tGENERATE_INFOPLIST_FILE = YES;")
        a("\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;")
        a("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.grokusage.tests;")
        a('\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";')
        a(f"\t\t\t\tSWIFT_VERSION = {SWIFT_VERSION};")
        a('\t\t\t\tTEST_HOST = "$(BUILT_PRODUCTS_DIR)/Grok Usage.app/Contents/MacOS/Grok Usage";')
        a("\t\t\t\tENABLE_TESTING_SEARCH_PATHS = YES;")
    a("\t\t\t};")
    a(f"\t\t\tname = {name};")
    a("\t\t};")


cfg(ids["dbg_proj"], "Debug", "project")
cfg(ids["rel_proj"], "Release", "project")
cfg(ids["dbg_app"], "Debug", "app")
cfg(ids["rel_app"], "Release", "app")
cfg(ids["dbg_test"], "Debug", "test")
cfg(ids["rel_test"], "Release", "test")
a("/* End XCBuildConfiguration section */")

a("/* Begin XCConfigurationList section */")
for cid, d, r, label in [
    (ids["proj_cfgs"], ids["dbg_proj"], ids["rel_proj"], 'PBXProject "GrokUsage"'),
    (ids["app_cfgs"], ids["dbg_app"], ids["rel_app"], 'PBXNativeTarget "GrokUsage"'),
    (ids["test_cfgs"], ids["dbg_test"], ids["rel_test"], 'PBXNativeTarget "GrokUsageTests"'),
]:
    a(f"\t\t{cid} /* Build configuration list for {label} */ = {{")
    a("\t\t\tisa = XCConfigurationList;")
    a("\t\t\tbuildConfigurations = (")
    a(f"\t\t\t\t{d} /* Debug */,")
    a(f"\t\t\t\t{r} /* Release */,")
    a("\t\t\t);")
    a("\t\t\tdefaultConfigurationIsVisible = 0;")
    a("\t\t\tdefaultConfigurationName = Release;")
    a("\t\t};")
a("/* End XCConfigurationList section */")
a("\t};")
a(f"\trootObject = {ids['project']} /* Project object */;")
a("}")

(PROJ / "project.pbxproj").write_text("\n".join(out) + "\n")

scheme_dir = PROJ / "xcshareddata" / "xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
(scheme_dir / "GrokUsage.xcscheme").write_text(f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{ids['app_target']}" BuildableName = "Grok Usage.app" BlueprintName = "GrokUsage" ReferencedContainer = "container:GrokUsage.xcodeproj"/>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference skipped = "NO">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{ids['test_target']}" BuildableName = "GrokUsageTests.xctest" BlueprintName = "GrokUsageTests" ReferencedContainer = "container:GrokUsage.xcodeproj"/>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{ids['app_target']}" BuildableName = "Grok Usage.app" BlueprintName = "GrokUsage" ReferencedContainer = "container:GrokUsage.xcodeproj"/>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{ids['app_target']}" BuildableName = "Grok Usage.app" BlueprintName = "GrokUsage" ReferencedContainer = "container:GrokUsage.xcodeproj"/>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug"/>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"/>
</Scheme>
""")
print(f"Generated project with {len(swift_files)} sources")
