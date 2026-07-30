import { BookingForm } from "@/components/BookingForm";
import { bookingTypeSlug } from "@/lib/config";

export default function BookingPage() {
  return <BookingForm slug={bookingTypeSlug} />;
}
