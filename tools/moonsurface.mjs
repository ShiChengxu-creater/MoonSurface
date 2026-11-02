#!/usr/bin/env node
// File/process adapter only. Geometry, JSON schema and job execution are MoonBit.
import { open } from 'node:fs/promises';
import { dirname, resolve, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const usage = 'Usage: node tools/moonsurface.mjs INPUT.json [--out NEW_OUTPUT.json]';
if (args.length === 1 && args[0] === '--help') {
  console.log(usage);
  process.exit(0);
}
if (!(args.length === 1 || (args.length === 3 && args[1] === '--out'))) {
  console.error(usage);
  process.exit(2);
}

try {
  const limit = 16 * 1024 * 1024;
  const file = await open(args[0], 'r');
  let bytes;
  try {
    const info = await file.stat();
    if (!info.isFile()) throw new Error('input must be a regular file');
    if (info.size > limit) throw new Error('input exceeds 16 MiB');
    const chunks = [];
    let total = 0;
    while (true) {
      const chunk = Buffer.alloc(Math.min(65536, limit + 1 - total));
      const { bytesRead } = await file.read(chunk);
      if (bytesRead === 0) break;
      total += bytesRead;
      if (total > limit) throw new Error('input exceeds 16 MiB');
      chunks.push(chunk.subarray(0, bytesRead));
    }
    bytes = Buffer.concat(chunks, total);
  } finally { await file.close(); }
  globalThis.__moonSurfaceInput = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  await import(pathToFileURL(join(root, '_build/js/debug/build/cmd/moonsurface/moonsurface.js')).href);
  const response = globalThis.__moonSurfaceOutput;
  if (typeof response !== 'string') throw new Error('MoonBit produced no job response');
  if (Buffer.byteLength(response) > 128 * 1024 * 1024) throw new Error('output exceeds 128 MiB');
  const status = JSON.parse(response).ok;
  if (!status) {
    process.stdout.write(response + '\n');
    process.exitCode = 2;
  } else if (args.length === 3) {
    const output = await open(args[2], 'wx');
    try { await output.writeFile(response + '\n', 'utf8'); }
    finally { await output.close(); }
  } else {
    process.stdout.write(response + '\n');
  }
} catch (error) {
  console.error('MoonSurface: ' + error.message);
  process.exitCode = 2;
} finally {
  delete globalThis.__moonSurfaceInput;
  delete globalThis.__moonSurfaceOutput;
}
