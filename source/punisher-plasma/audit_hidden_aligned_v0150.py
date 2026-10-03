"""Offline One-Two mesh removal and hierarchy-correct muzzle candidate.

No game access. Rest-pose equality is not gameplay alignment proof.
"""
from pathlib import Path
import hashlib, json, struct, importlib.util
import numpy as np
import native_audit as n

HERE = Path(__file__).resolve().parent
OUT = HERE / 'hidden-aligned-v0150'
OUT.mkdir(exist_ok=True)
PARENT = HERE / 'underbarrel-assets/05d8d8c073b9d502.unit'
CHILD = HERE / 'one-two-visual/02cd7321cd8445f5-stock.unit'
parent, child = PARENT.read_bytes(), CHILD.read_bytes()
assert hashlib.sha256(parent).hexdigest() == '834426b0a1acb672101dc1b4dba05edb730f00ae8b0c177159feff4170c0dc2c'
assert hashlib.sha256(child).hexdigest() == '66e64d997d8863d51bf47786409a47c5200bee8e34b3b8ec4eaf0b578740524b'

def joints(b):
    j = struct.unpack_from('<I', b, 52)[0]
    c = struct.unpack_from('<I', b, j)[0]
    assert 0 < c < 1024 and j + 16 + c * 136 <= len(b)
    start = j + 16
    hashes = struct.unpack_from('<' + 'I' * c, b, start + c * 132)
    parents = [struct.unpack_from('<HH', b, start + c * 128 + i * 4)[1] for i in range(c)]
    matrices = [np.array(struct.unpack_from('<16f', b, start + c * 64 + i * 64)).reshape(4, 4).T for i in range(c)]
    for i in range(c):
        raw = struct.unpack_from('<16f', b, start + i * 64)
        local = np.eye(4)
        local[:3, :3] = np.array(raw[:9]).reshape(3, 3).T
        local[:3, 3] = raw[9:12]
        assert np.allclose(raw[12:15], [1, 1, 1], atol=1e-6)
        expected = local if parents[i] == i else matrices[parents[i]] @ local
        assert np.allclose(expected, matrices[i], atol=2e-6), ('Hierarchy mismatch', i)
    def node(h):
        hits = [i for i, v in enumerate(hashes) if v == h]
        assert len(hits) == 1
        return hits[0]
    return start, c, parents, matrices, node

ps, pc, pp, pm, pn = joints(parent)
cs, cc, cp, cm, cn = joints(child)
mount, muzzle, child_muzzle = pn(0x7950e36e), pn(0x57520abf), cn(0x57520abf)
assert (mount, muzzle, child_muzzle, cc) == (35, 30, 13, 19)
assert np.allclose(cm[0], np.eye(4))
assert not any(p == child_muzzle and i != p for i, p in enumerate(cp)), 'Muzzle is not a leaf'
# Full inverse composition, including the mount's 180-degree rotation.
desired_global = np.linalg.inv(pm[mount]) @ pm[muzzle]
desired_local = np.linalg.inv(cm[cp[child_muzzle]]) @ desired_global
after = bytearray(child)
lo = cs + child_muzzle * 64
go = cs + cc * 64 + child_muzzle * 64
old_local = list(struct.unpack_from('<16f', child, lo))
new_local = list(desired_local[:3, :3].T.flatten()) + list(desired_local[:3, 3]) + old_local[12:]
struct.pack_into('<16f', after, lo, *new_local)
struct.pack_into('<16f', after, go, *desired_global.T.flatten())
lod, mesh = struct.unpack_from('<I', child, 48)[0], struct.unpack_from('<I', child, 100)[0]
assert (lod, mesh) == (160, 5536)
assert struct.unpack_from('<I', child, lod)[0] == 2 and struct.unpack_from('<I', child, mesh)[0] == 4
struct.pack_into('<I', after, lod, 0)
struct.pack_into('<I', after, mesh, 0)
after = bytes(after)
allowed = set(range(lo, lo + 48)) | set(range(go, go + 64)) | set(range(lod, lod + 4)) | set(range(mesh, mesh + 4))
changed = [i for i, (a, b) in enumerate(zip(child, after)) if a != b]
assert set(changed) <= allowed and len(after) == len(child)
_, _, ap, am, _ = joints(after)
assert ap == cp
for i in range(cc):
    if i != child_muzzle:
        assert after[cs + i * 64:cs + (i + 1) * 64] == child[cs + i * 64:cs + (i + 1) * 64]
        assert np.array_equal(am[i], cm[i])
aligned = pm[mount] @ am[child_muzzle]
error = float(np.max(np.abs(aligned - pm[muzzle])))
assert error < 2e-6
assert after[:48] == child[:48]
assert after[cs + cc * 128:cs + cc * 136] == child[cs + cc * 128:cs + cc * 136]
# Sole-owned child unit and firing node; no AR-11 asset/profile edit.
p = HERE.parents[1] / 'work/sai-mod/inspect.py'
ns = {'__file__': str(p)}
exec(compile(p.read_text().split("report={'weapon':")[0], str(p), 'exec'), ns)
e = ns['entities']
assert hashlib.sha256(e).hexdigest().upper() == json.loads((HERE / 'source-audit.json').read_text())['entity_sha256']
hits, meta = ns['component_for'](0x02cd7321cd8445f5, 'WeaponDataComponent')
assert len(hits) == 1
fire_nodes = struct.unpack_from('<24I', e, hits[0][1] + 204)
assert fire_nodes == (0x57520abf,) + (0,) * 23
uh, um = ns['component_for'](0x02cd7321cd8445f5, 'UnitComponent')
assert len(uh) == 1
uraw = e[uh[0][1]:uh[0][1] + um['stride']]
path_offsets = [i for i in range(0, len(uraw) - 7, 8) if struct.unpack_from('<Q', uraw, i)[0] == 0x02cd7321cd8445f5]
assert len(path_offsets) == 1
unit_refs = []
for i in range(um['map_count']):
    owner, idx = struct.unpack_from('<QI', e, um['group'] + 28 + i * 16)
    if owner:
        row = um['group'] + 28 + um['record_offset'] + idx * um['stride']
        if struct.unpack_from('<Q', e, row + path_offsets[0])[0] == 0x02cd7321cd8445f5:
            unit_refs.append(f'{owner:016X}')
assert unit_refs == ['02CD7321CD8445F5'], unit_refs
ah, at = ns['component_for'](0x02cd7321cd8445f5, 'AttachableComponent')
assert len(ah) == 1 and e[ah[0][1] + 12:ah[0][1] + 40] == bytes(28), 'Nonzero attachment offsets'
guards = []
for addr, mnemonic, operand in [
    (0x74966b, 'mov', 'edx, 0x7950e36e'),
    (0x749689, 'mov', 'edx, 0x7950e36e'),
    (0x7496aa, 'xor', 'r8d, r8d'),
    (0x7496ad, 'mov', 'r9d, dword ptr [r13 + 0xc]'),
    (0x7496b1, 'mov', 'edx, dword ptr [rsi + 0xc]'),
    (0x7496b4, 'mov', 'dword ptr [rsp + 0x20], eax'),
    (0x7496c3, 'call', 'qword ptr [r10 + 0xc8]')]:
    ins = next(n.md.disasm(n.text[addr - n.base:addr - n.base + 16], addr))
    assert (ins.mnemonic, ins.op_str) == (mnemonic, operand)
    guards.append({'rva': hex(addr), 'bytes': ins.bytes.hex(), 'instruction': mnemonic + ' ' + operand})
unit_file = OUT / '02cd7321cd8445f5-hidden-aligned.unit'
unit_file.write_bytes(after)
report = dict(status='PASS', scope='Offline byte isolation and rest-pose mount/muzzle transform equality ONLY',
    stock_sha256=hashlib.sha256(child).hexdigest(), candidate_sha256=hashlib.sha256(after).hexdigest(),
    unit_owner_references=unit_refs, fire_nodes=[hex(v) for v in fire_nodes if v],
    child_attachable_offsets_zero=True, native_mount_guards=guards,
    muzzle_joint=child_muzzle, muzzle_parent=cp[child_muzzle], child_muzzle_global=am[child_muzzle].tolist(),
    mount_global=pm[mount].tolist(), target_parent_muzzle=pm[muzzle].tolist(),
    old_mounted_muzzle=(pm[mount] @ cm[child_muzzle]).tolist(), new_mounted_muzzle=aligned.tolist(),
    maximum_matrix_error=error, changed_bytes=changed, allowed_ranges=[[lod,4],[mesh,4],[lo,48],[go,64]],
    other_18_joints_identical=True, parenting_names_references_identical=True,
    mesh_count=0, lod_count=0, original_assets_unchanged=True,
    reload='UNCHANGED v0149 2x', tuning='UNCHANGED', final_tuning='GATED',
    native_publication_safety='UNCHANGED', game_access=False, startup='NOTRUN', gameplay='NOTRUN',
    limitations=['Engine acceptance/rendering of zero mesh/LOD tables needs user test.',
                'Rest-pose equality does not prove animated runtime muzzle equality or projectile trajectory.',
                'One-Two donor unit intentionally replaced; AR-11 and other serialized unit owners excluded.'])
(OUT / 'visual-alignment-audit.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({k:report[k] for k in ['status','scope','maximum_matrix_error','unit_owner_references','reload','startup','gameplay']}, indent=2))
