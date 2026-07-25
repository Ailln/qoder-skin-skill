// 通过 CDP 量化每个 Qoder 渲染页面的正文对比度，把「换完肤自己看一眼」变成可失败的门禁。
//
// 检查的是 CSS 层面的前景色与合成后的背景色，专门用来抓「背景改深了但文字色没跟着改」
// 这一类必然不可读的 bug——Quest 页面最容易中招。
//
// 注意它测不到的东西：html::after 那层半透明背景图叠上去之后的观感。图压住文字属于主观
// 调优，仍然要靠截图判断。这里只保证「文字和它所在的面板底色本身对比度够」。
import { evaluate, listPageTargets, readArg } from "./cdp.mjs";

const port = Number(readArg("--port", "9333"));
const minNormal = Number(readArg("--min", "4.5"));

if (!Number.isInteger(port) || port < 1024 || port > 65535) {
  throw new Error(`CDP 端口非法：${port}`);
}

// 在页面里跑：收集可见文字节点，算出实际前景色与逐层合成的背景色，得出 WCAG 对比度。
const PROBE = `(() => {
  const parse = (c) => {
    const m = String(c).match(/rgba?\\(([^)]+)\\)/);
    if (!m) return null;
    const p = m[1].split(/[ ,\\/]+/).filter(Boolean).map(Number);
    return { r: p[0], g: p[1], b: p[2], a: p.length > 3 ? p[3] : 1 };
  };
  const over = (fg, bg) => ({
    r: fg.r * fg.a + bg.r * (1 - fg.a),
    g: fg.g * fg.a + bg.g * (1 - fg.a),
    b: fg.b * fg.a + bg.b * (1 - fg.a),
    a: 1
  });
  const lum = (c) => {
    const f = (v) => {
      v /= 255;
      return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
    };
    return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
  };
  const ratio = (a, b) => {
    const [hi, lo] = [lum(a), lum(b)].sort((x, y) => y - x);
    return (hi + 0.05) / (lo + 0.05);
  };

  // 从元素往上找，把沿途的半透明底色依次合成，直到遇到不透明的一层。
  const effectiveBg = (el) => {
    let acc = null;
    for (let n = el; n; n = n.parentElement) {
      const bg = parse(getComputedStyle(n).backgroundColor);
      if (!bg || bg.a === 0) continue;
      acc = acc ? over(acc, bg) : bg;
      if (acc.a >= 0.999) return acc;
    }
    const root = parse(getComputedStyle(document.documentElement).backgroundColor);
    return acc && root ? over(acc, root) : acc || root || { r: 255, g: 255, b: 255, a: 1 };
  };

  const out = [];
  const seen = new Set();
  for (const el of document.querySelectorAll("*")) {
    // 只看直接承载文字的叶子元素
    const text = Array.from(el.childNodes)
      .filter((n) => n.nodeType === 3)
      .map((n) => n.textContent.trim())
      .join(" ")
      .trim();
    if (!text) continue;

    const rect = el.getBoundingClientRect();
    if (rect.width < 2 || rect.height < 2) continue;
    const cs = getComputedStyle(el);
    if (cs.visibility === "hidden" || cs.display === "none" || Number(cs.opacity) < 0.15) continue;

    const fg = parse(cs.color);
    if (!fg || fg.a === 0) continue;
    const bg = effectiveBg(el);
    const composed = fg.a < 1 ? over(fg, bg) : fg;
    const r = ratio(composed, bg);

    const size = parseFloat(cs.fontSize) || 14;
    const bold = (parseInt(cs.fontWeight, 10) || 400) >= 700;
    // WCAG：大字（>=24px，或 >=18.66px 加粗）门槛放宽到 3:1
    const large = size >= 24 || (size >= 18.66 && bold);

    const key = text.slice(0, 40) + "|" + cs.color + "|" + Math.round(r * 100);
    if (seen.has(key)) continue;
    seen.add(key);

    out.push({
      text: text.slice(0, 48),
      ratio: Math.round(r * 100) / 100,
      color: cs.color,
      bg: "rgb(" + Math.round(bg.r) + ", " + Math.round(bg.g) + ", " + Math.round(bg.b) + ")",
      size: Math.round(size * 10) / 10,
      large
    });
  }
  return JSON.stringify(out);
})()`;

const targets = await listPageTargets(port);
if (targets.length === 0) {
  console.error("没有找到 Qoder 渲染页面。Qoder 是否用 launch-themed-qoder.sh 启动？");
  process.exit(1);
}

let failed = 0;
let checked = 0;

for (const target of targets) {
  const label = target.url.includes("agents-window") ? "Quest 页面" : target.title || target.id;
  let items;
  try {
    items = JSON.parse(await evaluate(target, PROBE));
  } catch (error) {
    console.warn(`[跳过] ${label}：${error.message}`);
    continue;
  }

  const bad = items
    .filter((i) => i.ratio < (i.large ? 3 : minNormal))
    .sort((a, b) => a.ratio - b.ratio);
  checked += items.length;

  if (bad.length === 0) {
    console.log(`  ✓ ${label}：${items.length} 处文字全部达标`);
    continue;
  }

  failed += bad.length;
  console.log(`  ✗ ${label}：${bad.length}/${items.length} 处文字对比度不足`);
  for (const i of bad.slice(0, 12)) {
    const need = i.large ? 3 : minNormal;
    console.log(`      ${i.ratio.toFixed(2)}:1（需 ${need}:1） ${i.color} on ${i.bg}  ${i.size}px  「${i.text}」`);
  }
  if (bad.length > 12) console.log(`      …另有 ${bad.length - 12} 处`);
}

console.log("");
if (failed > 0) {
  console.error(`对比度校验未通过：${failed} 处文字低于阈值（共检查 ${checked} 处）。`);
  console.error("多半是 Quest 页面只改了 --color-bg-* 没改 --color-text-*，见 references/runtime-layer.md。");
  process.exit(1);
}
console.log(`对比度校验通过（共检查 ${checked} 处文字）。`);
console.log("注意：本检查只看 CSS 配色，背景图压住文字的问题仍需看截图判断。");
