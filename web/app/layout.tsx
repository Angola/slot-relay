import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "予約フォーム（slot-relay 参照実装）",
  description: "slot-relay 予約 API を使った予約フォームの参照実装",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ja">
      <body>
        <main className="container">{children}</main>
      </body>
    </html>
  );
}
