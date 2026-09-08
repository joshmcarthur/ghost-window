#!/usr/bin/env python3
"""Generate GhostWindow.xcodeproj/project.pbxproj."""

from pathlib import Path

ROOT = Path("/workspace")
PROJ = ROOT / "GhostWindow.xcodeproj" / "project.pbxproj"

SOURCES = [
    "GhostWindow/App/AppNotifications.swift",
    "GhostWindow/App/GhostLogger.swift",
    "GhostWindow/App/GhostWindowApp.swift",
    "GhostWindow/App/GlobalShortcut.swift",
    "GhostWindow/App/LaunchAtLogin.swift",
    "GhostWindow/App/MenuBarController.swift",
    "GhostWindow/App/Permissions.swift",
    "GhostWindow/App/Settings.swift",
    "GhostWindow/Backends/OverlayBackend.swift",
    "GhostWindow/Backends/SkyLightBackend.swift",
    "GhostWindow/Backends/WindowGhostBackend.swift",
    "GhostWindow/SkyLight/SkyLightBridge.swift",
    "GhostWindow/SkyLight/SkyLightWindow.swift",
    "GhostWindow/Windowing/Diagnostics.swift",
    "GhostWindow/Windowing/FrontmostWindowResolver.swift",
    "GhostWindow/Windowing/GhostStateStore.swift",
    "GhostWindow/Windowing/WindowManager.swift",
    "GhostWindow/Windowing/WindowReference.swift",
]

RESOURCES = [
    "GhostWindow/Resources/Assets.xcassets",
]

TESTS = [
    "GhostWindowTests/GhostWindowTests.swift",
]


def hid(n: int) -> str:
    return f"A{n:023X}"


ids = {
    "project": hid(1),
    "group_root": hid(2),
    "group_app": hid(3),
    "group_skylight": hid(4),
    "group_backends": hid(5),
    "group_windowing": hid(6),
    "group_resources": hid(7),
    "group_tests": hid(8),
    "group_products": hid(9),
    "group_src": hid(10),
    "target_app": hid(20),
    "target_tests": hid(21),
    "product_app": hid(22),
    "product_tests": hid(23),
    "phase_sources": hid(30),
    "phase_resources": hid(31),
    "phase_frameworks": hid(32),
    "phase_test_sources": hid(33),
    "phase_test_frameworks": hid(34),
    "target_dep": hid(35),
    "container_proxy": hid(36),
    "conf_project": hid(40),
    "conf_app": hid(41),
    "conf_tests": hid(42),
    "debug_project": hid(50),
    "release_project": hid(51),
    "debug_app": hid(52),
    "release_app": hid(53),
    "debug_tests": hid(54),
    "release_tests": hid(55),
}

file_ids = {}
n = 100
for path in SOURCES + RESOURCES + TESTS + ["GhostWindow/Resources/Info.plist", "GhostWindow/Resources/GhostWindow.entitlements"]:
    file_ids[path] = hid(n)
    n += 1

build_ids = {}
n = 200
for path in SOURCES + RESOURCES:
    build_ids[path] = hid(n)
    n += 1
for path in TESTS:
    build_ids[path] = hid(n)
    n += 1

def file_ref(path: str) -> str:
    name = Path(path).name
    fid = file_ids[path]
    if path.endswith(".xcassets"):
        return f'\t\t{fid} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = {name}; sourceTree = "<group>"; }};'
    if path.endswith(".plist"):
        return f'\t\t{fid} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = {name}; sourceTree = "<group>"; }};'
    if path.endswith(".entitlements"):
        return f'\t\t{fid} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = {name}; sourceTree = "<group>"; }};'
    return f'\t\t{fid} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = "<group>"; }};'

def build_file(path: str) -> str:
    name = Path(path).name
    return f'\t\t{build_ids[path]} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ids[path]} /* {name} */; }};'

def resource_build(path: str) -> str:
    name = Path(path).name
    return f'\t\t{build_ids[path]} /* {name} in Resources */ = {{isa = PBXBuildFile; fileRef = {file_ids[path]} /* {name} */; }};'

lines = []
lines.append("// !$*UTF8*$!")
lines.append("{")
lines.append("\tarchiveVersion = 1;")
lines.append("\tclasses = {")
lines.append("\t};")
lines.append("\tobjectVersion = 56;")
lines.append("\tobjects = {")
lines.append("")
lines.append("/* Begin PBXBuildFile section */")
for path in SOURCES:
    lines.append(build_file(path))
for path in RESOURCES:
    lines.append(resource_build(path))
for path in TESTS:
    name = Path(path).name
    lines.append(f'\t\t{build_ids[path]} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ids[path]} /* {name} */; }};')
lines.append("/* End PBXBuildFile section */")
lines.append("")
lines.append("/* Begin PBXFileReference section */")
lines.append(f'\t\t{ids["product_app"]} /* GhostWindow.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = GhostWindow.app; sourceTree = BUILT_PRODUCTS_DIR; }};')
lines.append(f'\t\t{ids["product_tests"]} /* GhostWindowTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = GhostWindowTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};')
for path in SOURCES + RESOURCES + TESTS + ["GhostWindow/Resources/Info.plist", "GhostWindow/Resources/GhostWindow.entitlements"]:
    lines.append(file_ref(path))
lines.append("/* End PBXFileReference section */")
lines.append("")

def group(gid, name, children, path=None):
    lines.append(f"\t\t{gid} /* {name} */ = {{")
    lines.append("\t\t\tisa = PBXGroup;")
    lines.append("\t\t\tchildren = (")
    for child in children:
        lines.append(f"\t\t\t\t{child}")
    lines.append("\t\t\t);")
    if path:
        lines.append(f"\t\t\tpath = {path};")
    lines.append(f'\t\t\tsourceTree = "<group>";')
    lines.append("\t\t};")

lines.append("/* Begin PBXGroup section */")
group(ids["group_root"], "", [
    f'{ids["group_src"]} /* GhostWindow */,',
    f'{ids["group_tests"]} /* GhostWindowTests */,',
    f'{ids["group_products"]} /* Products */,',
])
group(ids["group_products"], "Products", [
    f'{ids["product_app"]} /* GhostWindow.app */,',
    f'{ids["product_tests"]} /* GhostWindowTests.xctest */,',
])
group(ids["group_src"], "GhostWindow", [
    f'{ids["group_app"]} /* App */,',
    f'{ids["group_skylight"]} /* SkyLight */,',
    f'{ids["group_backends"]} /* Backends */,',
    f'{ids["group_windowing"]} /* Windowing */,',
    f'{ids["group_resources"]} /* Resources */,',
], path="GhostWindow")

def files_in(prefix):
    out = []
    for path in SOURCES:
        if path.startswith(prefix):
            out.append(f'{file_ids[path]} /* {Path(path).name} */,')
    return out

group(ids["group_app"], "App", files_in("GhostWindow/App/"), path="App")
group(ids["group_skylight"], "SkyLight", files_in("GhostWindow/SkyLight/"), path="SkyLight")
group(ids["group_backends"], "Backends", files_in("GhostWindow/Backends/"), path="Backends")
group(ids["group_windowing"], "Windowing", files_in("GhostWindow/Windowing/"), path="Windowing")
group(ids["group_resources"], "Resources", [
    f'{file_ids["GhostWindow/Resources/Assets.xcassets"]} /* Assets.xcassets */,',
    f'{file_ids["GhostWindow/Resources/Info.plist"]} /* Info.plist */,',
    f'{file_ids["GhostWindow/Resources/GhostWindow.entitlements"]} /* GhostWindow.entitlements */,',
], path="Resources")
group(ids["group_tests"], "GhostWindowTests", [
    f'{file_ids["GhostWindowTests/GhostWindowTests.swift"]} /* GhostWindowTests.swift */,',
], path="GhostWindowTests")
lines.append("/* End PBXGroup section */")
lines.append("")

lines.append("/* Begin PBXContainerItemProxy section */")
lines.append(f'\t\t{ids["container_proxy"]} /* PBXContainerItemProxy */ = {{')
lines.append("\t\t\tisa = PBXContainerItemProxy;")
lines.append(f'\t\t\tcontainerPortal = {ids["project"]} /* Project object */;')
lines.append("\t\t\tproxyType = 1;")
lines.append(f'\t\t\tremoteGlobalIDString = {ids["target_app"]};')
lines.append('\t\t\tremoteInfo = GhostWindow;')
lines.append("\t\t};")
lines.append("/* End PBXContainerItemProxy section */")
lines.append("")
lines.append("/* Begin PBXTargetDependency section */")
lines.append(f'\t\t{ids["target_dep"]} /* PBXTargetDependency */ = {{')
lines.append("\t\t\tisa = PBXTargetDependency;")
lines.append('\t\t\ttarget = %s /* GhostWindow */;' % ids["target_app"])
lines.append(f'\t\t\ttargetProxy = {ids["container_proxy"]} /* PBXContainerItemProxy */;')
lines.append("\t\t};")
lines.append("/* End PBXTargetDependency section */")
lines.append("")
lines.append(f'\t\t{ids["target_app"]} /* GhostWindow */ = {{')
lines.append("\t\t\tisa = PBXNativeTarget;")
lines.append('\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget "GhostWindow" */;' % ids["conf_app"])
lines.append("\t\t\tbuildPhases = (")
lines.append(f'\t\t\t\t{ids["phase_sources"]} /* Sources */,')
lines.append(f'\t\t\t\t{ids["phase_frameworks"]} /* Frameworks */,')
lines.append(f'\t\t\t\t{ids["phase_resources"]} /* Resources */,')
lines.append("\t\t\t);")
lines.append("\t\t\tbuildRules = (")
lines.append("\t\t\t);")
lines.append("\t\t\tdependencies = (")
lines.append("\t\t\t);")
lines.append('\t\t\tname = GhostWindow;')
lines.append('\t\t\tproductName = GhostWindow;')
lines.append(f'\t\t\tproductReference = {ids["product_app"]} /* GhostWindow.app */;')
lines.append('\t\t\tproductType = "com.apple.product-type.application";')
lines.append("\t\t};")
lines.append(f'\t\t{ids["target_tests"]} /* GhostWindowTests */ = {{')
lines.append("\t\t\tisa = PBXNativeTarget;")
lines.append('\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget "GhostWindowTests" */;' % ids["conf_tests"])
lines.append("\t\t\tbuildPhases = (")
lines.append(f'\t\t\t\t{ids["phase_test_sources"]} /* Sources */,')
lines.append(f'\t\t\t\t{ids["phase_test_frameworks"]} /* Frameworks */,')
lines.append("\t\t\t);")
lines.append("\t\t\tbuildRules = (")
lines.append("\t\t\t);")
lines.append("\t\t\tdependencies = (")
lines.append(f'\t\t\t\t{ids["target_dep"]} /* PBXTargetDependency */,')
lines.append("\t\t\t);")
lines.append("\t\t\tproductName = GhostWindowTests;")
lines.append(f'\t\t\tproductReference = {ids["product_tests"]} /* GhostWindowTests.xctest */;')
lines.append('\t\t\tproductType = "com.apple.product-type.bundle.unit-test";')
lines.append("\t\t};")
lines.append("/* End PBXNativeTarget section */")
lines.append("")

lines.append("/* Begin PBXProject section */")
lines.append(f'\t\t{ids["project"]} /* Project object */ = {{')
lines.append("\t\t\tisa = PBXProject;")
lines.append("\t\t\tattributes = {")
lines.append("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
lines.append('\t\t\t\tLastSwiftUpdateCheck = 1600;')
lines.append('\t\t\t\tLastUpgradeCheck = 1600;')
lines.append("\t\t\t\tTargetAttributes = {")
lines.append(f'\t\t\t\t\t{ids["target_app"]} = {{')
lines.append("\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
lines.append("\t\t\t\t\t};")
lines.append(f'\t\t\t\t\t{ids["target_tests"]} = {{')
lines.append("\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
lines.append(f'\t\t\t\t\t\tTestTargetID = {ids["target_app"]};')
lines.append("\t\t\t\t\t};")
lines.append("\t\t\t\t};")
lines.append("\t\t\t};")
lines.append('\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXProject "GhostWindow" */;' % ids["conf_project"])
lines.append('\t\t\tcompatibilityVersion = "Xcode 14.0";')
lines.append('\t\t\tdevelopmentRegion = en;')
lines.append("\t\t\thasScannedForEncodings = 0;")
lines.append("\t\t\tknownRegions = (")
lines.append("\t\t\t\ten,")
lines.append("\t\t\t\tBase,")
lines.append("\t\t\t);")
lines.append(f'\t\t\tmainGroup = {ids["group_root"]};')
lines.append(f'\t\t\tproductRefGroup = {ids["group_products"]} /* Products */;')
lines.append('\t\t\tprojectDirPath = "";')
lines.append('\t\t\tprojectRoot = "";')
lines.append("\t\t\ttargets = (")
lines.append(f'\t\t\t\t{ids["target_app"]} /* GhostWindow */,')
lines.append(f'\t\t\t\t{ids["target_tests"]} /* GhostWindowTests */,')
lines.append("\t\t\t);")
lines.append("\t\t};")
lines.append("/* End PBXProject section */")
lines.append("")

lines.append("/* Begin PBXResourcesBuildPhase section */")
lines.append(f'\t\t{ids["phase_resources"]} /* Resources */ = {{')
lines.append("\t\t\tisa = PBXResourcesBuildPhase;")
lines.append("\t\t\tbuildActionMask = 2147483647;")
lines.append("\t\t\tfiles = (")
for path in RESOURCES:
    name = Path(path).name
    lines.append(f'\t\t\t\t{build_ids[path]} /* {name} in Resources */,')
lines.append("\t\t\t);")
lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
lines.append("\t\t};")
lines.append("/* End PBXResourcesBuildPhase section */")
lines.append("")

lines.append("/* Begin PBXFrameworksBuildPhase section */")
lines.append(f'\t\t{ids["phase_frameworks"]} /* Frameworks */ = {{')
lines.append("\t\t\tisa = PBXFrameworksBuildPhase;")
lines.append("\t\t\tbuildActionMask = 2147483647;")
lines.append("\t\t\tfiles = (")
lines.append("\t\t\t);")
lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
lines.append("\t\t};")
lines.append(f'\t\t{ids["phase_test_frameworks"]} /* Frameworks */ = {{')
lines.append("\t\t\tisa = PBXFrameworksBuildPhase;")
lines.append("\t\t\tbuildActionMask = 2147483647;")
lines.append("\t\t\tfiles = (")
lines.append("\t\t\t);")
lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
lines.append("\t\t};")
lines.append("/* End PBXFrameworksBuildPhase section */")
lines.append("")

lines.append("/* Begin PBXSourcesBuildPhase section */")
lines.append(f'\t\t{ids["phase_sources"]} /* Sources */ = {{')
lines.append("\t\t\tisa = PBXSourcesBuildPhase;")
lines.append("\t\t\tbuildActionMask = 2147483647;")
lines.append("\t\t\tfiles = (")
for path in SOURCES:
    name = Path(path).name
    lines.append(f'\t\t\t\t{build_ids[path]} /* {name} in Sources */,')
lines.append("\t\t\t);")
lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
lines.append("\t\t};")
lines.append(f'\t\t{ids["phase_test_sources"]} /* Sources */ = {{')
lines.append("\t\t\tisa = PBXSourcesBuildPhase;")
lines.append("\t\t\tbuildActionMask = 2147483647;")
lines.append("\t\t\tfiles = (")
for path in TESTS:
    name = Path(path).name
    lines.append(f'\t\t\t\t{build_ids[path]} /* {name} in Sources */,')
lines.append("\t\t\t);")
lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
lines.append("\t\t};")
lines.append("/* End PBXSourcesBuildPhase section */")
lines.append("")

common_debug = """
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_TESTABILITY = YES;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_OPTIMIZATION_LEVEL = 0;
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = macosx;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 5.0;
"""

common_release = """
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				SDKROOT = macosx;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
				SWIFT_VERSION = 5.0;
"""

app_settings = """
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_ENTITLEMENTS = GhostWindow/Resources/GhostWindow.entitlements;
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				CURRENT_PROJECT_VERSION = 1;
				ENABLE_HARDENED_RUNTIME = YES;
				ENABLE_TESTABILITY = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = GhostWindow/Resources/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/../Frameworks");
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				MARKETING_VERSION = 1.0.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.joshmcarthur.GhostWindow;
				PRODUCT_NAME = GhostWindow;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
"""

test_settings = """
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.joshmcarthur.GhostWindowTests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_VERSION = 5.0;
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/GhostWindow.app/Contents/MacOS/GhostWindow";
				BUNDLE_LOADER = "$(TEST_HOST)";
"""

lines.append("/* Begin XCBuildConfiguration section */")
lines.append(f'\t\t{ids["debug_project"]} /* Debug */ = {{')
lines.append("\t\t\tisa = XCBuildConfiguration;")
lines.append("\t\t\tbuildSettings = {")
lines.append(common_debug)
lines.append("\t\t\t};")
lines.append("\t\t\tname = Debug;")
lines.append("\t\t};")
lines.append(f'\t\t{ids["release_project"]} /* Release */ = {{')
lines.append("\t\t\tisa = XCBuildConfiguration;")
lines.append("\t\t\tbuildSettings = {")
lines.append(common_release)
lines.append("\t\t\t};")
lines.append("\t\t\tname = Release;")
lines.append("\t\t};")
lines.append(f'\t\t{ids["debug_app"]} /* Debug */ = {{')
lines.append("\t\t\tisa = XCBuildConfiguration;")
lines.append("\t\t\tbuildSettings = {")
lines.append(app_settings)
lines.append("\t\t\t};")
lines.append("\t\t\tname = Debug;")
lines.append("\t\t};")
lines.append(f'\t\t{ids["release_app"]} /* Release */ = {{')
lines.append("\t\t\tisa = XCBuildConfiguration;")
lines.append("\t\t\tbuildSettings = {")
lines.append(app_settings)
lines.append("\t\t\t};")
lines.append("\t\t\tname = Release;")
lines.append("\t\t};")
lines.append(f'\t\t{ids["debug_tests"]} /* Debug */ = {{')
lines.append("\t\t\tisa = XCBuildConfiguration;")
lines.append("\t\t\tbuildSettings = {")
lines.append(test_settings)
lines.append("\t\t\t};")
lines.append("\t\t\tname = Debug;")
lines.append("\t\t};")
lines.append(f'\t\t{ids["release_tests"]} /* Release */ = {{')
lines.append("\t\t\tisa = XCBuildConfiguration;")
lines.append("\t\t\tbuildSettings = {")
lines.append(test_settings)
lines.append("\t\t\t};")
lines.append("\t\t\tname = Release;")
lines.append("\t\t};")
lines.append("/* End XCBuildConfiguration section */")
lines.append("")

def conf_list(cid, name, debug, release):
    lines.append(f'\t\t{cid} /* Build configuration list for {name} */ = {{')
    lines.append("\t\t\tisa = XCConfigurationList;")
    lines.append("\t\t\tbuildConfigurations = (")
    lines.append(f"\t\t\t\t{debug} /* Debug */,")
    lines.append(f"\t\t\t\t{release} /* Release */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\tdefaultConfigurationIsVisible = 0;")
    lines.append("\t\t\tdefaultConfigurationName = Release;")
    lines.append("\t\t};")

lines.append("/* Begin XCConfigurationList section */")
conf_list(ids["conf_project"], 'PBXProject "GhostWindow"', ids["debug_project"], ids["release_project"])
conf_list(ids["conf_app"], 'PBXNativeTarget "GhostWindow"', ids["debug_app"], ids["release_app"])
conf_list(ids["conf_tests"], 'PBXNativeTarget "GhostWindowTests"', ids["debug_tests"], ids["release_tests"])
lines.append("/* End XCConfigurationList section */")
lines.append("\t};")
lines.append(f'\trootObject = {ids["project"]} /* Project object */;')
lines.append("}")

PROJ.parent.mkdir(parents=True, exist_ok=True)
PROJ.write_text("\n".join(lines) + "\n")
print(f"Wrote {PROJ}")
print(f"sources={len(SOURCES)} tests={len(TESTS)}")
