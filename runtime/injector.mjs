import { readFile, stat } from "node:fs/promises";
import { extname, resolve } from "node:path";
import { evaluate, listPageTargets, readArg, readSkinId } from "./cdp.mjs";

const skinId = readSkinId(readArg("--id", "custom"));
const port = Number(readArg("--port", "9333"));
const imagePath = resolve(readArg("--image", ""));
const cssPath = resolve(readArg("--css", "./skin.css"));
const intervalMs = Number(readArg("--interval", "2500"));

if (!Number.isInteger(port) || port < 1024 || port > 65535) {
  throw new Error(`CDP 端口非法：${port}`);
}

const MIME_BY_EXT = {
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".webp": "image/webp"
};
const mimeType = MIME_BY_EXT[extname(imagePath).toLowerCase()];
if (!mimeType) {
  throw new Error(`背景图格式不支持：${imagePath}（仅支持 webp/png/jpg）`);
}

const styleId = `qoder-skin-${skinId}-style`;

let css = "";
let dataUrl = "";
let imageMtime = 0;
let expression = "";

// CSS 每轮重读，图片按 mtime 重读：调 skin.css 或换图后无需重启注入器，
// 下一轮轮询就会生效，方便边看截图边微调。
async function refreshSources() {
  const [nextCss, imageStat] = await Promise.all([
    readFile(cssPath, "utf8"),
    stat(imagePath)
  ]);

  let changed = false;
  if (nextCss !== css) {
    css = nextCss;
    changed = true;
  }
  if (imageStat.mtimeMs !== imageMtime) {
    imageMtime = imageStat.mtimeMs;
    const image = await readFile(imagePath);
    dataUrl = `data:${mimeType};base64,${image.toString("base64")}`;
    changed = true;
  }
  if (!changed) {
    return false;
  }

  expression = `(() => {
    const styleId = ${JSON.stringify(styleId)};
    let style = document.getElementById(styleId);
    if (!style) {
      style = document.createElement("style");
      style.id = styleId;
      document.head.appendChild(style);
    }
    if (style.textContent !== ${JSON.stringify(css)}) {
      style.textContent = ${JSON.stringify(css)};
    }
    document.documentElement.style.setProperty("--qoder-skin-image", ${JSON.stringify(`url("${dataUrl}")`)});
    document.documentElement.dataset.qoderSkin = ${JSON.stringify(skinId)};
    return {
      title: document.title,
      url: location.href,
      styleAttached: Boolean(document.getElementById(styleId))
    };
  })()`;
  return true;
}

await refreshSources();

const injectedTargets = new Map();
let firstSuccess = false;

async function injectAll() {
  let sourcesChanged = false;
  try {
    sourcesChanged = await refreshSources();
  } catch (error) {
    console.warn(`[读取皮肤文件失败] ${error.message}`);
  }

  let targets;
  try {
    targets = await listPageTargets(port);
  } catch (error) {
    if (!firstSuccess) {
      console.log(`[等待 Qoder] ${error.message}`);
    }
    return;
  }

  for (const target of targets) {
    try {
      const result = await evaluate(target, expression);
      const previousUrl = injectedTargets.get(target.id);
      if (previousUrl !== target.url || sourcesChanged) {
        console.log(`[已应用] ${result?.title || target.title || "Qoder"} — ${target.url}`);
      }
      injectedTargets.set(target.id, target.url);
      firstSuccess = true;
    } catch (error) {
      console.warn(`[注入失败] ${target.title || target.id}: ${error.message}`);
    }
  }
}

console.log(`Qoder 皮肤运行时 [${skinId}] 正在监听 127.0.0.1:${port}`);
await injectAll();
setInterval(injectAll, intervalMs);
