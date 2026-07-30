import { CancelPanel } from "@/components/CancelPanel";

/**
 * 確認メールのキャンセル URL（CANCEL_URL_BASE + /c/:publicId/:token）に対応する画面。
 * 認可はトークンのみで行うため publicId は表示の手がかりとしてしか使わない。
 */
export default async function CancelPage({
  params,
}: {
  params: Promise<{ publicId: string; token: string }>;
}) {
  const { token } = await params;

  return <CancelPanel token={token} />;
}
