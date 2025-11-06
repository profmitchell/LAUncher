[PROJECT] LAUncher MCP Server

GOAL
- Implement an MCP server called "launcher" that exposes tools for controlling and analyzing synth patches.
- The server is a standalone CLI program (Node/TS is fine) that:
  - Reads/writes JSON-RPC 2.0 over stdin/stdout.
  - Implements MCP methods: tools/list, tools/call.
- Initially, it will mock plugin interactions. Later, it will call a local HTTP API exposed by the LAUncher macOS app.

MCP SERVER NAME
- "launcher"

MCP TOOLS

1) get_parameters
- Purpose:
  - Return a machine-friendly list of parameters from the current plugin.
- Request:
  - method: "tools/call"
  - toolName: "get_parameters"
  - arguments (JSON):
    {
      "filter": {
        "pathPrefix": "Filter",       // optional, string
        "onlyAutomatable": true       // optional, bool
      }
    }
- Response (result field):
  {
    "plugin": "Vital",
    "parameters": [
      {
        "id": "filter_cutoff",
        "path": "Filter/Cutoff",
        "address": 1024,
        "displayName": "Cutoff",
        "min": 20.0,
        "max": 20000.0,
        "unit": "Hz",
        "value": 1200.0
      },
      ...
    ]
  }

2) set_parameters
- Purpose:
  - Batch update parameter values.
- Request:
  - toolName: "set_parameters"
  - arguments:
    {
      "changes": [
        { "id": "filter_cutoff", "value": 800.0 },
        { "id": "env1_attack", "value": 0.05 }
      ]
    }
- Response:
  {
    "result": "ok",
    "applied": [
      { "id": "filter_cutoff", "value": 800.0 },
      { "id": "env1_attack", "value": 0.05 }
    ]
  }

3) get_patch_snapshot
- Purpose:
  - Return a more "musical" structured snapshot of the current patch.
- Request:
  - toolName: "get_patch_snapshot"
  - arguments:
    {
      "verbosity": "brief",          // "brief" | "full"
      "includeRawParameters": false  // optional
    }
- Response:
  {
    "plugin": "Vital",
    "name": "Untitled Patch",
    "categoryGuess": "Bass / Pluck",
    "snapshotId": "2025-11-06T23:14:10Z_abc123",
    "oscillators": [
      {
        "index": 1,
        "wave": "saw",
        "voices": 8,
        "detune": 0.35,
        "stereoWidth": 0.5
      }
    ],
    "filter": {
      "type": "Lowpass 24dB",
      "cutoffHz": 1100.0,
      "resonance": 0.4,
      "drive": 0.1
    },
    "ampEnv": {
      "attackMs": 3.0,
      "decayMs": 200.0,
      "sustain": 0.7,
      "releaseMs": 120.0
    },
    "modulationOverview": {
      "sidechainLFOs": 1,
      "envelopesUsed": 2,
      "macrosUsed": 3
    }
  }

4) set_patch_snapshot
- Purpose:
  - Recall/apply a patch snapshot, by ID or inline snapshot object.
- Request (by id):
  - toolName: "set_patch_snapshot"
  - arguments:
    {
      "snapshotId": "2025-11-06T23:14:10Z_abc123"
    }
- Request (inline):
    {
      "patch": { ... snapshot object from get_patch_snapshot ... }
    }
- Response:
  {
    "result": "ok",
    "appliedSnapshotId": "2025-11-06T23:14:10Z_abc123"
  }

5) save_patch_to_library
- Purpose:
  - Save the current patch snapshot + metadata into a local JSON library.
- Request:
  - toolName: "save_patch_to_library"
  - arguments:
    {
      "label": "Minimal Pluck 01",
      "tags": ["dnb", "minimal", "pluck"],
      "notes": "Good for midrange plucks, slightly hollow."
    }
- Behavior:
  - Internally calls get_patch_snapshot.
  - Appends a new entry to: ~/Library/Application Support/LAUncher/PatchLibrary.json
- Response:
  {
    "result": "ok",
    "libraryPath": "~/Library/Application Support/LAUncher/PatchLibrary.json",
    "entryId": "patch_001234"
  }

6) analyze_patch
- Purpose:
  - Provide a quick musical analysis: overview, timbre description, and usage notes.
- Request:
  - toolName: "analyze_patch"
  - arguments:
    {
      "snapshotId": null,              // use current if null
      "targetUse": "bass / dnb"        // optional hint for analysis
    }
- Response:
  {
    "summary": "Short, snappy bass pluck with a bright transient and controlled low-end.",
    "timbre": {
      "brightness": 0.7,
      "warmth": 0.5,
      "roughness": 0.2,
      "space": 0.3
    },
    "coreIngredients": [
      "Saw-based oscillator with mild detune",
      "Fast amp envelope (short attack/decay, medium sustain)",
      "Lowpass filter with cutoff around 1.1 kHz and moderate resonance",
      "Subtle unison spread for width"
    ],
    "usageNotes": [
      "Works well as a rhythmic mid-bass layer in minimal DnB.",
      "Consider sidechaining slightly to the kick for more clarity.",
      "Increase filter drive slightly for more aggression."
    ]
  }

7) explain_parameters
- Purpose:
  - Briefly explain what selected parameters do in musical terms.
- Request:
  - toolName: "explain_parameters"
  - arguments:
    {
      "parameterIds": ["filter_cutoff", "filter_resonance", "env1_attack"]
    }
- Response:
  {
    "explanations": [
      {
        "id": "filter_cutoff",
        "label": "Filter Cutoff",
        "description": "Controls where the lowpass filter starts to roll off high frequencies. Lower values make the sound darker; higher values make it brighter."
      },
      {
        "id": "filter_resonance",
        "label": "Filter Resonance",
        "description": "Boosts frequencies around the cutoff point, adding bite or a whistling character. Higher resonance can emphasize the movement of the filter."
      },
      {
        "id": "env1_attack",
        "label": "Envelope Attack",
        "description": "Determines how quickly the sound reaches full volume. Very short attack feels percussive; longer attack makes pads or swells."
      }
    ]
  }

IMPLEMENTATION NOTES
- The initial version of the server can mock plugin data:
  - Store parameters in memory and modify them when set_parameters is called.
  - Generate fake snapshots for testing.
- Later, replace mocks with calls to a local HTTP API:
  - Example endpoints:
    - GET http://127.0.0.1:5555/parameters
    - POST http://127.0.0.1:5555/parameters
    - GET http://127.0.0.1:5555/snapshot
    - POST http://127.0.0.1:5555/snapshot
    - POST http://127.0.0.1:5555/library
- The MCP server must:
  - Respond to "tools/list" with metadata for all tools above.
  - Respond to "tools/call" by parsing "toolName" and "arguments" and returning the appropriate JSON result.zzz