import Foundation
import WebKit

extension WebViewStore {
    static var answerCopyCaptureScriptSource: String {
        """
        (() => {
          if (window.__splitViewAnswerCopyCaptureInitialized) return;
          window.__splitViewAnswerCopyCaptureInitialized = true;

          const answerCopyHandlerName = "\(answerCopyCaptureMessageName)";

          const normalizeExtractedText = (value) => String(value || "")
            .replace(/\\u00A0/g, " ")
            .replace(/\\r/g, "")
            .replace(/[ \\t]+\\n/g, "\\n")
            .replace(/\\n{3,}/g, "\\n\\n")
            .trim();

          const postCopiedAnswerPayload = (payload) => {
            const normalized = payload && typeof payload === "object" ? payload : {};
            const trimmed = normalizeExtractedText(normalized.text || "");
            const fallbackClipboard = Boolean(normalized.fallbackClipboard) || !trimmed;
            if (!trimmed && !fallbackClipboard) return;
            try {
              const handlers = window.webkit && window.webkit.messageHandlers;
              if (handlers && handlers[answerCopyHandlerName]) {
                handlers[answerCopyHandlerName].postMessage(JSON.stringify({
                  text: trimmed || null,
                  url: location.href,
                  host: location.hostname || null,
                  fallbackClipboard
                }));
              }
            } catch (_) {}
          };

          const resolveButtonElement = (element) => {
            if (!(element instanceof Element)) return null;
            if (element.matches("button,[role='button']")) return element;
            return element.closest("button,[role='button']");
          };

          const copyButtonDescriptor = (button) => {
            const resolved = resolveButtonElement(button);
            if (!(resolved instanceof Element)) return "";
            return [
              resolved.getAttribute("aria-label") || "",
              resolved.getAttribute("title") || "",
              resolved.getAttribute("data-testid") || "",
              resolved.textContent || ""
            ].join(" ").toLowerCase();
          };

          const looksLikeCopyButton = (element) => {
            const button = resolveButtonElement(element);
            if (!button) return false;

            const descriptor = copyButtonDescriptor(button);
            if (!/(copy|복사)/.test(descriptor)) return false;
            if (/(copy code|code copy|코드 복사|copy link|링크 복사)/.test(descriptor)) return false;
            return true;
          };

          const eventPathElements = (event) => {
            try {
              const path = typeof event.composedPath === "function" ? event.composedPath() : [];
              return path.filter((node) => node instanceof Element);
            } catch (_) {
              const target = event && event.target;
              return target instanceof Element ? [target] : [];
            }
          };

          const findCopyButtonFromEvent = (event) => {
            const seen = new Set();
            for (const element of eventPathElements(event)) {
              const button = resolveButtonElement(element);
              if (!(button instanceof Element) || seen.has(button)) continue;
              seen.add(button);
              if (looksLikeCopyButton(button)) return button;
            }

            const target = event && event.target;
            return target instanceof Element && looksLikeCopyButton(target)
              ? resolveButtonElement(target)
              : null;
          };

          const parentElementOrHost = (node) => {
            if (!(node instanceof Element)) return null;
            if (node.parentElement) return node.parentElement;
            try {
              const root = node.getRootNode ? node.getRootNode() : null;
              if (root && root.host instanceof Element) return root.host;
            } catch (_) {}
            return null;
          };

          const findNearestAnswerContainerFromCopyButton = (button, event) => {
            if (!(button instanceof Element)) return null;
            const host = (location.hostname || "").toLowerCase();

            const hostSelectors = [];
            if (host.includes("openai.com") || host.includes("chatgpt.com")) {
              hostSelectors.push("[data-message-author-role='assistant']");
              hostSelectors.push("article");
            } else if (host.includes("gemini.google.com")) {
              hostSelectors.push("message-content");
              hostSelectors.push("model-response");
              hostSelectors.push("div[data-response-id]");
              hostSelectors.push("[data-response-id]");
              hostSelectors.push("response-container");
            } else if (host.includes("grok.com")) {
              hostSelectors.push("article");
              hostSelectors.push("[data-testid*='assistant']");
              hostSelectors.push("[data-testid*='response']");
              hostSelectors.push("[data-testid*='message']");
              hostSelectors.push("main section");
            } else if (host.includes("perplexity.ai")) {
              hostSelectors.push("main article");
              hostSelectors.push("main .prose");
              hostSelectors.push("div.prose");
            }

            const genericSelectors = ["article", ".prose", ".markdown"];
            const selectors = hostSelectors.concat(genericSelectors);

            const searchSeeds = [];
            const seenSeeds = new Set();
            const pushSeed = (node) => {
              if (!(node instanceof Element)) return;
              if (seenSeeds.has(node)) return;
              seenSeeds.add(node);
              searchSeeds.push(node);
            };

            pushSeed(button);
            for (const pathNode of eventPathElements(event)) {
              pushSeed(pathNode);
            }

            let node = button;
            for (let depth = 0; node && depth < 20; depth += 1) {
              pushSeed(node);
              node = parentElementOrHost(node);
            }

            for (const seed of searchSeeds) {
              for (const selector of selectors) {
                try {
                  const match = seed.closest(selector);
                  if (match) return match;
                } catch (_) {}
              }
            }

            return button.closest("article,section,div");
          };

          const extractTextFromContainer = (container) => {
            if (!(container instanceof Element)) return "";
            const direct = normalizeExtractedText(container.innerText || container.textContent || "");
            if (direct) return direct;

            try {
              if (container.shadowRoot) {
                const shadowText = normalizeExtractedText(container.shadowRoot.textContent || "");
                if (shadowText) return shadowText;

                const nested = container.shadowRoot.querySelector(
                  "message-content, model-response, [data-response-id], article, .markdown, .prose"
                );
                if (nested instanceof Element) {
                  const nestedText = normalizeExtractedText(nested.innerText || nested.textContent || "");
                  if (nestedText) return nestedText;
                }
              }
            } catch (_) {}

            return "";
          };

          const extractAnswerTextFromCopyButton = (event) => {
            const button = findCopyButtonFromEvent(event);
            if (!button) return "";
            const container = findNearestAnswerContainerFromCopyButton(button, event);
            if (!container) return "";

            const text = extractTextFromContainer(container);
            if (!text) return "";

            // Remove small button-label noise if it is embedded in container text.
            return text
              .replace(/(^|\\n)(Copy|Copy response|복사|답변 복사)(\\n|$)/gi, "$1")
              .replace(/\\n{3,}/g, "\\n\\n")
              .trim();
          };

          document.addEventListener("click", (event) => {
            const copyButton = findCopyButtonFromEvent(event);
            if (!copyButton) return;

            const answerText = extractAnswerTextFromCopyButton(event);
            postCopiedAnswerPayload({
              text: answerText,
              fallbackClipboard: !answerText
            });
          }, true);
        })();
        """
    }

    static func composerPrepareScript(payloadJSON: String) -> String {
        """
        (() => {
          try {
            const payload = \(payloadJSON);
            const rule = payload && payload.rule && typeof payload.rule === "object" ? payload.rule : null;
            const customSelectors = Array.isArray(rule && rule.composerSelectors) ? rule.composerSelectors.filter(Boolean) : [];
            const selectors = customSelectors.concat([
              "textarea#prompt-textarea",
              "div#prompt-textarea[contenteditable='true']",
              "div#ask-input[contenteditable='true']",
              "#ask-input[contenteditable='true']",
              ".ql-editor[contenteditable='true']",
              "rich-textarea .ql-editor[contenteditable='true']",
              "textarea[data-id='root']",
              "[role='textbox'][aria-multiline='true']",
              "div[contenteditable='true'][role='textbox']",
              "div[contenteditable='true']",
              "textarea"
            ]);

            const isEditable = (element) => {
              if (!(element instanceof HTMLElement)) return false;
              if (element.matches("textarea,input[type='text'],input[type='search']")) return true;
              return Boolean(element.isContentEditable);
            };

            const isComposerDisabled = (element) => {
              if (!(element instanceof HTMLElement)) return true;
              if (element.hasAttribute("disabled")) return true;
              if (element.getAttribute("aria-disabled") === "true") return true;
              if ("readOnly" in element && element.readOnly === true) return true;
              return false;
            };

            const isVisible = (element) => {
              if (!(element instanceof Element)) return false;
              const style = window.getComputedStyle(element);
              if (!style) return true;
              if (style.display === "none" || style.visibility === "hidden" || Number(style.opacity) === 0) return false;
              const rect = element.getBoundingClientRect();
              return rect.width > 0 && rect.height > 0;
            };

            const scoreComposer = (element) => {
              if (!isEditable(element)) return -10000;
              let score = 0;
              if (isVisible(element)) score += 200;
              if (!isComposerDisabled(element)) score += 120;

              const rect = element.getBoundingClientRect();
              const viewportHeight = Math.max(window.innerHeight || 0, document.documentElement?.clientHeight || 0);
              if (viewportHeight > 0 && rect.bottom >= viewportHeight * 0.45) score += 120;

              const idText = (element.id || "").toLowerCase();
              if (idText === "prompt-textarea" || idText === "ask-input") score += 500;

              const attrText = [
                element.getAttribute("aria-label") || "",
                element.getAttribute("placeholder") || "",
                element.getAttribute("name") || "",
                element.className || ""
              ].join(" ").toLowerCase();
              if (/prompt|message|ask|gemini|grok|perplexity|질문|무엇/.test(attrText)) score += 220;
              if (element.getAttribute("role") === "textbox") score += 120;

              const active = document.activeElement;
              if (active && (active === element || (element.contains && element.contains(active)))) score += 420;
              return score;
            };

            const active = document.activeElement;
            let best = isEditable(active) ? active : null;
            let bestScore = best ? scoreComposer(best) : -10000;

            for (const selector of selectors) {
              let nodes = [];
              try {
                nodes = Array.from(document.querySelectorAll(selector));
              } catch (_) {
                nodes = [];
              }

              for (const node of nodes) {
                const score = scoreComposer(node);
                if (score > bestScore) {
                  best = node;
                  bestScore = score;
                }
              }
            }

            if (!best || !isEditable(best) || isComposerDisabled(best)) {
              return JSON.stringify({ ok: false, reason: "입력창을 찾지 못했습니다." });
            }

            best.focus?.();
            try {
              if (best.isContentEditable) {
                const selection = window.getSelection?.();
                if (selection) {
                  const range = document.createRange();
                  range.selectNodeContents(best);
                  range.collapse(false);
                  selection.removeAllRanges();
                  selection.addRange(range);
                }
              } else if (typeof best.selectionStart === "number") {
                const length = (best.value || "").length;
                best.setSelectionRange?.(length, length);
              }
            } catch (_) {}

            return JSON.stringify({
              ok: true,
              focused: true,
              message: "입력창 준비 완료"
            });
          } catch (error) {
            const reason = error && error.message ? String(error.message) : "입력창 준비 스크립트 오류";
            return JSON.stringify({ ok: false, reason });
          }
        })();
        """
    }

    static func answerCopyButtonScript(payloadJSON: String) -> String {
        """
        (() => {
          try {
            const payload = \(payloadJSON);
            const targetOffset = Math.max(0, Number(payload && payload.targetOffset ? payload.targetOffset : 0));
            const host = (location.hostname || "").toLowerCase();

            const normalizeText = (value) => String(value || "")
              .replace(/\\s+/g, " ")
              .trim()
              .toLowerCase();

            const normalizeExtractedText = (value) => String(value || "")
              .replace(/\\u00A0/g, " ")
              .replace(/\\r/g, "")
              .replace(/[ \\t]+\\n/g, "\\n")
              .replace(/\\n{3,}/g, "\\n\\n")
              .trim();

            const sanitizeExtractedAnswerText = (value) => normalizeExtractedText(value)
              .replace(/(^|\\n)(복사|copy|대답 재확인|대화 공유|내보내기|좋아요|싫어요)(\\n|$)/gi, "$1")
              .replace(/\\n{3,}/g, "\\n\\n")
              .trim();

            const queryAllSafe = (root, selector) => {
              try {
                return Array.from(root.querySelectorAll(selector));
              } catch (_) {
                return [];
              }
            };

            const uniqueElements = (elements) => {
              const seen = new Set();
              const result = [];
              for (const element of elements) {
                if (!(element instanceof Element)) continue;
                if (seen.has(element)) continue;
                seen.add(element);
                result.push(element);
              }
              return result;
            };

            const isVisible = (element) => {
              if (!(element instanceof Element)) return false;
              const style = window.getComputedStyle(element);
              if (style && (style.display === "none" || style.visibility === "hidden")) return false;
              const rect = element.getBoundingClientRect();
              return rect.width > 0 && rect.height > 0;
            };

            const isEnabled = (element) => {
              if (!(element instanceof HTMLElement)) return false;
              if (element.hasAttribute("disabled")) return false;
              if (element.getAttribute("aria-disabled") === "true") return false;
              return true;
            };

            const resolveButton = (element) => {
              if (!(element instanceof Element)) return null;
              if (element.matches("button,[role='button']")) return element;
              return element.closest("button,[role='button']");
            };

            const getUseHrefTokens = (button) => {
              if (!(button instanceof Element)) return [];
              const tokens = [];
              const uses = button.querySelectorAll("svg use");
              uses.forEach((useNode) => {
                const href = useNode.getAttribute("href") || useNode.getAttribute("xlink:href") || "";
                if (href) tokens.push(href.toLowerCase());
              });
              return tokens;
            };

            const descriptor = (button) => {
              if (!(button instanceof Element)) return "";
              return normalizeText([
                button.getAttribute("aria-label") || "",
                button.getAttribute("title") || "",
                button.getAttribute("data-testid") || "",
                button.getAttribute("data-test-id") || "",
                button.className || "",
                button.textContent || ""
              ].join(" "));
            };

            const shouldSkipDescriptor = (text) => {
              if (!text) return false;
              return /(copy code|code copy|코드 복사|copy link|링크 복사)/.test(text);
            };

            const parentElementOrHost = (node) => {
              if (!(node instanceof Element)) return null;
              if (node.parentElement) return node.parentElement;
              try {
                const root = node.getRootNode ? node.getRootNode() : null;
                if (root && root.host instanceof Element) return root.host;
              } catch (_) {}
              return null;
            };

            const findClosestBySelectors = (element, selectors) => {
              if (!(element instanceof Element)) return null;
              for (const selector of selectors) {
                try {
                  const found = element.closest(selector);
                  if (found) return found;
                } catch (_) {}
              }
              return null;
            };

            const findLikelyAssistantContainer = (button) => {
              const resolved = resolveButton(button);
              if (!(resolved instanceof Element)) return null;

              const hostSelectors = (() => {
                if (host.includes("openai.com") || host.includes("chatgpt.com")) {
                  return ["[data-message-author-role='assistant']", "article"];
                }
                if (host.includes("gemini.google.com")) {
                  return ["model-response", "[data-response-id]", "response-container", "message-content", "article"];
                }
                if (host.includes("perplexity.ai")) {
                  return ["main article", "article", "div.prose"];
                }
                if (host.includes("grok.com")) {
                  return ["article", "main section"];
                }
                return ["article", "section", "main", "div.prose"];
              })();

              const direct = findClosestBySelectors(resolved, hostSelectors);
              if (direct) return direct;

              let node = resolved;
              for (let depth = 0; node && depth < 16; depth += 1) {
                const text = sanitizeExtractedAnswerText(node.innerText || node.textContent || "");
                if (text.length >= 120) return node;
                node = parentElementOrHost(node);
              }
              return null;
            };

            const extractTextFromContainer = (container) => {
              if (!(container instanceof Element)) return "";
              const direct = sanitizeExtractedAnswerText(container.innerText || container.textContent || "");
              if (direct) return direct;
              try {
                if (container.shadowRoot) {
                  const shadowText = sanitizeExtractedAnswerText(container.shadowRoot.textContent || "");
                  if (shadowText) return shadowText;
                }
              } catch (_) {}
              return "";
            };

            const extractCapturedText = (button) => {
              const container = findLikelyAssistantContainer(button);
              return extractTextFromContainer(container);
            };

            const clickButtonLikeUser = (target) => {
              if (!(target instanceof HTMLElement)) return false;
              target.focus?.();
              try {
                const eventInit = { bubbles: true, cancelable: true, composed: true };
                target.dispatchEvent(new PointerEvent("pointerdown", eventInit));
                target.dispatchEvent(new MouseEvent("mousedown", eventInit));
                target.dispatchEvent(new PointerEvent("pointerup", eventInit));
                target.dispatchEvent(new MouseEvent("mouseup", eventInit));
              } catch (_) {}
              target.click();
              return true;
            };

            const performCopyClick = (target, targetIndex, preCapturedText = "") => {
              if (!(target instanceof HTMLElement)) {
                return JSON.stringify({ ok: false, reason: "대상 복사 버튼을 선택하지 못했습니다." });
              }
              clickButtonLikeUser(target);

              return JSON.stringify({
                ok: true,
                clicked: true,
                targetOffset: targetIndex,
                message: targetIndex === 0 ? "최신 답변 복사 버튼 클릭 완료" : "직전 답변 복사 버튼 클릭 완료",
                capturedText: preCapturedText || extractCapturedText(target),
                url: location.href
              });
            };

            if (host.includes("gemini.google.com")) {
              const parseGeminiResponseToken = (button) => {
                const jslog = button.getAttribute("jslog") || "";
                const match = jslog.match(/r_[a-z0-9]+/i);
                return match ? match[0].toLowerCase() : "";
              };

              const geminiRawButtons = uniqueElements(
                queryAllSafe(document, "button[data-test-id='copy-response-button']")
                  .concat(queryAllSafe(document, "button[data-test-id='copy-button']"))
                  .concat(queryAllSafe(document, "button[mattooltip*='대답'][aria-label*='복사' i]"))
              );

              const geminiCandidates = uniqueElements(geminiRawButtons.map(resolveButton))
                .filter((button) => button instanceof Element && isVisible(button) && isEnabled(button))
                .filter((button) => {
                  const resolved = resolveButton(button);
                  if (!(resolved instanceof Element)) return false;
                  const desc = descriptor(resolved);
                  if (shouldSkipDescriptor(desc)) return false;

                  const hasCopyIcon = Boolean(
                    resolved.querySelector("mat-icon[fonticon='content_copy'], [fonticon='content_copy']")
                  );
                  if (!hasCopyIcon && !/(copy|복사)/.test(desc)) return false;

                  const dataTestId = (resolved.getAttribute("data-test-id") || "").toLowerCase();
                  if (dataTestId === "copy-response-button") return true;

                  const tooltip = normalizeText(resolved.getAttribute("mattooltip") || "");
                  if (dataTestId === "copy-button" && /(대답|response|답변)/.test(tooltip)) return true;

                  const token = parseGeminiResponseToken(resolved);
                  if (dataTestId === "copy-button" && token) return true;

                  return false;
                });

              const scoreGeminiButton = (button) => {
                const rect = button.getBoundingClientRect();
                const desc = descriptor(button);
                const dataTestId = (button.getAttribute("data-test-id") || "").toLowerCase();
                const tooltip = normalizeText(button.getAttribute("mattooltip") || "");
                const token = parseGeminiResponseToken(button);
                let score = 0;
                score += rect.top;
                score += rect.left * 0.001;
                if (dataTestId === "copy-response-button") score += 1200;
                if (dataTestId === "copy-button") score += 980;
                if (/(대답|response|답변)/.test(tooltip)) score += 600;
                if (token) score += 300;
                if (desc.includes("copy-response-button")) score += 280;
                return score;
              };

              const sortedGemini = geminiCandidates
                .map((button) => ({ button, score: scoreGeminiButton(button) }))
                .sort((a, b) => b.score - a.score)
                .map((entry) => entry.button);

              const dedupedByToken = [];
              const seenTokens = new Set();
              for (const button of sortedGemini) {
                const token = parseGeminiResponseToken(button);
                if (token && seenTokens.has(token)) continue;
                if (token) seenTokens.add(token);
                dedupedByToken.push(button);
              }
              const orderedGemini = dedupedByToken.length ? dedupedByToken : sortedGemini;
              if (orderedGemini.length > 0) {
                const targetIndex = Math.min(targetOffset, Math.max(0, orderedGemini.length - 1));
                return performCopyClick(orderedGemini[targetIndex], targetIndex);
              }

              const geminiMoreButtons = uniqueElements(
                queryAllSafe(document, "button[data-test-id='more-menu-button']")
                  .concat(queryAllSafe(document, "button[aria-label*='옵션 더보기' i]"))
                  .concat(queryAllSafe(document, "button[mattooltip*='더보기' i]"))
              )
                .map(resolveButton)
                .filter((button) => button instanceof Element && isVisible(button) && isEnabled(button))
                .map((button) => button);

              if (!geminiMoreButtons.length) {
                return JSON.stringify({ ok: false, reason: "제미나이 답변 복사 버튼을 찾지 못했습니다." });
              }

              const orderedMoreButtons = geminiMoreButtons
                .map((button) => {
                  const rect = button.getBoundingClientRect();
                  return { button, score: rect.top + (rect.left * 0.001) };
                })
                .sort((a, b) => b.score - a.score)
                .map((entry) => entry.button);

              const targetIndex = Math.min(targetOffset, Math.max(0, orderedMoreButtons.length - 1));
              const targetMoreButton = orderedMoreButtons[targetIndex];
              const preCapturedText = extractCapturedText(targetMoreButton);
              clickButtonLikeUser(targetMoreButton);

              const menuCopyCandidates = uniqueElements(
                queryAllSafe(document, "button[data-test-id='copy-response-button']")
                  .concat(queryAllSafe(document, "button[data-test-id='copy-button']"))
                  .concat(queryAllSafe(document, "button[aria-label*='복사' i]"))
                  .concat(queryAllSafe(document, ".mat-mdc-menu-panel button"))
              )
                .map(resolveButton)
                .filter((button) => button instanceof Element && isVisible(button) && isEnabled(button))
                .filter((button) => {
                  const resolved = resolveButton(button);
                  if (!(resolved instanceof Element)) return false;
                  const desc = descriptor(resolved);
                  if (shouldSkipDescriptor(desc)) return false;
                  const hasCopyIcon = Boolean(
                    resolved.querySelector("mat-icon[fonticon='content_copy'], [fonticon='content_copy']")
                  );
                  return hasCopyIcon || /(copy|복사)/.test(desc);
                })
                .map((button) => button);

              if (!menuCopyCandidates.length) {
                return JSON.stringify({
                  ok: false,
                  reason: "제미나이 더보기 메뉴를 열었지만 복사 버튼을 아직 찾지 못했습니다.",
                  retry: true
                });
              }

              return performCopyClick(menuCopyCandidates[0], targetIndex, preCapturedText);
            }

            const looksLikeCopyButton = (button) => {
              const resolved = resolveButton(button);
              if (!(resolved instanceof Element)) return false;

              const desc = descriptor(resolved);
              if (shouldSkipDescriptor(desc)) return false;
              if (/(copy|복사)/.test(desc)) return true;

              const iconTokens = getUseHrefTokens(resolved);
              if (iconTokens.some((token) => token.includes("#ce3544"))) return true;
              if (iconTokens.some((token) => token.includes("#pplx-icon-copy"))) return true;
              if (resolved.querySelector("mat-icon[fonticon='content_copy'], [fonticon='content_copy']")) return true;
              return false;
            };

            const hostMessageSelectors = (() => {
              if (host.includes("openai.com") || host.includes("chatgpt.com")) {
                return ["[data-message-author-role='assistant']", "main article", "article"];
              }
              if (host.includes("perplexity.ai")) {
                return ["main article", "article"];
              }
              if (host.includes("grok.com")) {
                return ["article", "main section"];
              }
              return ["article", "main section", ".prose"];
            })();

            const messageContainers = uniqueElements(
              hostMessageSelectors.flatMap((selector) => queryAllSafe(document, selector))
            );

            const collectCopyButtonsFromContainer = (container) => {
              const raw = queryAllSafe(container, "button,[role='button']");
              return raw
                .map(resolveButton)
                .filter((button) => button instanceof Element && looksLikeCopyButton(button))
                .map((button) => button);
            };

            const globalCandidates = queryAllSafe(document, "button,[role='button']")
              .map(resolveButton)
              .filter((button) => button instanceof Element && looksLikeCopyButton(button));

            const candidates = uniqueElements(
              messageContainers.flatMap((container) => collectCopyButtonsFromContainer(container)).concat(globalCandidates)
            )
              .filter((button) => isVisible(button) && isEnabled(button));

            if (!candidates.length) {
              return JSON.stringify({ ok: false, reason: "복사 버튼을 찾지 못했습니다." });
            }

            const scoreButton = (button) => {
              const rect = button.getBoundingClientRect();
              const desc = descriptor(button);
              const iconTokens = getUseHrefTokens(button);
              let score = 0;
              score += rect.top;
              score += rect.left * 0.001;
              if (/(copy|복사)/.test(desc)) score += 260;
              if (iconTokens.some((token) => token.includes("#ce3544"))) score += 300;
              if (iconTokens.some((token) => token.includes("#pplx-icon-copy"))) score += 260;
              if ((button.className || "").includes("last-response")) score += 160;
              return score;
            };

            const sorted = candidates
              .map((button) => ({ button, score: scoreButton(button) }))
              .sort((a, b) => b.score - a.score)
              .map((entry) => entry.button);

            const targetIndex = Math.min(targetOffset, Math.max(0, sorted.length - 1));
            return performCopyClick(sorted[targetIndex], targetIndex);
          } catch (error) {
            const reason = error && error.message ? String(error.message) : "복사 버튼 스크립트 오류";
            return JSON.stringify({ ok: false, reason });
          }
        })();
        """
    }

    static func composerSendScript(payloadJSON: String) -> String {
        """
        (() => {
          try {
          const payload = \(payloadJSON);
          const normalizeRule = (rule) => {
            if (!rule || typeof rule !== "object") return null;
            return {
              composerSelectors: Array.isArray(rule.composerSelectors) ? rule.composerSelectors.filter(Boolean) : [],
              sendButtonSelectors: Array.isArray(rule.sendButtonSelectors) ? rule.sendButtonSelectors.filter(Boolean) : [],
              sendPattern: typeof rule.sendPattern === "string" && rule.sendPattern.trim() ? rule.sendPattern : "send|submit|ask|arrow up|전송|보내기|질문|제출",
              enableEnterKey: rule.enableEnterKey !== false
            };
          };

          const rule = normalizeRule(payload.rule);
          const genericComposerSelectors = [
            "textarea#prompt-textarea",
            "div#prompt-textarea[contenteditable='true']",
            "div#ask-input[contenteditable='true']",
            "textarea[data-id='root']",
            "textarea[aria-label*='message' i]",
            "textarea[aria-label*='gemini' i]",
            "textarea[aria-label*='grok' i]",
            "textarea[placeholder*='gemini' i]",
            "textarea[placeholder*='anything' i]",
            "textarea[placeholder*='grok' i]",
            "textarea[placeholder*='ask' i]",
            "[data-testid*='composer'] textarea",
            "[data-testid*='prompt'] textarea",
            "div[contenteditable='true'][role='textbox']",
            "[role='textbox'][aria-multiline='true']",
            "div[contenteditable='true']",
            "textarea"
          ];
          const genericSendSelectors = [
            "button#composer-submit-button",
            "button[data-testid='send-button']",
            "button[data-testid*='send']",
            "[data-testid*='submit']",
            "button[type='submit']",
            "button[aria-label*='send' i]",
            "button[aria-label*='submit' i]",
            "button[aria-label*='제출' i]",
            "button[aria-label*='보내기' i]",
            "button[title*='send' i]",
            "button[aria-label*='ask' i]",
            "button[role='button']",
            "[id*='send' i]",
            "[id*='submit' i]",
            "div[role='button']",
            "div[tabindex]"
          ];

          const normalizeText = (value) => String(value || "")
            .replace(/\\u00A0/g, " ")
            .replace(/\\r/g, "")
            .replace(/[ \\t]+\\n/g, "\\n")
            .replace(/\\n{3,}/g, "\\n\\n")
            .trim();

          const queryAllDeep = (selectors) => {
            const results = [];
            const seen = new Set();

            const push = (el) => {
              if (!(el instanceof Element)) return;
              if (seen.has(el)) return;
              seen.add(el);
              results.push(el);
            };

            const visit = (root) => {
              if (!root) return;
              for (const selector of selectors) {
                try {
                  root.querySelectorAll(selector).forEach(push);
                } catch (_) {}
              }

              let descendants = [];
              try {
                descendants = Array.from(root.querySelectorAll("*"));
              } catch (_) {
                descendants = [];
              }
              for (const node of descendants) {
                if (node instanceof Element && node.shadowRoot) {
                  visit(node.shadowRoot);
                }
              }
            };

            visit(document);
            return results;
          };

          const uniqueElements = (elements) => {
            const seen = new Set();
            const result = [];
            for (const element of elements) {
              if (!(element instanceof Element)) continue;
              if (seen.has(element)) continue;
              seen.add(element);
              result.push(element);
            }
            return result;
          };

          const isVisible = (element) => {
            if (!(element instanceof Element)) return false;
            const style = window.getComputedStyle(element);
            if (!style) return true;
            if (style.display === "none" || style.visibility === "hidden" || Number(style.opacity) === 0) return false;
            const rect = element.getBoundingClientRect();
            return rect.width > 0 && rect.height > 0;
          };

          const isEditable = (element) => {
            if (!(element instanceof HTMLElement)) return false;
            if (element.matches("textarea,input[type='text'],input[type='search']")) return true;
            return Boolean(element.isContentEditable);
          };

          const isComposerDisabled = (element) => {
            if (!(element instanceof HTMLElement)) return true;
            if (element.hasAttribute("disabled")) return true;
            if (element.getAttribute("aria-disabled") === "true") return true;
            if ("readOnly" in element && element.readOnly === true) return true;
            return false;
          };

          const isLexicalComposer = (element) => {
            if (!(element instanceof HTMLElement)) return false;
            if (!element.isContentEditable) return false;
            if (element.id === "ask-input") return true;
            if (element.getAttribute("data-lexical-editor") === "true") return true;
            return false;
          };

          const extractComposerText = (composer) => {
            if (!composer) return "";
            if (composer instanceof HTMLTextAreaElement || composer instanceof HTMLInputElement) {
              return composer.value || "";
            }
            if (typeof composer.value === "string") return composer.value;
            return composer.innerText || composer.textContent || "";
          };

          const scoreComposer = (composer) => {
            if (!isEditable(composer)) return -10000;
            let score = 0;
            if (isVisible(composer)) {
              score += 180;
            } else {
              score -= 180;
            }

            if (!isComposerDisabled(composer)) {
              score += 120;
            } else {
              score -= 320;
            }

            const rect = composer.getBoundingClientRect();
            const viewportHeight = Math.max(window.innerHeight || 0, document.documentElement?.clientHeight || 0);
            if (viewportHeight > 0) {
              if (rect.bottom >= viewportHeight * 0.45) score += 150;
              if (rect.bottom >= viewportHeight * 0.70) score += 100;
            }

            const idText = (composer.id || "").toLowerCase();
            if (idText === "prompt-textarea" || idText === "ask-input") score += 500;

            const attrText = [
              composer.getAttribute("aria-label") || "",
              composer.getAttribute("placeholder") || "",
              composer.getAttribute("name") || "",
              composer.className || ""
            ].join(" ").toLowerCase();
            if (/prompt|message|ask|gemini|grok|perplexity|질문|무엇/.test(attrText)) score += 220;
            if (composer.getAttribute("role") === "textbox") score += 120;
            if (rect.width < 120 || rect.height < 20) score -= 150;

            const active = document.activeElement;
            if (active && (active === composer || (composer.contains && composer.contains(active)))) {
              score += 420;
            }

            return score;
          };

          const pickBest = (elements) => {
            if (!elements.length) return null;
            let best = elements[0];
            let bestScore = scoreComposer(best);
            for (let i = 1; i < elements.length; i += 1) {
              const candidate = elements[i];
              const score = scoreComposer(candidate);
              if (score > bestScore) {
                best = candidate;
                bestScore = score;
              }
            }
            return best;
          };

          const findComposer = () => {
            const selectors = [];
            if (rule && rule.composerSelectors && rule.composerSelectors.length) {
              selectors.push(...rule.composerSelectors);
            }
            selectors.push(...genericComposerSelectors);

            const candidates = queryAllDeep(selectors).filter(isEditable);
            const visible = candidates.filter(isVisible);
            if (visible.length) {
              return pickBest(visible);
            }
            if (candidates.length) return pickBest(candidates);

            const active = document.activeElement;
            if (isEditable(active)) return active;
            return null;
          };

          const setComposerText = (composer, text) => {
            if (!composer) return false;
            composer.focus?.();

            if (composer instanceof HTMLTextAreaElement || composer instanceof HTMLInputElement) {
              try {
                const prototype = composer instanceof HTMLTextAreaElement
                  ? window.HTMLTextAreaElement.prototype
                  : window.HTMLInputElement.prototype;
                const setter = Object.getOwnPropertyDescriptor(prototype, "value")?.set;
                if (setter) {
                  setter.call(composer, text);
                } else {
                  composer.value = text;
                }
              } catch (_) {
                composer.value = text;
              }
              composer.dispatchEvent(new Event("input", { bubbles: true }));
              composer.dispatchEvent(new Event("change", { bubbles: true }));
              return true;
            }

            if (composer.isContentEditable) {
              let usedExecCommand = false;
              try {
                const selection = window.getSelection?.();
                if (selection) {
                  const range = document.createRange();
                  range.selectNodeContents(composer);
                  selection.removeAllRanges();
                  selection.addRange(range);
                }
                const insertedByCommand = document.execCommand?.("insertText", false, text);
                if (!insertedByCommand) {
                  composer.textContent = text;
                } else {
                  usedExecCommand = true;
                }
              } catch (_) {
                composer.textContent = text;
              }
              if (!usedExecCommand && !(composer.textContent || "").trim()) {
                composer.textContent = text;
              }
              if (usedExecCommand) {
                composer.dispatchEvent(new Event("input", { bubbles: true, composed: true }));
              } else {
                try {
                  composer.dispatchEvent(
                    new InputEvent("input", {
                      bubbles: true,
                      composed: true,
                      inputType: "insertFromPaste"
                    })
                  );
                } catch (_) {
                  composer.dispatchEvent(new Event("input", { bubbles: true, composed: true }));
                }
              }
              composer.dispatchEvent(new Event("change", { bubbles: true, composed: true }));
              return true;
            }

            return false;
          };

          const looksLikeSendButton = (button) => {
            if (!(button instanceof Element)) return false;
            if (button.matches("button[type='submit'],input[type='submit']")) return true;

            const label = [
              button.getAttribute("aria-label") || "",
              button.getAttribute("title") || "",
              button.textContent || ""
            ].join(" ").toLowerCase();

            try {
              const pattern = new RegExp((rule && rule.sendPattern) || "send|submit|ask|arrow up|전송|보내기|질문|제출");
              return pattern.test(label);
            } catch (_) {
              return false;
            }
          };

          const scoreSendButton = (button, composer, isCustomSelector) => {
            if (!(button instanceof HTMLElement)) return -10000;
            let score = 0;
            if (isVisible(button)) {
              score += 100;
            } else {
              score -= 200;
            }
            if (looksLikeSendButton(button)) score += 280;
            if (isCustomSelector) score += 20;

            const idText = (button.id || "").toLowerCase();
            if (idText.includes("send") || idText.includes("submit")) score += 180;

            const labelText = [
              button.getAttribute("aria-label") || "",
              button.getAttribute("title") || "",
              button.getAttribute("data-testid") || "",
              button.className || "",
              button.textContent || ""
            ].join(" ").toLowerCase();
            if (/send|submit|ask|전송|보내기|질문|제출/.test(labelText)) score += 120;
            if (button instanceof HTMLButtonElement) score += 80;

            if (composer instanceof HTMLElement) {
              const composerRect = composer.getBoundingClientRect();
              const buttonRect = button.getBoundingClientRect();
              const dx = (buttonRect.left + buttonRect.width / 2) - (composerRect.right - 24);
              const dy = (buttonRect.top + buttonRect.height / 2) - (composerRect.top + composerRect.height / 2);
              const distance = Math.sqrt(dx * dx + dy * dy);
              score += Math.max(0, 360 - distance);

              const composerForm = composer.closest("form");
              const buttonForm = button.closest("form");
              if (composerForm && buttonForm && composerForm === buttonForm) {
                score += 420;
              }
            }

            return score;
          };

          const findSendButton = (composer) => {
            const selectors = [];
            const customSelectorSet = new Set();
            if (rule && rule.sendButtonSelectors && rule.sendButtonSelectors.length) {
              selectors.push(...rule.sendButtonSelectors);
              rule.sendButtonSelectors.forEach((selector) => customSelectorSet.add(selector));
            }
            selectors.push(...genericSendSelectors);

            let best = null;
            let bestScore = -10000;

            for (const selector of selectors) {
              let nodes = [];
              try {
                nodes = queryAllDeep([selector]);
              } catch (_) {
                nodes = [];
              }
              const enabled = nodes.filter(
                (node) =>
                  node instanceof HTMLElement &&
                  isVisible(node) &&
                  !node.hasAttribute("disabled") &&
                  node.getAttribute("aria-disabled") !== "true"
              );
              if (!enabled.length) continue;

              const isCustom = customSelectorSet.has(selector);
              for (const node of enabled) {
                if (!(node instanceof HTMLElement)) continue;
                const score = scoreSendButton(node, composer, isCustom);
                if (score > bestScore) {
                  best = node;
                  bestScore = score;
                }
              }
            }
            return best;
          };

          const verifyInserted = (composer, text) => {
            const expected = normalizeText(text);
            if (!expected) return false;
            const actual = normalizeText(extractComposerText(composer));
            if (!actual) return false;
            if (actual === expected) return true;
            if (expected.length <= 64) return actual.includes(expected);
            if (actual.includes(expected.slice(0, 64))) return true;

            const compact = (value) => String(value || "").replace(/\\s+/g, " ").trim();
            const compactExpected = compact(expected);
            const compactActual = compact(actual);
            if (!compactExpected || !compactActual) return false;
            return compactActual.includes(compactExpected);
          };

          const submitByEnterKey = (composer) => {
            if (!isEditable(composer)) return false;
            composer.focus?.();
            try {
              const keyEventInit = {
                key: "Enter",
                code: "Enter",
                keyCode: 13,
                which: 13,
                bubbles: true,
                cancelable: true
              };
              composer.dispatchEvent(new KeyboardEvent("keydown", keyEventInit));
              composer.dispatchEvent(new KeyboardEvent("keypress", keyEventInit));
              composer.dispatchEvent(new KeyboardEvent("keyup", keyEventInit));
              return true;
            } catch (_) {
              return false;
            }
          };

          const textToInsert = payload && typeof payload.text === "string" ? payload.text : "";
          const hasTextToInsert = textToInsert.trim().length > 0;
          if (!payload || (payload.submit !== true && !hasTextToInsert)) {
            return JSON.stringify({ ok: false, reason: "빈 텍스트" });
          }

          const resolveComposer = () => {
            const active = document.activeElement;
            if (isEditable(active)) return active;
            try {
              return findComposer();
            } catch (_) {
              return null;
            }
          };

          const clickSendButton = (button) => {
            if (!(button instanceof HTMLElement)) return false;
            button.focus?.();
            try {
              const eventInit = { bubbles: true, cancelable: true, composed: true };
              button.dispatchEvent(new PointerEvent("pointerdown", eventInit));
              button.dispatchEvent(new MouseEvent("mousedown", eventInit));
              button.dispatchEvent(new PointerEvent("pointerup", eventInit));
              button.dispatchEvent(new MouseEvent("mouseup", eventInit));
            } catch (_) {}
            try {
              button.click();
              return true;
            } catch (_) {
              return false;
            }
          };

          const findPostSubmitConfirmationButton = () => {
            if (!(host.includes("openai.com") || host.includes("chatgpt.com"))) return null;

            const dialogRoots = queryAllDeep([
              "[role='dialog']",
              "[aria-modal='true']",
              "[role='alertdialog']"
            ]).filter(isVisible);

            const candidates = uniqueElements(
              dialogRoots.flatMap((root) => queryAllDeep(["button", "[role='button']"]).filter((node) => root.contains(node)))
            )
              .filter((node) => node instanceof HTMLElement)
              .filter((node) => isVisible(node))
              .filter((node) => !node.hasAttribute("disabled"))
              .filter((node) => node.getAttribute("aria-disabled") !== "true");

            let best = null;
            let bestScore = -10000;
            for (const node of candidates) {
              const labelText = [
                node.getAttribute("aria-label") || "",
                node.getAttribute("title") || "",
                node.textContent || ""
              ].join(" ").toLowerCase();

              if (/(cancel|dismiss|close|취소|닫기)/.test(labelText)) continue;

              let score = 0;
              if (/(confirm|continue|send|submit|ok|확인|계속|보내기|전송|제출)/.test(labelText)) score += 400;
              if (node instanceof HTMLButtonElement) score += 40;
              if (score > bestScore) {
                best = node;
                bestScore = score;
              }
            }

            return bestScore > 0 ? best : null;
          };

          const confirmPostSubmitIfNeeded = () => {
            const button = findPostSubmitConfirmationButton();
            if (!(button instanceof HTMLElement)) return false;
            return clickSendButton(button);
          };

          const submitByForm = (composer) => {
            if (!(composer instanceof HTMLElement)) return false;
            const form = composer.closest("form");
            if (!(form instanceof HTMLFormElement)) return false;
            try {
              if (typeof form.requestSubmit === "function") {
                form.requestSubmit();
              } else {
                form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
              }
              return true;
            } catch (_) {
              return false;
            }
          };

          const composer = resolveComposer();
          if (!composer && hasTextToInsert) {
            return JSON.stringify({ ok: false, reason: "입력창을 찾지 못했습니다." });
          }

          let inserted = false;
          if (hasTextToInsert) {
            const insertedFirstTry = setComposerText(composer, textToInsert);
            inserted = insertedFirstTry && verifyInserted(composer, textToInsert);
            const allowRetry = !isLexicalComposer(composer);
            if (!inserted && allowRetry) {
              // Retry once for editors that ignore the first synthetic input event.
              const secondTry = setComposerText(composer, textToInsert);
              inserted = secondTry && verifyInserted(composer, textToInsert);
              if (!inserted) {
                return JSON.stringify({ ok: false, reason: "입력창에 텍스트를 넣지 못했습니다." });
              }
            } else if (!inserted && !allowRetry && insertedFirstTry) {
              // Lexical editors can apply DOM changes asynchronously; immediate verify can be stale.
              inserted = true;
            }
          }

          let submitted = false;
          let message = "입력 완료";
          if (payload.submit === true) {
            const submitComposer = resolveComposer() || composer;
            let button = null;
            try {
              button = findSendButton(submitComposer);
            } catch (_) {
              button = null;
            }

            if (button && clickSendButton(button)) {
              submitted = true;
              confirmPostSubmitIfNeeded();
              message = "입력 및 버튼 전송 시도 완료";
            } else if (submitComposer && (rule ? rule.enableEnterKey !== false : true) && submitByEnterKey(submitComposer)) {
              submitted = true;
              confirmPostSubmitIfNeeded();
              message = "입력 및 Enter 전송 시도 완료";
            } else if (submitByForm(submitComposer)) {
              submitted = true;
              confirmPostSubmitIfNeeded();
              message = "입력 및 Form 전송 시도 완료";
            } else {
              message = "입력 완료 (전송 경로 미탐지)";
            }
          }

          return JSON.stringify({
            ok: true,
            inserted,
            submitted,
            message
          });
          } catch (error) {
            const reason = error && error.message ? String(error.message) : "전송 스크립트 오류";
            const stack = error && error.stack ? String(error.stack).slice(0, 1200) : "";
            return JSON.stringify({ ok: false, reason, stack });
          }
        })();
        """
    }

    static var temporaryChatButtonScriptSource: String {
        """
        (() => {
          try {
            const host = (location.hostname || "").toLowerCase();

            const isVisible = (element) => {
              if (!(element instanceof Element)) return false;
              const style = window.getComputedStyle(element);
              if (!style) return true;
              if (style.display === "none" || style.visibility === "hidden" || Number(style.opacity) === 0) return false;
              const rect = element.getBoundingClientRect();
              return rect.width > 0 && rect.height > 0;
            };

            const isEnabled = (element) => {
              if (!(element instanceof Element)) return false;
              if (element.hasAttribute("disabled")) return false;
              if (element.getAttribute("aria-disabled") === "true") return false;
              return true;
            };

            const resolveButton = (element) => {
              if (!(element instanceof Element)) return null;
              if (element.matches("button,[role='button']")) return element;
              return element.closest("button,[role='button']");
            };

            const uniqueElements = (elements) => {
              const seen = new Set();
              return elements.filter((element) => {
                if (!(element instanceof Element)) return false;
                if (seen.has(element)) return false;
                seen.add(element);
                return true;
              });
            };

            const queryButtons = (selectors) =>
              uniqueElements(
                selectors.flatMap((selector) => {
                  try {
                    return Array.from(document.querySelectorAll(selector)).map(resolveButton);
                  } catch (_) {
                    return [];
                  }
                })
              )
                .filter((button) => button instanceof Element)
                .filter((button) => isVisible(button) && isEnabled(button));

            const clickButtonLikeUser = (button) => {
              if (!(button instanceof HTMLElement)) return false;
              button.focus?.();
              const eventInit = { bubbles: true, cancelable: true, composed: true };
              try {
                button.dispatchEvent(new PointerEvent("pointerdown", eventInit));
                button.dispatchEvent(new MouseEvent("mousedown", eventInit));
                button.dispatchEvent(new PointerEvent("pointerup", eventInit));
                button.dispatchEvent(new MouseEvent("mouseup", eventInit));
              } catch (_) {}
              try {
                button.click();
                return true;
              } catch (_) {
                return false;
              }
            };

            if (host.includes("openai.com") || host.includes("chatgpt.com")) {
              const candidates = queryButtons([
                "button[aria-label='임시 채팅 켜기']",
                "button[aria-label*='임시 채팅' i]"
              ]);

              if (!candidates.length) {
                return JSON.stringify({ ok: false, reason: "ChatGPT 임시채팅 버튼을 찾지 못했습니다." });
              }

              const clicked = clickButtonLikeUser(candidates[0]);
              return JSON.stringify({
                ok: clicked,
                clicked,
                message: clicked ? "ChatGPT 임시채팅 버튼 클릭 완료" : "ChatGPT 임시채팅 버튼 클릭 실패",
                reason: clicked ? null : "ChatGPT 임시채팅 버튼 클릭 실패"
              });
            }

            if (host.includes("gemini.google.com")) {
              const tempChatButtons = queryButtons([
                "button[data-test-id='temp-chat-button']",
                "button[aria-label='임시 채팅']"
              ]);

              if (tempChatButtons.length) {
                const clicked = clickButtonLikeUser(tempChatButtons[0]);
                return JSON.stringify({
                  ok: clicked,
                  clicked,
                  message: clicked ? "Gemini 임시채팅 버튼 클릭 완료" : "Gemini 임시채팅 버튼 클릭 실패",
                  reason: clicked ? null : "Gemini 임시채팅 버튼 클릭 실패"
                });
              }

              const menuButtons = queryButtons([
                "button[data-test-id='side-nav-menu-button']",
                "button[aria-label='기본 메뉴']"
              ]);

              if (!menuButtons.length) {
                return JSON.stringify({ ok: false, reason: "Gemini 메뉴 버튼을 찾지 못했습니다." });
              }

              const menuClicked = clickButtonLikeUser(menuButtons[0]);
              if (!menuClicked) {
                return JSON.stringify({ ok: false, reason: "Gemini 메뉴 버튼 클릭 실패" });
              }

              return JSON.stringify({
                ok: false,
                retry: true,
                reason: "Gemini 메뉴를 열었지만 임시채팅 버튼을 아직 찾지 못했습니다."
              });
            }

            return JSON.stringify({ ok: false, reason: "임시채팅을 지원하지 않는 서비스입니다." });
          } catch (error) {
            const reason = error && error.message ? String(error.message) : "임시채팅 버튼 스크립트 오류";
            return JSON.stringify({ ok: false, reason });
          }
        })();
        """
    }

}
