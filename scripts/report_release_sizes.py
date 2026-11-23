#!/usr/bin/env python3
"""Record distribution file sizes without treating upload packages as downloads."""
import hashlib
import json
import plistlib
from pathlib import Path
import subprocess
import sys
from zipfile import ZipFile


def main():
    release = Path(sys.argv[1]).resolve()
    artifacts = []
    for folder in (release / 'ios', release / 'android'):
        for path in sorted(folder.glob('*')):
            if path.suffix not in ('.ipa', '.apk', '.aab'):
                continue
            digest = hashlib.sha256()
            with path.open('rb') as source:
                for chunk in iter(lambda: source.read(1024 * 1024), b''):
                    digest.update(chunk)
            item = {
                'path': str(path.relative_to(release)),
                'bytes': path.stat().st_size,
                'sha256': digest.hexdigest(),
            }
            with ZipFile(path) as archive:
                damaged = archive.testzip()
                if damaged is not None:
                    raise ValueError(f'Corrupt archive entry in {path.name}: {damaged}')
                if path.suffix == '.ipa':
                    entries = archive.infolist()
                    for prefix, label in [('Payload/', 'payload'), ('Symbols/', 'symbols')]:
                        files = [entry for entry in entries if entry.filename.startswith(prefix)]
                        item[f'{label}_compressed_bytes'] = sum(entry.compress_size for entry in files)
                        item[f'{label}_uncompressed_bytes'] = sum(entry.file_size for entry in files)
                    info_path = next(entry.filename for entry in entries
                                     if entry.filename.startswith('Payload/')
                                     and entry.filename.count('/') == 2
                                     and entry.filename.endswith('.app/Info.plist'))
                    info = plistlib.loads(archive.read(info_path))
                    item['app_name'] = info['CFBundleDisplayName']
                    item['version'] = info['CFBundleShortVersionString']
                    item['build'] = info['CFBundleVersion']
            artifacts.append(item)
            print(f"{item['path']}: {item['bytes'] / 1_000_000:.2f} MB")
            if path.suffix == '.ipa':
                print(f"  Compressed payload: {item['payload_compressed_bytes'] / 1_000_000:.2f} MB; separate native symbols in upload: {item['symbols_compressed_bytes'] / 1_000_000:.2f} MB")
    reports = [str(path.relative_to(release)) for path in release.rglob('App Thinning Size Report.txt')]
    data = {
        'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
        'working_tree_changed': bool(subprocess.check_output(['git', 'status', '--porcelain'], text=True).strip()),
        'artifacts': artifacts,
        'ios_size_reports': reports,
        'dart_symbol_files': [str(path.relative_to(release)) for path in (release / 'symbols').rglob('*.symbols')],
        'note': 'IPA/AAB upload sizes are not store download sizes. Apple and Google determine final per-device delivery sizes. Preserve this directory, including symbols, for crash diagnosis.',
    }
    (release / 'sizes.json').write_text(json.dumps(data, indent=2) + '\n')
    for report in reports:
        print(f'iOS per-device size report: {report}')


if __name__ == '__main__':
    main()
