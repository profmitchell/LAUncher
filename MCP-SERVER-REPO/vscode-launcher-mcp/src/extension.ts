import * as fs from 'fs';
import * as path from 'path';
import * as vscode from 'vscode';
import { LauncherMcpWebviewViewProvider } from './configWebview';
import * as mcp from './mcpService';
import { log, outputChannel } from './log';
import { getCursorMcpPath, getWorkspaceMcpPath } from './paths';

export function activate(context: vscode.ExtensionContext): void {
  context.subscriptions.push(outputChannel);

  const provider = new LauncherMcpWebviewViewProvider(context.extensionUri);
  context.subscriptions.push(
    vscode.window.registerWebviewViewProvider(LauncherMcpWebviewViewProvider.viewType, provider)
  );

  const run = async (fn: () => Promise<{ ok: boolean; message: string }>, useWindow = true) => {
    const r = await fn();
    if (useWindow) {
      if (r.ok) {
        vscode.window.showInformationMessage(`LAUncher MCP: ${r.message}`);
      } else {
        vscode.window.showErrorMessage(`LAUncher MCP: ${r.message}`);
      }
    }
  };

  context.subscriptions.push(
    vscode.commands.registerCommand('launcherMcp.openSetup', async () => {
      await vscode.commands.executeCommand('workbench.view.extension.launcher-mcp');
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand('launcherMcp.showOutput', () => {
      outputChannel.show(true);
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand('launcherMcp.setupVsCodeWorkspace', () =>
      run(() => mcp.setupWorkspace())
    )
  );

  context.subscriptions.push(
    vscode.commands.registerCommand('launcherMcp.setupVsCodeUser', () => run(() => mcp.setupVsCodeUser()))
  );

  context.subscriptions.push(
    vscode.commands.registerCommand('launcherMcp.setupCursorUser', () => run(() => mcp.setupCursor()))
  );

  context.subscriptions.push(
    vscode.commands.registerCommand('launcherMcp.removeFromConfigs', () => run(() => mcp.removeAll()))
  );

  context.subscriptions.push(
    vscode.commands.registerCommand('launcherMcp.testServer', () => run(() => mcp.runTest()))
  );

  context.subscriptions.push(
    vscode.commands.registerCommand('launcherMcp.diagnose', async () => {
      await mcp.runDiagnose();
      vscode.window.showInformationMessage('LAUncher MCP: Diagnose finished — see Output → LAUncher MCP');
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand('launcherMcp.openWorkspaceMcp', async () => {
      const ws = getWorkspaceMcpPath();
      if (!ws) {
        vscode.window.showErrorMessage('LAUncher MCP: Open a folder first.');
        return;
      }
      if (!fs.existsSync(ws)) {
        const create = await vscode.window.showInformationMessage(
          '.vscode/mcp.json does not exist yet.',
          'Create from LAUncher MCP'
        );
        if (create === 'Create from LAUncher MCP') {
          const r = await mcp.setupWorkspace();
          if (!r.ok) {
            vscode.window.showErrorMessage(`LAUncher MCP: ${r.message}`);
            return;
          }
        }
      }
      if (fs.existsSync(ws)) {
        const doc = await vscode.workspace.openTextDocument(ws);
        await vscode.window.showTextDocument(doc);
      }
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand('launcherMcp.openCursorMcp', async () => {
      const p = getCursorMcpPath();
      if (!fs.existsSync(p)) {
        vscode.window.showWarningMessage(`File does not exist yet: ${p}`);
      }
      const uri = vscode.Uri.file(p);
      const doc = await vscode.workspace.openTextDocument(uri);
      await vscode.window.showTextDocument(doc);
    })
  );
}

export function deactivate(): void {
  //
}
