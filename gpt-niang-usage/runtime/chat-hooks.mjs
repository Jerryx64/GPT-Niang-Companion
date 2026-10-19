import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {atomicJson} from './usage.mjs';

const safeId = value => typeof value === 'string' && /^[a-zA-Z0-9_-]{1,120}$/.test(value);
export function readApprovalRecords(dataDir) {
  if (!dataDir) return [];
  const directory = path.join(dataDir, 'chat-approvals');
  try { return fs.readdirSync(directory).filter(name => /^thread-[a-zA-Z0-9_-]+--[a-f0-9]{32}\.json$/.test(name)).slice(0, 256).flatMap(name => {
    try { const file = path.join(directory, name); if (fs.statSync(file).size > 4096) return [];
      const value = JSON.parse(fs.readFileSync(file, 'utf8'));
      return safeId(value.threadId) && typeof value.id === 'string' && /^[a-f0-9]{32}$/.test(value.id) && Number.isFinite(value.at) ? [value] : [];
    } catch { return []; }
  }); } catch { return []; }
}
export function recordChatHook(input, dataDir, now = Date.now()) {
  if (!safeId(input?.session_id) || !dataDir) return;
  const event = input.hook_event_name;
  if (!['PermissionRequest', 'PostToolUse', 'Stop', 'Interrupt'].includes(event)) return;
  const directory = path.join(dataDir, 'chat-approvals');
  const prefix = 'thread-' + input.session_id + '--';
  if (event === 'Stop' || event === 'Interrupt') {
    for (const value of readApprovalRecords(dataDir)) {
      if (value.threadId === input.session_id && (!input.turn_id || value.turnId === input.turn_id)) {
        try { fs.unlinkSync(path.join(directory, prefix + value.id + '.json')); } catch {}
      }
    }
  } else {
    // PermissionRequest has no tool_use_id. Correlate the same tool input without persisting commands or arguments.
    const content = input.tool_input && typeof input.tool_input === 'object'
      ? Object.fromEntries(Object.entries(input.tool_input).filter(([key]) => key !== 'description').sort(([a], [b]) => a.localeCompare(b))) : input.tool_input;
    const id = createHash('sha256').update(JSON.stringify([input.turn_id || '', input.tool_name, content])).digest('hex').slice(0, 32);
    const file = path.join(directory, prefix + id + '.json');
    if (event === 'PermissionRequest') atomicJson(file, {id, threadId: input.session_id, turnId: input.turn_id || null, at: now, kind: 'approval'});
    else { try { fs.unlinkSync(file); } catch {} }
  }
  atomicJson(path.join(dataDir, 'chat-hook-health.json'), {at: now, event, version: 1});
}
export async function runChatHook() {
  try {
    let text = '';
    for await (const chunk of process.stdin) { text += chunk; if (text.length > 2 * 1024 * 1024) throw new Error('Input too large'); }
    const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
    const config = JSON.parse(fs.readFileSync(path.join(root, 'installation.json'), 'utf8').replace(/^\uFEFF/, ''));
    recordChatHook(JSON.parse(text), config.dataDir);
  } catch {}
  // Informational only. Never approve, deny, rewrite or continue a Codex operation.
  process.stdout.write('{}\n');
}
if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) await runChatHook();
