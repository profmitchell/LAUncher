import * as child_process from 'child_process';
import * as fs from 'fs';
import * as http from 'http';
import * as path from 'path';
import * as vscode from 'vscode';
import { readJsonFile, writeJsonFile } from './jsonConfig';
import { log, outputChannel } from './log';
import {
  getCursorMcpPath,
  getVsCodeUserMcpPath,
  getWorkspaceMcpPath,
  resolveServerScriptPath,
  scriptUnderWorkspace,
} from './paths';

export type UiState = {
  serverScriptPath: string;
  nodeExecutable: string;
  vsCodeServerKey: string;
  cursorServerKey: string;
  devWatchGlob: string;
  resolvedScriptPath: string | null;
  scriptExists: boolean;
  workspaceFolder: string | null;
  workspaceMcpPath: string | null;
  workspaceMcpExists: boolean;
  vsCodeUserMcpPath: string | null;
  vsCodeUserMcpExists: boolean;
  cursorMcpPath: string;
  cursorMcpExists: boolean;
  nodeVersion: string | null;
  nodeCheckError: string | null;
};

function configScope(): vscode.Uri | null {
  return vscode.workspace.workspaceFolders?.[0]?.uri ?? null;
}

function getCfg(): vscode.WorkspaceConfiguration {
  return vscode.workspace.getConfiguration('launcherMcp', configScope());
}

export function getNode(): string {
  return getCfg().get<string>('nodeExecutable')?.trim() || 'node';
}

export function getVsCodeServerKey(): string {
  return getCfg().get<string>('vsCodeServerKey')?.trim() || 'launcher';
}

export function getCursorServerKey(): string {
  return getCfg().get<string>('cursorServerKey')?.trim() || 'launcher';
}

function getDevWatchGlob(): string {
  return getCfg().get<string>('devWatchGlob')?.trim() ?? '';
}

function buildVsCodeServerEntry(scriptPath: string, node: string): Record<string, unknown> {
  const entry: Record<string, unknown> = {
    type: 'stdio',
    command: node,
    args: [scriptPath],
  };
  const folder = vscode.workspace.workspaceFolders?.[0];
  const watchGlob = getDevWatchGlob();
  if (folder && watchGlob && scriptUnderWorkspace(scriptPath)) {
    entry.dev = { watch: watchGlob };
  }
  return entry;
}

export function mergeVsCodeMcp(filePath: string, serverKey: string, scriptPath: string, node: string): void {
  const data = readJsonFile(filePath);
  const servers = { ...((data.servers as Record<string, unknown>) ?? {}) };
  servers[serverKey] = buildVsCodeServerEntry(scriptPath, node);
  data.servers = servers;
  writeJsonFile(filePath, data);
}

export function mergeCursorMcp(filePath: string, serverKey: string, scriptPath: string, node: string): void {
  const data = readJsonFile(filePath);
  const mcpServers = { ...((data.mcpServers as Record<string, unknown>) ?? {}) };
  mcpServers[serverKey] = {
    command: node,
    args: [scriptPath],
  };
  data.mcpServers = mcpServers;
  writeJsonFile(filePath, data);
}

function deleteServerKeyVsCode(data: Record<string, unknown>, key: string): boolean {
  const servers = (data.servers as Record<string, unknown>) ?? {};
  if (!(key in servers)) {
    return false;
  }
  delete servers[key];
  data.servers = servers;
  return true;
}

function deleteServerKeyCursor(data: Record<string, unknown>, key: string): boolean {
  const mcpServers = (data.mcpServers as Record<string, unknown>) ?? {};
  if (!(key in mcpServers)) {
    return false;
  }
  delete mcpServers[key];
  data.mcpServers = mcpServers;
  return true;
}

export async function resolveScriptForInstall(): Promise<string | undefined> {
  return resolveServerScriptPath();
}

export async function getUiState(): Promise<UiState> {
  const cfg = getCfg();
  const serverScriptPath = cfg.get<string>('serverScriptPath') ?? '';
  const nodeExecutable = cfg.get<string>('nodeExecutable') ?? 'node';
  const vsCodeServerKey = cfg.get<string>('vsCodeServerKey') ?? 'launcher';
  const cursorServerKey = cfg.get<string>('cursorServerKey') ?? 'launcher';
  const devWatchGlob = cfg.get<string>('devWatchGlob') ?? '**/launcher-server.js';

  const resolved = await resolveServerScriptPath();
  const manual = serverScriptPath.trim();
  const scriptExists = resolved ? fs.existsSync(resolved) : false;

  let nodeVersion: string | null = null;
  let nodeCheckError: string | null = null;
  try {
    nodeVersion = child_process.execFileSync(nodeExecutable.trim() || 'node', ['-v'], { encoding: 'utf8' }).trim();
  } catch (e) {
    nodeCheckError = (e as Error).message;
  }

  const ws = getWorkspaceMcpPath();
  const user = getVsCodeUserMcpPath();
  const cur = getCursorMcpPath();

  return {
    serverScriptPath: manual,
    nodeExecutable: nodeExecutable.trim() || 'node',
    vsCodeServerKey: vsCodeServerKey.trim() || 'launcher',
    cursorServerKey: cursorServerKey.trim() || 'launcher',
    devWatchGlob,
    resolvedScriptPath: resolved ?? null,
    scriptExists,
    workspaceFolder: vscode.workspace.workspaceFolders?.[0]?.uri.fsPath ?? null,
    workspaceMcpPath: ws ?? null,
    workspaceMcpExists: ws ? fs.existsSync(ws) : false,
    vsCodeUserMcpPath: user ?? null,
    vsCodeUserMcpExists: user ? fs.existsSync(user) : false,
    cursorMcpPath: cur,
    cursorMcpExists: fs.existsSync(cur),
    nodeVersion,
    nodeCheckError,
  };
}

export async function saveSettingsFromUi(fields: {
  serverScriptPath: string;
  nodeExecutable: string;
  vsCodeServerKey: string;
  cursorServerKey: string;
  devWatchGlob: string;
}): Promise<void> {
  const scope = configScope();
  const target = scope ? vscode.ConfigurationTarget.Workspace : vscode.ConfigurationTarget.Global;
  const cfg = getCfg();
  await cfg.update('serverScriptPath', fields.serverScriptPath, target);
  await cfg.update('nodeExecutable', fields.nodeExecutable, target);
  await cfg.update('vsCodeServerKey', fields.vsCodeServerKey, target);
  await cfg.update('cursorServerKey', fields.cursorServerKey, target);
  await cfg.update('devWatchGlob', fields.devWatchGlob, target);
}

export async function pickServerScript(): Promise<void> {
  const picked = await vscode.window.showOpenDialog({
    canSelectFiles: true,
    canSelectFolders: false,
    canSelectMany: false,
    filters: { JavaScript: ['js'], 'All': ['*'] },
    title: 'Select launcher-server.js',
  });
  if (!picked?.[0]) {
    return;
  }
  const cfg = getCfg();
  const target = configScope() ? vscode.ConfigurationTarget.Workspace : vscode.ConfigurationTarget.Global;
  await cfg.update('serverScriptPath', picked[0].fsPath, target);
}

export async function setupWorkspace(): Promise<{ ok: boolean; message: string }> {
  const script = await resolveScriptForInstall();
  if (!script) {
    return { ok: false, message: 'Could not find launcher-server.js. Set path or open the LAUncher repo.' };
  }
  const ws = getWorkspaceMcpPath();
  if (!ws) {
    return { ok: false, message: 'Open a folder in the editor first.' };
  }
  mergeVsCodeMcp(ws, getVsCodeServerKey(), script, getNode());
  log(`Wrote VS Code workspace MCP: ${ws}`);
  return { ok: true, message: `Updated ${path.join('.vscode', 'mcp.json')}. Reload the window if the agent does not see it.` };
}

export async function setupVsCodeUser(): Promise<{ ok: boolean; message: string }> {
  const script = await resolveScriptForInstall();
  if (!script) {
    return { ok: false, message: 'Could not find launcher-server.js.' };
  }
  const userPath = getVsCodeUserMcpPath();
  if (!userPath) {
    return { ok: false, message: 'Could not resolve VS Code user mcp.json path.' };
  }
  mergeVsCodeMcp(userPath, getVsCodeServerKey(), script, getNode());
  log(`Wrote VS Code user MCP: ${userPath}`);
  return { ok: true, message: `Updated user mcp.json: ${userPath}` };
}

export async function setupCursor(): Promise<{ ok: boolean; message: string }> {
  const script = await resolveScriptForInstall();
  if (!script) {
    return { ok: false, message: 'Could not find launcher-server.js.' };
  }
  mergeCursorMcp(getCursorMcpPath(), getCursorServerKey(), script, getNode());
  log(`Wrote Cursor MCP: ${getCursorMcpPath()}`);
  return { ok: true, message: 'Updated ~/.cursor/mcp.json. Restart Cursor to load MCP.' };
}

export async function removeAll(): Promise<{ ok: boolean; message: string }> {
  const vsKey = getVsCodeServerKey();
  const curKey = getCursorServerKey();
  const touched: string[] = [];

  const ws = getWorkspaceMcpPath();
  if (ws && fs.existsSync(ws)) {
    const d = readJsonFile(ws);
    if (deleteServerKeyVsCode(d, vsKey)) {
      writeJsonFile(ws, d);
      touched.push(ws);
    }
  }

  const userPath = getVsCodeUserMcpPath();
  if (userPath && fs.existsSync(userPath)) {
    const d = readJsonFile(userPath);
    if (deleteServerKeyVsCode(d, vsKey)) {
      writeJsonFile(userPath, d);
      touched.push(userPath);
    }
  }

  const cursorPath = getCursorMcpPath();
  if (fs.existsSync(cursorPath)) {
    const d = readJsonFile(cursorPath);
    if (deleteServerKeyCursor(d, curKey)) {
      writeJsonFile(cursorPath, d);
      touched.push(cursorPath);
    }
  }

  if (touched.length === 0) {
    return { ok: true, message: 'No matching server entries found.' };
  }
  log(`Removed server keys from:\n${touched.join('\n')}`);
  return { ok: true, message: `Removed from ${touched.length} file(s).` };
}

export function runToolsListSmoke(scriptPath: string, node: string): Promise<{ ok: boolean; detail: string }> {
  const payload = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}\n';
  return new Promise((resolve) => {
    const proc = child_process.spawn(node, [scriptPath], {
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    let buf = '';
    let err = '';
    let settled = false;
    const finish = (ok: boolean, detail: string) => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      try {
        proc.kill('SIGTERM');
      } catch {
        //
      }
      resolve({ ok, detail });
    };

    const timer = setTimeout(() => finish(false, 'timeout after 8s'), 8000);

    proc.stdout?.on('data', (c) => {
      buf += c.toString();
      for (const line of buf.split('\n')) {
        const t = line.trim();
        if (!t) {
          continue;
        }
        try {
          const j = JSON.parse(t) as { result?: { tools?: unknown[] } };
          if (j.result?.tools && Array.isArray(j.result.tools)) {
            finish(true, `${j.result.tools.length} tools`);
            return;
          }
        } catch {
          //
        }
      }
    });
    proc.stderr?.on('data', (c) => (err += c.toString()));
    proc.on('error', (e) => finish(false, (e as Error).message));
    proc.on('close', (code) => {
      if (settled) {
        return;
      }
      finish(false, `exit ${code}. stderr: ${err.slice(0, 400)}`);
    });
    proc.stdin?.write(payload);
    proc.stdin?.end();
  });
}

export function checkHttpHealth(): Promise<{ ok: boolean; detail: string }> {
  return new Promise((resolve) => {
    const req = http.get('http://127.0.0.1:5555/health', { timeout: 2000 }, (res) => {
      let body = '';
      res.on('data', (c) => (body += c));
      res.on('end', () => {
        resolve({ ok: res.statusCode === 200, detail: `HTTP ${res.statusCode} ${body.slice(0, 120)}` });
      });
    });
    req.on('error', (e) => resolve({ ok: false, detail: (e as Error).message }));
    req.on('timeout', () => {
      req.destroy();
      resolve({ ok: false, detail: 'timeout' });
    });
  });
}

export async function runTest(): Promise<{ ok: boolean; message: string }> {
  const script = await resolveScriptForInstall();
  if (!script) {
    return { ok: false, message: 'No launcher-server.js resolved.' };
  }
  const node = getNode();
  log(`Smoke test: ${node} ${script}`);
  const r = await runToolsListSmoke(script, node);
  if (r.ok) {
    log(`OK — ${r.detail}`);
    return { ok: true, message: `tools/list OK (${r.detail})` };
  }
  log(`FAIL — ${r.detail}`);
  return { ok: false, message: r.detail };
}

export async function runDiagnose(): Promise<{ lines: string[] }> {
  outputChannel.show(true);
  const lines: string[] = [];
  const push = (s: string) => {
    lines.push(s);
    log(s);
  };

  push('--- LAUncher MCP diagnose ---');
  const script = await resolveServerScriptPath();
  push(`launcher-server.js: ${script ?? '(not found)'}`);
  push(`Workspace MCP: ${getWorkspaceMcpPath() ?? '(no folder)'}`);
  push(`VS Code user MCP: ${getVsCodeUserMcpPath() ?? '(unknown)'}`);
  push(`Cursor MCP: ${getCursorMcpPath()}`);

  const node = getNode();
  try {
    const v = child_process.execFileSync(node, ['-v'], { encoding: 'utf8' }).trim();
    push(`Node: ${v} (${node})`);
  } catch (e) {
    push(`Node: FAILED — ${(e as Error).message}`);
  }

  if (script) {
    const smoke = await runToolsListSmoke(script, node);
    push(`tools/list: ${smoke.ok ? 'OK' : 'FAIL'} — ${smoke.detail}`);
  }

  const health = await checkHttpHealth();
  push(`LAUncher HTTP /health (5555): ${health.ok ? 'OK' : 'FAIL'} — ${health.detail}`);
  push('--- end ---');
  return { lines };
}
