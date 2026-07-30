import Link from "next/link";
import { bookingApiUrl, bookingTypeSlug } from "@/lib/config";

export default function Home() {
  return (
    <section className="card">
      <h1>slot-relay 予約フォーム（参照実装）</h1>
      <p>
        この Next.js アプリは、予約 API の公開エンドポイントだけで予約画面が成立することを示すための
        参照実装です。実際のサイト（genba-tsunagu.jp など）は、同じ API を自前のデザインで呼び出します。
      </p>

      <dl className="summary">
        <dt>API</dt>
        <dd>
          <code>{bookingApiUrl}</code>
        </dd>
        <dt>予約メニュー</dt>
        <dd>
          <code>{bookingTypeSlug}</code>
        </dd>
      </dl>

      <p>
        <Link href="/booking" className="primary-link">
          予約画面へ
        </Link>
      </p>
    </section>
  );
}
