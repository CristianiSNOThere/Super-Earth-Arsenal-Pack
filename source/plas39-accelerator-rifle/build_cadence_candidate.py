"""Build v1.1.8 from tested isolation candidate and retain v1.0.6 balances."""
from pathlib import Path

root = Path(__file__).resolve().parent
source = (root / 'build_isolation_candidate.py').read_text()
source = source.replace('1.1.7', '1.1.8').replace('1.0.5', '1.0.7')
source = source.replace("ROOT / 'work/rapid-arc-thrower/release-repo/mods/PLAS-39-Accelerator-Rifle-v1.1.6.zip'",
                        "OUT / 'PLAS-39-Accelerator-Rifle-v1.1.7.zip'")
source = source.replace("ROOT / 'work/super-earth-arsenal-modpack-repo/Super-Earth-Arsenal-Modpack-v1.0.4.zip'",
                        "OUT / 'Super-Earth-Arsenal-Modpack-v1.0.6.zip'")
source = source.replace("readme.replace('v1.1.6', 'v1.1.8')", "readme.replace('v1.1.7', 'v1.1.8')")
source = source.replace("readme.replace('v1.0.4', 'v1.0.7').replace('v1.1.6', 'v1.1.8')",
                        "readme.replace('v1.0.6', 'v1.0.7').replace('v1.1.7', 'v1.1.8')")
source = source.replace("'PLAS-39 firing-mode correction\\n\\n'",
                        "'PLAS-39 firing-mode correction\\n\\n'")
source = source.replace("'Semi fires one round at 200 RPM with a 0.01-second minimum charge. '",
                        "'Semi fires one round at 200 RPM with a 0.30-second firing interval and a 0.01-second minimum charge. '")
source = source.replace("    with zipfile.ZipFile(source) as z:", """    expected = {'individual': '4F788AF8F929CE73516BBE3D43A14671A42350212FE159E06809336D1519C06E',
                'modpack': '8CD7C229575E24E537179DC6D35B36557FEAB9BF4CDA68921AE706EB47AF73E4'}
    assert build.sha(source.read_bytes()) == expected[kind], 'Candidate base hash changed'
    assert not destination.exists(), 'Refusing to overwrite an existing test package'
    with zipfile.ZipFile(source) as z:""")
exec(compile(source, str(root / 'build_isolation_candidate.py'), 'exec'))
