"use client";

import { useEffect, useRef } from "react";
import { turnstileSiteKey } from "@/lib/config";

declare global {
  interface Window {
    turnstile?: {
      render: (
        element: HTMLElement,
        options: { sitekey: string; callback: (token: string) => void; "expired-callback"?: () => void },
      ) => string;
      remove: (widgetId: string) => void;
    };
  }
}

const SCRIPT_URL = "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit";

/**
 * Cloudflare Turnstile ウィジェット。
 * サイトキーが未設定なら何も描画しない（API 側もシークレット未設定なら検証をスキップする）。
 */
export function TurnstileWidget({ onToken }: { onToken: (token: string) => void }) {
  const container = useRef<HTMLDivElement>(null);
  const onTokenRef = useRef(onToken);
  onTokenRef.current = onToken;

  useEffect(() => {
    if (!turnstileSiteKey || !container.current) return;

    const element = container.current;
    let widgetId: string | undefined;
    let cancelled = false;

    const render = () => {
      if (cancelled || !window.turnstile) return;
      widgetId = window.turnstile.render(element, {
        sitekey: turnstileSiteKey,
        callback: (token) => onTokenRef.current(token),
        "expired-callback": () => onTokenRef.current(""),
      });
    };

    if (window.turnstile) {
      render();
    } else {
      const script = document.createElement("script");
      script.src = SCRIPT_URL;
      script.async = true;
      script.onload = render;
      document.head.appendChild(script);
    }

    return () => {
      cancelled = true;
      if (widgetId && window.turnstile) window.turnstile.remove(widgetId);
    };
  }, []);

  if (!turnstileSiteKey) return null;

  return <div ref={container} data-testid="turnstile" />;
}
