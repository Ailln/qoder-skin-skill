import { evaluate, listPageTargets, readArg, readSkinId } from "./cdp.mjs";

const rawId = readArg("--id", "");
const skinId = rawId ? readSkinId(rawId) : "";
const port = Number(readArg("--port", "9333"));

// 不传 --id 时移除本项目注入的所有皮肤 style，只匹配 qoder-skin-*-style 前缀，
// 不会碰 Qoder 自己或其他扩展的样式节点。
const selector = skinId
  ? `#qoder-skin-${skinId}-style`
  : `style[id^="qoder-skin-"][id$="-style"]`;

const expression = `(() => {
  const nodes = document.querySelectorAll(${JSON.stringify(selector)});
  nodes.forEach((node) => node.remove());
  document.documentElement.style.removeProperty("--qoder-skin-image");
  delete document.documentElement.dataset.qoderSkin;
  return { title: document.title, removed: nodes.length };
})()`;

const targets = await listPageTargets(port);
if (targets.length === 0) {
  console.log("没有找到 Qoder 渲染页面，可能 Qoder 已退出或未开启调试端口。");
}
for (const target of targets) {
  const result = await evaluate(target, expression);
  console.log(`[已恢复] ${result?.title || target.title || target.id}（移除 ${result?.removed ?? 0} 个 style 节点）`);
}
