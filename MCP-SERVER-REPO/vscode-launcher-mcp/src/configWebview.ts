import * as vscode from 'vscode';
import * as mcp from './mcpService';

export class LauncherMcpWebviewViewProvider implements vscode.WebviewViewProvider {
  public static readonly viewType = 'launcherMcp.config';

  private view?: vscode.WebviewView;

  constructor(private readonly extensionUri: vscode.Uri) {}

  resolveWebviewView(
    webviewView: vscode.WebviewView,
    _context: vscode.WebviewViewResolveContext,
    _token: vscode.CancellationToken
  ): void {
    this.view = webviewView;
    webviewView.webview.options = {
      enableScripts: true,
      localResourceRoots: [this.extensionUri],
    };

    webviewView.webview.html = this.getHtml(webviewView.webview);

    webviewView.webview.onDidReceiveMessage(async (msg) => {
      switch (msg.type) {
        case 'refresh':
          await this.pushState();
          break;
        case 'saveSettings':
          await mcp.saveSettingsFromUi(msg.payload);
          await this.pushState();
          this.postResult(true, 'Settings saved.');
          break;
        case 'pickScript':
          await mcp.pickServerScript();
          await this.pushState();
          break;
        case 'setupWorkspace': {
          const r = await mcp.setupWorkspace();
          await this.pushState();
          this.postResult(r.ok, r.message);
          break;
        }
        case 'setupVsCodeUser': {
          const r = await mcp.setupVsCodeUser();
          await this.pushState();
          this.postResult(r.ok, r.message);
          break;
        }
        case 'setupCursor': {
          const r = await mcp.setupCursor();
          await this.pushState();
          this.postResult(r.ok, r.message);
          break;
        }
        case 'removeAll': {
          const r = await mcp.removeAll();
          await this.pushState();
          this.postResult(r.ok, r.message);
          break;
        }
        case 'test': {
          const r = await mcp.runTest();
          await this.pushState();
          this.postResult(r.ok, r.message);
          break;
        }
        case 'diagnose': {
          const { lines } = await mcp.runDiagnose();
          webviewView.webview.postMessage({ type: 'diagnose', lines });
          break;
        }
        case 'openOutput':
          await vscode.commands.executeCommand('launcherMcp.showOutput');
          break;
        case 'openWorkspaceMcp':
          await vscode.commands.executeCommand('launcherMcp.openWorkspaceMcp');
          break;
        case 'openCursorMcp':
          await vscode.commands.executeCommand('launcherMcp.openCursorMcp');
          break;
        case 'openSettings':
          await vscode.commands.executeCommand(
            'workbench.action.openSettings',
            'launcherMcp'
          );
          break;
        default:
          break;
      }
    });

    webviewView.onDidChangeVisibility(async () => {
      if (webviewView.visible) {
        await this.pushState();
      }
    });

    void this.pushState();
  }

  private postResult(ok: boolean, message: string): void {
    this.view?.webview.postMessage({ type: 'result', ok, message });
  }

  private async pushState(): Promise<void> {
    const payload = await mcp.getUiState();
    this.view?.webview.postMessage({ type: 'state', payload });
  }

  private getHtml(webview: vscode.Webview): string {
    const nonce = String(Date.now());
    const csp = [
      `default-src 'none'`,
      `style-src ${webview.cspSource} 'unsafe-inline'`,
      `script-src 'nonce-${nonce}'`,
    ].join('; ');

    return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta http-equiv="Content-Security-Policy" content="${csp}" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <style>
    :root {
      font-family: var(--vscode-font-family);
      font-size: var(--vscode-font-size);
      color: var(--vscode-foreground);
    }
    body {
      margin: 0;
      padding: 10px 12px 16px;
      line-height: 1.45;
    }
    h1 {
      font-size: 1.05em;
      font-weight: 600;
      margin: 0 0 10px;
      letter-spacing: 0.02em;
    }
    .hint {
      opacity: 0.85;
      font-size: 0.92em;
      margin-bottom: 12px;
    }
    section {
      margin-bottom: 14px;
      padding-bottom: 12px;
      border-bottom: 1px solid var(--vscode-widget-border, rgba(128,128,128,.35));
    }
    section:last-of-type { border-bottom: none; }
    label {
      display: block;
      font-size: 0.85em;
      margin-top: 8px;
      margin-bottom: 3px;
      opacity: 0.92;
    }
    input[type="text"] {
      width: 100%;
      box-sizing: border-box;
      padding: 5px 7px;
      border: 1px solid var(--vscode-input-border, #555);
      background: var(--vscode-input-background);
      color: var(--vscode-input-foreground);
      border-radius: 2px;
    }
    .row { display: flex; gap: 6px; flex-wrap: wrap; align-items: center; margin-top: 6px; }
    button {
      font-family: inherit;
      font-size: var(--vscode-font-size);
      padding: 5px 10px;
      border-radius: 2px;
      border: 1px solid var(--vscode-button-border, transparent);
      background: var(--vscode-button-secondaryBackground);
      color: var(--vscode-button-secondaryForeground);
      cursor: pointer;
    }
    button.primary {
      background: var(--vscode-button-background);
      color: var(--vscode-button-foreground);
    }
    button:disabled { opacity: 0.45; cursor: default; }
    .pill {
      display: inline-block;
      font-size: 0.78em;
      padding: 2px 7px;
      border-radius: 8px;
      margin-left: 6px;
      vertical-align: middle;
    }
    .ok { background: var(--vscode-testing-iconPassed, #3fb950); color: #fff; }
    .bad { background: var(--vscode-testing-iconFailed, #f85149); color: #fff; }
    .path {
      font-size: 0.82em;
      word-break: break-all;
      opacity: 0.9;
      margin: 4px 0;
    }
    #toast {
      margin-top: 10px;
      padding: 8px 10px;
      border-radius: 3px;
      font-size: 0.9em;
      display: none;
    }
    #toast.show { display: block; }
    #toast.ok { background: color-mix(in srgb, var(--vscode-testing-iconPassed, #3fb950) 25%, transparent); }
    #toast.err { background: color-mix(in srgb, var(--vscode-testing-iconFailed, #f85149) 25%, transparent); }
    #diag {
      margin-top: 8px;
      font-size: 0.78em;
      white-space: pre-wrap;
      max-height: 140px;
      overflow: auto;
      padding: 6px 8px;
      background: var(--vscode-textBlockQuote-background);
      border: 1px solid var(--vscode-widget-border, #444);
      border-radius: 2px;
      display: none;
    }
    #diag.show { display: block; }
  </style>
</head>
<body>
  <h1>LAUncher MCP</h1>
  <p class="hint">Wire <code>launcher-server.js</code> into VS Code or Cursor MCP, then smoke-test the server and LAUncher’s HTTP API.</p>

  <section>
    <strong>Resolved script</strong>
    <span id="scriptPill" class="pill"></span>
    <div class="path" id="resolvedPath"></div>
    <div class="row">
      <button type="button" id="pick">Browse…</button>
      <button type="button" id="clearPath">Clear saved path</button>
    </div>
    <label for="manualPath">Saved path (optional, overrides search)</label>
    <input type="text" id="manualPath" placeholder="Leave empty to auto-detect in workspace" autocomplete="off" />
  </section>

  <section>
    <strong>Tooling</strong>
    <label for="nodeExe">Node executable</label>
    <input type="text" id="nodeExe" autocomplete="off" />
    <label for="vsKey">VS Code server id (<code>servers</code> key)</label>
    <input type="text" id="vsKey" autocomplete="off" />
    <label for="curKey">Cursor server id (<code>mcpServers</code> key)</label>
    <input type="text" id="curKey" autocomplete="off" />
    <label for="watchGlob">dev.watch glob (VS Code only, empty to skip)</label>
    <input type="text" id="watchGlob" autocomplete="off" />
    <div class="row" style="margin-top:10px">
      <button type="button" class="primary" id="save">Save settings</button>
      <button type="button" id="openVsSettings">Open in Settings UI</button>
    </div>
  </section>

  <section>
    <strong>Install MCP entry</strong>
    <div class="row">
      <button type="button" class="primary" id="btnWs">Workspace .vscode/mcp.json</button>
      <button type="button" id="btnUser">VS Code user mcp.json</button>
    </div>
    <div class="row">
      <button type="button" id="btnCursor">Cursor ~/.cursor/mcp.json</button>
    </div>
  </section>

  <section>
    <strong>Verify &amp; files</strong>
    <div class="row">
      <button type="button" id="btnTest">Smoke test (tools/list)</button>
      <button type="button" id="btnDiag">Run diagnose</button>
    </div>
    <div class="row">
      <button type="button" id="btnOpenWs">Open workspace mcp.json</button>
      <button type="button" id="btnOpenCur">Open Cursor mcp.json</button>
      <button type="button" id="btnOut">Output log</button>
    </div>
    <div id="diag"></div>
  </section>

  <section>
    <strong>Maintain</strong>
    <div class="row">
      <button type="button" id="btnRemove">Remove server from all configs</button>
      <button type="button" id="btnRefresh">Refresh status</button>
    </div>
    <div class="path" id="statusLines"></div>
  </section>

  <div id="toast"></div>

  <script nonce="${nonce}">
    const vscode = acquireVsCodeApi();

    function el(id) { return document.getElementById(id); }

    function showToast(ok, text) {
      const t = el('toast');
      t.className = 'show ' + (ok ? 'ok' : 'err');
      t.textContent = text;
      clearTimeout(showToast._tm);
      showToast._tm = setTimeout(() => { t.className = ''; t.textContent = ''; }, 6000);
    }

    function applyState(s) {
      el('manualPath').value = s.serverScriptPath || '';
      el('nodeExe').value = s.nodeExecutable || 'node';
      el('vsKey').value = s.vsCodeServerKey || 'launcher';
      el('curKey').value = s.cursorServerKey || 'launcher';
      el('watchGlob').value = s.devWatchGlob || '';

      const rp = s.resolvedScriptPath || '(none — set path or open repo)';
      el('resolvedPath').textContent = rp;

      const pill = el('scriptPill');
      pill.textContent = s.scriptExists ? 'OK' : 'Missing';
      pill.className = 'pill ' + (s.scriptExists ? 'ok' : 'bad');

      const parts = [];
      parts.push('Workspace: ' + (s.workspaceFolder ? s.workspaceFolder : '(no folder open)'));
      parts.push('.vscode/mcp.json: ' + (s.workspaceMcpPath || '—') + (s.workspaceMcpExists ? ' (exists)' : ''));
      parts.push('VS Code user: ' + (s.vsCodeUserMcpPath || '—') + (s.vsCodeUserMcpExists ? ' (exists)' : ''));
      parts.push('Cursor: ' + s.cursorMcpPath + (s.cursorMcpExists ? ' (exists)' : ''));
      parts.push('Node: ' + (s.nodeVersion || '—') + (s.nodeCheckError ? (' — ' + s.nodeCheckError) : ''));
      el('statusLines').textContent = parts.join(String.fromCharCode(10));

      const busy = !s.workspaceFolder;
      el('btnWs').disabled = busy;
    }

    window.addEventListener('message', (event) => {
      const m = event.data;
      if (m.type === 'state') applyState(m.payload);
      if (m.type === 'result') showToast(m.ok, m.message);
      if (m.type === 'diagnose') {
        const d = el('diag');
        d.textContent = (m.lines || []).join(String.fromCharCode(10));
        d.className = 'show';
      }
    });

    function post(t, payload) { vscode.postMessage(payload ? { type: t, payload } : { type: t }); }

    el('save').onclick = () => post('saveSettings', {
      serverScriptPath: el('manualPath').value.trim(),
      nodeExecutable: el('nodeExe').value.trim(),
      vsCodeServerKey: el('vsKey').value.trim(),
      cursorServerKey: el('curKey').value.trim(),
      devWatchGlob: el('watchGlob').value.trim()
    });
    el('pick').onclick = () => post('pickScript');
    el('clearPath').onclick = () => {
      el('manualPath').value = '';
      post('saveSettings', {
        serverScriptPath: '',
        nodeExecutable: el('nodeExe').value.trim(),
        vsCodeServerKey: el('vsKey').value.trim(),
        cursorServerKey: el('curKey').value.trim(),
        devWatchGlob: el('watchGlob').value.trim()
      });
    };
    el('btnWs').onclick = () => post('setupWorkspace');
    el('btnUser').onclick = () => post('setupVsCodeUser');
    el('btnCursor').onclick = () => post('setupCursor');
    el('btnRemove').onclick = () => post('removeAll');
    el('btnTest').onclick = () => post('test');
    el('btnDiag').onclick = () => post('diagnose');
    el('btnOpenWs').onclick = () => post('openWorkspaceMcp');
    el('btnOpenCur').onclick = () => post('openCursorMcp');
    el('btnOut').onclick = () => post('openOutput');
    el('btnRefresh').onclick = () => post('refresh');
    el('openVsSettings').onclick = () => post('openSettings');

    post('refresh');
  </script>
</body>
</html>`;
  }
}
