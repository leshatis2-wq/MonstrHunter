"""Generate the checked-in Xcode project on Windows, using Python stdlib only."""
from pathlib import Path
import hashlib
import json
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
objects = {}


def uid(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()


def add(key_name, isa, **fields):
    key = uid(key_name)
    objects[key] = {"isa": isa, **fields}
    return key


def serialize(value, level=0):
    pad = "\t" * level
    if isinstance(value, dict):
        return "{\n" + "".join(
            f"{pad}\t{json.dumps(str(k))} = {serialize(v, level + 1)};\n"
            for k, v in value.items()) + pad + "}"
    if isinstance(value, list):
        return "(\n" + "".join(f"{pad}\t{serialize(v, level + 1)},\n" for v in value) + pad + ")"
    return json.dumps(str(value), ensure_ascii=True)


def configurations(name, base):
    refs = []
    for configuration in ["Debug", "Release"]:
        settings = dict(base)
        settings.update(SWIFT_OPTIMIZATION_LEVEL="-Onone" if configuration == "Debug" else "-O",
                        DEBUG_INFORMATION_FORMAT="dwarf" if configuration == "Debug" else "dwarf-with-dsym")
        if configuration == "Debug":
            settings.update(ENABLE_TESTABILITY="YES", SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG",
                            GCC_PREPROCESSOR_DEFINITIONS=["$(inherited)", "DEBUG=1"])
        refs.append(add(f"{name}.{configuration}", "XCBuildConfiguration", name=configuration, buildSettings=settings))
    return add(f"{name}.configurations", "XCConfigurationList", buildConfigurations=refs,
               defaultConfigurationIsVisible="0", defaultConfigurationName="Release")


groups, phases = [], {}
for folder in ["Sources", "Tests"]:
    files, builds = [], []
    for path in sorted((ROOT / folder).glob("*.swift")):
        ref = add(str(path.relative_to(ROOT)), "PBXFileReference", lastKnownFileType="sourcecode.swift",
                  path=path.name, sourceTree="<group>")
        files.append(ref)
        builds.append(add(f"build.{folder}.{path.name}", "PBXBuildFile", fileRef=ref))
    groups.append(add(folder, "PBXGroup", children=files, path=folder, sourceTree="<group>"))
    phases[folder] = add(f"{folder}.phase", "PBXSourcesBuildPhase", buildActionMask="2147483647",
                         files=builds, runOnlyForDeploymentPostprocessing="0")

info = add("Info.plist", "PBXFileReference", lastKnownFileType="text.plist.xml", path="Info.plist", sourceTree="<group>")
app_product = add("app.product", "PBXFileReference", explicitFileType="wrapper.application",
                  includeInIndex="0", path="MonsterHunt.app", sourceTree="BUILT_PRODUCTS_DIR")
test_product = add("tests.product", "PBXFileReference", explicitFileType="wrapper.cfbundle",
                   includeInIndex="0", path="MonsterHuntTests.xctest", sourceTree="BUILT_PRODUCTS_DIR")
products = add("Products", "PBXGroup", children=[app_product, test_product], name="Products", sourceTree="<group>")
main_group = add("main", "PBXGroup", children=groups + [info, products], sourceTree="<group>")

common = dict(SDKROOT="iphoneos", IPHONEOS_DEPLOYMENT_TARGET="17.0", SWIFT_VERSION="5.0",
              TARGETED_DEVICE_FAMILY="1", CLANG_ENABLE_MODULES="YES", CLANG_ENABLE_OBJC_ARC="YES",
              SUPPORTED_PLATFORMS="iphoneos iphonesimulator", CODE_SIGN_STYLE="Automatic",
              MARKETING_VERSION="0.1.0", CURRENT_PROJECT_VERSION="1")
project_configs = configurations("project", common)
app_configs = configurations("app", dict(PRODUCT_NAME="$(TARGET_NAME)",
    PRODUCT_BUNDLE_IDENTIFIER="com.monsterhunt.prototype", INFOPLIST_FILE="Info.plist",
    GENERATE_INFOPLIST_FILE="NO", LD_RUNPATH_SEARCH_PATHS=["$(inherited)", "@executable_path/Frameworks"]))
test_configs = configurations("tests", dict(PRODUCT_NAME="$(TARGET_NAME)",
    PRODUCT_BUNDLE_IDENTIFIER="com.monsterhunt.prototype.tests", GENERATE_INFOPLIST_FILE="YES",
    TEST_HOST="$(BUILT_PRODUCTS_DIR)/MonsterHunt.app/MonsterHunt", BUNDLE_LOADER="$(TEST_HOST)",
    LD_RUNPATH_SEARCH_PATHS=["$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks"]))


def empty_phase(name, isa):
    return add(name, isa, buildActionMask="2147483647", files=[], runOnlyForDeploymentPostprocessing="0")


app = add("app", "PBXNativeTarget", name="MonsterHunt", productName="MonsterHunt",
          productReference=app_product, productType="com.apple.product-type.application",
          buildConfigurationList=app_configs, buildPhases=[phases["Sources"],
          empty_phase("app.frameworks", "PBXFrameworksBuildPhase"),
          empty_phase("app.resources", "PBXResourcesBuildPhase")], buildRules=[], dependencies=[])
proxy = add("proxy", "PBXContainerItemProxy", containerPortal=uid("project"), proxyType="1",
            remoteGlobalIDString=app, remoteInfo="MonsterHunt")
dependency = add("testDependency", "PBXTargetDependency", target=app, targetProxy=proxy)
tests = add("tests", "PBXNativeTarget", name="MonsterHuntTests", productName="MonsterHuntTests",
            productReference=test_product, productType="com.apple.product-type.bundle.unit-test",
            buildConfigurationList=test_configs, buildPhases=[phases["Tests"],
            empty_phase("tests.frameworks", "PBXFrameworksBuildPhase"),
            empty_phase("tests.resources", "PBXResourcesBuildPhase")], buildRules=[], dependencies=[dependency])
project = add("project", "PBXProject", attributes={"LastUpgradeCheck": "1600",
              "TargetAttributes": {app: {"CreatedOnToolsVersion": "16.0"},
                                   tests: {"CreatedOnToolsVersion": "16.0", "TestTargetID": app}}},
              buildConfigurationList=project_configs, compatibilityVersion="Xcode 14.0",
              developmentRegion="ru", hasScannedForEncodings="0", knownRegions=["ru", "en", "Base"],
              mainGroup=main_group, productRefGroup=products, projectDirPath="", projectRoot="", targets=[app, tests])

destination = ROOT / "MonsterHunt.xcodeproj"
destination.mkdir(exist_ok=True)
document = dict(archiveVersion="1", classes={}, objectVersion="56", objects=objects, rootObject=project)
(destination / "project.pbxproj").write_text("// !$*UTF8*$!\n" + serialize(document) + "\n", encoding="utf-8")

scheme = ET.Element("Scheme", LastUpgradeVersion="1600", version="1.3")


def reference(parent, target, name, product):
    ET.SubElement(parent, "BuildableReference", BuildableIdentifier="primary", BlueprintIdentifier=target,
                  BuildableName=product, BlueprintName=name, ReferencedContainer="container:MonsterHunt.xcodeproj")


build_action = ET.SubElement(scheme, "BuildAction", parallelizeBuildables="YES", buildImplicitDependencies="YES")
entries = ET.SubElement(build_action, "BuildActionEntries")
for target, name, product in [(app, "MonsterHunt", "MonsterHunt.app"), (tests, "MonsterHuntTests", "MonsterHuntTests.xctest")]:
    entry = ET.SubElement(entries, "BuildActionEntry", buildForTesting="YES", buildForRunning="YES" if target == app else "NO",
                          buildForProfiling="YES" if target == app else "NO", buildForArchiving="YES" if target == app else "NO",
                          buildForAnalyzing="YES")
    reference(entry, target, name, product)
test_action = ET.SubElement(scheme, "TestAction", buildConfiguration="Debug",
    selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB",
    selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", shouldUseLaunchSchemeArgsEnv="YES")
testables = ET.SubElement(test_action, "Testables")
testable = ET.SubElement(testables, "TestableReference", skipped="NO")
reference(testable, tests, "MonsterHuntTests", "MonsterHuntTests.xctest")
launch = ET.SubElement(scheme, "LaunchAction", buildConfiguration="Debug",
    selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB",
    selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", launchStyle="0", useCustomWorkingDirectory="NO",
    ignoresPersistentStateOnLaunch="NO", debugDocumentVersioning="YES", allowLocationSimulation="YES")
reference(ET.SubElement(launch, "BuildableProductRunnable", runnableDebuggingMode="0"), app, "MonsterHunt", "MonsterHunt.app")
profile = ET.SubElement(scheme, "ProfileAction", buildConfiguration="Release", shouldUseLaunchSchemeArgsEnv="YES")
reference(ET.SubElement(profile, "BuildableProductRunnable", runnableDebuggingMode="0"), app, "MonsterHunt", "MonsterHunt.app")
ET.SubElement(scheme, "AnalyzeAction", buildConfiguration="Debug")
ET.SubElement(scheme, "ArchiveAction", buildConfiguration="Release", revealArchiveInOrganizer="YES")
schemes = destination / "xcshareddata" / "xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
ET.indent(scheme)
ET.ElementTree(scheme).write(schemes / "MonsterHunt.xcscheme", encoding="utf-8", xml_declaration=True)
print(f"Generated Xcode project: {len(objects)} objects; app + tests + shared scheme")
