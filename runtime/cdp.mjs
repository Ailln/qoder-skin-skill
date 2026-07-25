const REQUEST_TIMEOUT_MS = 5000;

export function readArg(name, fallback) {
  const index = process.argv.indexOf(name);
  if (index === -1 || index + 1 >= process.argv.length) {
    return fallback;
  }
  return process.argv[index + 1];
}

// 皮肤 id 会被拼进 DOM 元素 id 和 CSS 选择器，必须限制成安全字符集。
export function readSkinId(value) {
  if (!/^[a-z0-9][a-z0-9-]{0,63}$/.test(value)) {
    throw new Error(`皮肤 id 非法：${value}（只允许小写字母、数字和连字符）`);
  }
  return value;
}

export async function listPageTargets(port) {
  const response = await fetch(`http://127.0.0.1:${port}/json/list`, {
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS)
  });
  if (!response.ok) {
    throw new Error(`CDP target list returned HTTP ${response.status}`);
  }

  const targets = await response.json();
  return targets.filter((target) => {
    if (target.type !== "page" || !target.webSocketDebuggerUrl) {
      return false;
    }
    return target.url.includes("vscode-app") || target.url.includes("vscode-file");
  });
}

export async function evaluate(target, expression) {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(target.webSocketDebuggerUrl);
    const timeout = setTimeout(() => {
      socket.close();
      reject(new Error(`Timed out while injecting ${target.title || target.id}`));
    }, REQUEST_TIMEOUT_MS);

    const finish = (error, value) => {
      clearTimeout(timeout);
      try {
        socket.close();
      } catch {
        // The target may already have closed.
      }
      if (error) {
        reject(error);
      } else {
        resolve(value);
      }
    };

    socket.addEventListener("open", () => {
      socket.send(JSON.stringify({
        id: 1,
        method: "Runtime.evaluate",
        params: {
          expression,
          awaitPromise: true,
          returnByValue: true
        }
      }));
    });

    socket.addEventListener("message", (event) => {
      const message = JSON.parse(String(event.data));
      if (message.id !== 1) {
        return;
      }
      if (message.error || message.result?.exceptionDetails) {
        finish(new Error(JSON.stringify(message.error || message.result.exceptionDetails)));
        return;
      }
      finish(null, message.result?.result?.value);
    });

    socket.addEventListener("error", () => {
      finish(new Error(`WebSocket failed for ${target.title || target.id}`));
    });
  });
}
