from pathlib import Path
source=Path('work/sai-mod/test.py').resolve()
# The historical runner's final ZIP assertion targets v0.2. Run its native
# transaction fixtures against the updated resolved source; candidate ZIP
# roundtrips are checked independently by fix.py.
code=source.read_text().split("package=OUT/'SAI-Focus-Precision-v0.2.zip'",1)[0]
exec(compile(code,str(source),'exec'),{'__file__':str(source)})
print('PASS: SAI native transaction, rollback, protection, checksum and discovery fixtures')
