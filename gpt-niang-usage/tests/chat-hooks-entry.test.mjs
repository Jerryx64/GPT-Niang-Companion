import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

test('Windows hook entry records approval metadata and never grants a permission', {skip:process.platform !== 'win32'}, t => {
  const plugin = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'GPT娘 hook test '));
  t.after(() => fs.rmSync(fixture, {recursive:true,force:true}));
  const root = path.join(fixture, 'plugin with spaces');
  const dataDir = path.join(fixture, 'state');
  fs.cpSync(path.join(plugin, 'runtime'), path.join(root, 'runtime'), {recursive:true});
  fs.cpSync(path.join(plugin, '.codex-plugin'), path.join(root, '.codex-plugin'), {recursive:true});
  fs.writeFileSync(path.join(root, 'installation.json'), JSON.stringify({dataDir}));
  const hooks = JSON.parse(fs.readFileSync(path.join(plugin, 'hooks', 'hooks.json'), 'utf8')).hooks;
  const tool = {session_id:'test_hook_entry',turn_id:'test_turn',tool_name:'Bash',tool_input:{command:'echo private-command'}};
  const records = () => fs.existsSync(path.join(dataDir,'chat-approvals')) ? fs.readdirSync(path.join(dataDir,'chat-approvals')) : [];
  const invoke = event => {
    const result = spawnSync(hooks[event][0].hooks[0].commandWindows, {
      encoding:'utf8',input:JSON.stringify({...tool,hook_event_name:event}),windowsHide:true,
      env:{...process.env,PLUGIN_ROOT:root},timeout:3000,shell:process.env.ComSpec || 'cmd.exe'
    });
    assert.equal(result.status,0,result.stderr);
    assert.deepEqual(JSON.parse(result.stdout),{});
    assert.equal(JSON.parse(fs.readFileSync(path.join(dataDir,'chat-hook-health.json'),'utf8')).event,event);
  };
  invoke('PermissionRequest');
  assert.equal(records().length,1);
  const record = fs.readFileSync(path.join(dataDir,'chat-approvals',records()[0]),'utf8');
  assert.equal(record.includes('private-command'),false);
  assert.equal(record.includes('decision'),false);
  invoke('PostToolUse');
  assert.equal(records().length,0);
  invoke('PermissionRequest');
  invoke('Stop');
  assert.equal(records().length,0);
  invoke('PermissionRequest');
  invoke('Interrupt');
  assert.equal(records().length,0);
});
