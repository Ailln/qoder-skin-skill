// 通过 CDP 给每个 Qoder 渲染页面截图，用于换肤后的自我验证。
import { mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { command, listPageTargets, readArg } from "./cdp.mjs";

const port = Number(readArg("--port", "9333"));
const outDir = resolve(readArg("--out", "./screenshots"));

if (!Number.isInteger(port) || port < 1024 || port > 65535) {
  throw new Error(`CDP 端口非法：${port}`);
}

await mkdir(outDir, { recursive: true });

const targets = await listPageTargets(port);
if (targets.length === 0) {
  console.log("没有找到 Qoder 渲染页面。Qoder 是否用 launch-themed-qoder.sh 启动？");
}

const used = new Map();
for (const target of targets) {
  // 页面标题可能重复或含路径分隔符，做一次安全化并去重。
  const base = (target.title || "qoder").replace(/[^\w一-龥.-]+/g, "-").slice(0, 40) || "qoder";
  const seen = (used.get(base) ?? 0) + 1;
  used.set(base, seen);
  const name = seen > 1 ? `${base}-${seen}` : base;

  try {
    const result = await command(target, [
      ["Page.enable"],
      ["Page.captureScreenshot", { format: "png", captureBeyondViewport: false }]
    ], 15000);
    const file = `${outDir}/${name}.png`;
    await writeFile(file, Buffer.from(result.data, "base64"));
    console.log(`[已截图] ${file}`);
  } catch (error) {
    console.warn(`[截图失败] ${target.title || target.id}: ${error.message}`);
  }
}
