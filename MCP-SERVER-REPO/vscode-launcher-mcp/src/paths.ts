import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import * as vscode from 'vscode';

export function getCursorMcpPath(): string {
  return path.join(os.homedir(), '.cursor', 'mcp.json');
}

/** VS Code / Insiders user mcp.json (best-effort; profiles may relocate this). */
export function getVsCodeUserMcpPath(): string | undefined {
  const home = os.homedir();
  const isInsiders = vscode.env.appName.toLowerCase().includes('insiders');
  if (process.platform === 'darwin') {
    const dir = isInsiders ? 'Code - Insiders' : 'Code';
    return path.join(home, 'Library', 'Application Support', dir, 'User', 'mcp.json');
  }
  if (process.platform === 'win32') {
    const appData = process.env.APPDATA;
    if (!appData) {
      return undefined;
    }
    const dir = isInsiders ? 'Code - Insiders' : 'Code';
    return path.join(appData, dir, 'User', 'mcp.json');
  }
  const dir = isInsiders ? 'code-insiders' : 'code';
  return path.join(home, '.config', dir, 'User', 'mcp.json');
}

export function getWorkspaceMcpPath(): string | undefined {
  const folder = vscode.workspace.workspaceFolders?.[0];
  if (!folder) {
    return undefined;
  }
  return path.join(folder.uri.fsPath, '.vscode', 'mcp.json');
}

export async function resolveServerScriptPath(): Promise<string | undefined> {
  const cfg = vscode.workspace.getConfiguration('launcherMcp');
  const manual = (cfg.get<string>('serverScriptPath') ?? '').trim();
  if (manual) {
    return fs.existsSync(manual) ? manual : undefined;
  }

  const matches = await vscode.workspace.findFiles(
    '**/launcher-server.js',
    '**/node_modules/**',
    15
  );
  if (matches.length === 0) {
    return undefined;
  }

  const needleLa = path.join('LAUncher', 'dev', 'mcp');
  const inLa = matches.find((u) => u.fsPath.includes(needleLa));
  if (inLa) {
    return inLa.fsPath;
  }
  const inMcpDir = matches.find((u) => /[/\\]mcp[/\\]launcher-server\.js$/.test(u.fsPath));
  return (inMcpDir ?? matches[0]).fsPath;
}

export function scriptUnderWorkspace(scriptPath: string): boolean {
  const folder = vscode.workspace.workspaceFolders?.[0];
  if (!folder) {
    return false;
  }
  const root = folder.uri.fsPath;
  const norm = path.normalize(scriptPath);
  return norm.startsWith(root + path.sep) || norm === root;
}
