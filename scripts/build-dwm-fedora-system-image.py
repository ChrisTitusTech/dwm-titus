#!/usr/bin/env python3
"""Build a sanitized root filesystem in a disposable KVM guest (never on host)."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def run(*args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True, help='Verified Fedora 44 Server netinst ISO')
    parser.add_argument('--output', type=Path, required=True, help='New root filesystem .tar.zst (or legacy .tar.xz)')
    parser.add_argument('--variant', choices=['standard', 'nvidia'], default='standard')
    parser.add_argument('--timeout', type=int, default=7200)
    args = parser.parse_args()
    args.input = args.input.resolve(strict=True)
    args.output = args.output.absolute()
    # Pin the reviewed Fedora 44 Server base used by both firmware paths.
    with args.input.open('rb') as stream:
        source_sha256 = hashlib.file_digest(stream, 'sha256').hexdigest()
    if source_sha256 != 'ae20c06bea746913cadea7d80463e13f4bf55bee4df2918111c921c674b70283':
        parser.error('input checksum does not match Fedora 44 Server 1.7 x86_64')
    if (not args.output.name.endswith(('.tar.zst', '.tar.xz')) or args.output.exists()
            or args.output.with_name(args.output.name + '.json').exists()):
        parser.error('output and its manifest must be new .tar.zst or .tar.xz files')
    compression = 'zstd' if args.output.name.endswith('.tar.zst') else 'xz'
    compression_args = ['-T0', '-19'] if compression == 'zstd' else ['-T4', '-6']
    for tool in ['qemu-system-x86_64', 'qemu-img', 'xorriso', 'guestfish', compression, 'time', 'ksvalidator']:
        if not shutil.which(tool):
            parser.error(f'missing tool: {tool}')
    repo = Path(__file__).resolve().parent.parent
    args.output.parent.mkdir(parents=True, exist_ok=True)
    test_root = Path(os.environ.get('DWM_TEST_TMP_ROOT', str(Path.home() / 'tmp')))
    test_root.mkdir(parents=True, exist_ok=True)
    evidence = args.output.with_name(args.output.name + '.logs')
    evidence.mkdir(exist_ok=False)
    with tempfile.TemporaryDirectory(prefix='dwm-factory.', dir=test_root) as temp:
        work = Path(temp)
        env = os.environ.copy()
        env['TMPDIR'] = str(work)
        env['LIBGUESTFS_BACKEND'] = 'direct'
        with (evidence / 'build.log').open('w') as log:
            run(repo / 'scripts/build-dwm-fedora-installer-iso.sh', '--input', args.input,
                '--output', work / 'network.iso', '--variant', args.variant,
                env=env, stdout=log, stderr=subprocess.STDOUT)
            profile = repo / ('dwm-fedora-nvidia.ks' if args.variant == 'nvidia' else 'dwm-fedora.ks')
            ks = ('text\nlang en_US.UTF-8\nkeyboard us\ntimezone UTC --utc\n'
                  'rootpw --lock\nuser --name=imagebuilder --groups=wheel --lock\n'
                  'ignoredisk --only-use=vda\nzerombr\nclearpart --all --initlabel --drives=vda\n'
                  'autopart --type=plain --nohome\npoweroff\n' + profile.read_text())
            ks = ks.replace('set -eu\n', 'set -eu\nexec > /dev/ttyS0 2>&1\n')
            boot_packages = run('bash', repo / 'scripts/dwm-packages.sh', 'fedora',
                                'image-boot', capture_output=True, text=True).stdout
            boot_packages += run('bash', repo / 'scripts/dwm-packages.sh', 'fedora',
                                 'image-desktop', capture_output=True, text=True).stdout
            ks = ks.replace('%packages\n', '%packages\n' + boot_packages, 1)
            ks += ('\n%post --interpreter=/bin/bash --erroronfail\nset -euo pipefail\nexec > /dev/ttyS0 2>&1\n'
                   f"printf '%s\\n' '{args.variant}' > /etc/dwm-titus-factory-target\n"
                   'bash /home/imagebuilder/.local/share/dwm-titus/scripts/image/prepare-factory.sh --factory-target\n%end\n')
            (work / 'factory.ks').write_text(ks)
            run('ksvalidator', work / 'factory.ks', stdout=log, stderr=subprocess.STDOUT)
            run('xorriso', '-indev', work / 'network.iso', '-outdev', work / 'factory.iso',
                '-boot_image', 'any', 'replay', '-map', work / 'factory.ks', '/factory.ks',
                stdout=log, stderr=subprocess.STDOUT)
            for name in ['vmlinuz', 'initrd.img']:
                run('xorriso', '-osirrox', 'on', '-indev', args.input, '-extract',
                    '/images/pxeboot/' + name, work / name, stdout=log, stderr=subprocess.STDOUT)
            run('qemu-img', 'create', '-f', 'qcow2', work / 'factory.qcow2', '50G', stdout=log)
            shutil.copy2('/usr/share/edk2/ovmf/OVMF_VARS.fd', work / 'vars.fd')
            command = ['qemu-system-x86_64', '-enable-kvm', '-machine', 'q35', '-cpu', 'host',
                       '-smp', '4', '-m', '6144', '-display', 'none', '-serial', 'stdio', '-monitor', 'none',
                       '-qmp', f'unix:{work}/qmp.sock,server=on,wait=off',
                       '-drive', 'if=pflash,format=raw,readonly=on,file=/usr/share/edk2/ovmf/OVMF_CODE.fd',
                       '-drive', f'if=pflash,format=raw,file={work}/vars.fd',
                       '-drive', f'file={work}/factory.qcow2,if=virtio,format=qcow2',
                       '-cdrom', str(work / 'factory.iso'), '-nic', 'user,model=virtio-net-pci',
                       '-kernel', str(work / 'vmlinuz'), '-initrd', str(work / 'initrd.img'),
                       '-append', 'inst.stage2=hd:LABEL=Fedora-S-dvd-x86_64-44 inst.ks=hd:LABEL=Fedora-S-dvd-x86_64-44:/factory.ks inst.text console=ttyS0']
            (evidence / 'qemu-command.json').write_text(json.dumps(command, indent=2) + '\n')
            with (evidence / 'factory-console.log').open('w') as console:
                run(*command, stdout=console, stderr=subprocess.STDOUT, timeout=args.timeout)
            marker = run('guestfish', '--ro', '-a', work / 'factory.qcow2', '-i', 'cat',
                         '/etc/dwm-titus-image', env=env, capture_output=True, text=True).stdout
            if f'variant={args.variant}\n' not in marker:
                raise RuntimeError('Factory did not finish preparation')
            run('guestfish', '-a', work / 'factory.qcow2', '-i',
                'upload', repo / 'scripts/image/check-root.sh', '/tmp/dwm-image-check.sh', ':',
                'sh', 'bash /tmp/dwm-image-check.sh', ':', 'rm-f', '/tmp/dwm-image-check.sh', ':',
                'tar-out', '/',
                work / 'rootfs.tar', 'numericowner:true', 'xattrs:true', 'selinux:true', 'acls:true',
                env=env, stdout=log, stderr=subprocess.STDOUT)
            tar_size = (work / 'rootfs.tar').stat().st_size
            with (work / 'rootfs.tar').open('rb') as stream:
                tar_digest = hashlib.file_digest(stream, 'sha256').hexdigest()
            run('/usr/bin/time', '--verbose', '--output', evidence / 'compression.txt',
                compression, *compression_args, work / 'rootfs.tar',
                stdout=log, stderr=subprocess.STDOUT)
            # Copy into an adjacent temporary file; publish only a completed capture.
            with tempfile.NamedTemporaryFile(dir=args.output.parent, delete=False) as out:
                staged = Path(out.name)
            try:
                suffix = '.zst' if compression == 'zstd' else '.xz'
                shutil.copyfile(work / ('rootfs.tar' + suffix), staged)
                with staged.open('rb') as stream:
                    digest = hashlib.file_digest(stream, 'sha256').hexdigest()
                staged.replace(args.output)
            finally:
                staged.unlink(missing_ok=True)
            manifest = {'protocol': 2, 'variant': args.variant, 'fedora': '44', 'architecture': 'x86_64',
                        'source_sha256': source_sha256, 'sha256': digest, 'size': args.output.stat().st_size,
                        'compression': compression, 'compression_args': compression_args,
                        'tar_sha256': tar_digest, 'tar_size': tar_size}
            args.output.with_name(args.output.name + '.json').write_text(json.dumps(manifest, indent=2) + '\n')
            print(json.dumps(manifest))


if __name__ == '__main__':
    main()
