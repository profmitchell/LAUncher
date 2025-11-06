#!/usr/bin/env node
/**
 * LAUncher MCP Server
 * 
 * A Model Context Protocol server that exposes tools for controlling and analyzing synth patches.
 * Reads/writes JSON-RPC 2.0 over stdin/stdout.
 */

const readline = require('readline');
const http = require('http');

// HTTP API Configuration
const HTTP_API_URL = 'http://localhost:5555';
const USE_REAL_API = true; // Set to false to use mock data

// HTTP client helper
async function httpRequest(method, path, body = null) {
    return new Promise((resolve, reject) => {
        const url = new URL(path, HTTP_API_URL);
        const options = {
            hostname: url.hostname,
            port: url.port || 5555,
            path: url.pathname,
            method: method,
            headers: {
                'Content-Type': 'application/json',
            }
        };

        const req = http.request(options, (res) => {
            let data = '';
            res.on('data', (chunk) => { data += chunk; });
            res.on('end', () => {
                try {
                    const json = JSON.parse(data);
                    resolve(json);
                } catch (e) {
                    resolve(data);
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

// Check if HTTP API is available
async function checkAPIAvailable() {
    if (!USE_REAL_API) return false;
    try {
        await httpRequest('GET', '/health');
        return true;
    } catch (e) {
        return false;
    }
}

// Mock plugin data for initial implementation
let mockParameters = {
    "filter_cutoff": { id: "filter_cutoff", path: "Filter/Cutoff", address: 1024, displayName: "Cutoff", min: 20.0, max: 20000.0, unit: "Hz", value: 1200.0 },
    "filter_resonance": { id: "filter_resonance", path: "Filter/Resonance", address: 1025, displayName: "Resonance", min: 0.0, max: 1.0, unit: "", value: 0.4 },
    "env1_attack": { id: "env1_attack", path: "Envelope 1/Attack", address: 2000, displayName: "Attack", min: 0.0, max: 10.0, unit: "s", value: 0.05 },
    "env1_decay": { id: "env1_decay", path: "Envelope 1/Decay", address: 2001, displayName: "Decay", min: 0.0, max: 10.0, unit: "s", value: 0.2 },
    "env1_sustain": { id: "env1_sustain", path: "Envelope 1/Sustain", address: 2002, displayName: "Sustain", min: 0.0, max: 1.0, unit: "", value: 0.7 },
    "env1_release": { id: "env1_release", path: "Envelope 1/Release", address: 2003, displayName: "Release", min: 0.0, max: 10.0, unit: "s", value: 1.2 },
    "osc1_wave": { id: "osc1_wave", path: "Oscillator 1/Wave", address: 3000, displayName: "Wave", min: 0.0, max: 10.0, unit: "", value: 2.0 },
    "osc1_detune": { id: "osc1_detune", path: "Oscillator 1/Detune", address: 3001, displayName: "Detune", min: -1.0, max: 1.0, unit: "", value: 0.35 },
    "osc1_voices": { id: "osc1_voices", path: "Oscillator 1/Voices", address: 3002, displayName: "Voices", min: 1.0, max: 16.0, unit: "", value: 8.0 },
    "osc1_stereoWidth": { id: "osc1_stereoWidth", path: "Oscillator 1/Stereo Width", address: 3003, displayName: "Stereo Width", min: 0.0, max: 1.0, unit: "", value: 0.5 }
};

let currentPlugin = "Vital";
let currentPatchName = "Untitled Patch";
let patchLibrary = [];
let patchCounter = 1;

// Tool definitions
const tools = [
    {
        name: "get_parameters",
        description: "Return a machine-friendly list of parameters from the current plugin.",
        inputSchema: {
            type: "object",
            properties: {
                filter: {
                    type: "object",
                    properties: {
                        pathPrefix: { type: "string", description: "Filter parameters by path prefix" },
                        onlyAutomatable: { type: "boolean", description: "Return only automatable parameters" }
                    }
                }
            }
        }
    },
    {
        name: "set_parameters",
        description: "Batch update parameter values.",
        inputSchema: {
            type: "object",
            properties: {
                changes: {
                    type: "array",
                    items: {
                        type: "object",
                        properties: {
                            id: { type: "string" },
                            value: { type: "number" }
                        },
                        required: ["id", "value"]
                    }
                }
            },
            required: ["changes"]
        }
    },
    {
        name: "get_patch_snapshot",
        description: "Return a musical structured snapshot of the current patch.",
        inputSchema: {
            type: "object",
            properties: {
                verbosity: { type: "string", enum: ["brief", "full"], default: "brief" },
                includeRawParameters: { type: "boolean", default: false }
            }
        }
    },
    {
        name: "set_patch_snapshot",
        description: "Recall/apply a patch snapshot, by ID or inline snapshot object.",
        inputSchema: {
            type: "object",
            properties: {
                snapshotId: { type: "string" },
                patch: { type: "object" }
            }
        }
    },
    {
        name: "save_patch_to_library",
        description: "Save the current patch snapshot + metadata into a local JSON library.",
        inputSchema: {
            type: "object",
            properties: {
                label: { type: "string" },
                tags: { type: "array", items: { type: "string" } },
                notes: { type: "string" }
            },
            required: ["label"]
        }
    },
    {
        name: "analyze_patch",
        description: "Provide a quick musical analysis: overview, timbre description, and usage notes.",
        inputSchema: {
            type: "object",
            properties: {
                snapshotId: { type: ["string", "null"] },
                targetUse: { type: "string" }
            }
        }
    },
    {
        name: "explain_parameters",
        description: "Briefly explain what selected parameters do in musical terms.",
        inputSchema: {
            type: "object",
            properties: {
                parameterIds: {
                    type: "array",
                    items: { type: "string" }
                }
            },
            required: ["parameterIds"]
        }
    },
    {
        name: "randomize_parameters",
        description: "Intelligently randomize parameters with reasonable variations, preserving musical character.",
        inputSchema: {
            type: "object",
            properties: {
                intensity: { type: "number", minimum: 0.0, maximum: 1.0, default: 0.4, description: "Randomization intensity (0.0 = subtle, 1.0 = wild)" },
                preserveCategories: { type: "array", items: { type: "string" }, description: "Parameter categories to preserve (e.g., ['Filter', 'Envelope 1'])" },
                excludeIds: { type: "array", items: { type: "string" }, description: "Parameter IDs to exclude from randomization" }
            }
        }
    }
];

// Tool implementations
async function handleGetParameters(args) {
    // Try HTTP API first
    const apiAvailable = await checkAPIAvailable();
    if (apiAvailable) {
        try {
            const response = await httpRequest('POST', '/api/get_parameters', {});
            let filtered = response.parameters || [];
            
            if (args.filter) {
                if (args.filter.pathPrefix) {
                    filtered = filtered.filter(p => p.path?.startsWith(args.filter.pathPrefix));
                }
                if (args.filter.onlyAutomatable !== undefined) {
                    // Filter automatable parameters if needed
                }
            }
            
            return {
                plugin: response.plugin || currentPlugin,
                parameters: filtered
            };
        } catch (error) {
            console.error('HTTP API error, falling back to mock:', error.message);
        }
    }
    
    // Fallback to mock data
    let filtered = Object.values(mockParameters);
    
    if (args.filter) {
        if (args.filter.pathPrefix) {
            filtered = filtered.filter(p => p.path.startsWith(args.filter.pathPrefix));
        }
        if (args.filter.onlyAutomatable !== undefined) {
            // In mock, all parameters are automatable
        }
    }
    
    return {
        plugin: currentPlugin,
        parameters: filtered
    };
}

async function handleSetParameters(args) {
    // Try HTTP API first
    const apiAvailable = await checkAPIAvailable();
    if (apiAvailable) {
        try {
            const response = await httpRequest('POST', '/api/set_parameters', {
                changes: args.changes
            });
            return response;
        } catch (error) {
            console.error('HTTP API error, falling back to mock:', error.message);
        }
    }
    
    // Fallback to mock data
    const applied = [];
    
    for (const change of args.changes) {
        if (mockParameters[change.id]) {
            const param = mockParameters[change.id];
            const clampedValue = Math.max(param.min, Math.min(param.max, change.value));
            mockParameters[change.id].value = clampedValue;
            applied.push({ id: change.id, value: clampedValue });
        }
    }
    
    return {
        result: "ok",
        applied
    };
}

function handleGetPatchSnapshot(args) {
    const snapshotId = `2025-11-06T${new Date().toISOString().split('T')[1]}_${Math.random().toString(36).substr(2, 6)}`;
    
    const snapshot = {
        plugin: currentPlugin,
        name: currentPatchName,
        categoryGuess: "Bass / Pluck",
        snapshotId,
        oscillators: [
            {
                index: 1,
                wave: ["sine", "saw", "square", "triangle"][Math.floor(mockParameters.osc1_wave.value)] || "saw",
                voices: Math.floor(mockParameters.osc1_voices.value),
                detune: mockParameters.osc1_detune.value,
                stereoWidth: mockParameters.osc1_stereoWidth.value
            }
        ],
        filter: {
            type: "Lowpass 24dB",
            cutoffHz: mockParameters.filter_cutoff.value,
            resonance: mockParameters.filter_resonance.value,
            drive: 0.1
        },
        ampEnv: {
            attackMs: mockParameters.env1_attack.value * 1000,
            decayMs: mockParameters.env1_decay.value * 1000,
            sustain: mockParameters.env1_sustain.value,
            releaseMs: mockParameters.env1_release.value * 1000
        },
        modulationOverview: {
            sidechainLFOs: 1,
            envelopesUsed: 2,
            macrosUsed: 3
        }
    };
    
    if (args.includeRawParameters) {
        snapshot.rawParameters = Object.values(mockParameters);
    }
    
    return snapshot;
}

function handleSetPatchSnapshot(args) {
    if (args.snapshotId) {
        // Load from library by ID
        const patch = patchLibrary.find(p => p.snapshotId === args.snapshotId);
        if (patch) {
            // Apply patch parameters
            for (const param of patch.rawParameters || []) {
                if (mockParameters[param.id]) {
                    mockParameters[param.id].value = param.value;
                }
            }
            currentPatchName = patch.name || currentPatchName;
            return {
                result: "ok",
                appliedSnapshotId: args.snapshotId
            };
        } else {
            throw new Error(`Snapshot ${args.snapshotId} not found`);
        }
    } else if (args.patch) {
        // Apply inline patch
        const patch = args.patch;
        if (patch.rawParameters) {
            for (const param of patch.rawParameters) {
                if (mockParameters[param.id]) {
                    mockParameters[param.id].value = param.value;
                }
            }
        }
        currentPatchName = patch.name || currentPatchName;
        return {
            result: "ok",
            appliedSnapshotId: patch.snapshotId || `inline_${Date.now()}`
        };
    } else {
        throw new Error("Either snapshotId or patch must be provided");
    }
}

function handleSavePatchToLibrary(args) {
    const snapshot = handleGetPatchSnapshot({ includeRawParameters: true });
    const entryId = `patch_${String(patchCounter++).padStart(6, '0')}`;
    
    const entry = {
        entryId,
        ...snapshot,
        label: args.label,
        tags: args.tags || [],
        notes: args.notes || "",
        savedAt: new Date().toISOString()
    };
    
    patchLibrary.push(entry);
    
    // In real implementation, would write to ~/Library/Application Support/LAUncher/PatchLibrary.json
    const libraryPath = "~/Library/Application Support/LAUncher/PatchLibrary.json";
    
    return {
        result: "ok",
        libraryPath,
        entryId
    };
}

function handleAnalyzePatch(args) {
    const snapshot = args.snapshotId 
        ? patchLibrary.find(p => p.snapshotId === args.snapshotId)
        : handleGetPatchSnapshot({});
    
    if (!snapshot) {
        throw new Error("Patch not found");
    }
    
    const filterCutoff = snapshot.filter?.cutoffHz || mockParameters.filter_cutoff.value;
    const attack = snapshot.ampEnv?.attackMs || mockParameters.env1_attack.value * 1000;
    const decay = snapshot.ampEnv?.decayMs || mockParameters.env1_decay.value * 1000;
    
    const brightness = Math.min(1.0, filterCutoff / 10000.0);
    const warmth = snapshot.filter?.resonance || 0.5;
    const roughness = snapshot.oscillators?.[0]?.detune || 0.2;
    const space = snapshot.oscillators?.[0]?.stereoWidth || 0.3;
    
    let summary = "Short, snappy bass pluck with a bright transient and controlled low-end.";
    if (attack > 100) {
        summary = "Warm pad with gentle attack and smooth decay.";
    } else if (filterCutoff < 500) {
        summary = "Dark, sub-heavy bass with powerful low-end presence.";
    }
    
    const coreIngredients = [
        `${snapshot.oscillators?.[0]?.wave || "Saw"}-based oscillator with ${snapshot.oscillators?.[0]?.detune ? "mild" : "no"} detune`,
        `Fast amp envelope (${attack.toFixed(1)}ms attack/${decay.toFixed(1)}ms decay, ${((snapshot.ampEnv?.sustain || 0.7) * 100).toFixed(0)}% sustain)`,
        `Lowpass filter with cutoff around ${filterCutoff.toFixed(0)} Hz and ${((snapshot.filter?.resonance || 0.4) * 100).toFixed(0)}% resonance`,
        snapshot.oscillators?.[0]?.stereoWidth ? "Subtle unison spread for width" : "Mono output"
    ];
    
    const usageNotes = args.targetUse?.includes("dnb") ? [
        "Works well as a rhythmic mid-bass layer in minimal DnB.",
        "Consider sidechaining slightly to the kick for more clarity.",
        "Increase filter drive slightly for more aggression."
    ] : [
        "Versatile patch suitable for various genres.",
        "Adjust filter cutoff to taste.",
        "Modulate parameters for movement."
    ];
    
    return {
        summary,
        timbre: {
            brightness,
            warmth,
            roughness,
            space
        },
        coreIngredients,
        usageNotes
    };
}

function handleExplainParameters(args) {
    const explanations = [];
    
    const descriptions = {
        "filter_cutoff": "Controls where the lowpass filter starts to roll off high frequencies. Lower values make the sound darker; higher values make it brighter.",
        "filter_resonance": "Boosts frequencies around the cutoff point, adding bite or a whistling character. Higher resonance can emphasize the movement of the filter.",
        "env1_attack": "Determines how quickly the sound reaches full volume. Very short attack feels percussive; longer attack makes pads or swells.",
        "env1_decay": "Controls how quickly the sound falls from peak to sustain level after the attack phase.",
        "env1_sustain": "Sets the level the sound holds at after decay, while a note is held. 0% means no sustain; 100% means full volume.",
        "env1_release": "Determines how quickly the sound fades out after releasing a key. Longer release creates tail/reverb-like effects.",
        "osc1_wave": "Selects the oscillator waveform. Different waves produce different harmonic content: sine (pure), saw (bright), square (hollow), triangle (mellow).",
        "osc1_detune": "Slightly detunes the oscillator to create thickness and width. Positive values sharpen; negative values flatten.",
        "osc1_voices": "Sets the number of unison voices. More voices create thicker, wider sound but use more CPU.",
        "osc1_stereoWidth": "Controls the stereo spread of the oscillator. 0% is mono; 100% is full stereo width."
    };
    
    for (const paramId of args.parameterIds) {
        const param = mockParameters[paramId];
        if (param) {
            explanations.push({
                id: paramId,
                label: param.displayName,
                description: descriptions[paramId] || `Parameter ${param.displayName} controls ${param.path}.`
            });
        }
    }
    
    return { explanations };
}

async function handleRandomizeParameters(args) {
    // Try HTTP API first
    const apiAvailable = await checkAPIAvailable();
    if (apiAvailable) {
        try {
            const response = await httpRequest('POST', '/api/randomize_parameters', {
                intensity: args.intensity || 0.4,
                preserveCategories: args.preserveCategories || []
            });
            return response;
        } catch (error) {
            console.error('HTTP API error, falling back to mock:', error.message);
        }
    }
    
    // Fallback to mock data
    const intensity = Math.max(0.0, Math.min(1.0, args.intensity || 0.4));
    const preserveCategories = args.preserveCategories || [];
    const excludeIds = args.excludeIds || [];
    
    const applied = [];
    let randomizedCount = 0;
    
    // Get all parameters
    const allParams = Object.values(mockParameters);
    
    for (const param of allParams) {
        // Skip if excluded
        if (excludeIds.includes(param.id)) {
            continue;
        }
        
        // Skip if category should be preserved
        let shouldPreserve = false;
        for (const category of preserveCategories) {
            if (param.path.startsWith(category)) {
                shouldPreserve = true;
                break;
            }
        }
        if (shouldPreserve) {
            continue;
        }
        
        // Intelligent randomization based on parameter type
        const range = param.max - param.min;
        const currentValue = param.value;
        
        // Calculate variation amount based on intensity
        // Lower intensity = smaller variations around current value
        // Higher intensity = larger variations across full range
        let variationAmount;
        if (intensity < 0.5) {
            // Subtle: vary within 10-30% of range centered on current value
            variationAmount = range * (0.1 + intensity * 0.4);
        } else {
            // More wild: vary within 30-100% of range
            variationAmount = range * (0.3 + (intensity - 0.5) * 1.4);
        }
        
        // Special handling for different parameter types
        let newValue;
        
        if (param.unit === "Hz" && param.id.includes("cutoff")) {
            // Filter cutoff: prefer musical ranges
            // Map to logarithmic space for more musical variation
            const logMin = Math.log10(param.min);
            const logMax = Math.log10(param.max);
            const logCurrent = Math.log10(Math.max(param.min, Math.min(param.max, currentValue)));
            const logVariation = (logMax - logMin) * variationAmount / range;
            const logNew = logCurrent + (Math.random() - 0.5) * logVariation * 2;
            newValue = Math.pow(10, Math.max(logMin, Math.min(logMax, logNew)));
        } else if (param.path.includes("Wave") || param.path.includes("wave")) {
            // Waveform: discrete selection
            const waveOptions = [0, 1, 2, 3, 4, 5]; // Common waveforms
            newValue = waveOptions[Math.floor(Math.random() * waveOptions.length)];
        } else if (param.path.includes("Voices") || param.path.includes("voices")) {
            // Voices: discrete integer values
            const minVoices = Math.max(1, Math.floor(param.min));
            const maxVoices = Math.floor(param.max);
            newValue = Math.floor(Math.random() * (maxVoices - minVoices + 1)) + minVoices;
        } else if (param.path.includes("Envelope") || param.path.includes("env")) {
            // Envelope times: exponential variation for more musical feel
            const logMin = Math.log10(Math.max(0.001, param.min));
            const logMax = Math.log10(param.max);
            const logCurrent = Math.log10(Math.max(0.001, currentValue));
            const logVariation = (logMax - logMin) * variationAmount / range;
            const logNew = logCurrent + (Math.random() - 0.5) * logVariation * 2;
            newValue = Math.pow(10, Math.max(logMin, Math.min(logMax, logNew)));
        } else {
            // Default: vary around current value with Gaussian-like distribution
            const offset = (Math.random() - 0.5) * variationAmount * 2;
            newValue = currentValue + offset;
        }
        
        // Clamp to valid range
        newValue = Math.max(param.min, Math.min(param.max, newValue));
        
        // Update parameter
        mockParameters[param.id].value = newValue;
        applied.push({ id: param.id, value: newValue });
        randomizedCount++;
    }
    
    return {
        result: "ok",
        applied,
        intensity,
        randomizedCount
    };
}

// JSON-RPC 2.0 handler
const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    terminal: false
});

rl.on('line', async (line) => {
    try {
        const request = JSON.parse(line);
        
        if (request.method === "tools/list") {
            const response = {
                jsonrpc: "2.0",
                id: request.id,
                result: {
                    tools: tools.map(tool => ({
                        name: tool.name,
                        description: tool.description,
                        inputSchema: tool.inputSchema
                    }))
                }
            };
            console.log(JSON.stringify(response));
        } else if (request.method === "tools/call") {
            const { toolName, arguments: args } = request.params;
            let result;
            
            try {
                switch (toolName) {
                    case "get_parameters":
                        result = await handleGetParameters(args || {});
                        break;
                    case "set_parameters":
                        result = await handleSetParameters(args);
                        break;
                    case "get_patch_snapshot":
                        result = handleGetPatchSnapshot(args || {});
                        break;
                    case "set_patch_snapshot":
                        result = handleSetPatchSnapshot(args);
                        break;
                    case "save_patch_to_library":
                        result = handleSavePatchToLibrary(args);
                        break;
                    case "analyze_patch":
                        result = handleAnalyzePatch(args || {});
                        break;
                    case "explain_parameters":
                        result = handleExplainParameters(args);
                        break;
                    case "randomize_parameters":
                        result = await handleRandomizeParameters(args || {});
                        break;
                    default:
                        throw new Error(`Unknown tool: ${toolName}`);
                }
                
                const response = {
                    jsonrpc: "2.0",
                    id: request.id,
                    result
                };
                console.log(JSON.stringify(response));
            } catch (error) {
                const errorResponse = {
                    jsonrpc: "2.0",
                    id: request.id,
                    error: {
                        code: -32000,
                        message: error.message
                    }
                };
                console.log(JSON.stringify(errorResponse));
            }
        } else {
            const errorResponse = {
                jsonrpc: "2.0",
                id: request.id,
                error: {
                    code: -32601,
                    message: `Method not found: ${request.method}`
                }
            };
            console.log(JSON.stringify(errorResponse));
        }
    } catch (error) {
        const errorResponse = {
            jsonrpc: "2.0",
            id: null,
            error: {
                code: -32700,
                message: "Parse error"
            }
        };
        console.log(JSON.stringify(errorResponse));
    }
});

