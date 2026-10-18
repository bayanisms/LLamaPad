"""Run a local GGUF across this Mac and a tethered LlamaPad RPC worker."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
import re
from pathlib import Path
import signal
import socket
import struct
import subprocess
import time
import urllib.error
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('model', type=Path)
    parser.add_argument('--alias', help='API model name; defaults to the GGUF filename without its extension')
    parser.add_argument('--local-only', action='store_true', help='Run on the Mac without starting the iPad or USB tunnel')
    parser.add_argument('--gpu-layers', default='999', help='GPU layer limit (0–999 or auto), primarily for Mac-only memory tuning')
    parser.add_argument('--fit', choices=['on', 'off'], default='off')
    parser.add_argument('--cpu-moe', action='store_true', help='Keep expert source weights in host memory')
    parser.add_argument('--moe-cache-mib', type=int, default=0, help='Upstream GPU expert cache for host weights, in MiB')
    parser.add_argument('--device', help='iPad UDID; defaults to your own local install record')
    parser.add_argument('--bundle-id', default='dev.local.LlamaPad', help='Installed app bundle identifier')
    parser.add_argument('--server-binary', type=Path, default=ROOT / 'build-mac/bin/llama-server',
        help='Coordinator executable for an isolated native experiment')
    parser.add_argument('--mac-metal-env', action='append', default=[], metavar='NAME=VALUE')
    parser.add_argument('--ipad-metal-env', action='append', default=[], metavar='NAME=VALUE')
    parser.add_argument('--split', default='40,60', help='Mac,iPad layer proportions')
    parser.add_argument('--ipad-first', action='store_true',
        help='Place the first layers on the iPad and the final layers/output on the Mac')
    parser.add_argument('--context', type=int, default=2048)
    parser.add_argument('--batch', type=int, default=256)
    parser.add_argument('--micro-batch', type=int, default=64)
    parser.add_argument('--threads', type=int, default=6)
    parser.add_argument('--checkpoints', type=int, default=0,
        help='Prompt-context snapshots per slot; zero disables these, but speculative rollback can still use snapshots')
    parser.add_argument('--ngram-draft', type=int, default=0,
        help='Opt-in n-gram speculation for text/code reuse: maximum 1–64 draft tokens; zero disables it')
    parser.add_argument('--ngram-match', type=int, default=24,
        help='N-gram lookup length, 16–64 tokens; used with --ngram-draft')
    parser.add_argument('--ngram-min', type=int, default=8,
        help='Minimum proposed n-gram draft length; used with --ngram-draft')
    parser.add_argument('--mtp-draft', type=int, default=0,
        help='Experimental built-in MTP draft length, 1–8; zero disables speculation')
    parser.add_argument('--draft-model', type=Path,
        help='Experimental DFlash GGUF; target weights remain unchanged')
    parser.add_argument('--draft-tokens', type=int, default=7,
        help='Maximum DFlash draft tokens, 1–15')
    parser.add_argument('--draft-device', choices=['MTL0', 'RPC0'], default='RPC0',
        help='Device for the separate DFlash model; RPC0 leaves more Mac memory available')
    parser.add_argument('--mac-k-mma-min-rows', type=int, default=0,
        help='Experimental Q4_K/Q6_K MMA threshold: 0 stock, 2–16 rows, 17 disables the few-row path')
    parser.add_argument('--ipad-k-mma-min-rows', type=int, default=0,
        help='Independent iPad Q4_K/Q6_K MMA threshold; same range as the Mac option')
    parser.add_argument('--no-repack', action='store_true', help='Keep CPU weights mapped instead of creating repacked copies')
    parser.add_argument('--reasoning', choices=['auto', 'on', 'off'], default='auto')
    parser.add_argument('--reasoning-budget', type=int, help='Optional thinking token budget; zero closes thinking immediately')
    parser.add_argument('--log-verbosity', type=int, choices=range(6), default=4)
    parser.add_argument('--override-tensor', action='append', default=[],
        help='llama.cpp tensor-pattern=buffer override; repeat for additional patterns')
    parser.add_argument('--node-memory', type=int, default=10240, help='RPC buffer budget in MiB')
    parser.add_argument('--port', type=int, default=8080)
    parser.add_argument('--rpc-port', type=int, default=50052)
    parser.add_argument('--log-dir', type=Path, default=ROOT / 'build/rpc/current')
    args = parser.parse_args()
    if not args.model.is_file():
        parser.error('The model file does not exist.')
    alias = args.alias or re.sub(r'[^a-zA-Z0-9_.-]+', '-', args.model.stem).lower()
    if not alias.strip() or any(character.isspace() for character in alias):
        parser.error('Choose a nonempty model alias without whitespace.')
    if not (512 <= args.node_memory <= 12288 and 32 <= args.micro_batch <= args.batch <= 2048):
        parser.error('Invalid memory or batch size.')
    if not (256 <= args.context <= 32768 and 1 <= args.threads <= 16):
        parser.error('Invalid context or CPU thread count.')
    if not 0 <= args.checkpoints <= 32:
        parser.error('Use 0–32 context checkpoints.')
    if not 0 <= args.mtp_draft <= 8:
        parser.error('Use 0–8 MTP draft tokens.')
    if not 0 <= args.ngram_draft <= 64 or not 16 <= args.ngram_match <= 64 or not 1 <= args.ngram_min <= 64:
        parser.error('Use 0–64 n-gram draft tokens, a 16–64 token lookup, and a 1–64 token minimum.')
    if args.ngram_draft:
        if args.ngram_min > args.ngram_draft:
            parser.error('The n-gram minimum cannot exceed the maximum draft length.')
        if args.draft_model or args.mtp_draft:
            parser.error('N-gram speculation cannot be combined with a draft model or MTP in this launcher.')
    if args.draft_model and (args.mtp_draft or not args.draft_model.is_file()):
        parser.error('DFlash requires an existing draft model and cannot be combined with --mtp-draft.')
    if not 1 <= args.draft_tokens <= 15:
        parser.error('Use 1–15 DFlash draft tokens.')
    if any(value != 0 and not 2 <= value <= 17
            for value in (args.mac_k_mma_min_rows, args.ipad_k_mma_min_rows)):
        parser.error('K-quant MMA thresholds must be 0 or 2–17.')
    if args.rpc_port != 50052:
        parser.error('The automatic LlamaPad worker currently listens on port 50052.')
    if not 1024 <= args.port <= 65535 or args.port == args.rpc_port:
        parser.error('Choose a separate HTTP port between 1024 and 65535.')
    try:
        fractions = [float(x) for x in args.split.split(',')]
        assert len(fractions) == 2 and all(0 < x < float('inf') for x in fractions)
    except (ValueError, AssertionError):
        parser.error('Split must contain two positive numbers: Mac,iPad.')
    if args.gpu_layers != 'auto' and not (args.gpu_layers.isdecimal() and 0 <= int(args.gpu_layers) <= 999):
        parser.error('Use 0–999 GPU layers or auto.')
    if not 0 <= args.moe_cache_mib <= 12288:
        parser.error('Use 0–12288 MiB of expert cache.')
    if args.local_only and (args.draft_model or args.mtp_draft):
        parser.error('The local-only comparison currently supports ordinary decoding.')
    if not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', args.bundle_id):
        parser.error('Use a valid dot-separated bundle identifier.')
    if not args.device and not args.local_only:
        record = ROOT / 'build/device-signing.json'
        if not record.is_file():
            parser.error('Pass --device DEVICE_UDID or install first to create your local signing record.')
        args.device = json.loads(record.read_text())['device']
    metal_environment = {}
    for target, values in [('mac', args.mac_metal_env), ('ipad', args.ipad_metal_env)]:
        metal_environment[target] = {}
        for assignment in values:
            name, separator, value = assignment.partition('=')
            if not separator or not re.fullmatch(r'(LLAMAPAD_METAL_|GGML_METAL_)[A-Z0-9_]+', name) or '\0' in value:
                parser.error('Metal environment entries must be GGML_METAL_* or LLAMAPAD_METAL_* NAME=VALUE pairs.')
            if name == 'LLAMAPAD_METAL_COMMAND_BUFFERS' and value not in ('0', '1', '2'):
                parser.error('LLAMAPAD_METAL_COMMAND_BUFFERS supports 0–2 extra command buffers.')
            metal_environment[target][name] = value
    binary = args.server_binary.resolve()
    if not binary.is_file():
        parser.error('The coordinator executable does not exist.')
    revision = (ROOT / 'upstream.lock').read_text().strip()
    version = subprocess.check_output([str(binary), '--version'], stderr=subprocess.STDOUT, text=True)
    if revision[:7] not in version:
        raise RuntimeError('Rebuild the Mac coordinator to match upstream.lock first.')
    for port in ([args.port] if args.local_only else [args.port, args.rpc_port]):
        with socket.socket() as check:
            check.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            check.bind(('127.0.0.1', port))
    args.log_dir.mkdir(parents=True, exist_ok=True)

    def device(*command):
        result = subprocess.run(['xcrun', 'devicectl', 'device', *command],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=75)
        with (args.log_dir / 'device.log').open('a') as log:
            log.write(result.stdout)
        if result.returncode:
            raise RuntimeError(result.stdout)

    def interrupted(signum, frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, interrupted)
    def start_worker():
        nonlocal tunnel
        print('Starting iPad RPC worker…', flush=True)
        launch_id = uuid.uuid4().hex
        node_environment = {'LLAMAPAD_RPC_MEMORY_MIB': str(args.node_memory), 'LLAMAPAD_RPC_LAUNCH_ID': launch_id}
        node_environment.update(metal_environment['ipad'])
        if args.ipad_k_mma_min_rows:
            node_environment['LLAMAPAD_METAL_K_MMA_MIN_ROWS'] = str(args.ipad_k_mma_min_rows)
        device('process', 'launch', '--device', args.device, '--timeout', '60', '--terminate-existing',
            '--environment-variables', json.dumps(node_environment),
            args.bundle_id, '--llamapad-rpc-node')
        with (args.log_dir / 'iproxy.log').open('w') as log:
            tunnel = subprocess.Popen(['iproxy', '--local', '--udid', args.device,
                f'{args.rpc_port}:50052'], stdout=log, stderr=log, start_new_session=True)
        deadline = time.monotonic() + 60
        while True:
            try:
                with socket.create_connection(('127.0.0.1', args.rpc_port), timeout=3) as connection:
                    connection.sendall(bytes([14]) + struct.pack('<Q', 24) + bytes(24))
                    header = b''
                    while len(header) < 8:
                        data = connection.recv(8 - len(header))
                        if not data:
                            raise OSError('RPC worker disconnected during handshake')
                        header += data
                    size, = struct.unpack('<Q', header)
                    if not 1 <= size <= 1024:
                        raise RuntimeError('Invalid RPC handshake length')
                    data = b''
                    while len(data) < size:
                        part = connection.recv(size - len(data))
                        if not part:
                            raise OSError('Incomplete RPC handshake')
                        data += part
                    if data[0] != 8:
                        raise RuntimeError('Unexpected RPC protocol version')
                break
            except OSError:
                if time.monotonic() >= deadline or tunnel.poll() is not None:
                    raise
                time.sleep(.5)
        status_path = args.log_dir / 'node-start.json'
        for attempt in range(10):
            device('copy', 'from', '--device', args.device, '--timeout', '30',
                '--source', 'Documents/RuntimeStatus.json', '--destination', str(status_path.resolve()),
                '--domain-type', 'appDataContainer', '--domain-identifier', args.bundle_id)
            snapshot = json.loads(status_path.read_text())
            if snapshot.get('launchID') == launch_id:
                break
            time.sleep(.5)
        else:
            raise RuntimeError('No fresh worker snapshot. Install LlamaPad 0.3.1 and keep it foreground.')
        if snapshot['revision'] != revision:
            raise RuntimeError('Reinstall LlamaPad to match the Mac revision first.')
        experiments = {'PROFILE', 'SINGLE_FUSION_PACK', 'SIGMOID_ROUTER', 'GATED_CONV',
            'MOE_ROWS', 'MOE_SIMDGROUPS', 'DENSE_ROWS', 'DENSE_SIMDGROUPS', 'COMMAND_BUFFERS'}
        if any(name.removeprefix('LLAMAPAD_METAL_') in experiments for name in metal_environment['ipad']) and \
                snapshot.get('metalPatch') not in ('lfm2-decode-1', 'lfm2-decode-2'):
            raise RuntimeError('Reinstall LlamaPad 0.3.1 before enabling the new iPad Metal experiments.')
        if 'LLAMAPAD_METAL_COMMAND_BUFFERS' in metal_environment['ipad'] and snapshot.get('metalPatch') != 'lfm2-decode-2':
            raise RuntimeError('Reinstall LlamaPad 0.3.1 build 5 for command-buffer tuning.')
        return snapshot

    tunnel = server = None
    try:
        snapshot = None if args.local_only else start_worker()
        devices = 'MTL0' if args.local_only else ('RPC0,MTL0' if args.ipad_first else 'MTL0,RPC0')
        split = ','.join(reversed(args.split.split(','))) if args.ipad_first else args.split
        command = [str(binary), '-m', str(args.model.resolve())]
        # The RPC argument registers remote devices while parsing. It must come
        # before --device so names such as RPC0 can be resolved.
        if not args.local_only:
            command += ['--rpc', f'127.0.0.1:{args.rpc_port}']
        command += ['--device', devices,
            '-ngl', str(args.gpu_layers), '-c', str(args.context), '-b', str(args.batch), '-ub', str(args.micro_batch),
            '-t', str(args.threads), '-tb', str(args.threads), '-fa', 'on', '-ctk', 'f16', '-ctv', 'f16',
            '--load-mode', 'mmap', '--fit', args.fit, '--cache-ram', '0',
            '--ctx-checkpoints', str(args.checkpoints), '-np', '1',
            '--host', '127.0.0.1', '--port', str(args.port), '--alias', alias,
            '--reasoning', args.reasoning, '--no-ui', '-lv', str(args.log_verbosity)]
        if not args.local_only:
            command += ['--split-mode', 'layer', '--tensor-split', split]
        if args.cpu_moe:
            command += ['--cpu-moe']
        if args.moe_cache_mib:
            command += ['--moe-cache-mib', str(args.moe_cache_mib)]
        if args.no_repack:
            command += ['--no-repack']
        if args.reasoning_budget is not None:
            command += ['--reasoning-budget', str(args.reasoning_budget)]
        for override in args.override_tensor:
            command += ['--override-tensor', override]
        if args.ngram_draft:
            command += ['--spec-type', 'ngram-mod', '--spec-ngram-mod-n-match', str(args.ngram_match),
                '--spec-ngram-mod-n-min', str(args.ngram_min), '--spec-ngram-mod-n-max', str(args.ngram_draft)]
        elif args.draft_model:
            # DFlash can share the target's output projection. Its context must
            # see both backends even when all its own tensors live on one GPU.
            draft_buffer = 'MTL0' if args.draft_device == 'MTL0' else f'RPC0[127.0.0.1:{args.rpc_port}]'
            command += ['--spec-type', 'draft-dflash', '--spec-draft-model', str(args.draft_model.resolve()),
                '--spec-draft-n-max', str(args.draft_tokens), '--spec-draft-n-min', '1',
                '--spec-draft-device', devices, '--spec-draft-ngl', '999',
                '--spec-draft-override-tensor', f'.*={draft_buffer}']
        elif args.mtp_draft:
            command += ['--spec-type', 'draft-mtp', '--spec-draft-n-max', str(args.mtp_draft),
                '--spec-draft-n-min', '1']
        else:
            command += ['--spec-type', 'none']
        server_environment = os.environ.copy()
        for name in list(server_environment):
            if name.startswith('LLAMAPAD_METAL_'):
                server_environment.pop(name)
        server_environment.update(metal_environment['mac'])
        if args.mac_k_mma_min_rows:
            server_environment['LLAMAPAD_METAL_K_MMA_MIN_ROWS'] = str(args.mac_k_mma_min_rows)
        with (args.log_dir / 'server.log').open('w') as log:
            server = subprocess.Popen(command, stdout=log, stderr=log, start_new_session=True,
                env=server_environment)
        (args.log_dir / 'run.json').write_text(json.dumps({
            'started': datetime.now(timezone.utc).isoformat(), 'revision': revision,
            'launcher_pid': os.getpid(), 'server_pid': server.pid, 'tunnel_pid': tunnel.pid if tunnel else None,
            'local_only': args.local_only,
            'model_bytes': args.model.stat().st_size, 'node_memory_mib': args.node_memory,
            'metal_k_mma_min_rows': {'mac': args.mac_k_mma_min_rows, 'ipad': args.ipad_k_mma_min_rows},
            'metal_environment': metal_environment,
            'ngram_speculation': {'type': 'ngram-mod', 'match': args.ngram_match,
                'minimum': args.ngram_min, 'maximum': args.ngram_draft} if args.ngram_draft else None,
            'coordinator_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
            'metal_library_sha256': hashlib.sha256((binary.parent / 'libggml-metal.dylib').read_bytes()).hexdigest()
                if (binary.parent / 'libggml-metal.dylib').is_file() else None,
            'command': command, 'node_start': snapshot}, indent=2))
        print(f'Loading model. Logs: {args.log_dir / "server.log"}', flush=True)
        ready = False
        while server.poll() is None:
            if not ready:
                try:
                    with urllib.request.urlopen(f'http://127.0.0.1:{args.port}/health', timeout=2) as response:
                        ready = json.load(response).get('status') == 'ok'
                    if ready:
                        print(f'Ready: http://127.0.0.1:{args.port}/v1 — press Ctrl-C to stop.', flush=True)
                except (OSError, urllib.error.URLError):
                    pass
            time.sleep(1)
        if server.returncode:
            raise RuntimeError(f'Coordinator exited with {server.returncode}; see {args.log_dir / "server.log"}')
    except KeyboardInterrupt:
        print('Stopping coordinator and USB tunnel…', flush=True)
    finally:
        for process in [server, tunnel]:
            if process is not None and process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=20)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == '__main__':
    main()
