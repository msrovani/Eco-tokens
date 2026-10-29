#!/usr/bin/env node
/**
 * Eco-Tokens MCP — stdio JSON-RPC 2.0 (uma mensagem por linha).
 * Tools: get_current_task | update_task_status | run_verification | search_ast_symbol
 */
"use strict";

const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");
const readline = require("readline");

const ROOT = path.resolve(__dirname, "..");
const TASKS_PATH = path.join(ROOT, ".tasks.json");
const VERIFY_SH = path.join(ROOT, "scripts", "verify.sh");
const VALID_STATUS = new Set([
  "TODO",
  "WORKING",
  "BLOCKED",
  "READY_FOR_REVIEW",
]);

function send(msg) {
  process.stdout.write(JSON.stringify(msg) + "\n");
}

function ok(id, result) {
  send({ jsonrpc: "2.0", id, result });
}

function fail(id, code, message, data) {
  const err = { code, message };
  if (data !== undefined) err.data = data;
  send({ jsonrpc: "2.0", id, error: err });
}

function readTasks() {
  const raw = fs.readFileSync(TASKS_PATH, "utf8");
  return JSON.parse(raw);
}

function writeTasks(doc) {
  fs.writeFileSync(TASKS_PATH, JSON.stringify(doc, null, 2) + "\n", "utf8");
}

function findBash() {
  const candidates = [
    process.env.ECO_BASH,
    "bash",
    "C:\\Program Files\\Git\\bin\\bash.exe",
    "C:\\Program Files\\Git\\usr\\bin\\bash.exe",
    "/bin/bash",
    "/usr/bin/bash",
  ].filter(Boolean);
  for (const c of candidates) {
    try {
      const r = spawnSync(c, ["-lc", "echo ok"], {
        encoding: "utf8",
        timeout: 5000,
      });
      if (r.status === 0) return c;
    } catch (_) {
      /* try next */
    }
  }
  return null;
}

function runVerification() {
  const bash = findBash();
  if (!bash) {
    return {
      ok: false,
      exit_code: 1,
      output: "VERIFY_FAIL reason=bash_not_found",
    };
  }
  const r = spawnSync(bash, [VERIFY_SH], {
    cwd: ROOT,
    encoding: "utf8",
    env: process.env,
    maxBuffer: 2 * 1024 * 1024,
  });
  const out = ((r.stdout || "") + (r.stderr || "")).trim();
  const lines = out.split(/\r?\n/);
  const slim = lines.slice(-40).join("\n");
  return {
    ok: r.status === 0,
    exit_code: r.status == null ? 1 : r.status,
    output: slim || "(empty)",
  };
}

function searchAstSymbol(symbol) {
  if (!symbol || typeof symbol !== "string") {
    return { ok: false, error: "symbol required" };
  }
  const maxLines = 30;
  const hasAstGrep =
    spawnSync("ast-grep", ["--version"], { encoding: "utf8" }).status === 0;

  let r;
  if (hasAstGrep) {
    r = spawnSync(
      "ast-grep",
      ["run", "--pattern", symbol, "--lang", "rust", "-A", "2", "-B", "1"],
      { cwd: ROOT, encoding: "utf8", maxBuffer: 1024 * 1024 }
    );
    if (r.status !== 0 || !(r.stdout || "").trim()) {
      r = spawnSync(
        "ast-grep",
        ["run", "--pattern", symbol, "-A", "2", "-B", "1"],
        { cwd: ROOT, encoding: "utf8", maxBuffer: 1024 * 1024 }
      );
    }
  } else {
    const rgBin = process.env.ECO_RG || "rg";
    r = spawnSync(
      rgBin,
      [
        "-n",
        "--no-heading",
        "--color",
        "never",
        "-m",
        String(maxLines),
        "-g",
        "!target/**",
        "-g",
        "!**/node_modules/**",
        "-g",
        "!.git/**",
        symbol,
        ".",
      ],
      { cwd: ROOT, encoding: "utf8", maxBuffer: 1024 * 1024 }
    );
  }

  const text = ((r.stdout || "") + (r.stderr || "")).trim();
  const slim = text
    .split(/\r?\n/)
    .slice(0, maxLines)
    .join("\n");
  return {
    ok: r.status === 0 || slim.length > 0,
    tool: hasAstGrep ? "ast-grep" : "ripgrep",
    symbol,
    snippet: slim || "(no matches)",
    lines: slim ? slim.split(/\r?\n/).length : 0,
  };
}

function updateTaskStatus(status, reason) {
  if (!VALID_STATUS.has(status)) {
    return {
      ok: false,
      error: `invalid status; use ${[...VALID_STATUS].join("|")}`,
    };
  }
  const doc = readTasks();
  const task = doc.active_task || {};
  const prev = task.status || "TODO";
  task.status = status;
  task.reason = reason || "";
  task.updated_at = new Date().toISOString();

  if (status === "WORKING") {
    task.attempts = (Number(task.attempts) || 0) + 1;
  } else if (status === "TODO") {
    task.attempts = 0;
  } else if (status === "READY_FOR_REVIEW") {
    /* keep attempts as evidence of work */
  } else if (status === "BLOCKED") {
    /* keep attempts; circuit breaker already counted failures */
  }

  doc.active_task = task;
  doc.last_transition = { from: prev, to: status, reason: reason || "" };
  writeTasks(doc);
  return { ok: true, active_task: task };
}

const TOOLS = [
  {
    name: "get_current_task",
    description: "Lê .tasks.json e devolve a tarefa ativa (Eco-Tokens).",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "update_task_status",
    description:
      "Atualiza status da tarefa ativa (TODO|WORKING|BLOCKED|READY_FOR_REVIEW) e attempts.",
    inputSchema: {
      type: "object",
      properties: {
        status: {
          type: "string",
          enum: ["TODO", "WORKING", "BLOCKED", "READY_FOR_REVIEW"],
        },
        reason: { type: "string" },
      },
      required: ["status"],
      additionalProperties: false,
    },
  },
  {
    name: "run_verification",
    description:
      "Executa scripts/verify.sh e devolve output enxuto (últimas linhas).",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "search_ast_symbol",
    description:
      "Busca cirúrgica de símbolo via ast-grep ou ripgrep (máx. 30 linhas).",
    inputSchema: {
      type: "object",
      properties: {
        symbol: { type: "string", description: "Nome/padrão do símbolo" },
      },
      required: ["symbol"],
      additionalProperties: false,
    },
  },
];

async function callTool(name, args) {
  switch (name) {
    case "get_current_task":
      return { content: [{ type: "text", text: JSON.stringify(readTasks(), null, 2) }] };
    case "update_task_status":
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify(
              updateTaskStatus(args.status, args.reason),
              null,
              2
            ),
          },
        ],
      };
    case "run_verification":
      return {
        content: [{ type: "text", text: JSON.stringify(runVerification(), null, 2) }],
      };
    case "search_ast_symbol":
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify(searchAstSymbol(args.symbol), null, 2),
          },
        ],
      };
    default:
      throw Object.assign(new Error(`Unknown tool: ${name}`), { code: -32601 });
  }
}

function handle(msg) {
  if (!msg || typeof msg !== "object") return;
  const { id, method, params } = msg;

  if (method === "initialize") {
    ok(id, {
      protocolVersion: (params && params.protocolVersion) || "2024-11-05",
      capabilities: { tools: {} },
      serverInfo: { name: "eco-tokens", version: "1.0.0" },
    });
    return;
  }

  if (method === "notifications/initialized" || method === "initialized") {
    return;
  }

  if (method === "tools/list") {
    ok(id, { tools: TOOLS });
    return;
  }

  if (method === "tools/call") {
    const name = params && params.name;
    const args = (params && params.arguments) || {};
    callTool(name, args)
      .then((result) => ok(id, result))
      .catch((e) =>
        fail(id, e.code || -32000, e.message || String(e), { tool: name })
      );
    return;
  }

  if (method === "ping") {
    ok(id, {});
    return;
  }

  if (id !== undefined && id !== null) {
    fail(id, -32601, `Method not found: ${method}`);
  }
}

const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
rl.on("line", (line) => {
  const trimmed = line.trim();
  if (!trimmed) return;
  try {
    handle(JSON.parse(trimmed));
  } catch (e) {
    send({
      jsonrpc: "2.0",
      id: null,
      error: { code: -32700, message: "Parse error", data: String(e) },
    });
  }
});

process.stdin.on("end", () => process.exit(0));
