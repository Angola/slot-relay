import type { NextConfig } from "next";

const config: NextConfig = {
  reactStrictMode: true,
  // 予約 API は別ホスト（booking-api.stagehubs.net）。ブラウザから直接呼ぶため
  // rewrite は使わない。CORS の許可 Origin は API 側の予約メニューに登録する。
};

export default config;
