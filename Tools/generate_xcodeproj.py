#!/usr/bin/env python3
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT_DIR = ROOT / "CareVoiceAI.xcodeproj"
PBXPROJ = PROJECT_DIR / "project.pbxproj"
APP_DIR = ROOT / "CareVoiceAI"


def oid(seed: str) -> str:
    return hashlib.sha1(seed.encode("utf-8")).hexdigest().upper()[:24]


def quote(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


swift_files = sorted(str(path.relative_to(ROOT)) for path in APP_DIR.rglob("*.swift"))
resource_files = [
    "CareVoiceAI/Resources/Assets.xcassets",
    "CareVoiceAI/Resources/vi.lproj/Localizable.strings",
]

product_ref = oid("product")
main_group = oid("main_group")
app_group = oid("app_group")
products_group = oid("products_group")
project_id = oid("project")
target_id = oid("target")
sources_phase = oid("sources_phase")
resources_phase = oid("resources_phase")
frameworks_phase = oid("frameworks_phase")
project_config_list = oid("project_config_list")
target_config_list = oid("target_config_list")
project_debug = oid("project_debug")
project_release = oid("project_release")
target_debug = oid("target_debug")
target_release = oid("target_release")

file_refs = {}
build_files = {}
for path in swift_files + resource_files:
    file_refs[path] = oid(f"file:{path}")
    build_files[path] = oid(f"build:{path}")


def file_type(path: str) -> str:
    if path.endswith(".swift"):
        return "sourcecode.swift"
    if path.endswith(".xcassets"):
        return "folder.assetcatalog"
    if path.endswith(".strings"):
        return "text.plist.strings"
    return "file"


lines = []
lines.append("// !$*UTF8*$!")
lines.append("{")
lines.append("\tarchiveVersion = 1;")
lines.append("\tclasses = {};")
lines.append("\tobjectVersion = 56;")
lines.append("\tobjects = {")

lines.append("\n/* Begin PBXBuildFile section */")
for path, build_id in build_files.items():
    lines.append(f"\t\t{build_id} /* {Path(path).name} in {'Sources' if path.endswith('.swift') else 'Resources'} */ = {{isa = PBXBuildFile; fileRef = {file_refs[path]} /* {Path(path).name} */; }};")
lines.append("/* End PBXBuildFile section */")

lines.append("\n/* Begin PBXFileReference section */")
lines.append(f"\t\t{product_ref} /* CareVoiceAI.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = CareVoiceAI.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
for path, ref_id in file_refs.items():
    name = Path(path).name
    lines.append(f"\t\t{ref_id} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {file_type(path)}; path = {quote(path)}; sourceTree = SOURCE_ROOT; }};")
lines.append("/* End PBXFileReference section */")

lines.append("\n/* Begin PBXFrameworksBuildPhase section */")
lines.append(f"\t\t{frameworks_phase} /* Frameworks */ = {{")
lines.append("\t\t\tisa = PBXFrameworksBuildPhase;")
lines.append("\t\t\tbuildActionMask = 2147483647;")
lines.append("\t\t\tfiles = ();")
lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
lines.append("\t\t};")
lines.append("/* End PBXFrameworksBuildPhase section */")

lines.append("\n/* Begin PBXGroup section */")
lines.append(f"\t\t{main_group} = {{")
lines.append("\t\t\tisa = PBXGroup;")
lines.append("\t\t\tchildren = (")
lines.append(f"\t\t\t\t{app_group} /* CareVoiceAI */,")
lines.append(f"\t\t\t\t{products_group} /* Products */,")
lines.append("\t\t\t);")
lines.append("\t\t\tsourceTree = \"<group>\";")
lines.append("\t\t};")
lines.append(f"\t\t{app_group} /* CareVoiceAI */ = {{")
lines.append("\t\t\tisa = PBXGroup;")
lines.append("\t\t\tchildren = (")
for path in swift_files + resource_files:
    lines.append(f"\t\t\t\t{file_refs[path]} /* {Path(path).name} */,")
lines.append("\t\t\t);")
lines.append("\t\t\tpath = CareVoiceAI;")
lines.append("\t\t\tsourceTree = \"<group>\";")
lines.append("\t\t};")
lines.append(f"\t\t{products_group} /* Products */ = {{")
lines.append("\t\t\tisa = PBXGroup;")
lines.append("\t\t\tchildren = (")
lines.append(f"\t\t\t\t{product_ref} /* CareVoiceAI.app */,")
lines.append("\t\t\t);")
lines.append("\t\t\tname = Products;")
lines.append("\t\t\tsourceTree = \"<group>\";")
lines.append("\t\t};")
lines.append("/* End PBXGroup section */")

lines.append("\n/* Begin PBXNativeTarget section */")
lines.append(f"\t\t{target_id} /* CareVoiceAI */ = {{")
lines.append("\t\t\tisa = PBXNativeTarget;")
lines.append(f"\t\t\tbuildConfigurationList = {target_config_list} /* Build configuration list for PBXNativeTarget \"CareVoiceAI\" */;")
lines.append("\t\t\tbuildPhases = (")
lines.append(f"\t\t\t\t{sources_phase} /* Sources */,")
lines.append(f"\t\t\t\t{frameworks_phase} /* Frameworks */,")
lines.append(f"\t\t\t\t{resources_phase} /* Resources */,")
lines.append("\t\t\t);")
lines.append("\t\t\tbuildRules = ();")
lines.append("\t\t\tdependencies = ();")
lines.append("\t\t\tname = CareVoiceAI;")
lines.append(f"\t\t\tproductReference = {product_ref} /* CareVoiceAI.app */;")
lines.append("\t\t\tproductType = \"com.apple.product-type.application\";")
lines.append("\t\t};")
lines.append("/* End PBXNativeTarget section */")

lines.append("\n/* Begin PBXProject section */")
lines.append(f"\t\t{project_id} /* Project object */ = {{")
lines.append("\t\t\tisa = PBXProject;")
lines.append("\t\t\tattributes = {")
lines.append("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
lines.append("\t\t\t\tLastSwiftUpdateCheck = 1600;")
lines.append("\t\t\t\tLastUpgradeCheck = 1600;")
lines.append("\t\t\t\tTargetAttributes = {")
lines.append(f"\t\t\t\t\t{target_id} = {{")
lines.append("\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
lines.append("\t\t\t\t\t};")
lines.append("\t\t\t\t};")
lines.append("\t\t\t};")
lines.append(f"\t\t\tbuildConfigurationList = {project_config_list} /* Build configuration list for PBXProject \"CareVoiceAI\" */;")
lines.append("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
lines.append("\t\t\tdevelopmentRegion = vi;")
lines.append("\t\t\thasScannedForEncodings = 0;")
lines.append("\t\t\tknownRegions = (vi, en, Base);")
lines.append(f"\t\t\tmainGroup = {main_group};")
lines.append("\t\t\tproductRefGroup = {products_group};".replace("{products_group}", products_group))
lines.append("\t\t\tprojectDirPath = \"\";")
lines.append("\t\t\tprojectRoot = \"\";")
lines.append("\t\t\ttargets = (")
lines.append(f"\t\t\t\t{target_id} /* CareVoiceAI */,")
lines.append("\t\t\t);")
lines.append("\t\t};")
lines.append("/* End PBXProject section */")

lines.append("\n/* Begin PBXResourcesBuildPhase section */")
lines.append(f"\t\t{resources_phase} /* Resources */ = {{")
lines.append("\t\t\tisa = PBXResourcesBuildPhase;")
lines.append("\t\t\tbuildActionMask = 2147483647;")
lines.append("\t\t\tfiles = (")
for path in resource_files:
    lines.append(f"\t\t\t\t{build_files[path]} /* {Path(path).name} in Resources */,")
lines.append("\t\t\t);")
lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
lines.append("\t\t};")
lines.append("/* End PBXResourcesBuildPhase section */")

lines.append("\n/* Begin PBXSourcesBuildPhase section */")
lines.append(f"\t\t{sources_phase} /* Sources */ = {{")
lines.append("\t\t\tisa = PBXSourcesBuildPhase;")
lines.append("\t\t\tbuildActionMask = 2147483647;")
lines.append("\t\t\tfiles = (")
for path in swift_files:
    lines.append(f"\t\t\t\t{build_files[path]} /* {Path(path).name} in Sources */,")
lines.append("\t\t\t);")
lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
lines.append("\t\t};")
lines.append("/* End PBXSourcesBuildPhase section */")


def config_block(config_id: str, name: str, target: bool) -> list[str]:
    settings = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION": "YES_AGGRESSIVE",
        "CLANG_CXX_LANGUAGE_STANDARD": '"gnu++20"',
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_ENABLE_OBJC_WEAK": "YES",
        "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING": "YES",
        "CLANG_WARN_BOOL_CONVERSION": "YES",
        "CLANG_WARN_COMMA": "YES",
        "CLANG_WARN_CONSTANT_CONVERSION": "YES",
        "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS": "YES",
        "CLANG_WARN_DIRECT_OBJC_ISA_USAGE": "YES_ERROR",
        "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
        "CLANG_WARN_EMPTY_BODY": "YES",
        "CLANG_WARN_ENUM_CONVERSION": "YES",
        "CLANG_WARN_INFINITE_RECURSION": "YES",
        "CLANG_WARN_INT_CONVERSION": "YES",
        "CLANG_WARN_NON_LITERAL_NULL_CONVERSION": "YES",
        "CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF": "YES",
        "CLANG_WARN_OBJC_LITERAL_CONVERSION": "YES",
        "CLANG_WARN_OBJC_ROOT_CLASS": "YES_ERROR",
        "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
        "CLANG_WARN_RANGE_LOOP_ANALYSIS": "YES",
        "CLANG_WARN_STRICT_PROTOTYPES": "YES",
        "CLANG_WARN_SUSPICIOUS_MOVE": "YES",
        "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE",
        "CLANG_WARN_UNREACHABLE_CODE": "YES",
        "CLANG_WARN__DUPLICATE_METHOD_MATCH": "YES",
        "COPY_PHASE_STRIP": "NO" if name == "Debug" else "YES",
        "DEBUG_INFORMATION_FORMAT": "dwarf" if name == "Debug" else '"dwarf-with-dsym"',
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "ENABLE_TESTABILITY": "YES" if name == "Debug" else "NO",
        "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "GCC_OPTIMIZATION_LEVEL": "0" if name == "Debug" else "s",
        "GCC_PREPROCESSOR_DEFINITIONS": '"DEBUG=1 $(inherited)"' if name == "Debug" else "",
        "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
        "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
        "GCC_WARN_UNDECLARED_SELECTOR": "YES",
        "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
        "GCC_WARN_UNUSED_FUNCTION": "YES",
        "GCC_WARN_UNUSED_VARIABLE": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": "15.0",
        "SDKROOT": "iphoneos",
        "SWIFT_COMPILATION_MODE": "singlefile" if name == "Debug" else "wholemodule",
        "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"' if name == "Debug" else '"-O"',
    }
    if target:
        settings.update({
            "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "CareVoicePrimary",
            "CODE_SIGN_ENTITLEMENTS": "CareVoiceAI/CareVoiceAI.entitlements",
            "CODE_SIGN_STYLE": "Automatic",
            "CURRENT_PROJECT_VERSION": "1",
            "DEVELOPMENT_ASSET_PATHS": "",
            "ENABLE_PREVIEWS": "YES",
            "GENERATE_INFOPLIST_FILE": "NO",
            "INFOPLIST_FILE": "CareVoiceAI/Resources/Info.plist",
            "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks"',
            "MARKETING_VERSION": "1.0.0",
            "PRODUCT_BUNDLE_IDENTIFIER": "com.carevoice.ai",
            "PRODUCT_NAME": '"$(TARGET_NAME)"',
            "SWIFT_EMIT_LOC_STRINGS": "YES",
            "SWIFT_VERSION": "5.0",
            "TARGETED_DEVICE_FAMILY": '"1,2"',
        })
    out = [f"\t\t{config_id} /* {name} */ = {{", "\t\t\tisa = XCBuildConfiguration;", "\t\t\tbuildSettings = {"]
    for key, value in settings.items():
        if value:
            out.append(f"\t\t\t\t{key} = {value};")
    out.extend(["\t\t\t};", f"\t\t\tname = {name};", "\t\t};"])
    return out


lines.append("\n/* Begin XCBuildConfiguration section */")
lines.extend(config_block(project_debug, "Debug", False))
lines.extend(config_block(project_release, "Release", False))
lines.extend(config_block(target_debug, "Debug", True))
lines.extend(config_block(target_release, "Release", True))
lines.append("/* End XCBuildConfiguration section */")

lines.append("\n/* Begin XCConfigurationList section */")
for list_id, debug_id, release_id, owner in [
    (project_config_list, project_debug, project_release, 'PBXProject "CareVoiceAI"'),
    (target_config_list, target_debug, target_release, 'PBXNativeTarget "CareVoiceAI"'),
]:
    lines.append(f"\t\t{list_id} /* Build configuration list for {owner} */ = {{")
    lines.append("\t\t\tisa = XCConfigurationList;")
    lines.append("\t\t\tbuildConfigurations = (")
    lines.append(f"\t\t\t\t{debug_id} /* Debug */,")
    lines.append(f"\t\t\t\t{release_id} /* Release */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\tdefaultConfigurationIsVisible = 0;")
    lines.append("\t\t\tdefaultConfigurationName = Release;")
    lines.append("\t\t};")
lines.append("/* End XCConfigurationList section */")

lines.append("\t};")
lines.append(f"\trootObject = {project_id} /* Project object */;")
lines.append("}")

PROJECT_DIR.mkdir(exist_ok=True)
PBXPROJ.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"Generated {PBXPROJ.relative_to(ROOT)} with {len(swift_files)} Swift files")
