import { readFile } from "node:fs/promises";
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

const [image, css] = await Promise.all([
  readFile(imagePath),
  readFile(cssPath, "utf8")
]);

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

const dataUrl = `data:${mimeType};base64,${image.toString("base64")}`;
const styleId = `qoder-skin-${skinId}-style`;
const expression = `(() => {
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

const injectedTargets = new Map();
let firstSuccess = false;

async function injectAll() {
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
      if (previousUrl !== target.url) {
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
