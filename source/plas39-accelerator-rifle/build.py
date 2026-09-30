"""Build the local PLAS-39 Accelerator Rifle quick-shot update."""
from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import sys
import zipfile

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parents[1]
DATA = PROJECT / "work/flag-mod/filediver-master/datalibrary"
BASE_PACKAGE = PROJECT / "work/rapid-arc-thrower/release-repo/mods/Preset-01-03-plas39_accelerator_rifle-v1.0.0.zip"
OUTPUT = PROJECT / "outputs"
PACKAGE = OUTPUT / "PLAS-39-Accelerator-Rifle-v1.1.5.zip"
README_OUT = OUTPUT / "PLAS-39-Accelerator-Rifle-v1.1.5-README.md"
REPORT_OUT = OUTPUT / "PLAS-39-Accelerator-Rifle-v1.1.5-Validation.json"
VERSION = "1.1.5"
ARCHIVE_NAME = "9ba626afa44a3aa3.patch_0"
GUID = "d4154ed1-20aa-5ee1-80a4-3331d7d5d4b3"
PROFILE_RESOURCE = "mods/codex/preset01_plas39_accelerator_rifle"
ENTRY_RESOURCE = "mods/codex/plas39_accelerator_firemode"
IMPL_RESOURCE = ENTRY_RESOURCE + "_impl"
OWNER = "30061F91AF477F5E"
EXE_SHA = "F5FEE03DCFDB2E553A4752C283590950AC13316B376D8196AA556FF0400D5F06"
GAME_DLL_SHA = "2E2C3B7C2500646DADD5F2B4C6E0504DBB7E7896139F64CDDC0D1813C718F51E"
ENTITY_SHA = "21377252B81FDBC670EBA1E59A8AB64B170323DF208F175E708992E4C1FB515E"
RESOURCE_HEADER = struct.Struct("<II")
GAME = Path(r"D:\SteamLibrary\steamapps\common\Helldivers 2")

sys.path.insert(0, str(PROJECT / "work/expanded-stat-editor"))
import audit_data
from lua_runtime import Lua51


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def load_archive_builder():
    path = PROJECT / "work/flag-mod/BingusSharedLoader-main/scripts/archive.py"
    spec = importlib.util.spec_from_file_location("plas39_archive", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("Bingus Shared Loader archive helpers are unavailable")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def resource_envelopes(patch: bytes) -> dict[int, bytes]:
    if len(patch) < 104 or struct.unpack_from("<I", patch, 0)[0] != 0xF0000011:
        raise RuntimeError("The existing PLAS-39 package has an invalid addon archive")
    type_count, count = struct.unpack_from("<II", patch, 4)
    if type_count != 1 or count < 1:
        raise RuntimeError("Unexpected Lua resource archive inventory")
    table_start = 72 + 32 * type_count
    resources: dict[int, bytes] = {}
    spans = []
    for index in range(count):
        row = patch[table_start + index * 80:table_start + (index + 1) * 80]
        if len(row) != 80:
            raise RuntimeError("Truncated resource table")
        key, kind, offset = struct.unpack_from("<QQQ", row, 0)
        length = struct.unpack_from("<I", row, 56)[0]
        if kind != 0xA14E8DFA2CD117E2 or offset + length > len(patch) or length < 8:
            raise RuntimeError("Invalid Lua resource type or range")
        envelope = patch[offset:offset + length]
        body_length, envelope_version = RESOURCE_HEADER.unpack_from(envelope, 0)
        if envelope_version != 2 or body_length + 8 != length:
            raise RuntimeError("Invalid Lua resource envelope")
        if key in resources:
            raise RuntimeError(f"Duplicate resource hash {key:016X}")
        resources[key] = envelope
        spans.append((offset, offset + length))
    spans.sort()
    if any(a[1] > b[0] for a, b in zip(spans, spans[1:])):
        raise RuntimeError("Resource payloads overlap")
    return resources


def envelope(body: bytes) -> bytes:
    return RESOURCE_HEADER.pack(len(body), 2) + body


def owner_map_index(blob: bytes, meta: dict, owner: str, record_index: int) -> int:
    target = int(owner, 16)
    for index in range(meta["map_count"]):
        identity, mapped_index = struct.unpack_from("<QI", blob, meta["payload_file_offset"] + index * 16)
        if identity == target:
            if mapped_index != record_index:
                raise RuntimeError(f"{owner}: component map changed its record index")
            return index
    raise RuntimeError(f"{owner}: component resource map entry not found")


def resolve_mode_source() -> tuple[str, dict]:
    entity_blob = (DATA / "generated_entities.dl_bin").read_bytes()
    if sha(entity_blob) != ENTITY_SHA:
        raise RuntimeError("Supported game entity data changed")
    _, typelib_version, type_map = audit_data.parse_typelib(DATA / "dl_library.dl_typelib")
    if typelib_version != 4:
        raise RuntimeError(f"Unsupported entity type library version: {typelib_version}")

    weapon_rows, weapon_owners, weapon_meta = audit_data.component_records(
        entity_blob, "WeaponDataComponent", type_map)
    charge_rows, charge_owners, charge_meta = audit_data.component_records(
        entity_blob, "WeaponChargeComponent", type_map)
    weapon = weapon_rows[OWNER]
    charge = charge_rows[OWNER]
    if weapon_meta["map_count"] != 730 or weapon_meta["record_count"] != 366 or weapon_meta["stride"] != 1232:
        raise RuntimeError("PLAS-39 WeaponData component layout changed")
    if charge_meta["map_count"] != 20 or charge_meta["record_count"] != 11 or charge_meta["stride"] != 216:
        raise RuntimeError("PLAS-39 WeaponCharge component layout changed")
    if weapon_owners[OWNER]["record_index"] != 185 or charge_owners[OWNER]["record_index"] != 2:
        raise RuntimeError("PLAS-39 component indices changed")
    weapon_map_index = owner_map_index(entity_blob, weapon_meta, OWNER, weapon_owners[OWNER]["record_index"])
    charge_map_index = owner_map_index(entity_blob, charge_meta, OWNER, charge_owners[OWNER]["record_index"])
    if entity_blob.count(weapon) != 1 or entity_blob.count(charge) != 1:
        raise RuntimeError("PLAS-39 source component rows are not unique")
    if struct.unpack_from("<I", weapon, 140)[0] != 3:
        raise RuntimeError("PLAS-39 source burst count changed")
    if [struct.unpack_from("<I", weapon, offset)[0] for offset in (144, 148, 152, 156)] != [2, 0, 0, 0]:
        raise RuntimeError("PLAS-39 source fire-mode values changed")
    if [struct.unpack_from("<I", weapon, offset)[0] for offset in (184, 188)] != [0, 3]:
        raise RuntimeError("PLAS-39 source function values changed")
    charge_times = [struct.unpack_from("<f", charge, offset)[0] for offset in (0, 24, 48)]
    if any(abs(actual - expected) > 0.000001 for actual, expected in zip(charge_times, (0.45, 0.5, 0.9))):
        raise RuntimeError(f"Unexpected PLAS-39 charge timings: {charge_times}")

    weapon_group_start = weapon_owners[OWNER]["record_file_offset"] - (
        28 + weapon_meta["map_count"] * 16 + weapon_owners[OWNER]["record_index"] * weapon_meta["stride"])
    charge_group_start = charge_owners[OWNER]["record_file_offset"] - (
        28 + charge_meta["map_count"] * 16 + charge_owners[OWNER]["record_index"] * charge_meta["stride"])
    weapon_header = entity_blob[weapon_group_start:weapon_group_start + 28]
    charge_header = entity_blob[charge_group_start:charge_group_start + 28]
    if len(weapon_header) != 28 or len(charge_header) != 28:
        raise RuntimeError("Could not derive component group headers")

    source = (ROOT / "mode.lua").read_text(encoding="utf-8")
    replacements = {
        "__WEAPON_HEADER__": weapon_header.hex(),
        "__CHARGE_HEADER__": charge_header.hex(),
        "__WEAPON_TOTAL__": str(28 + weapon_meta["group_size"]),
        "__CHARGE_TOTAL__": str(28 + charge_meta["group_size"]),
        "__WEAPON_MAP_COUNT__": str(weapon_meta["map_count"]),
        "__CHARGE_MAP_COUNT__": str(charge_meta["map_count"]),
        "__WEAPON_MAP_INDEX__": str(weapon_map_index),
        "__CHARGE_MAP_INDEX__": str(charge_map_index),
        "__WEAPON_RECORD_INDEX__": str(weapon_owners[OWNER]["record_index"]),
        "__CHARGE_RECORD_INDEX__": str(charge_owners[OWNER]["record_index"]),
        "__WEAPON_STRIDE__": str(weapon_meta["stride"]),
        "__CHARGE_STRIDE__": str(charge_meta["stride"]),
        "__OWNER_LITTLE_ENDIAN__": bytes.fromhex(OWNER)[::-1].hex(),
        "__CHARGE_STOCK_ROW__": charge.hex(),
        "__CHARGE_MIN_STOCK__": charge[:4].hex(),
        "__CHARGE_MIN_QUICK__": struct.pack("<f", 0.01).hex(),
    }
    for marker, value in replacements.items():
        if source.count(marker) != 1:
            raise RuntimeError(f"Expected one source placeholder {marker}")
        source = source.replace(marker, value)
    if "__" in source:
        raise RuntimeError("Unresolved build placeholders remain")

    report = {
        "entity_data_sha256": sha(entity_blob),
        "type_library_version": typelib_version,
        "owner_hash": OWNER,
        "weapon_data": {
            "map_count": weapon_meta["map_count"],
            "record_count": weapon_meta["record_count"],
            "record_index": weapon_owners[OWNER]["record_index"],
            "map_index": weapon_map_index,
            "stride": weapon_meta["stride"],
            "row_sha256": sha(weapon),
            "burst_rounds_stock": struct.unpack_from("<I", weapon, 140)[0],
            "native_burst_limit_runtime": 1,
            "fire_mode_slots_source": [struct.unpack_from("<I", weapon, offset)[0] for offset in (144, 148, 152, 156)],
            "fire_mode_slots_runtime": [3, 2, 0, 0],
            "function_info_source": list(struct.unpack_from("<II", weapon, 184)),
            "function_info_runtime": [3, 0],
        },
        "weapon_charge": {
            "map_count": charge_meta["map_count"],
            "record_count": charge_meta["record_count"],
            "record_index": charge_owners[OWNER]["record_index"],
            "map_index": charge_map_index,
            "stride": charge_meta["stride"],
            "row_sha256": sha(charge),
            "charge_times_seconds": charge_times,
            "quick_minimum_seconds": 0.01,
            "extra_charge_releases_stock": struct.unpack_from("<I", charge, 188)[0],
            "extra_charge_releases_semi": 0,
            "extra_charge_releases_burst": 2,
            "repeat_interval_seconds": struct.unpack_from("<f", charge, 192)[0],
        },
        "exact_offsets_changed_at_runtime": {
            "WeaponDataComponent": [140, 144, 148, 184, 188],
            "WeaponChargeComponent": [0, 188],
            "NativeChargeState_on_entering_semi": [20, 24],
            "ProjectileWeaponComponent": [8, 236],
        },
    }
    if struct.unpack_from("<I", charge, 188)[0] != 2 or abs(struct.unpack_from("<f", charge, 192)[0] - 0.12) > 1e-6:
        raise RuntimeError("PLAS-39 native charge repetition fields changed")
    return source, report


def resolve_native_source():
    saved = PROJECT / "work/dual-mode-hover-pack/native-research/20260929T101529Z/text.bin"
    code = saved.read_bytes()
    if sha(code) != "AF65FC548952D338173CCDF2BF3FAD16229A9AB9CA52394885C143C1089D484B":
        raise RuntimeError("Saved exact-build native code snapshot changed")
    ranges = [(0x509570,48), (0x504D80,48), (0x7567C8,14), (0x73D97A,72), (0x756AA0,18), (0x514C10,48), (0x515100,48), (0x614D26,23), (0x614C4D,14), (0x73C948,12), (0x73EDB8,66), (0x73F6CA,50), (0x6194F6,58), (0x61A099,62), (0x5052C0,189), (0x172F790,110), (0x172F8A0,259)]
    ranges += [(0x611BB3,37), (0x611C4C,34), (0x612CF8,20), (0x73CE52,49)]
    guards = [{"rva": rva, "bytes": code[rva-0x1000:rva-0x1000+n].hex()} for rva,n in ranges]
    literal = "{" + ",".join("{rva=" + str(g["rva"]) + ",bytes='" + g["bytes"] + "'}" for g in guards) + "}"
    source = (ROOT / "native.lua").read_text(encoding="utf-8")
    source = source.replace("__OWNER_LITTLE_ENDIAN__", bytes.fromhex(OWNER)[::-1].hex())
    source = source.replace("__NATIVE_GUARDS__",literal)
    if "__" in source:
        raise RuntimeError("Unresolved native source placeholders")
    return source, guards


def build() -> dict:
    archive_builder = load_archive_builder()
    if archive_builder.ARCHIVE != ARCHIVE_NAME or archive_builder.TYPE != 0xA14E8DFA2CD117E2:
        raise RuntimeError("Shared-loader archive settings changed")
    if sha((GAME / "bin/helldivers2.exe").read_bytes()) != EXE_SHA:
        raise RuntimeError("Unsupported game executable")
    if sha((GAME / "data/game/game.dll").read_bytes()) != GAME_DLL_SHA:
        raise RuntimeError("Unsupported game module")

    if not BASE_PACKAGE.is_file():
        raise FileNotFoundError(f"Current PLAS-39 package is missing: {BASE_PACKAGE}")
    with zipfile.ZipFile(BASE_PACKAGE) as base:
        base_manifest = json.loads(base.read("manifest.json"))
        if base_manifest.get("Guid") != GUID:
            raise RuntimeError("Current PLAS-39 package identity changed")
        if base_manifest.get("Name") != "Preset 1 - PLAS-39 Accelerator Rifle":
            raise RuntimeError(f"Unexpected existing PLAS-39 package name: {base_manifest.get('Name')!r}")
        resources = resource_envelopes(base.read("Addon/" + ARCHIVE_NAME))
    base_zip_hash = sha(BASE_PACKAGE.read_bytes())

    # Keep the existing Arsenal profile identity and stable manager option while
    # replacing its visible in-game name. This preserves the user's saved toggle.
    profile_key = archive_builder.resource_hash(PROFILE_RESOURCE)
    if profile_key not in resources:
        raise RuntimeError("Existing PLAS-39 profile resource was not found")
    profile_envelope = resources[profile_key]
    profile_length, _ = RESOURCE_HEADER.unpack_from(profile_envelope, 0)
    profile_source = profile_envelope[8:8 + profile_length]
    if not profile_source.startswith(("-- HD2-Addon: " + PROFILE_RESOURCE + "\n").encode()):
        raise RuntimeError("Existing PLAS-39 profile resource identity changed")
    old_label = b"name = 'Preset 1 - PLAS-39 Accelerator Rifle'"
    if profile_source.count(old_label) != 1:
        raise RuntimeError("Expected profile display name not found exactly once")
    profile_source = profile_source.replace(old_label, b"name = 'PLAS-39 Accelerator Rifle'")
    resources[profile_key] = envelope(profile_source)

    mode_source, data_report = resolve_mode_source()
    native_source, native_guards = resolve_native_source()
    windows_source = (ROOT / "windows.lua").read_text(encoding="utf-8")
    startup_source = (ROOT / "startup.lua").read_text(encoding="utf-8")
    entry_source = (
        f"-- HD2-Addon: {ENTRY_RESOURCE}\n"
        f"return require('{IMPL_RESOURCE}')\n"
    ).encode("utf-8")
    if len(entry_source.splitlines()[0]) >= 256:
        raise RuntimeError("The loader discovery comment is too long")
    implementation_source = (
        "local make_api = (function()\n" + windows_source + "\nend)()\n"
        "local patch = (function()\n" + mode_source + "\nend)()\n"
        "local native = (function()\n" + native_source + "\nend)()\n"
        "local start = (function()\n" + startup_source + "\nend)()\n"
        "start(make_api, patch, native)\n"
    ).encode("utf-8")
    compiled = Lua51().compile(implementation_source, "@plas39_accelerator_firemode.lua")
    if not compiled.startswith((b"\x1bLua", b"\x1bLJ")):
        raise RuntimeError("LuaJIT did not produce a compiled Lua chunk")

    for name, body in ((ENTRY_RESOURCE, entry_source), (IMPL_RESOURCE, compiled)):
        key = archive_builder.resource_hash(name)
        if key in resources:
            raise RuntimeError(f"Addon resource already exists: {name}")
        resources[key] = envelope(body)
    patch = archive_builder.make_archive(resources)

    manifest = {
        "Version": 1,
        "Guid": GUID,
        "Name": "PLAS-39 Accelerator Rifle v" + VERSION,
        "Description": "Keeps the PLAS-39 Accelerator Rifle tuning and adds a quick single-shot mode selectable from Weapon Wheel Left while retaining its charged three-round burst. Requires Bingus Shared Loader v15 or newer and Steam build 25480438.",
        "Options": [{
            "Name": "Enable PLAS-39 Accelerator Rifle preset",
            "Description": "Applies the PLAS-39 tuning and left-side quick-shot fire mode.",
            "Include": ["Addon"],
        }],
    }
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    files = {
        "manifest.json": (json.dumps(manifest, indent=2, ensure_ascii=False) + "\n").encode("utf-8"),
        "Addon/" + ARCHIVE_NAME: patch,
        "Addon/" + ARCHIVE_NAME + ".stream": b"",
        "Addon/" + ARCHIVE_NAME + ".gpu_resources": b"",
        "README.txt": readme.encode("utf-8"),
        "Source/mode.lua": mode_source.encode("utf-8"),
        "Source/windows.lua": windows_source.encode("utf-8"),
        "Source/native.lua": native_source.encode("utf-8"),
        "Source/startup.lua": startup_source.encode("utf-8"),
        "Source/entry.lua": entry_source,
        "Source/implementation.lua": implementation_source,
        "Source/profile.lua": profile_source,
    }
    OUTPUT.mkdir(exist_ok=True)
    with zipfile.ZipFile(PACKAGE, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for name, data in sorted(files.items()):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            z.writestr(info, data)

    with zipfile.ZipFile(PACKAGE) as built:
        if built.testzip() is not None:
            raise RuntimeError("Built package ZIP failed its integrity check")
        if set(built.namelist()) != set(files):
            raise RuntimeError("Built package contains missing or unexpected files")
        if json.loads(built.read("manifest.json")) != manifest:
            raise RuntimeError("Built manifest differs from its source")
        packaged_resources = resource_envelopes(built.read("Addon/" + ARCHIVE_NAME))
        if packaged_resources != resources:
            raise RuntimeError("Built add-on archive differs from the validated resource map")
        entry_env = packaged_resources[archive_builder.resource_hash(ENTRY_RESOURCE)]
        entry_body = entry_env[8:8 + RESOURCE_HEADER.unpack_from(entry_env)[0]]
        if not entry_body.startswith(("-- HD2-Addon: " + ENTRY_RESOURCE + "\n").encode()):
            raise RuntimeError("The add-on discovery entry is not plaintext or correctly named")
        impl_env = packaged_resources[archive_builder.resource_hash(IMPL_RESOURCE)]
        impl_body = impl_env[8:8 + RESOURCE_HEADER.unpack_from(impl_env)[0]]
        if not impl_body.startswith((b"\x1bLua", b"\x1bLJ")):
            raise RuntimeError("The implementation resource is not compiled Lua bytecode")

    README_OUT.write_text(readme, encoding="utf-8", newline="\n")
    report = {
        "result": "built_and_package_inspected",
        "version": VERSION,
        "package": str(PACKAGE),
        "package_sha256": sha(PACKAGE.read_bytes()),
        "base_package": str(BASE_PACKAGE),
        "base_package_sha256": base_zip_hash,
        "manifest_guid_reused": GUID,
        "arsenal_option_name_preserved": manifest["Options"][0]["Name"],
        "old_profile_settings_preserved": True,
        "retained_source_resources": len(resources) - 2,
        "firemode_resource_names": [ENTRY_RESOURCE, IMPL_RESOURCE],
        "compiled_lua_bytes": len(compiled),
        "selection_source": "native WeaponDataComponent +0x60 array, 12-byte rows, FireMode at +0",
        "native_code_guards": native_guards,
        "private_memory_scan_bytes": 0,
        "semi_rpm": 200,
        "burst_rpm_setting": 550,
        "burst_physical_interval_seconds": 0.12,
        "burst_audio_candidate": "ordinary event posting; MIDI disabled only for Burst; gameplay pending",
        "zip_integrity": "passed",
        "archive_resource_roundtrip": "passed",
        "lua_chunk_compilation": "passed",
        "gameplay_tested": False,
        "game_process_modified": False,
        "arsenal_settings_modified": False,
        "github_or_discord_changed": False,
        **data_report,
    }
    REPORT_OUT.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return report


if __name__ == "__main__":
    print(json.dumps(build(), indent=2, ensure_ascii=False))
