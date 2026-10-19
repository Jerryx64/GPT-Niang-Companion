import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import {RolloutTail, allowedRollout} from './thread-speed.mjs';
import {readApprovalRecords} from './chat-hooks.mjs';

const require = createRequire(import.meta.url);
export class ChatActivity {
  constructor() { this.workState = 'unknown'; this.lastAt = null; this.startedAt = null; this.pendingInput = new Map(); }
  get state() { return this.pendingInput.size ? 'waiting' : this.workState; }
  get waitingKind() { return [...this.pendingInput.values()].some(value => value.kind === 'approval') ? 'approval' : this.pendingInput.size ? 'question' : null; }
  accept(record) {
    const at = Date.parse(record?.timestamp);
    if (!Number.isFinite(at)) return;
    const event = record.payload;
    if (record.type === 'response_item') {
      if (event?.type === 'function_call' && /^(?:functions\.)?request_user_input(?:_async)?$/.test(event.name || '')) {
        this.pendingInput.set(event.call_id, {kind: 'question', async: /_async$/.test(event.name)}); this.lastAt = at;
      } else if (event?.type === 'function_call' && /^(?:functions\.)?request_permissions$/.test(event.name || '')) {
        this.pendingInput.set(event.call_id, {kind: 'approval'}); this.lastAt = at;
      } else if (event?.type === 'function_call_output' && this.pendingInput.has(event.call_id)) {
        const pending = this.pendingInput.get(event.call_id);
        let result; try { result = JSON.parse(event.output); } catch {}
        if (!pending.async || result?.accepted !== true) this.pendingInput.delete(event.call_id);
        this.lastAt = at;
      } else if (event?.type === 'message' && event.role === 'user') {
        const content = (event.content || []).map(item => item.text || '').join('\n');
        const replies = content.match(/call_[A-Za-z0-9]+/g);
        if (content.includes('send_user_message_question_reply') && replies) {
          for (const id of replies) this.pendingInput.delete(id);
        } else {
          for (const [id, pending] of this.pendingInput) if (pending.kind === 'question') this.pendingInput.delete(id);
        }
      }
      return;
    }
    if (record.type !== 'event_msg' || !event) return;
    if (event.type === 'task_started') { this.pendingInput.clear(); this.workState = 'running'; this.startedAt = at; }
    else if (event.type === 'task_complete') { this.pendingInput.clear(); this.workState = event.status === 'failed' ? 'failed' : 'completed'; }
    else if (event.type === 'turn_aborted') { this.pendingInput.clear(); this.workState = 'interrupted'; }
    else if (['exec_approval_request', 'apply_patch_approval_request', 'request_user_input'].includes(event.type)) this.pendingInput.set(event.id || event.call_id || 'event-request', {kind: event.type === 'request_user_input' ? 'question' : 'approval'});
    else if (['approval_response', 'exec_approval_response', 'apply_patch_approval_response'].includes(event.type)) {
      for (const [id, pending] of this.pendingInput) if (pending.kind === 'approval') this.pendingInput.delete(id);
      this.workState = 'running';
    }
    else if (event.type === 'error') this.workState = event.will_retry ? 'running' : 'failed';
    else if (['token_count', 'agent_message', 'agent_reasoning', 'item_completed'].includes(event.type)) {
      if (['unknown', 'failed'].includes(this.workState)) this.workState = 'running';
    } else return;
    this.lastAt = at;
  }
  displayState(now = Date.now()) {
    // An unfinished old log is evidence of an interrupted observation, not a live task.
    return this.state === 'running' && now - this.lastAt > 30 * 60 * 1000 ? 'uncertain' : this.state;
  }
}

export function createChatMonitor(codexHome = process.env.CODEX_HOME || path.join(os.homedir(), '.codex'), dataDir = null) {
  const tails = new Map();
  return {snapshot(now = Date.now()) {
    let db;
    try {
      let DatabaseSync;
      try { ({DatabaseSync} = require('node:sqlite')); }
      catch { throw new Error('聊天面板需要 Node.js 22.13 或更新版本'); }
      const name = fs.readdirSync(codexHome).filter(name => /^state_\d+\.sqlite$/.test(name))
        .sort((a, b) => Number(b.match(/\d+/)[0]) - Number(a.match(/\d+/)[0]))[0];
      if (!name) throw new Error('尚未找到本机 Codex 聊天');
      db = new DatabaseSync(path.join(codexHome, name), {readOnly: true});
      db.exec('PRAGMA busy_timeout=100;');
      const columns = new Set(db.prepare('PRAGMA table_info(threads)').all().map(row => row.name));
      const title = columns.has('name') ? "COALESCE(NULLIF(name,''),title)" : 'title';
      const rows = db.prepare(`SELECT id,${title} AS title,rollout_path,cwd,updated_at FROM threads
        WHERE archived=0 AND source IN ('cli','vscode','appServer','unknown')
        ORDER BY updated_at DESC LIMIT 60`).all();
      const active = new Set();
      const approvals = readApprovalRecords(dataDir);
      const threads = rows.map(row => {
        const output = {id: row.id, title: String(row.title || '未命名聊天').slice(0, 200), cwd: row.cwd,
          state: 'unknown', lastAt: row.updated_at * 1000};
        const file = allowedRollout(row.rollout_path, codexHome);
        if (!file) return output;
        active.add(file);
        try {
          if (!tails.has(file)) tails.set(file, new RolloutTail(file, () => new ChatActivity()));
          const activity = tails.get(file).update();
          const pending = approvals.filter(request => request.threadId === row.id && request.at >= (activity.startedAt || 0) && !['completed', 'interrupted'].includes(activity.state));
          return {...output, state: pending.length ? 'waiting' : activity.displayState(now), startedAt: activity.startedAt,
            waitingKind: pending.length ? 'approval' : activity.waitingKind,
            attentionId: pending.length ? pending.map(request => request.id).join(',') : [...activity.pendingInput.keys()].join(','),
            lastAt: activity.lastAt || output.lastAt};
        } catch { return output; }
      });
      for (const file of tails.keys()) if (!active.has(file)) tails.delete(file);
      const priority = {waiting: 0, failed: 1, running: 2, uncertain: 3, completed: 4, interrupted: 5, unknown: 6};
      threads.sort((a, b) => priority[a.state] - priority[b.state] || (a.waitingKind === 'approval' ? 0 : 1) - (b.waitingKind === 'approval' ? 0 : 1) || b.lastAt - a.lastAt);
      return {ok: true, at: now, threads: threads.slice(0, 30), error: null};
    } catch (error) {
      return {ok: false, at: now, threads: [], error: error.code === 'SQLITE_BUSY' ? '聊天列表忙碌，稍后重试' :
        /^聊天面板|^尚未找到/.test(error.message) ? error.message : '暂时无法读取本机聊天'};
    } finally { try { db?.close(); } catch {} }
  }};
}
if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  console.log(JSON.stringify(createChatMonitor().snapshot()));
}
