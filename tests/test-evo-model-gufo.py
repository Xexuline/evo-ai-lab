#!/usr/bin/env python3
"""Behavioral lifecycle tests without GPU, systemd user session or real models."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / 'scripts/evo-model'
GUFO_MODELS_RESPONSE = '{"object":"list","data":[{"id":"Qwen3.8 Flash Next","object":"model","created":1791994928,"owned_by":"gufo","context_length":131072,"architecture":{"input_modalities":["text","image"]}}]}'
FAKE = r'''#!/usr/bin/env python3
import json, os, pathlib, subprocess, sys, secrets
root = pathlib.Path(os.environ['TEST_ROOT'])
args = sys.argv[1:]
name = pathlib.Path(sys.argv[0]).name
with (root/'calls').open('a') as f: f.write(json.dumps([name]+args)+'\n')
statefile = root/'containers'
containers = json.loads(statefile.read_text()) if statefile.exists() else {}
def save(): statefile.write_text(json.dumps(containers))
def value(flag): return args[args.index(flag)+1]
if name == 'podman':
    if args[0] == 'info': print('true'); sys.exit()
    if args[:2] == ['image','exists']: sys.exit()
    if args[0] == 'ps':
        if os.environ.get('FAIL_INSPECT'): sys.exit(125)
        filters = [a.split('label=',1)[1].split('=',1) for a in args if a.startswith('label=')]
        print('\n'.join(k for k,v in containers.items() if all(v['labels'].get(a)==b for a,b in filters)))
    elif args[0] == 'run':
        labels = dict(args[i+1].split('=',1) for i,a in enumerate(args) if a=='--label')
        cid = secrets.token_hex(32)
        containers[cid] = {'labels': labels, 'state': 'running', 'name': value('--name')}
        save()
        pathlib.Path(value('--cidfile')).write_text(cid)
        if os.environ.get('FAIL_RUN'): sys.exit(125)
    elif args[:2] == ['container','exists']:
        if os.environ.get('FAIL_EXISTS'): sys.exit(125)
        sys.exit(0 if args[-1] in containers else 1)
    elif args[0] == 'inspect':
        obj=containers.get(args[-1])
        if not obj: sys.exit(125)
        if '.State.Status' in value('--format'): print(obj['state'])
        else: print(('foreign' if os.environ.get('BAD_OWNER') else obj['labels']['org.evo-model.owner'])+'/'+obj['labels']['org.evo-model.instance'])
    elif args[0] == 'rm':
        if os.environ.get('FAIL_REMOVE'): sys.exit(125)
        containers.pop(args[-1],None); save()
    else: sys.exit(99)
elif name == 'systemctl':
    action=args[1]
    instance=args[-1].removeprefix('evo-model@').removesuffix('.service')
    active=root/('active-'+instance)
    if action == 'start':
        subprocess.run([os.environ['CLI'],'run-selected',instance],check=True)
        active.touch()
    elif action == 'stop':
        active.unlink(missing_ok=True)
        # Simulate ExecStopPost even when the main process has already died.
        subprocess.run([os.environ['CLI'],'cleanup-runtime',instance],check=True)
    elif action == 'is-active':
        if active.exists(): print('active'); sys.exit()
        print('inactive'); sys.exit(3)
    elif action == 'show': print('123')
elif name == 'curl':
    if os.environ.get('CURL_FAIL'): sys.exit(7)
    print(os.environ.get('API_RESPONSE','{"data":[{"id":"/models/model.gguf","object":"model"}]}'))
    if '--write-out' in args: print(os.environ.get('HTTP_STATUS','200'))
    if os.environ.get('DROP_SERVICE_DURING_CURL'):
        for active in root.glob('active-*'): active.unlink()
    if os.environ.get('DROP_CONTAINER_DURING_CURL'):
        for obj in containers.values(): obj['state']='exited'
        save()
elif name == 'ss':
    if os.environ.get('PORT_BUSY'): print('LISTEN 0 4096 0.0.0.0:9123 0.0.0.0:*')
elif name == 'distrobox':
    if args[0]=='list': print('id | legacy-container | Up | image')
elif name == 'id':
    if args == ['-u']: print(os.environ.get('TEST_UID',os.geteuid()))
    elif args == ['-g']: print(os.environ.get('TEST_GID',os.getegid()))
    else: sys.exit(99)
elif name == 'journalctl': pass
else: sys.exit(99)
'''

class Lifecycle(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.profiles = self.root/'profiles'; self.profiles.mkdir()
        self.state = self.root/'state'
        binary = self.root/'bin'; binary.mkdir()
        for command in ('podman','systemctl','curl','ss','distrobox','journalctl','id'):
            target=binary/command; target.write_text(FAKE); target.chmod(0o755)
        self.model = self.root/'models with spaces'/'model.gguf'
        self.model.parent.mkdir(); self.model.touch()
        (self.model.parent/'draft.gguf').touch()
        self.env = dict(os.environ, PATH=str(binary)+':'+os.environ['PATH'],
                        TEST_ROOT=str(self.root), CLI=str(CLI), EVO_MODEL_PROFILE_DIR=str(self.profiles),
                        EVO_MODEL_STATE_DIR=str(self.state), EVO_MODEL_HEALTH_TIMEOUT='1')
        self.profile('gufo-a')

    def profile(self, name, backend='gufo'):
        common=f'PROFILE_NAME={name}\nBACKEND={backend}\nMODEL_PATH={self.model}\nCONTEXT_SIZE=131072\nHOST=127.0.0.1\nPORT=9123\n'
        extra=('GUFO_IMAGE=registry/gufo@sha256:'+'a'*64+'\nCONTAINER_PORT=8081\nSESSIONS=3\nSPEC_TYPE=mtp\nDRAFT_MODEL_PATH='+str(self.model.parent/'draft.gguf')+'\n') if backend=='gufo' else 'CONTAINER=legacy-container\nGPU_LAYERS=99\nPARALLEL_SLOTS=3\n'
        (self.profiles/(name+'.conf')).write_text(common+extra)

    def run_cli(self, *args, ok=True, **env):
        result=subprocess.run([str(CLI),*args],env=dict(self.env,**env),text=True,capture_output=True)
        if ok: self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        else: self.assertNotEqual(result.returncode,0,result.stdout+result.stderr)
        return result

    def calls(self):
        return [json.loads(x) for x in (self.root/'calls').read_text().splitlines()]

    def containers(self):
        p=self.root/'containers'
        return json.loads(p.read_text()) if p.exists() else {}

    def test_command_and_status(self):
        self.run_cli('start','gufo-a')
        run=next(c for c in self.calls() if c[:2]==['podman','run'])
        expected=['gufo','serve','--host','0.0.0.0','--port','8081','llm','--model','/models/model.gguf',
                  '--speculative','mtp','--mtp-model','/models/draft.gguf','--sessions','3','--context','131072']
        self.assertEqual(run[-len(expected):],expected)
        self.assertIn(f'--userns=keep-id:uid={os.geteuid()},gid={os.getegid()}',run)
        self.assertIn('127.0.0.1:9123:8081',run)
        self.assertIn(str(self.model.parent)+':/models:ro',run)
        self.assertIn('--pull=never',run)
        self.assertNotIn('-it',run)
        self.assertEqual((self.state/'gufo-a/selected-profile').read_text(),'gufo-a\n')
        status=json.loads(self.run_cli('status','gufo-a','--json').stdout)['instances']['gufo-a']
        self.assertEqual(status['backend'],'gufo')
        self.assertEqual(status['sessions'],3)
        self.assertEqual(status['context_total'],131072)
        self.assertIsNone(status['context_per_slot'])
        self.assertEqual(status['api'],'ready')
        self.assertEqual(status['container_state'],'running')
        self.assertEqual(status['health_endpoint'],'http://127.0.0.1:9123/v1/models')
        text_status=self.run_cli('status','gufo-a').stdout
        self.assertIn('Sessions: 3',text_status)
        self.assertNotIn('Parallel slots:',text_status)
        self.assertIsNone(status['parallel_slots'])
        self.assertIn('gufo-a',json.loads(self.run_cli('status','--json').stdout)['instances'])
        self.assertIn('selected:gufo-a',self.run_cli('list').stdout)
        self.run_cli('logs','gufo-a','-f')
        self.assertIn(['journalctl','--user','-u','evo-model@gufo-a.service','-f'],self.calls())

    def test_user_namespace_uses_current_uid_and_primary_gid(self):
        self.run_cli('start','gufo-a',TEST_UID='2345',TEST_GID='3456')
        run=next(c for c in self.calls() if c[:2]==['podman','run'])
        self.assertIn('--userns=keep-id:uid=2345,gid=3456',run)
        self.assertNotIn('--userns=keep-id:uid=1000,gid=1000',run)

    def test_stop_restart_isolation_and_missing_profile(self):
        self.profile('gufo-b')
        self.run_cli('start','gufo-a'); self.run_cli('start','gufo-b')
        old=(self.state/'gufo-a/gufo-owner').read_text()
        self.run_cli('restart','gufo-a')
        self.assertNotEqual(old,(self.state/'gufo-a/gufo-owner').read_text())
        # Simulate lost main process, missing cidfile and changed/deleted profile.
        (self.root/'active-gufo-a').unlink()
        (self.state/'gufo-a/gufo.cid').unlink()
        (self.profiles/'gufo-a.conf').unlink()
        self.run_cli('stop','gufo-a'); self.run_cli('stop','gufo-a')
        self.assertEqual([v['labels']['org.evo-model.instance'] for v in self.containers().values()],['gufo-b'])
        self.assertTrue((self.state/'gufo-a/selected-profile').exists())

    def test_cleanup_failures_never_claim_success(self):
        self.run_cli('start','gufo-a')
        for failure in ('FAIL_INSPECT','FAIL_EXISTS','FAIL_REMOVE','BAD_OWNER'):
            self.run_cli('stop','gufo-a',ok=False,**{failure:'1'})
            self.assertTrue((self.state/'gufo-a/gufo-owner').exists())
            self.assertTrue(self.containers())
        self.run_cli('stop','gufo-a')
        self.assertFalse(self.containers())

    def test_health_accepts_real_gufo_response_without_matching_filename(self):
        result=self.run_cli('start','gufo-a',API_RESPONSE=GUFO_MODELS_RESPONSE)
        self.assertIn('API ready:',result.stdout)
        status=self.run_cli('status','gufo-a','--json',API_RESPONSE=GUFO_MODELS_RESPONSE)
        self.assertEqual(json.loads(status.stdout)['instances']['gufo-a']['api'],'ready')
        # Any nonempty model ID is acceptable, including a later list element.
        response='{"data":[null,42,{}, {"id":"unrelated display name","object":"model"}]}'
        self.assertIn('API: ready',self.run_cli('status','gufo-a',API_RESPONSE=response).stdout)

    def test_health_requires_models_json_and_running_container(self):
        self.run_cli('start','gufo-a')
        invalid=('not json', 'null', '[]', '42', '{}', '{"error":"/models/model.gguf"}',
                 '{"data":null}', '{"data":{}}', '{"data":"model"}', '{"data":[]}',
                 '{"data":[null,42,"model",[]]}', '{"data":[{}]}',
                 '{"data":[{"id":"another"}]}', '{"data":[{"object":"model"}]}',
                 '{"data":[{"id":"","object":"model"}]}',
                 '{"data":[{"id":"  ","object":"model"}]}',
                 '{"data":[{"id":123,"object":"model"}]}',
                 '{"data":[{"id":"another","object":"error"}]}')
        for response in invalid:
            with self.subTest(response=response):
                status=self.run_cli('status','gufo-a','--json',API_RESPONSE=response)
                self.assertEqual(json.loads(status.stdout)['instances']['gufo-a']['api'],'not-ready')
        data=self.containers()
        for v in data.values(): v['state']='exited'
        (self.root/'containers').write_text(json.dumps(data))
        self.assertIn('API: not-ready',self.run_cli('status','gufo-a').stdout)

    def test_health_requires_http_200(self):
        self.run_cli('start','gufo-a')
        for code in ('201','204','302','404','503'):
            with self.subTest(code=code):
                status=self.run_cli('status','gufo-a',HTTP_STATUS=code,API_RESPONSE=GUFO_MODELS_RESPONSE)
                self.assertIn('API: not-ready',status.stdout)
        self.assertIn('API: not-ready',self.run_cli('status','gufo-a',CURL_FAIL='1').stdout)

    def test_health_rechecks_service_and_container_after_response(self):
        for failure in ('DROP_SERVICE_DURING_CURL','DROP_CONTAINER_DURING_CURL'):
            with self.subTest(failure=failure):
                self.run_cli('start','gufo-a')
                status=self.run_cli('status','gufo-a',API_RESPONSE=GUFO_MODELS_RESPONSE,**{failure:'1'})
                self.assertIn('API: not-ready',status.stdout)
                self.run_cli('stop','gufo-a')
        self.run_cli('start','gufo-a')
        (self.root/'active-gufo-a').unlink()
        self.assertIn('API: not-ready',self.run_cli('status','gufo-a',API_RESPONSE=GUFO_MODELS_RESPONSE).stdout)

    def test_timeout_cleans_up(self):
        self.run_cli('start','gufo-a',ok=False,API_RESPONSE='{"data":[]}')
        self.assertFalse(self.containers())
        self.assertFalse((self.state/'gufo-a/gufo-owner').exists())

    def test_failed_start_cleans_partial_container(self):
        self.run_cli('start','gufo-a',ok=False,FAIL_RUN='1')
        self.assertFalse(self.containers())
        self.assertFalse((self.state/'gufo-a/gufo-owner').exists())

    def test_separate_mtp_directory_and_no_speculation(self):
        p=self.profiles/'gufo-a.conf'
        draft=self.root/'mtp separate'/'draft.gguf'
        draft.parent.mkdir(); draft.touch()
        p.write_text(p.read_text().replace(str(self.model.parent/'draft.gguf'),str(draft)))
        self.run_cli('start','gufo-a')
        run=next(c for c in self.calls() if c[:2]==['podman','run'])
        self.assertIn(str(draft.parent)+':/mtp:ro',run)
        self.assertIn('/mtp/draft.gguf',run)
        self.run_cli('stop','gufo-a')
        p.write_text('\n'.join(line for line in p.read_text().splitlines() if not line.startswith(('SPEC_TYPE=','DRAFT_MODEL_PATH=')))+'\n')
        self.run_cli('start','gufo-a')
        run=[c for c in self.calls() if c[:2]==['podman','run']][-1]
        self.assertNotIn('--speculative',run)
        self.assertNotIn('--mtp-model',run)

    def test_busy_port_does_not_create_container(self):
        self.run_cli('start','gufo-a',ok=False,PORT_BUSY='1')
        self.assertFalse(self.containers())
        self.assertFalse((self.state/'gufo-a/selected-profile').exists())

    def test_generic_instances_for_legacy_backend(self):
        for backend in ('ROCm','Vulkan','RADV/Vulkan'):
            self.profile('legacy',backend)
            self.run_cli('start','legacy',API_RESPONSE='{"data":[{"id":"model.gguf"}]}')
            self.assertEqual((self.state/'legacy/selected-profile').read_text(),'legacy\n')
            self.run_cli('restart','legacy',API_RESPONSE='{"data":[{"id":"model.gguf"}]}')
            self.run_cli('status','legacy'); self.run_cli('logs','legacy'); self.run_cli('stop','legacy')
        self.assertFalse(any(c[0]=='podman' for c in self.calls()))
        enters=[c for c in self.calls() if c[:2]==['distrobox','enter']]
        self.assertTrue(enters)
        self.assertTrue(all(c[-2:]==['--port','9123'] for c in enters))

    def test_worker_agent_are_backend_independent(self):
        for instance in ('worker','agent'):
            self.run_cli('start',instance,'gufo-a')
            self.assertEqual((self.state/instance/'selected-profile').read_text(),'gufo-a\n')
            self.run_cli('stop',instance)

    def test_reject_unknown_backend_or_incompatible_options(self):
        p=self.profiles/'gufo-a.conf'; original=p.read_text()
        for text in (original.replace('BACKEND=gufo','BACKEND=typo'), original+'GPU_LAYERS=99\n',
                     original.replace('SESSIONS=3','SESSIONS=0'), original.replace('CONTAINER_PORT=8081','CONTAINER_PORT=65536'),
                     original.replace('SPEC_TYPE=mtp','SPEC_TYPE=draft-mtp')):
            p.write_text(text)
            self.run_cli('--validate-profile','gufo-a',ok=False)
        p.write_text(original)
        self.run_cli('--validate-profile','gufo-a')
        self.run_cli('stop','../gufo-a',ok=False)

    def test_unit_has_cleanup_after_main_process_exit(self):
        unit=(ROOT/'systemd/evo-model@.service').read_text()
        self.assertIn('ExecStopPost=%h/.local/bin/evo-model cleanup-runtime %i',unit)
        self.assertIn('KillMode=control-group',unit)

if __name__=='__main__': unittest.main()
