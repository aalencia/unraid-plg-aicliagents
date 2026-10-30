"""Build a separately versioned fork release from committed source bytes.

Usage: python3 tools/build-downstream-release.py [source_commit]
Never runs the installer. The published tar member set and modes are retained.
"""
import copy
import gzip
import hashlib
import html
import io
import json
from pathlib import Path
import re
import subprocess
import sys
import tarfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
VERSION = '2026.10.29.01'
TAG = 'downstream-' + VERSION
URL = 'https://raw.githubusercontent.com/aalencia/unraid-plg-aicliagents/' + TAG


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args])


def build(ref='HEAD'):
    ref = git('rev-parse', ref).decode().strip()
    old_tar = git('show', ref + ':src.tar.gz')
    source = {}
    with tarfile.open(fileobj=io.BytesIO(git('archive', '--format=tar', ref, 'src'))) as committed:
        for member in committed.getmembers():
            if member.isfile():
                source[member.name] = (b'100644', committed.extractfile(member).read())
            elif member.issym():
                source[member.name] = (b'120000', member.linkname.encode())
            elif not member.isdir():
                raise ValueError('Unsupported source entry: ' + member.name)
    timestamp = int(git('show', '-s', '--format=%ct', ref))
    tar_bytes = io.BytesIO()
    with tarfile.open(fileobj=io.BytesIO(old_tar), mode='r:gz') as old, tarfile.open(fileobj=tar_bytes, mode='w', format=tarfile.PAX_FORMAT) as new:
        seen = set()
        for entry in old.getmembers():
            entry = copy.copy(entry)
            entry.mtime = timestamp
            entry.uid = entry.gid = 0
            entry.uname = entry.gname = 'root'
            if entry.isfile() or entry.issym():
                mode, data = source[entry.name]
                seen.add(entry.name)
                if entry.issym():
                    if mode != b'120000' or entry.linkname != data.decode():
                        raise ValueError('Symlink metadata changed: ' + entry.name)
                    new.addfile(entry)
                else:
                    entry.size = len(data)
                    new.addfile(entry, io.BytesIO(data))
            else:
                if not entry.isdir():
                    raise ValueError('Unsafe archive member: ' + entry.name)
                new.addfile(entry)
        if seen != set(source):
            raise ValueError('Source/archive member set mismatch')
    archive = gzip.compress(tar_bytes.getvalue(), mtime=0)
    (ROOT / 'src.tar.gz').write_bytes(archive)

    template = git('show', 'c9f750d4eae1c4f09faa8daaf43ee1487e145a0b:unraid-aicliagents.plg').decode()
    before, changes = template.split('<CHANGES>', 1)
    history, after = changes.split('</CHANGES>', 1)
    before = before.replace('2026.10.21.01', VERSION).replace('https://raw.githubusercontent.com/johnpwhite/unraid-plg-aicliagents/main', URL)
    after = after.replace('2026.10.21.01', VERSION).replace('https://raw.githubusercontent.com/johnpwhite/unraid-plg-aicliagents/main', URL)
    descriptor = before + '<CHANGES>\n## ' + VERSION + '\n\nDownstream runtime boot fix. Same-layout live updates preserve running sessions and skip storage initialization and migration. Required runtime failure blocks activation and auto-launch.\n' + history + '</CHANGES>' + after
    preflight = git('show', ref + ':tools/downstream-preflight.sh').decode()
    marker = 'export OLD_LAYOUT_VERSION="$_OLD_LV"'
    descriptor = descriptor.replace(marker, marker + '\n\n' + html.escape(preflight, quote=False), 1)
    descriptor = re.sub(r'^    find "\$LOCAL_CACHE".*-delete.*$', '    # Downstream: retain versioned release cache for rollback.', descriptor, flags=re.M)
    marker = '# #337: EVERY background process'
    live_exit = '''if [ "${AICLI_RUNTIME_ONLY:-0}" = "1" ]; then
    for _php in TerminalService AutoLaunchService; do
        /usr/bin/php -l "$EMHTTP_DEST/src/includes/services/$_php.php" || exit 1
    done
    /usr/bin/php -r 'require $argv[1]; if (!\\AICliAgents\\Services\\TerminalService::runtimeReady()) exit(1);' "$EMHTTP_DEST/src/includes/services/TerminalService.php" || exit 1
    echo "AICLI_DOWNSTREAM_POSTFLIGHT_PASS"
    readlink -f "$EMHTTP_DEST/src"
    sha256sum "$EMHTTP_DEST/src/includes/services/TerminalService.php" "$EMHTTP_DEST/src/includes/services/AutoLaunchService.php" "$CONFIG_DIR/unraid-aicliagents.cfg"
    log_ok "Runtime fix installed. Storage initialization and background migrations skipped."
    rm -f /tmp/aicli-*.sh /tmp/aicli-*.page /tmp/aicli-src.tar.gz
    exit 0
fi

'''
    descriptor = descriptor.replace(marker, html.escape(live_exit, quote=False) + marker, 1)
    old = 'if [ -f /usr/local/emhttp/plugins/unraid-aicliagents/src/scripts/installer/migrate-btrfs-to-squashfs.sh ]; then'
    descriptor = descriptor.replace(old, 'if [ "${AICLI_PRESERVE_STORAGE:-0}" != "1" ] &amp;&amp; [ -f /usr/local/emhttp/plugins/unraid-aicliagents/src/scripts/installer/migrate-btrfs-to-squashfs.sh ]; then')
    artifact_hashes = {}

    def pin(match):
        block = match.group(0)
        suffix = re.search(r'<URL>' + re.escape(URL) + r'/([^<]+)</URL>', block)
        if suffix:
            path = suffix.group(1)
            data = archive if path == 'src.tar.gz' else git('show', ref + ':' + path)
            sha = hashlib.sha256(data).hexdigest()
            artifact_hashes[path] = sha
            block = re.sub(r'<SHA256>[^<]*</SHA256>', '<SHA256>' + sha + '</SHA256>', block)
        return block

    descriptor = re.sub(r'<FILE Name="[^"]+">.*?</FILE>', pin, descriptor, flags=re.S)
    ET.fromstring(descriptor)
    if len(artifact_hashes) != 12:
        raise ValueError('Expected twelve pinned release files')
    (ROOT / 'unraid-aicliagents.plg').write_text(descriptor, encoding='utf-8', newline='\n')
    manifest = {'version': VERSION, 'tag': TAG, 'source_commit': ref, 'upstream_patch': 'e7f7c74040b55b2446fdb5698908e33d55195379', 'artifacts': artifact_hashes, 'plg_sha256': hashlib.sha256(descriptor.encode()).hexdigest(), 'production_installed': False}
    (ROOT / 'downstream-release.json').write_text(json.dumps(manifest, indent=2) + '\n', newline='\n')
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    build(sys.argv[1] if len(sys.argv) > 1 else 'HEAD')
