"""Build an independent ARC-3 gameplay package for the supported Steam build."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import struct
import sys
import zipfile

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parents[1]
DATA = PROJECT / "work/flag-mod/filediver-master/datalibrary"
OUT = PROJECT / "outputs"
GAME = Path(r"D:\SteamLibrary\steamapps\common\Helldivers 2")
sys.path.insert(0, str(PROJECT / "work/expanded-stat-editor"))
import audit_data as audit

EXE_SHA = "F5FEE03DCFDB2E553A4752C283590950AC13316B376D8196AA556FF0400D5F06"
DLL_SHA = "2E2C3B7C2500646DADD5F2B4C6E0504DBB7E7896139F64CDDC0D1813C718F51E"
RESOURCE = "mods/codex/rapid_arc_thrower"
GUID = "2f61e45d-92fc-4517-b931-a6cd10515357"


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def resource_hash(name: str) -> int:
    b = name.encode()
    mask, m = (1 << 64) - 1, 0xC6A4A7935BD1E995
    h = (len(b) * m) & mask
    for off in range(0, len(b) // 8 * 8, 8):
        k = int.from_bytes(b[off:off + 8], "little")
        k = (k * m) & mask
        k ^= k >> 47
        k = (k * m) & mask
        h = ((h ^ k) * m) & mask
    tail = b[len(b) // 8 * 8:]
    if tail:
        h = ((h ^ int.from_bytes(tail, "little")) * m) & mask
    h ^= h >> 47
    h = (h * m) & mask
    return h ^ (h >> 47)


def archive(payload: bytes) -> bytes:
    lua_type = 0xA14E8DFA2CD117E2
    packed = struct.pack("<II", len(payload), 2) + payload
    start = 192
    end = (start + len(packed) + 15) & ~15
    header = struct.pack("<III20sQQ24s", 0xF0000011, 1, 1, b"", end, 0, b"")
    type_entry = struct.pack("<IIQIIII", 0, 0, lua_type, 1, 0, 16, 16)
    toc = struct.pack("<7Q6I", resource_hash(RESOURCE), lua_type, start, 0, 0, 0, 0,
                      len(packed), 0, 0, 16, 16, 0)
    return (header + type_entry + toc).ljust(start, b"\0") + packed + b"\0" * (end-start-len(packed))


def build() -> dict:
    assert sha((GAME / "bin/helldivers2.exe").read_bytes()) == EXE_SHA, "Unsupported EXE"
    assert sha((GAME / "data/game/game.dll").read_bytes()) == DLL_SHA, "Unsupported game.dll"
    entity_blob = (DATA / "generated_entities.dl_bin").read_bytes()
    damage_blob = (DATA / "generated_damage_settings.dl_bin").read_bytes()
    arc_blob = (DATA / "generated_arc_settings.dl_bin").read_bytes()
    assert sha(entity_blob) == "21377252B81FDBC670EBA1E59A8AB64B170323DF208F175E708992E4C1FB515E"
    assert sha(damage_blob) == "55E2BC4AC209D45363670A5952C3FE5DE045854AA062634A5A2444CB11510C35"
    _, version, types = audit.parse_typelib(DATA / "dl_library.dl_typelib")
    assert version == 4
    charge, owners, charge_meta = audit.component_records(entity_blob, "WeaponChargeComponent", types)
    owner = "96DE9CD50F7306E6"
    assert owners[owner]["record_index"] == 6 and charge_meta["stride"] == 216
    charge_row = charge[owner]
    assert entity_blob.count(charge_row) == 1 and entity_blob.count(charge_row[:64]) == 1
    assert [struct.unpack_from("<f",charge_row,o)[0] for o in (0,24,48)] == [1.0, struct.unpack("<f",bytes.fromhex("cdcc8c3f"))[0], struct.unpack("<f",bytes.fromhex("9a99993f"))[0]]
    assert [struct.unpack_from("<f",charge_row,o)[0] for o in (80,84)] == [1.0,1.0]
    charge_offset = owners[owner]["record_file_offset"]
    group_start = charge_meta["payload_file_offset"] - 28
    assert charge_offset-group_start == 1644
    charge_header = entity_blob[group_start:group_start+28]
    assert len(charge_header) == 28 and charge_meta["group_size"] == 2696
    weapon, weapon_owners, weapon_meta = audit.component_records(entity_blob, "WeaponDataComponent", types)
    assert weapon_owners[owner]["record_index"] == 327 and weapon_meta["stride"] == 1232
    assert weapon_owners[owner]["record_file_offset"] == 26566228
    weapon_row = weapon[owner]
    assert sha(weapon_row) == "6AC7F208AC866344E733AD3B59CFC04B6576191B5F4BC29E2DAC0B5CFCAD03C9"
    assert [struct.unpack_from("<f", weapon_row, o)[0] for o in (76,80)] == [1.0,1.0]
    assert entity_blob.count(weapon_row) == 1
    health, _, _ = audit.component_records(entity_blob, "HealthComponent", types)
    behemoth_head = health["A05BD1EC67B3AC4C"][520:1072]
    bull_head = health["3AFF5FD7D5450B99"][520:1072]
    for head in (behemoth_head,bull_head):
        assert struct.unpack_from("<f",head,204)[0] == 1.0
        assert struct.unpack_from("<I",head,216)[0] == 4
        assert struct.unpack_from("<i",head,232)[0] == 1600
        assert head[244] == 1  # head death causes entity death
    arc_rows, arc_offsets, arc_meta = audit.row_table_records(DATA / "generated_arc_settings.dl_bin", audit.T_ARC, 104, [])
    arc_row = arc_rows["7"]
    assert arc_meta["row_count"] == 16 and arc_offsets["7"]["row_file_offset"] == 44 and len(arc_blob) == 1708
    assert audit.u32(arc_row,36) == 197 and audit.f32(arc_row,8) == 55.0
    assert [audit.u32(arc_row,o) for o in (0,28,32)] == [7,1,1]
    assert arc_blob.count(arc_row) == 1
    arc_weapons, _, _ = audit.component_records(entity_blob,"ArcWeaponComponent",types)
    assert [h for h,r in arc_weapons.items() if audit.u32(r,0)==7] == [owner]
    damage_rows, damage_offsets, damage_meta = audit.row_table_records(DATA / "generated_damage_settings.dl_bin", audit.T_DAMAGE, 76, [])
    damage_row = damage_rows["197"]
    assert damage_offsets["197"]["row_file_offset"] == 15072
    assert damage_meta["row_count"] == 649 and len(damage_blob) == 49424
    assert damage_blob.count(damage_row) == 1
    assert [audit.u32(damage_row,o) for o in (0,4,8,28,32,36,44)] == [197,250,100,20,35,10,37]
    assert audit.f32(damage_row,48) == 8.0
    assert damage_row[52:76] == b"\0"*24
    source = (ROOT / "arc_patch.lua").read_text(encoding="utf-8")
    replacements = {
        "__DAMAGE_ROW__": damage_row.hex(),
        "__CHARGE_ROW__": charge_row.hex(),
        "__CHARGE_OWNER__": bytes.fromhex(owner)[::-1].hex(),
        "__CHARGE_HEADER__": charge_header.hex(),
        "__WEAPON_ROW__": weapon_row.hex(),
        "__ARC_HEADER__": arc_blob[:28].hex(),
        "__ARC_ROW__": arc_row.hex(),
    }
    for marker, value in replacements.items():
        assert source.count(marker) == 1
        source = source.replace(marker,value)
    (ROOT / "patch_resolved.lua").write_bytes(source.encode("utf-8"))
    windows = (ROOT / "windows.lua").read_text(encoding="utf-8")
    startup = (ROOT / "startup.lua").read_text(encoding="utf-8")
    entry = (f"-- HD2-Addon: {RESOURCE}\n"
             "local make_api=(function()\n"+windows+"\nend)()\n"
             "local patch=(function()\n"+source+"\nend)()\n"
             "local start=(function()\n"+startup+"\nend)()\n"
             "start(make_api,patch)\n")
    (ROOT / "entry.lua").write_bytes(entry.encode("utf-8"))
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    manifest = {
        "Version": 1, "Guid": GUID, "Name": "ARC-3 Rapid Arc Thrower v0.10",
        "Description": "Sets minimum/full/overcharge times to 0.307692/0.338462/0.369231 seconds, reach to 45 m, normal/durable damage per pulse to 226/90, Stun Medium buildup to 0.8, demolition to 4, hit reaction force strength to 25, impulse to 2, and horizontal/vertical camera climb multipliers to 0.4. Requires Bingus Shared Loader v18+.",
        "Options": [{"Name":"Rapid Arc Thrower gameplay", "Description":"ARC-3 adjusted charge, 45 m reach, moderate pushback, Behemoth-head damage and reduced camera climb.", "Include":["Addon"]}],
    }
    OUT.mkdir(exist_ok=True)
    (OUT / "ARC-3-Rapid-Arc-Thrower-v0.10-README.md").write_text(readme,encoding="utf-8")
    path = OUT / "ARC-3-Rapid-Arc-Thrower-v0.10.zip"
    files = {
        "manifest.json": json.dumps(manifest,indent=2).encode(),
        "README.md": readme.encode(),
        "Addon/9ba626afa44a3aa3.patch_0": archive(entry.encode()),
        "Addon/9ba626afa44a3aa3.patch_0.stream": b"",
        "Addon/9ba626afa44a3aa3.patch_0.gpu_resources": b"",
        "Source/arc_patch.lua": source.encode(),
        "Source/windows.lua": windows.encode(),
        "Source/startup.lua": startup.encode(),
        "Source/entry.lua": entry.encode(),
    }
    with zipfile.ZipFile(path,"w",zipfile.ZIP_DEFLATED) as z:
        for name,data in files.items(): z.writestr(name,data)
    report = {
        "steam_build":25480438,"exe_sha256":EXE_SHA,"game_dll_sha256":DLL_SHA,
        "charge_owner":owner,"charge_record_file_offset":charge_offset,
        "charge_record_sha256":sha(charge_row),"damage_row":197,"damage_row_file_offset":15072,
        "damage_row_sha256":sha(damage_row),
        "weapon_record_file_offset":26566228,"weapon_record_sha256":sha(weapon_row),
        "arc_row":7,"arc_row_file_offset":44,"arc_row_sha256":sha(arc_row),
        "stock":{"range_m":55,"charge_seconds":[1,1.1,1.2],"normal":250,"durable":100,"stun_buildup":8,"demolition":20,"force_strength":35,"force_impulse":10},
        "target":{"range_m":45,"charge_seconds":[0.2/0.65,0.22/0.65,0.24/0.65],"normal":226,"durable":90,"stun_buildup":0.8,"demolition":4,"force_strength":25,"force_impulse":2,"camera_climb_multiplier":[0.4,0.4]},
        "behemoth_head":{"zone_health":1600,"durable_fraction":1.0,"armor":4,"death_kills_entity":True,"hits_at_90_durable":18,"theoretical_seconds_at_minimum_charge":18*(0.2/0.65)},
        "actual_pulse_interval_measured":False,"charge_audio_changed":False,"in_game_verified":False,
        "package":str(path),"package_sha256":sha(path.read_bytes()),
    }
    (ROOT / "build-report.json").write_text(json.dumps(report,indent=2),encoding="utf-8")
    (OUT / "ARC-3-Rapid-Arc-Thrower-v0.10-Validation.json").write_text(json.dumps(report,indent=2),encoding="utf-8")
    return report


if __name__ == "__main__":
    print(json.dumps(build(),indent=2))
