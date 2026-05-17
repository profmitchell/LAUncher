#!/usr/bin/env node
/**
 * LAUncher MCP Server
 *
 * JSON-RPC 2.0 over stdin/stdout. All live plugin control goes through LAUncher's
 * HTTP API (default http://localhost:5555). No mock fallback — start LAUncher with a plugin loaded.
 */

const readline = require('readline');
const http = require('http');

const HTTP_API_URL = process.env.LAUNCHER_HTTP_URL || 'http://localhost:5555';

function httpRequest(method, path, body = null) {
    return new Promise((resolve, reject) => {
        const url = new URL(path, HTTP_API_URL);
        const options = {
            hostname: url.hostname,
            port: url.port || 5555,
            path: url.pathname,
            method,
            headers: {
                'Content-Type': 'application/json',
            },
        };

        const req = http.request(options, (res) => {
            let data = '';
            res.on('data', (chunk) => {
                data += chunk;
            });
            res.on('end', () => {
                if (res.statusCode < 200 || res.statusCode >= 300) {
                    reject(new Error(`HTTP ${res.statusCode} ${method} ${path}: ${data.slice(0, 400)}`));
                    return;
                }
                const trimmed = data.trim();
                if (!trimmed) {
                    resolve(null);
                    return;
                }
                try {
                    resolve(JSON.parse(trimmed));
                } catch {
                    resolve(trimmed);
                }
            });
        });

        req.on('error', (error) => {
            reject(error);
        });

        if (body) {
            req.write(JSON.stringify(body));
        }
        req.end();
    });
}

async function assertLaUncherUp() {
    try {
        await httpRequest('GET', '/health');
    } catch (e) {
        const detail =
            e && e.errors && e.errors[0] && e.errors[0].message
                ? e.errors[0].message
                : e && e.message
                  ? e.message
                  : String(e);
        throw new Error(
            `LAUncher HTTP API not reachable at ${HTTP_API_URL}. Open LAUncher, load a plugin (MCP server starts with the session). ${detail}`
        );
    }
}

const notImplemented = (tool) => {
    throw new Error(
        `${tool} is not implemented on LAUncher's HTTP API yet. Wired today: GET /health, POST /api/get_parameters, /api/set_parameters, /api/randomize_parameters.`
    );
};

// Tool definitions
const tools = [
    {
        name: 'get_parameters',
        description: 'Return parameters from the current plugin via LAUncher (requires app + plugin on port 5555).',
        inputSchema: {
            type: 'object',
            properties: {
                filter: {
                    type: 'object',
                    properties: {
                        pathPrefix: { type: 'string', description: 'Filter parameters by path/display prefix' },
                        onlyAutomatable: { type: 'boolean', description: 'Reserved; AU listing may not expose flags' },
                    },
                },
            },
        },
    },
    {
        name: 'set_parameters',
        description: 'Batch update parameter values on the loaded plugin via LAUncher HTTP API.',
        inputSchema: {
            type: 'object',
            properties: {
                changes: {
                    type: 'array',
                    items: {
                        type: 'object',
                        properties: {
                            id: { type: 'string' },
                            value: { type: 'number' },
                        },
                        required: ['id', 'value'],
                    },
                },
            },
            required: ['changes'],
        },
    },
    {
        name: 'get_patch_snapshot',
        description: 'Snapshot of current patch: live AU parameters from LAUncher (same source as get_parameters, plus snapshot id).',
        inputSchema: {
            type: 'object',
            properties: {
                verbosity: { type: 'string', enum: ['brief', 'full'], default: 'brief' },
                includeRawParameters: { type: 'boolean', default: false },
            },
        },
    },
    {
        name: 'set_patch_snapshot',
        description: 'Apply parameters from an inline patch object with rawParameters [{id,value}, ...] via LAUncher set_parameters.',
        inputSchema: {
            type: 'object',
            properties: {
                snapshotId: { type: 'string' },
                patch: { type: 'object' },
            },
        },
    },
    {
        name: 'save_patch_to_library',
        description: 'Reserved for future LAUncher API (not available over HTTP yet).',
        inputSchema: {
            type: 'object',
            properties: {
                label: { type: 'string' },
                tags: { type: 'array', items: { type: 'string' } },
                notes: { type: 'string' },
            },
            required: ['label'],
        },
    },
    {
        name: 'analyze_patch',
        description: 'Reserved for future LAUncher API (not available over HTTP yet).',
        inputSchema: {
            type: 'object',
            properties: {
                snapshotId: { type: ['string', 'null'] },
                targetUse: { type: 'string' },
            },
        },
    },
    {
        name: 'explain_parameters',
        description: 'Describe parameters using live AU metadata from LAUncher (paths, ranges, current values).',
        inputSchema: {
            type: 'object',
            properties: {
                parameterIds: {
                    type: 'array',
                    items: { type: 'string' },
                },
            },
            required: ['parameterIds'],
        },
    },
    {
        name: 'randomize_parameters',
        description: 'Randomize plugin parameters via LAUncher (same as in-app MCP randomize).',
        inputSchema: {
            type: 'object',
            properties: {
                intensity: {
                    type: 'number',
                    minimum: 0.0,
                    maximum: 1.0,
                    default: 0.4,
                    description: 'Randomization intensity (0.0 = subtle, 1.0 = wild)',
                },
                preserveCategories: {
                    type: 'array',
                    items: { type: 'string' },
                    description: "Parameter path prefixes to preserve (e.g. ['Filter'])",
                },
                excludeIds: {
                    type: 'array',
                    items: { type: 'string' },
                    description: 'Ignored by LAUncher HTTP API today (Swift engine may still honor internally later)',
                },
            },
        },
    },
];

async function handleGetParameters(args) {
    await assertLaUncherUp();
    const response = await httpRequest('POST', '/api/get_parameters', {});
    let filtered = response.parameters || [];

    if (args.filter) {
        if (args.filter.pathPrefix) {
            const prefix = args.filter.pathPrefix;
            filtered = filtered.filter(
                (p) =>
                    (p.path && p.path.startsWith(prefix)) ||
                    (p.displayName && p.displayName.startsWith(prefix))
            );
        }
    }

    return {
        plugin: response.plugin || 'Unknown',
        parameters: filtered,
    };
}

async function handleSetParameters(args) {
    await assertLaUncherUp();
    return httpRequest('POST', '/api/set_parameters', {
        changes: args.changes,
    });
}

async function handleGetPatchSnapshot(args) {
    await assertLaUncherUp();
    const live = await httpRequest('POST', '/api/get_parameters', {});
    const params = live.parameters || [];
    const snapshotId = `${new Date().toISOString().replace(/[:.]/g, '-')}_${Math.random().toString(36).slice(2, 8)}`;

    const snapshot = {
        plugin: live.plugin || 'Unknown',
        name: 'Current patch',
        snapshotId,
        source: 'launched_http_api',
        parameterCount: params.length,
    };

    if (args.includeRawParameters === true || args.verbosity === 'full') {
        snapshot.rawParameters = params;
    }
    return snapshot;
}

async function handleSetPatchSnapshot(args = {}) {
    await assertLaUncherUp();
    if (args.snapshotId) {
        throw new Error(
            'Recalling patch by snapshotId is not supported yet. Use set_patch_snapshot with patch.rawParameters from get_patch_snapshot, or use set_parameters.'
        );
    }
    const patch = args.patch;
    if (!patch || !Array.isArray(patch.rawParameters)) {
        throw new Error('set_patch_snapshot requires patch.rawParameters as an array of { id, value } from a prior snapshot.');
    }
    const changes = patch.rawParameters
        .map((p) => ({ id: p.id, value: Number(p.value) }))
        .filter((c) => c.id && Number.isFinite(c.value));
    if (changes.length === 0) {
        throw new Error('No valid { id, value } entries in patch.rawParameters');
    }
    await httpRequest('POST', '/api/set_parameters', { changes });
    return {
        result: 'ok',
        appliedSnapshotId: patch.snapshotId || `inline_${Date.now()}`,
        appliedCount: changes.length,
    };
}

function handleSavePatchToLibrary() {
    notImplemented('save_patch_to_library');
}

function handleAnalyzePatch() {
    notImplemented('analyze_patch');
}

async function handleExplainParameters(args) {
    await assertLaUncherUp();
    const live = await httpRequest('POST', '/api/get_parameters', {});
    const byId = new Map((live.parameters || []).map((p) => [p.id, p]));
    const explanations = [];
    for (const paramId of args.parameterIds) {
        const param = byId.get(paramId);
        if (param) {
            explanations.push({
                id: paramId,
                label: param.displayName,
                description: `Live AU parameter "${param.displayName}" (${param.path || 'path unknown'}). Value ${param.value} (range ${param.min}–${param.max}).`,
            });
        }
    }
    return { explanations };
}

async function handleRandomizeParameters(args) {
    await assertLaUncherUp();
    return httpRequest('POST', '/api/randomize_parameters', {
        intensity: args.intensity ?? 0.4,
        preserveCategories: args.preserveCategories || [],
    });
}

const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    terminal: false,
});

rl.on('line', async (line) => {
    try {
        const request = JSON.parse(line);

        if (request.method === 'tools/list') {
            const response = {
                jsonrpc: '2.0',
                id: request.id,
                result: {
                    tools: tools.map((tool) => ({
                        name: tool.name,
                        description: tool.description,
                        inputSchema: tool.inputSchema,
                    })),
                },
            };
            console.log(JSON.stringify(response));
        } else if (request.method === 'tools/call') {
            const { toolName, arguments: args } = request.params;
            let result;

            try {
                switch (toolName) {
                    case 'get_parameters':
                        result = await handleGetParameters(args || {});
                        break;
                    case 'set_parameters':
                        result = await handleSetParameters(args);
                        break;
                    case 'get_patch_snapshot':
                        result = await handleGetPatchSnapshot(args || {});
                        break;
                    case 'set_patch_snapshot':
                        result = await handleSetPatchSnapshot(args);
                        break;
                    case 'save_patch_to_library':
                        result = handleSavePatchToLibrary(args);
                        break;
                    case 'analyze_patch':
                        result = handleAnalyzePatch(args || {});
                        break;
                    case 'explain_parameters':
                        result = await handleExplainParameters(args);
                        break;
                    case 'randomize_parameters':
                        result = await handleRandomizeParameters(args || {});
                        break;
                    default:
                        throw new Error(`Unknown tool: ${toolName}`);
                }

                const response = {
                    jsonrpc: '2.0',
                    id: request.id,
                    result,
                };
                console.log(JSON.stringify(response));
            } catch (error) {
                const errorResponse = {
                    jsonrpc: '2.0',
                    id: request.id,
                    error: {
                        code: -32000,
                        message: error.message,
                    },
                };
                console.log(JSON.stringify(errorResponse));
            }
        } else {
            const errorResponse = {
                jsonrpc: '2.0',
                id: request.id,
                error: {
                    code: -32601,
                    message: `Method not found: ${request.method}`,
                },
            };
            console.log(JSON.stringify(errorResponse));
        }
    } catch (error) {
        const errorResponse = {
            jsonrpc: '2.0',
            id: null,
            error: {
                code: -32700,
                message: 'Parse error',
            },
        };
        console.log(JSON.stringify(errorResponse));
    }
});
