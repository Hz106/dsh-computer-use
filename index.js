/**
 * Computer Use — agent tools for this Windows desktop.
 *
 * The tool runs a PowerShell helper that talks to user32 directly: screenshots,
 * window listing/focus, mouse move/click/drag, typing and key combos. It uses
 * the real cursor and real keyboard, so the user must not fight for the mouse
 * while a call is running; see README.md.
 */
import { execFile } from 'node:child_process'
import { mkdirSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'

const SCRIPT = fileURLToPath(new URL('./computer.ps1', import.meta.url))
const ACTIONS = ['windows', 'screenshot', 'focus', 'move', 'click', 'drag', 'type', 'key']

function powershellPath() {
  const root = process.env.SystemRoot ?? 'C:\\Windows'
  return join(root, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe')
}

function shotDirectory() {
  const directory = join(tmpdir(), 'dsh-computer-use')
  mkdirSync(directory, { recursive: true })
  return directory
}

/** Run one action through the PowerShell helper and parse its JSON reply. */
function run(action, payload) {
  return new Promise((resolve, reject) => {
    const request = { action, dir: shotDirectory(), ...payload }
    const encoded = Buffer.from(JSON.stringify(request), 'utf8').toString('base64')
    execFile(
      powershellPath(),
      ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', SCRIPT, '-ArgsB64', encoded],
      { windowsHide: true, timeout: 45_000, maxBuffer: 8 * 1024 * 1024, encoding: 'utf8' },
      (error, stdout, stderr) => {
        if (error !== null) {
          const detail = (stderr || stdout || error.message).trim()
          reject(new Error(detail.slice(0, 900)))
          return
        }
        const line = stdout.trim().split(/\r?\n/).filter((item) => item.trim() !== '').pop()
        try {
          const parsed = JSON.parse(line)
          if (parsed?.ok === false) reject(new Error(String(parsed.error ?? 'helper failed').slice(0, 900)))
          else resolve(parsed)
        } catch (parseError) {
          reject(new Error(`unexpected helper output: ${String(line).slice(0, 500)}`))
        }
      },
    )
  })
}

function describe(args, value) {
  if (value?.summary) return value.summary
  return `${args.action} done`
}

/** The tool registry is the only service this plugin needs. */
export const inject = ['tools']

export function apply(ctx) {
  ctx.tools.register({
      name: 'computer_use',
      description:
        'Operate this Windows desktop: take a screenshot, list windows, focus a window, move/click/drag the mouse, type text, press key combos. It drives the REAL cursor and keyboard, so ask the user to leave the machine alone while you work; a screenshot returns a PNG path that `read_image` can open. Coordinates are physical pixels from the top-left of the virtual screen (DPI aware).',
      parameters: {
        action: {
          type: 'string',
          required: true,
          enum: ACTIONS,
          description:
            'windows: list visible windows. screenshot: capture the whole desktop. focus: bring a window forward. move/click/drag: pointer actions. type: paste text. key: press a combo such as ctrl+s.',
        },
        x: { type: 'integer', description: 'Pointer x in physical pixels (move, click, drag start).' },
        y: { type: 'integer', description: 'Pointer y in physical pixels (move, click, drag start).' },
        toX: { type: 'integer', description: 'Drag end x.' },
        toY: { type: 'integer', description: 'Drag end y.' },
        button: {
          type: 'string',
          enum: ['left', 'right'],
          description: 'Mouse button for click (default left).',
        },
        double: { type: 'boolean', description: 'Double-click when true.' },
        window: {
          type: 'string',
          description: 'For focus: part of the window title or the process name (case-insensitive).',
        },
        text: { type: 'string', description: 'Text to paste for the type action (Unicode is fine).' },
        keys: {
          type: 'string',
          description: 'Key combo for the key action, e.g. "ctrl+s", "enter", "f5", "ctrl+shift+t".',
        },
      },
      output: {
        schema: {
          type: 'object',
          additionalProperties: false,
          required: ['ok', 'summary'],
          properties: {
            ok: { type: 'boolean' },
            summary: { type: 'string' },
            path: { type: 'string', description: 'PNG path for screenshot.' },
            width: { type: 'integer' },
            height: { type: 'integer' },
            windows: { type: 'array', items: { type: 'object', additionalProperties: true, properties: {} } },
          },
        },
        render: (_args, value) => [
          {
            type: 'text',
            text: value?.path ? `${value.summary}\n${value.path}` : String(value?.summary ?? ''),
          },
        ],
      },
      execute(args) {
        if (typeof args?.action !== 'string' || !ACTIONS.includes(args.action)) {
          throw new Error(`action must be one of: ${ACTIONS.join(', ')}`)
        }
        return run(args.action, {
          x: args.x,
          y: args.y,
          toX: args.toX,
          toY: args.toY,
          button: args.button,
          double: args.double === true,
          window: args.window,
          text: args.text,
          keys: args.keys,
        }).then((value) => ({
          ok: value?.ok !== false,
          summary: describe(args, value),
          ...(typeof value?.path === 'string' ? { path: value.path } : {}),
          ...(Number.isInteger(value?.width) ? { width: value.width } : {}),
          ...(Number.isInteger(value?.height) ? { height: value.height } : {}),
          ...(Array.isArray(value?.windows) ? { windows: value.windows } : {}),
        }))
      },
      presentCall: (args) => ({
        card: 'generic',
        title: `Computer: ${String(args?.action ?? '')}`,
        kind: 'execute',
      }),
    })
}
